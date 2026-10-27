import Foundation

public struct BootedSimulator: Sendable, Hashable {
    public var udid: String
    public var name: String
    /// "iOS 27.0"
    public var runtime: String
    public var launchdPid: pid_t
    public var bootedAt: Date?

    public init(udid: String, name: String, runtime: String, launchdPid: pid_t, bootedAt: Date?) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
        self.launchdPid = launchdPid
        self.bootedAt = bootedAt
    }
}

public struct SimulatorUsage: Sendable, Equatable {
    public var simulator: BootedSimulator
    public var footprint: UInt64
    public var cpu: Double
    public var processCount: Int
}

public enum SimulatorScanner {
    /// Each booted simulator runs its own `launchd_sim`, started with the device's bootstrap plist:
    /// `…/CoreSimulator/Devices/<UDID>/data/var/run/launchd_bootstrap.plist`.
    public static func booted(in samples: [ProcessSample], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BootedSimulator] {
        samples.filter { $0.name == "launchd_sim" }.compactMap { sample in
            guard let udid = ProcessSampler.arguments(sample.pid).lazy.compactMap(udid(in:)).first else { return nil }
            let plist = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/device.plist")
            let device = (try? Data(contentsOf: plist))
                .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
            return BootedSimulator(
                udid: udid,
                name: device["name"] as? String ?? "Simulator",
                runtime: runtimeLabel(device["runtime"] as? String ?? ""),
                launchdPid: sample.pid,
                bootedAt: sample.startedAt
            )
        }
    }

    static func udid(in argument: String) -> String? {
        let parts = argument.split(separator: "/")
        guard let index = parts.firstIndex(of: "Devices"), index + 1 < parts.count else { return nil }
        let candidate = String(parts[index + 1])
        return UUID(uuidString: candidate) != nil ? candidate : nil
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-0" → "iOS 27.0"
    static func runtimeLabel(_ identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last, let dash = last.firstIndex(of: "-") else { return identifier }
        let platform = last[..<dash]
        let version = last[last.index(after: dash)...].replacingOccurrences(of: "-", with: ".")
        return "\(platform) \(version)"
    }

    /// Everything a simulator runs descends from its `launchd_sim`, so its cost is that whole tree.
    public static func usage(of simulators: [BootedSimulator], samples: [ProcessSample], cpu: [pid_t: Double]) -> [SimulatorUsage] {
        var children: [pid_t: [ProcessSample]] = [:]
        for sample in samples { children[sample.parentPid, default: []].append(sample) }
        let byPid = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        return simulators.map { simulator in
            var footprint: UInt64 = 0
            var share = 0.0
            var count = 0
            var stack = [simulator.launchdPid]
            var seen = Set<pid_t>()
            while let pid = stack.popLast() {
                guard seen.insert(pid).inserted else { continue }
                if let sample = byPid[pid] {
                    footprint += sample.footprint
                    share += cpu[pid] ?? 0
                    count += 1
                }
                stack += children[pid, default: []].map(\.pid)
            }
            return SimulatorUsage(simulator: simulator, footprint: footprint, cpu: share, processCount: count)
        }
        .sorted { $0.footprint > $1.footprint }
    }

    /// The same as `xcrun simctl shutdown <udid>`. Apps in the simulator quit; the device and its data stay.
    public static func shutDown(_ udid: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "shutdown", udid]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ShutDownError(status: process.terminationStatus) }
    }

    public struct ShutDownError: Error { public var status: Int32 }
}
