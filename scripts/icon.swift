import AppKit
import Foundation

// Draws the app icon from plain shapes: a moon warping from an inner orbit to an outer one.
// Apple's licence does not allow SF Symbols in app icons. Proportions follow Apple's macOS icon grid:
// an 824-point body with 185-point corners on a 1024-point canvas.
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: "Hostshift.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let centre = NSPoint(x: 512, y: 500)
let tilt = 24.0
let innerOrbit = (rx: 235.0, ry: 105.0)
let outerOrbit = (rx: 365.0, ry: 168.0)
let gold = NSColor(red: 1, green: 0.84, blue: 0.42, alpha: 1)

func onOrbit(_ orbit: (rx: Double, ry: Double), _ angle: Double) -> NSPoint {
    let x = orbit.rx * cos(angle), y = orbit.ry * sin(angle), t = tilt * .pi / 180
    return NSPoint(x: centre.x + x * cos(t) - y * sin(t), y: centre.y + x * sin(t) + y * cos(t))
}

func drawIcon(in canvas: NSRect) {
    let unit = canvas.width / 1024
    func scaled(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x * unit, y: p.y * unit) }
    func circle(_ p: NSPoint, _ radius: Double) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: (p.x - radius) * unit, y: (p.y - radius) * unit, width: 2 * radius * unit, height: 2 * radius * unit))
    }
    func tilted(_ path: NSBezierPath) -> NSBezierPath {
        let transform = NSAffineTransform()
        transform.translateX(by: centre.x * unit, yBy: centre.y * unit)
        transform.rotate(byDegrees: tilt)
        path.transform(using: transform as AffineTransform)
        return path
    }
    func orbitPath(_ orbit: (rx: Double, ry: Double)) -> NSBezierPath {
        tilted(NSBezierPath(ovalIn: NSRect(x: -orbit.rx * unit, y: -orbit.ry * unit, width: 2 * orbit.rx * unit, height: 2 * orbit.ry * unit)))
    }
    // The near half of each orbit lies below the tilted axis and is drawn over the planet.
    func clipToHalf(near: Bool) {
        tilted(NSBezierPath(rect: NSRect(x: -600 * unit, y: near ? -600 * unit : 0, width: 1200 * unit, height: 600 * unit))).addClip()
    }
    func strokeOrbits() {
        let inner = orbitPath(innerOrbit), outer = orbitPath(outerOrbit)
        inner.lineWidth = 14 * unit
        NSColor.white.withAlphaComponent(0.22).setStroke()
        inner.stroke()
        outer.lineWidth = 18 * unit
        NSColor.white.withAlphaComponent(0.55).setStroke()
        outer.stroke()
    }

    // Deep-space tile with stars.
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit), xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 24 * unit
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.22, green: 0.17, blue: 0.52, alpha: 1), NSColor(red: 0.06, green: 0.05, blue: 0.17, alpha: 1)])?
        .draw(in: body, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    var seed: UInt64 = 42
    func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(1 << 31)
    }
    for _ in 0..<34 {
        let star = NSPoint(x: 130 + random() * 764, y: 130 + random() * 764)
        NSColor.white.withAlphaComponent(0.3 + random() * 0.55).setFill()
        circle(star, 2 + random() * 3.5).fill()
    }

    // Far half of the orbits, then the planet, then the near half.
    NSGraphicsContext.saveGraphicsState()
    clipToHalf(near: false)
    strokeOrbits()
    NSGraphicsContext.restoreGraphicsState()
    let planet = circle(centre, 140)
    NSGradient(starting: NSColor.systemTeal, ending: NSColor.systemIndigo)?.draw(in: planet, angle: -60)
    NSGraphicsContext.saveGraphicsState()
    planet.addClip()
    NSColor.black.withAlphaComponent(0.28).setFill()
    circle(NSPoint(x: centre.x + 70, y: centre.y - 70), 150).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clipToHalf(near: true)
    strokeOrbits()
    NSGraphicsContext.restoreGraphicsState()

    // Where the moon left from, and warp streaks trailing it onto the outer orbit.
    NSColor.white.withAlphaComponent(0.3).setFill()
    circle(onOrbit(innerOrbit, 0.3), 20).fill()
    let moonAngle = 0.9
    let moon = onOrbit(outerOrbit, moonAngle)
    // Streaks follow arcs parallel to the outer orbit, trailing behind the moon's direction of travel.
    for (offset, span, width, alpha) in [(-32.0, 0.5, 13.0, 0.85), (0.0, 0.75, 18.0, 1.0), (32.0, 0.38, 13.0, 0.85)] {
        let radii = (rx: outerOrbit.rx + offset, ry: outerOrbit.ry + offset * outerOrbit.ry / outerOrbit.rx)
        let streak = NSBezierPath()
        let steps = 24
        for step in 0...steps {
            let angle = moonAngle - 0.11 - span * Double(step) / Double(steps)
            let point = scaled(onOrbit(radii, angle))
            step == 0 ? streak.move(to: point) : streak.line(to: point)
        }
        streak.lineWidth = width * unit
        streak.lineCapStyle = .round
        streak.lineJoinStyle = .round
        (offset == 0 ? NSColor.white : NSColor.systemTeal).withAlphaComponent(alpha).setStroke()
        streak.stroke()
    }
    NSGradient(colors: [gold.withAlphaComponent(0.5), gold.withAlphaComponent(0)])?.draw(in: circle(moon, 62), relativeCenterPosition: .zero)
    gold.setFill()
    circle(moon, 38).fill()
    NSColor.white.setFill()
    circle(NSPoint(x: moon.x - 8, y: moon.y + 8), 18).fill()
    NSGraphicsContext.restoreGraphicsState()
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
