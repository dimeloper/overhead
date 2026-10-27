import Foundation

/// A git checkout: a repository, or a worktree of one (its `.git` is a file).
public struct Project: Sendable, Hashable {
    public var name: String
    public var path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct ProjectUsage: Sendable, Equatable {
    public var project: Project
    public var footprint: UInt64
    /// Process names, largest first, without duplicates.
    public var processes: [String]
}

public struct Attribution: Sendable, Equatable {
    /// Largest first.
    public var projects: [ProjectUsage]
    public var unattributed: UInt64

    public init(projects: [ProjectUsage], unattributed: UInt64) {
        self.projects = projects
        self.unattributed = unattributed
    }
}

public enum ProjectDiscovery {
    /// Home folders that never hold source checkouts. Skipping them keeps a scan of `~` cheap.
    static let skipped: Set<String> = ["Library", "Applications", "Pictures", "Music", "Movies", "Public", "Desktop", "Downloads"]

    /// Git checkouts up to two levels below `home` (`~/repo`, `~/folder/repo`), plus agent worktrees kept inside a
    /// repo at `.claude/worktrees/*`.
    public static func discover(home: URL, fileManager: FileManager = .default) -> [Project] {
        var found: [Project] = []
        for level1 in children(of: home, fileManager) where !skipped.contains(level1.lastPathComponent) {
            if isCheckout(level1, fileManager) {
                found += checkout(level1, fileManager)
                continue
            }
            for level2 in children(of: level1, fileManager) where isCheckout(level2, fileManager) {
                found += checkout(level2, fileManager)
            }
        }
        return found
    }

    static func checkout(_ url: URL, _ fileManager: FileManager) -> [Project] {
        let repo = Project(name: url.lastPathComponent, path: url.path)
        let worktrees = children(of: url.appendingPathComponent(".claude/worktrees"), fileManager)
            .filter { isCheckout($0, fileManager) }
            .map { Project(name: "\(url.lastPathComponent) · \($0.lastPathComponent)", path: $0.path) }
        return [repo] + worktrees
    }

    static func isCheckout(_ url: URL, _ fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    static func children(of url: URL, _ fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let urls = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.filter {
            let values = try? $0.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }
}

public enum ProjectAttribution {
    /// Charges each process to the deepest project its working directory sits in, so a worktree inside a repo gets
    /// its own row instead of inflating the repo's.
    public static func attribute(_ samples: [ProcessSample], to projects: [Project]) -> Attribution {
        let byDepth = projects.sorted { $0.path.count > $1.path.count }
        var totals: [Project: (bytes: UInt64, processes: [(String, UInt64)])] = [:]
        var unattributed: UInt64 = 0

        for sample in samples {
            guard let cwd = sample.workingDirectory, let project = byDepth.first(where: { contains($0.path, cwd) }) else {
                unattributed += sample.footprint
                continue
            }
            totals[project, default: (0, [])].bytes += sample.footprint
            totals[project, default: (0, [])].processes.append((sample.name, sample.footprint))
        }

        let usages = totals.map { project, total in
            var seen = Set<String>()
            let names = total.processes.sorted { $0.1 > $1.1 }.map(\.0).filter { seen.insert($0).inserted }
            return ProjectUsage(project: project, footprint: total.bytes, processes: names)
        }
        return Attribution(projects: usages.sorted { $0.footprint > $1.footprint }, unattributed: unattributed)
    }

    /// `/a/app` contains `/a/app` and `/a/app/src`, never `/a/app-2`.
    static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
