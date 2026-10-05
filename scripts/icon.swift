import AppKit
import Foundation

// Draws the app icon from plain shapes: an H whose right stem has shifted up.
// Apple's licence does not allow SF Symbols in app icons. Proportions follow Apple's macOS icon grid:
// an 824-point body with 185-point corners on a 1024-point canvas.
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: "Hostshift.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let gold = NSColor(red: 1, green: 0.78, blue: 0.28, alpha: 1)
let tileTop = NSColor(red: 0.30, green: 0.27, blue: 0.78, alpha: 1)
let tileBottom = NSColor(red: 0.16, green: 0.13, blue: 0.45, alpha: 1)

func drawIcon(in canvas: NSRect) {
    let unit = canvas.width / 1024
    func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double, radius: Double, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit),
                     xRadius: radius * unit, yRadius: radius * unit).fill()
    }

    let body = NSBezierPath(roundedRect: NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit), xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 24 * unit
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: tileTop, ending: tileBottom)?.draw(in: body, angle: -90)

    box(323, 257, 150, 440, radius: 18, .white)    // left stem
    box(461, 425, 100, 112, radius: 0, .white)     // crossbar
    box(551, 327, 150, 440, radius: 18, gold)      // right stem, shifted up
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appending(path: "icon_\(size)x\(size)\(suffix).png"))
    }
}
