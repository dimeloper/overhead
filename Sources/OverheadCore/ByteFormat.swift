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
