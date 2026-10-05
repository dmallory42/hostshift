import AppKit

extension NSImage {
    /// The app icon's shifted H as an 18-point template image, so macOS tints it for the menu bar.
    @MainActor static var menuBarIcon: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            // Shapes match scripts/icon.swift, scaled from the H's 378 × 510-point bounds on its 1024-point canvas.
            let scale = 14.0 / 510
            let originX = (18 - 378 * scale) / 2 - 323 * scale
            let originY = 2 - 257 * scale
            NSColor.black.setFill()
            for (x, y, width, height, radius) in [(323.0, 257.0, 150.0, 440.0, 18.0), (461, 425, 100, 112, 0), (551, 327, 150, 440, 18)] {
                NSBezierPath(roundedRect: NSRect(x: originX + x * scale, y: originY + y * scale, width: width * scale, height: height * scale),
                             xRadius: radius * scale, yRadius: radius * scale).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
