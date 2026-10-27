import AppKit
import SwiftUI

/// `Overhead --snapshot <file.png> [--full]` renders the popover offscreen once real samples are in, writes a PNG and quits.
/// It lays the view out in a real window, so scroll views, pickers and buttons render as they do on screen.
@MainActor
enum Snapshot {
    static func runIfRequested(model: OverheadModel) {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return }
        let output = URL(fileURLWithPath: arguments[flag + 1])

        // Two samples are needed before CPU figures exist; the ports scan runs on the first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            // `--full` lifts the scroll cap so every section is in the picture.
            let cap: CGFloat = arguments.contains("--full") ? 4000 : 520
            let host = NSHostingView(rootView: PopoverView(model: model, listCap: cap).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(white: 0.12, alpha: 1)
            window.contentView = host
            // A second layout pass after measured sizes settle, as the real popover gets.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                do {
                    try rep.representation(using: .png, properties: [:])?.write(to: output)
                    print("snapshot \(Int(host.bounds.width))x\(Int(host.bounds.height)) → \(output.path)")
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                    exit(1)
                }
            }
        }
    }
}
