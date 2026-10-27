import Foundation

public enum ByteFormat {
    /// "6.1 GB", "820 MB": one decimal from 1 GB up, the style the menu bar has room for.
    public static func short(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
