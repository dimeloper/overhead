import Darwin
import Foundation

/// A dev server Park will stop.
public struct ServerToStop: Sendable, Equatable {
    public var pid: pid_t
    public var ports: [UInt16]
    public var process: String
    /// Signal the whole group when its leader is part of the project and is not a shell, so `pnpm dev` and the
    /// `node` it started stop together. Otherwise only `pid`.
    public var processGroup: pid_t?
    /// What to type to start it again: the group leader's command line.
    public var command: String
    public var workingDirectory: String
}

/// What parking a project would do, shown before anything happens.
public struct ParkPlan: Sendable, Equatable {
    public var project: Project
    public var servers: [ServerToStop]
    public var simulators: [BootedSimulator]
    /// Coding agents working in the project. Park never stops them.
    public var agents: [String]
    public var uncommittedChanges: Int?

    public var isEmpty: Bool { servers.isEmpty && simulators.isEmpty }
}

/// The setup sheet kept for a parked project, so Resume can bring it back.
public struct ParkedProject: Codable, Sendable, Equatable {
    public struct Command: Codable, Sendable, Equatable {
        public var command: String
        public var workingDirectory: String
        public var ports: [UInt16]
    }

    public struct Simulator: Codable, Sendable, Equatable {
        public var udid: String
        public var name: String
        public var runtime: String
    }

    public var name: String
    public var path: String
    public var parkedAt: Date
    public var branch: String?
    public var commands: [Command]
    public var simulators: [Simulator]
    /// `.env` file names only. Their contents are never read.
    public var envFiles: [String]
    /// Pinned tool versions: `.nvmrc`, `.python-version` and the like, file name to first line.
    public var toolVersions: [String: String]
}

public enum Parker {
    static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "login", "tmux", "screen", "nu"]
    static let agents = ["claude", "codex", "gemini"]

    public static func plan(
        for project: Project,
        projects: [Project],
        samples: [ProcessSample],
        ports: PortReport,
        simulators: [BootedSimulator],
        appsBySimulator: [String: Set<String>],
        bundleIDs: Set<String>
    ) -> ParkPlan {
        let byPid = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func inProject(_ sample: ProcessSample) -> Bool {
            guard let cwd = sample.workingDirectory else { return false }
            return ProjectAttribution.project(containing: cwd, in: projects) == project
        }

        var servers: [ServerToStop] = []
        for (pid, entries) in Dictionary(grouping: ports.ports.filter { $0.project == project.name }, by: \.pid) {
            guard let sample = byPid[pid] else { continue }
            let leader = byPid[sample.processGroup]
            let useGroup = leader.map { inProject($0) && !shells.contains($0.name) && $0.processGroup != getpgrp() } ?? false
            let source = useGroup ? leader! : sample
            servers.append(ServerToStop(
                pid: pid,
                ports: entries.map(\.port).sorted(),
                process: sample.name,
                processGroup: useGroup ? sample.processGroup : nil,
                command: shellCommand(ProcessSampler.arguments(source.pid), fallback: source.name),
                workingDirectory: source.workingDirectory ?? project.path
            ))
        }

        let matched = simulators.filter { simulator in
            (appsBySimulator[simulator.udid] ?? []).contains { BundleIdentifiers.matches(app: $0, declared: bundleIDs) }
        }
        let agentNames = samples.filter { sample in agents.contains(sample.name) && inProject(sample) }.map(\.name)

        return ParkPlan(
            project: project,
            servers: servers.sorted { ($0.ports.first ?? 0) < ($1.ports.first ?? 0) },
            simulators: matched,
            agents: agentNames,
            uncommittedChanges: nil
        )
    }

    /// Stops the servers (SIGTERM), shuts the simulators down, and returns the setup sheet. Files are never touched.
    public static func park(_ plan: ParkPlan, now: Date = Date()) -> ParkedProject {
        for server in plan.servers {
            if let group = server.processGroup { killpg(group, SIGTERM) } else { kill(server.pid, SIGTERM) }
        }
        for simulator in plan.simulators { try? SimulatorScanner.shutDown(simulator.udid) }
        return sheet(for: plan, now: now)
    }

    static func sheet(for plan: ParkPlan, now: Date) -> ParkedProject {
        let root = URL(fileURLWithPath: plan.project.path)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var versions: [String: String] = [:]
        for name in [".nvmrc", ".node-version", ".python-version", ".ruby-version", ".tool-versions"] where files.contains(name) {
            let text = (try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? ""
            if let line = text.split(whereSeparator: \.isNewline).first { versions[name] = String(line).trimmingCharacters(in: .whitespaces) }
        }
        return ParkedProject(
            name: plan.project.name,
            path: plan.project.path,
            parkedAt: now,
            branch: branch(at: root),
            commands: plan.servers.map { .init(command: $0.command, workingDirectory: $0.workingDirectory, ports: $0.ports) },
            simulators: plan.simulators.map { .init(udid: $0.udid, name: $0.name, runtime: $0.runtime) },
            envFiles: files.filter { $0 == ".env" || $0.hasPrefix(".env.") }.sorted(),
            toolVersions: versions
        )
    }

    /// The checked-out branch from `HEAD`, following a worktree's `.git` file to its real git dir.
    static func branch(at root: URL) -> String? {
        var gitDir = root.appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: gitDir, encoding: .utf8), pointer.hasPrefix("gitdir:") {
            gitDir = URL(fileURLWithPath: pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: root)
        }
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let ref = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return ref.hasPrefix("ref: refs/heads/") ? String(ref.dropFirst("ref: refs/heads/".count)) : nil
    }

    /// `git status --porcelain` line count, or nil when git is unavailable.
    public static func uncommittedChanges(at path: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "status", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).count
    }

    /// Arguments joined so they paste back into a shell.
    static func shellCommand(_ arguments: [String], fallback: String) -> String {
        guard let first = arguments.first else { return fallback }
        return ([interpreterName(first)] + arguments.dropFirst()).map(quoted).joined(separator: " ")
    }

    static let interpreters: Set<String> = ["node", "python", "python3", "ruby", "bun", "deno", "php"]

    /// Interpreters often re-exec under an install path (`…/Python.framework/…/MacOS/Python`, `~/.nvm/…/bin/node`).
    /// The name you would type is what pastes back usefully.
    static func interpreterName(_ executable: String) -> String {
        guard executable.hasPrefix("/") else { return executable }
        let name = (executable as NSString).lastPathComponent
        if name == "Python" && executable.contains("/Python.framework/") { return "python3" }
        return interpreters.contains(name) ? name : executable
    }

    /// Single-quotes anything beyond plain characters.
    public static func quoted(_ argument: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))
        return argument.unicodeScalars.allSatisfy(safe.contains) && !argument.isEmpty
            ? argument
            : "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Boots the saved simulators and opens Simulator. Servers are not restarted: they would miss the environment
    /// your shell gives them, so the setup sheet keeps their commands to paste instead.
    public static func resume(_ parked: ParkedProject) {
        for simulator in parked.simulators { run("/usr/bin/xcrun", ["simctl", "boot", simulator.udid]) }
        if !parked.simulators.isEmpty { run("/usr/bin/open", ["-a", "Simulator"]) }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Parked projects, kept as JSON in Application Support so they survive a restart.
public struct ParkedStore {
    public let file: URL

    public init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Overhead/parked.json")) {
        self.file = file
    }

    public func load() -> [ParkedProject] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ParkedProject].self, from: data)) ?? []
    }

    public func save(_ projects: [ParkedProject]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: file, options: .atomic)
    }
}
