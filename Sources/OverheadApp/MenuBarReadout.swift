import AppKit
import OverheadCore
import SwiftUI

/// What the menu bar shows: small labels over values, like iStat Menus.
struct MenuBarReadout: View {
    struct Column: Equatable {
        var label: String
        var value: String
        /// The widest value this column can show, so the readout does not jitter as numbers change.
        var widest: String
    }

    var columns: [Column]
    var holdingAwake: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            if holdingAwake {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 11, weight: .semibold))
            }
            ForEach(columns, id: \.label) { column in
                VStack(alignment: .leading, spacing: -1) {
                    Text(column.label).font(.system(size: 7.5, weight: .bold)).kerning(0.4).opacity(0.75)
                    ZStack(alignment: .leading) {
                        Text(column.widest).hidden()
                        Text(column.value)
                    }
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
                .fixedSize()
            }
            // With every readout turned off, a small gauge keeps the menu bar item clickable.
            if columns.isEmpty && !holdingAwake {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.horizontal, 1)
        .frame(height: 22)
        .foregroundStyle(.black)
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
