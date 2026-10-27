import Foundation
import IOKit.pwr_mgt

public enum KeepAwakeMode: String, CaseIterable, Sendable {
    case off, automatic, on
}

/// Decides when "automatic" keep-awake holds. Busy means working, not merely open: an idle `claude` session or a
/// dev server waiting for requests uses almost no CPU, so neither keeps the Mac up.
public struct KeepAwakePolicy {
    /// Build tools and coding agents count wherever they run.
    static let watchedTools = ["xcodebuild", "swift-build", "swift-frontend", "clang", "cargo", "rustc", "gradle", "eas", "fastlane", "pod", "claude", "codex", "gemini", "docker-buildx"]

    /// A project or tool is busy above a quarter of one core.
    public var busyCoreShare = 0.25
    /// Keep holding this long after the last busy sample, so the Mac does not sleep between two build steps.
    public var holdAfterQuiet: TimeInterval = 120

    private var lastBusyAt: Date?
    private var lastReason: String?

    public init() {}

    /// What is keeping the Mac busy right now, if anything: a watched tool first, then the busiest project.
    public func busyReason(samples: [ProcessSample], rates: [pid_t: Double], projects: [ProjectUsage], cores: Int) -> String? {
        let threshold = busyCoreShare / Double(max(cores, 1))
        let tool = samples
            .filter { sample in Self.watchedTools.contains { sample.name.hasPrefix($0) } && (rates[sample.pid] ?? 0) >= threshold }
            .max { (rates[$0.pid] ?? 0) < (rates[$1.pid] ?? 0) }
        if let tool {
            let project = projects.first { $0.processes.contains(tool.name) }?.project.name
            return project.map { "\($0) is running \(tool.name)" } ?? "\(tool.name) is running"
        }
        if let project = projects.filter({ $0.cpu >= threshold }).max(by: { $0.cpu < $1.cpu }) {
            return "\(project.project.name) is busy"
        }
        return nil
    }

    /// The reason to hold right now, or nil when the Mac may sleep.
    public mutating func evaluate(busy reason: String?, at now: Date) -> String? {
        if let reason {
            lastBusyAt = now
            lastReason = reason
            return reason
        }
        guard let lastBusyAt, now.timeIntervalSince(lastBusyAt) < holdAfterQuiet else { return nil }
        return lastReason
    }
}

/// An IOKit assertion that keeps the system awake while the display may still sleep. It shows in
/// `pmset -g assertions` under the given name.
public final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    public private(set) var reason: String?

    public init() {}

    deinit { release() }

    public func hold(_ reason: String) {
        guard reason != self.reason else { return }
        if self.reason != nil {
            // Already holding: rename rather than drop and retake, which would leave a gap.
            IOPMAssertionSetProperty(id, kIOPMAssertionNameKey as CFString, "Overhead: \(reason)" as CFString)
            self.reason = reason
            return
        }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Overhead: \(reason)" as CFString,
            &id
        )
        if result == kIOReturnSuccess { self.reason = reason }
    }

    public func release() {
        guard reason != nil else { return }
        IOPMAssertionRelease(id)
        id = 0
        reason = nil
    }
}
