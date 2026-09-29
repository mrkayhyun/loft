// Renders Burrow's 1024×1024 app icon to the path given as the first argument.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let canvas: CGFloat = 1024
let inset: CGFloat = 100 // macOS icon grid: artwork sits inside an 824pt squircle
let radius: CGFloat = 186

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.png>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

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

    // Violet → magenta body with a deep base in the lower corner.
    let body = NSGradient(colors: [
        NSColor(red: 0.98, green: 0.45, blue: 0.95, alpha: 1),
        NSColor(red: 0.49, green: 0.42, blue: 1.0, alpha: 1),
        NSColor(red: 0.16, green: 0.1, blue: 0.42, alpha: 1),
    ], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    body.draw(in: squircle, angle: -60)

    // Glossy top highlight.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
    gloss.draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Burrow opening: a soft dark ellipse.
    let hole = NSRect(x: tile.midX - 250, y: tile.minY + 120, width: 500, height: 150)
    NSGradient(colors: [NSColor.black.withAlphaComponent(0.55), NSColor.black.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(ovalIn: hole), relativeCenterPosition: .zero)

    // White hare glyph peeking out of the burrow.
    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = glyph.size
        let origin = NSPoint(x: tile.midX - size.width / 2, y: tile.minY + 190)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        glow.shadowBlurRadius = 18
        glow.shadowOffset = NSSize(width: 0, height: -8)
        glow.set()
        glyph.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

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
