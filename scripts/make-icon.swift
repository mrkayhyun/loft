// Renders Loft's 1024×1024 app icon to the path given as the first argument.
// Usage: swift scripts/make-icon.swift out.png
//
// The mark (gable roof + skylight) is drawn from primitives — no SF Symbols,
// whose license forbids use in app icons. Geometry matches LoftMark.swift.
import AppKit

let canvas: CGFloat = 1024
let inset: CGFloat = 100 // macOS icon grid: artwork sits inside an 824pt squircle
let radius: CGFloat = 186

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.png>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

/// Unit-square point (y up) → tile coordinates.
func point(_ x: CGFloat, _ y: CGFloat, in tile: NSRect) -> NSPoint {
    NSPoint(x: tile.minX + x * tile.width, y: tile.minY + y * tile.height)
}

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    let tile = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // Drop shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Dawn sky: warm peach at the top fading into violet and deep indigo.
    let body = NSGradient(colors: [
        NSColor(red: 1.0, green: 0.72, blue: 0.55, alpha: 1),
        NSColor(red: 0.62, green: 0.45, blue: 1.0, alpha: 1),
        NSColor(red: 0.13, green: 0.1, blue: 0.38, alpha: 1),
    ], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    body.draw(in: squircle, angle: -90)

    // Glossy top highlight.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.3), NSColor.white.withAlphaComponent(0)])!
    gloss.draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    glow.shadowBlurRadius = 20
    glow.shadowOffset = NSSize(width: 0, height: -10)
    glow.set()
    NSColor.white.set()

    // Gable roof.
    let roof = NSBezierPath()
    roof.move(to: point(0.2, 0.38, in: tile))
    roof.line(to: point(0.5, 0.7, in: tile))
    roof.line(to: point(0.8, 0.38, in: tile))
    roof.lineWidth = tile.width * 0.09
    roof.lineCapStyle = .round
    roof.lineJoinStyle = .round
    roof.stroke()

    // Skylight.
    let window = tile.width * 0.075
    let center = point(0.5, 0.44, in: tile)
    NSBezierPath(ovalIn: NSRect(x: center.x - window, y: center.y - window, width: window * 2, height: window * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Hairline edge.
    NSColor.white.withAlphaComponent(0.22).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()
    return true
}

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
do {
    try png.write(to: output)
} catch {
    FileHandle.standardError.write(Data("cannot write \(output.path): \(error)\n".utf8))
    exit(1)
}
