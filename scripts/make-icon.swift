// Renders the 1024×1024 app icon PNG. Usage: swift scripts/make-icon.swift out.png
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Squircle tile (macOS icon grid: 824pt tile centered in 1024).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.26, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.09, alpha: 1),
])!.draw(in: tilePath, angle: -90)

// Soft glow beneath the notch.
NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
let glowCenter = NSPoint(x: 512, y: 640)
NSGradient(colors: [
    NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.55, alpha: 0.55),
    NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.95, alpha: 0.25),
    NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.2, alpha: 0),
])!.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 360, options: [])

// Expanded notch: flares into the top edge, rounded bottom.
let notchTop = tile.maxY
let body = NSRect(x: 232, y: 560, width: 560, height: notchTop - 560)
let flare: CGFloat = 36
let corner: CGFloat = 90
let notch = NSBezierPath()
notch.move(to: NSPoint(x: body.minX - flare, y: notchTop))
notch.curve(to: NSPoint(x: body.minX, y: notchTop - flare),
            controlPoint1: NSPoint(x: body.minX - flare / 2, y: notchTop),
            controlPoint2: NSPoint(x: body.minX, y: notchTop - flare / 2))
notch.line(to: NSPoint(x: body.minX, y: body.minY + corner))
notch.curve(to: NSPoint(x: body.minX + corner, y: body.minY),
            controlPoint1: NSPoint(x: body.minX, y: body.minY + corner * 0.45),
            controlPoint2: NSPoint(x: body.minX + corner * 0.45, y: body.minY))
notch.line(to: NSPoint(x: body.maxX - corner, y: body.minY))
notch.curve(to: NSPoint(x: body.maxX, y: body.minY + corner),
            controlPoint1: NSPoint(x: body.maxX - corner * 0.45, y: body.minY),
            controlPoint2: NSPoint(x: body.maxX, y: body.minY + corner * 0.45))
notch.line(to: NSPoint(x: body.maxX, y: notchTop - flare))
notch.curve(to: NSPoint(x: body.maxX + flare, y: notchTop),
            controlPoint1: NSPoint(x: body.maxX, y: notchTop - flare / 2),
            controlPoint2: NSPoint(x: body.maxX + flare / 2, y: notchTop))
notch.close()
NSColor.black.setFill()
notch.fill()

// Album art tile.
let art = NSRect(x: 290, y: 615, width: 150, height: 150)
let artPath = NSBezierPath(roundedRect: art, xRadius: 30, yRadius: 30)
NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.45, blue: 0.45, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.25, blue: 0.95, alpha: 1),
])!.draw(in: artPath, angle: -45)

// Equalizer bars.
let heights: [CGFloat] = [70, 130, 95, 150, 60]
for (index, height) in heights.enumerated() {
    let x = 520 + CGFloat(index) * 46
    let bar = NSRect(x: x, y: 690 - height / 2, width: 26, height: height)
    NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.7, alpha: 1).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 13, yRadius: 13).fill()
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
