import AppKit

// Draws AppIcon.iconset: a dark squircle with the notch biting into its top
// edge and a couple of shelf cards below it.

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

func draw(_ side: CGFloat) {
    let inset = side * 0.055
    let body = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let bodyPath = NSBezierPath(roundedRect: body,
                                xRadius: body.width * 0.2237,
                                yRadius: body.width * 0.2237)

    NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.19, alpha: 1),
               ending: NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1))?
        .draw(in: bodyPath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()

    // The notch: only its rounded bottom shows, the rest is clipped by the body.
    let notchWidth = body.width * 0.44
    let notchHeight = body.height * 0.13
    let notch = NSRect(x: body.midX - notchWidth / 2,
                       y: body.maxY - notchHeight,
                       width: notchWidth,
                       height: notchHeight * 2)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: notch,
                 xRadius: notchHeight * 0.55,
                 yRadius: notchHeight * 0.55).fill()

    // Back card, peeking out from behind.
    let backWidth = body.width * 0.44
    let backHeight = body.height * 0.26
    let back = NSRect(x: body.midX - backWidth / 2,
                      y: body.minY + body.height * 0.34,
                      width: backWidth,
                      height: backHeight)
    NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
    NSBezierPath(roundedRect: back,
                 xRadius: backHeight * 0.24,
                 yRadius: backHeight * 0.24).fill()

    // Front card with a hint of an image inside it.
    let frontWidth = body.width * 0.58
    let frontHeight = body.height * 0.32
    let front = NSRect(x: body.midX - frontWidth / 2,
                       y: body.minY + body.height * 0.17,
                       width: frontWidth,
                       height: frontHeight)
    let frontPath = NSBezierPath(roundedRect: front,
                                 xRadius: frontHeight * 0.24,
                                 yRadius: frontHeight * 0.24)
    NSGradient(starting: NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.63, green: 0.45, blue: 0.98, alpha: 1))?
        .draw(in: frontPath, angle: -60)

    NSGraphicsContext.restoreGraphicsState()
}

func render(_ pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels,
                                     pixelsHigh: pixels,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for entry in sizes {
    guard let data = render(entry.pixels) else { continue }
    try data.write(to: outputDirectory.appendingPathComponent("\(entry.name).png"))
}
print("iconset written to \(outputDirectory.path)")
