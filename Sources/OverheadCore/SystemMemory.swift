import Darwin
import Foundation

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
}

/// Machine-wide memory, counted the way Activity Monitor's "Memory Used" does: app memory + wired + compressed.
public struct SystemMemory: Sendable, Equatable {
    public var total: UInt64
    public var used: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure

    public init(total: UInt64, used: UInt64, swapUsed: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.used = used
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    public enum ReadError: Error { case hostStatistics(kern_return_t) }

    public static func read() throws -> SystemMemory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw ReadError.hostStatistics(result) }

        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed: UInt64 = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)

        return SystemMemory(
            total: ProcessInfo.processInfo.physicalMemory,
            used: used,
            swapUsed: swapUsed,
            pressure: MemoryPressure(rawValue: Int(level)) ?? .normal
        )
    }
}
