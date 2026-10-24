import AppKit

// Generate both resolutions from the same vector layout; Finder uses the HiDPI TIFF.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 760.0
let height = 440.0
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1).cgColor
}

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
        pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setFillColor(color(1, 1, 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let wave = CGMutablePath()
    wave.move(to: CGPoint(x: 300, y: 440))
    wave.addCurve(to: CGPoint(x: 310, y: 0), control1: CGPoint(x: 480, y: 240),
                  control2: CGPoint(x: 450, y: 175))
    wave.addLine(to: CGPoint(x: 760, y: 0))
    wave.addLine(to: CGPoint(x: 760, y: 440))
    wave.closeSubpath()
    context.saveGState()
    context.addPath(wave)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(1, 0.95, 0.86), color(1, 0.98, 0.96), color(0.94, 0.96, 1)] as CFArray,
        locations: [0, 0.55, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 420, y: 0),
                               end: CGPoint(x: 600, y: 440), options: [])
    context.restoreGState()

    func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
              ink: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 40, y: y, width: 680, height: size + 12),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                             .foregroundColor: ink, .paragraphStyle: paragraph])
    }
    text("HlgBridge", y: 362, size: 27, weight: .semibold,
         ink: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1))
    text("让 HLG 照片自然呈现", y: 331, size: 14, weight: .regular, ink: .secondaryLabelColor)

    // The two actual icons and their labels are Finder items, not part of this image.
    context.setStrokeColor(color(0.86, 0.58, 0.23))
    context.setLineWidth(3.5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 351, y: 220))
    context.addLine(to: CGPoint(x: 409, y: 220))
    context.move(to: CGPoint(x: 398, y: 231))
    context.addLine(to: CGPoint(x: 409, y: 220))
    context.addLine(to: CGPoint(x: 398, y: 209))
    context.strokePath()

    text("将 HlgBridge 拖到「应用程序」即可安装", y: 62, size: 17,
         weight: .medium, ink: NSColor(srgbRed: 0.25, green: 0.27, blue: 0.31, alpha: 1))
    text("安装完成后，可推出此磁盘", y: 32, size: 12, weight: .regular,
         ink: .secondaryLabelColor)
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
