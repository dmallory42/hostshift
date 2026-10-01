import AppKit
import Foundation

// Draws the disk image background at 1x and 2x. Icon positions in package-dmg.sh match the arrow ends.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 600, height: 400)
for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGradient(starting: NSColor(white: 0.97, alpha: 1), ending: NSColor(white: 0.90, alpha: 1))?
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: 210))
    arrow.line(to: NSPoint(x: 340, y: 210))
    arrow.move(to: NSPoint(x: 326, y: 222))
    arrow.line(to: NSPoint(x: 342, y: 210))
    arrow.line(to: NSPoint(x: 326, y: 198))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(white: 0.55, alpha: 1).setStroke()
    arrow.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSAttributedString(string: "Drag Hostshift to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(white: 0.35, alpha: 1),
        .paragraphStyle: paragraph,
    ]).draw(in: NSRect(x: 0, y: 60, width: size.width, height: 24))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: output.appending(path: scale == 2 ? "background@2x.png" : "background.png"))
}
