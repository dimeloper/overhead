import AppKit
import SwiftUI

/// `Overhead --snapshot <file.png> [--full] [--park <project>] [--demo]` renders the popover offscreen once real samples are in, writes a PNG and quits.
/// `--demo` uses made-up projects instead of this Mac's, for the README.
/// It lays the view out in a real window, so scroll views, pickers and buttons render as they do on screen.
@MainActor
enum Snapshot {
    /// The Settings window, laid out in a real window like the popover.
    static func settings(_ model: OverheadModel) throws -> Data {
        let host = NSHostingView(rootView: SettingsView(model: model, updater: Updater()))
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return try png(of: host)
    }

    /// The view drawn at 2x, as a Retina screen shows it, whatever screen (if any) the offscreen window is on.
    static func png(of view: NSView, scale: Int = 2) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * scale, pixelsHigh: Int(view.bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return png
    }

    /// The menu bar image as macOS tints it: once on a light bar, once on a dark one, at 4x so it can be read.
    static func menuBar(_ readout: MenuBarReadout, layoutCheck: Bool = true) throws -> Data {
        let strip = VStack(alignment: .leading, spacing: 0) {
            readout.padding(.horizontal, 8).frame(height: 24).background(Color(white: 0.92))
            readout.colorInvert().padding(.horizontal, 8).frame(height: 24).background(Color(white: 0.12))
            // Layout check for the unplugged case, which a plugged-in Mac cannot show for real.
            if layoutCheck { MenuBarReadout(columns: [
                .init(label: "CPU", value: "100%", widest: "100%"),
                .init(label: "MEM", value: "100%", widest: "100%"),
                .init(label: "BAT", value: "10:00", widest: "10:00"),
            ], holdingAwake: true)
                .padding(.horizontal, 8).frame(height: 24).background(Color(white: 0.92)) }
        }
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 4
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    static func runIfRequested(model: OverheadModel) {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return }
        let output = URL(fileURLWithPath: arguments[flag + 1])

        // `--park <project>` opens that project's Park panel first, the way clicking Park does.
        if let park = arguments.firstIndex(of: "--park"), park + 1 < arguments.count {
            let name = arguments[park + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if let project = model.attribution.projects.first(where: { $0.project.name == name })?.project {
                    model.preparePark(project)
                } else {
                    FileHandle.standardError.write(Data("no running project named \(name)\n".utf8))
                }
            }
        }

        // Two samples are needed before CPU figures exist; the ports scan runs on the first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            // `--full` lifts the scroll cap so every section is in the picture.
            let cap: CGFloat = arguments.contains("--full") ? 4000 : 520
            let host = NSHostingView(rootView: PopoverView(model: model, updater: Updater(), listCap: cap).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(white: 0.12, alpha: 1)
            window.contentView = host
            // A second layout pass after measured sizes settle, as the real popover gets.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                do {
                    try png(of: host).write(to: output)
                    try menuBar(model.menuReadout, layoutCheck: !model.isDemo).write(to: output.deletingPathExtension().appendingPathExtension("menubar.png"))
                    try settings(model).write(to: output.deletingPathExtension().appendingPathExtension("settings.png"))
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
