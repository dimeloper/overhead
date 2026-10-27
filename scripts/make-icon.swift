// Draws the app icon into an .iconset folder: a dark tile with three bars, the projects of the popover's memory bar,
// in the brand colours. Usage: swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
let orange = color(0.984, 0.573, 0.235)
let pink = color(0.925, 0.282, 0.600)
let lilac = color(0.655, 0.545, 0.980)
let teal = color(0.369, 0.918, 0.831)

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: an 824 pt tile centred in 1024, corner radius about 185.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: color(0.17, 0.17, 0.19), ending: color(0.07, 0.07, 0.08))!.draw(in: shape, angle: -90)
    color(1, 1, 1).withAlphaComponent(0.08).setStroke()
    shape.lineWidth = 4
    shape.stroke()

    // Three bars, longest first, each on a faint full-length track.
    let left: CGFloat = 230, full: CGFloat = 564, height: CGFloat = 92
    let bars: [(y: CGFloat, length: CGFloat, colors: [NSColor])] = [
        (612, 0.86, [orange, pink]),
        (466, 0.62, [lilac, lilac]),
        (320, 0.38, [teal, teal]),
    ]
    for bar in bars {
        let track = NSBezierPath(roundedRect: NSRect(x: left, y: bar.y, width: full, height: height), xRadius: height / 2, yRadius: height / 2)
        color(1, 1, 1).withAlphaComponent(0.09).setFill()
        track.fill()
        let fill = NSBezierPath(roundedRect: NSRect(x: left, y: bar.y, width: full * bar.length, height: height), xRadius: height / 2, yRadius: height / 2)
        NSGradient(colors: bar.colors)!.draw(in: fill, angle: 0)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try draw(pixels: points).write(to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(pixels: points * 2).write(to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print(out.path)
