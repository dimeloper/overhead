import AppKit
import OverheadCore
import SwiftUI

/// What the menu bar shows: small labels over values, like iStat Menus.
struct MenuBarReadout: View {
    var cpu: String
    var memory: String
    /// Only while running on battery.
    var battery: String?
    var holdingAwake: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            if holdingAwake {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 11, weight: .semibold))
            }
            column("CPU", cpu, sample: "100%")
            column("MEM", memory, sample: "63.9G")
            if let battery { column("BAT", battery, sample: "10:00") }
        }
        .padding(.horizontal, 1)
        .frame(height: 22)
        .foregroundStyle(.black)
    }

    /// Each column is as wide as its widest possible value, so the readout does not jitter as numbers change.
    private func column(_ label: String, _ value: String, sample: String) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(label).font(.system(size: 7.5, weight: .bold)).kerning(0.4).opacity(0.75)
            ZStack(alignment: .leading) {
                Text(sample).hidden()
                Text(value)
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .fixedSize()
    }

    /// A template image: macOS tints it for light and dark menu bars and for the highlighted state.
    @MainActor
    func image(scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) -> NSImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = scale
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 22))
        image.isTemplate = true
        return image
    }
}

extension ByteFormat {
    /// "52.7G", "820M": memory in the width the menu bar has.
    static func menu(_ bytes: UInt64) -> String {
        short(bytes).replacingOccurrences(of: " GB", with: "G").replacingOccurrences(of: " MB", with: "M")
    }
}
