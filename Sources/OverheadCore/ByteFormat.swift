import Foundation

public enum ByteFormat {
    /// "6.1 GB", "820 MB": one decimal from 1 GB up, the style the menu bar has room for.
    public static func short(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    /// "2 h 40 m", "35 m".
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) m" : "\(minutes) m"
    }

    /// "20 min", "22 h", "3 d": how long something has been running, short enough for a detail line.
    public static func uptime(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 48 * 60 { return "\(minutes / 60) h" }
        return "\(minutes / (24 * 60)) d"
    }

    /// "2:40": the menu bar form.
    public static func clock(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "22%" of the whole machine; "<1%" rather than a misleading zero.
    public static func percent(_ share: Double) -> String {
        let value = share * 100
        return value > 0 && value < 1 ? "<1%" : String(format: "%.0f%%", value)
    }
}
