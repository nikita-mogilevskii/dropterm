import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconsetPath = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func draw(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let inset = rect.insetBy(dx: s * 0.08, dy: s * 0.08)
    let background = NSBezierPath(roundedRect: inset, xRadius: s * 0.2, yRadius: s * 0.2)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.15, alpha: 1),
        ending: NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.23, alpha: 1))!
    gradient.draw(in: background, angle: -60)

    // Terminal prompt ">_" glyph
    let glyphRect = inset.insetBy(dx: inset.width * 0.2, dy: inset.height * 0.2)
    let fontSize = s * 0.42

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95)
    ]

    let glyph = NSAttributedString(string: ">_", attributes: attributes)
    let glyphSize = glyph.size()
    let glyphOrigin = NSPoint(
        x: glyphRect.midX - glyphSize.width / 2,
        y: glyphRect.midY - glyphSize.height / 2
    )
    glyph.draw(at: glyphOrigin)

    image.unlockFocus()
    return image
}

for size in sizes {
    let image = draw(size: size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    if size < 1024 {
        try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size).png"))
    }
    if size >= 32 {
        try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}
print("Wrote \(iconsetPath)")
