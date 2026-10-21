import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let edge = CGFloat(pixels)
        NSColor(calibratedRed: 0.19, green: 0.33, blue: 0.29, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: edge, height: edge), xRadius: edge * 0.23, yRadius: edge * 0.23).fill()
        let symbol = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: edge * 0.56, weight: .medium))!
        let white = NSImage(size: symbol.size)
        white.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        white.unlockFocus()
        white.draw(in: NSRect(x: edge * 0.22, y: edge * 0.2, width: edge * 0.56, height: edge * 0.6))
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: output.appendingPathComponent(name))
    }
}
