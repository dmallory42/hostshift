import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: "Hostshift.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = bounds.insetBy(dx: Double(pixels) * 0.07, dy: Double(pixels) * 0.07)
        let background = NSBezierPath(roundedRect: inset, xRadius: Double(pixels) * 0.19, yRadius: Double(pixels) * 0.19)
        NSGradient(starting: NSColor.systemTeal, ending: NSColor.systemIndigo)?.draw(in: background, angle: -70)
        let config = NSImage.SymbolConfiguration(pointSize: Double(pixels) * 0.49, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let rect = NSRect(x: Double(pixels) * 0.23, y: Double(pixels) * 0.23, width: Double(pixels) * 0.54, height: Double(pixels) * 0.54)
            symbol.draw(in: rect)
        }
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: output.appending(path: "icon_\(size)x\(size)\(suffix).png"))
        }
    }
}
