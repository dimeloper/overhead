import Darwin
import Foundation

/// Machine-wide CPU ticks since boot, summed over every core.
public struct CPUTicks: Sendable, Equatable {
    public var busy: UInt64
    public var idle: UInt64

    public init(busy: UInt64, idle: UInt64) {
        self.busy = busy
        self.idle = idle
    }

    public static func read() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(
            busy: UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3),  // user, system, nice
            idle: UInt64(ticks.2)
        )
    }

    /// Share of the whole machine that was busy between two readings, 0...1.
    public func load(since earlier: CPUTicks) -> Double {
        let busy = Double(self.busy &- earlier.busy)
        let total = busy + Double(idle &- earlier.idle)
        return total > 0 ? busy / total : 0
    }
}

/// Turns cumulative CPU time per process into a rate between two samples.
public struct ActivityTracker {
    private var previous: [pid_t: UInt64] = [:]
    private var previousAt: Date?
    private let cores: Double

    public init(cores: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.cores = Double(max(cores, 1))
    }

    /// Share of the whole machine each process used since the last call, 0...1. Empty on the first call. A pid whose
    /// CPU time went backwards was reused by a new process and is skipped for this round.
    public mutating func update(_ samples: [ProcessSample], at now: Date) -> [pid_t: Double] {
        defer {
            previous = Dictionary(samples.map { ($0.pid, $0.cpuTime) }, uniquingKeysWith: { $1 })
            previousAt = now
        }
        guard let previousAt, now > previousAt else { return [:] }
        let capacity = now.timeIntervalSince(previousAt) * 1_000_000_000 * cores
        var rates: [pid_t: Double] = [:]
        for sample in samples {
            guard let before = previous[sample.pid], sample.cpuTime >= before else { continue }
            rates[sample.pid] = Double(sample.cpuTime - before) / capacity
        }
        return rates
    }
}
