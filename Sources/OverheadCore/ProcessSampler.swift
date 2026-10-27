import Darwin
import Foundation

/// One process at one moment. `footprint` is the figure Activity Monitor shows in its Memory column.
public struct ProcessSample: Sendable, Equatable {
    public var pid: pid_t
    public var name: String
    public var workingDirectory: String?
    public var footprint: UInt64
    /// User + system CPU time since the process started, in nanoseconds.
    public var cpuTime: UInt64

    public init(pid: pid_t, name: String, workingDirectory: String?, footprint: UInt64, cpuTime: UInt64 = 0) {
        self.pid = pid
        self.name = name
        self.workingDirectory = workingDirectory
        self.footprint = footprint
        self.cpuTime = cpuTime
    }
}

public enum ProcessSampler {
    /// Every process this user can inspect. Other users' and system processes fail `proc_pid_rusage` and are skipped.
    public static func sampleAll() -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let written = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard written > 0 else { return [] }
        return pids.prefix(Int(written)).compactMap { pid in pid > 0 ? sample(pid) : nil }
    }

    static func sample(_ pid: pid_t) -> ProcessSample? {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard ok == 0 else { return nil }
        return ProcessSample(
            pid: pid,
            name: name(pid),
            workingDirectory: workingDirectory(pid),
            footprint: usage.ri_phys_footprint,
            cpuTime: nanoseconds(usage.ri_user_time + usage.ri_system_time)
        )
    }

    /// `proc_pid_rusage` reports CPU time in Mach ticks, not nanoseconds: 125/3 ns each on Apple silicon, 1 on Intel.
    static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    static func nanoseconds(_ ticks: UInt64) -> UInt64 {
        ticks.multipliedReportingOverflow(by: timebase.numer).overflow
            ? ticks / timebase.denom * timebase.numer
            : ticks * timebase.numer / timebase.denom
    }

    static func name(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        let short = String(cString: buffer)
        guard isVersion(short) else { return short }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return short }
        return displayName(short: short, executablePath: String(cString: path))
    }

    /// Self-updating CLIs install each release as `<tool>/versions/<x.y.z>` (Claude Code does), so the kernel's short
    /// name is a version number. The folder above `versions` is the tool's name.
    static func displayName(short: String, executablePath: String) -> String {
        let parts = executablePath.split(separator: "/")
        guard parts.count >= 3, parts[parts.count - 2] == "versions" else { return short }
        return String(parts[parts.count - 3])
    }

    static func isVersion(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isNumber || $0 == "." } && name.contains(".")
    }

    static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty || path == "/" ? nil : path
    }
}
