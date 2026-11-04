// Renders Resources/AppIcon.icns. Run with scripts/make-icon.sh.
import AppKit

@main
struct MakeIcon {
    static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func gradient(_ colors: [UInt32]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(color) as CFArray, locations: nil)!
    }

    /// Drawn on a 1024 canvas, y-down, using the standard macOS icon grid (824pt body).
    static func draw(in context: CGContext) {
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(shape)
        context.setFillColor(color(0x12162A))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.drawLinearGradient(gradient([0x262E52, 0x0F1322]), start: CGPoint(x: 180, y: 100),
                                   end: CGPoint(x: 844, y: 924), options: [])
        // A quiet teal glow behind the mark, top-left.
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x2FBFAE).copy(alpha: 0.28)!, color(0x2FBFAE).copy(alpha: 0)!] as CFArray,
                              locations: nil)!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 300), startRadius: 0,
                                   endCenter: CGPoint(x: 330, y: 300), endRadius: 560, options: [])
        context.restoreGState()

        // Hairline highlight around the edge.
        context.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        context.setLineWidth(3)
        context.strokePath()

        let markRect = body.insetBy(dx: 96, dy: 96)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 34, color: color(0x2FBFAE).copy(alpha: 0.45))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(GitOSMarkGeometry.graph(in: markRect))
        context.clip()
        context.drawLinearGradient(gradient([0x6FE9D3, 0x8FA4FF]), start: CGPoint(x: markRect.minX, y: markRect.minY),
                                   end: CGPoint(x: markRect.maxX, y: markRect.maxY), options: [])
        context.endTransparencyLayer()
        context.restoreGState()

        context.saveGState()
        context.setShadow(offset: .zero, blur: 30, color: color(0xFFC978).copy(alpha: 0.55))
        context.addPath(GitOSMarkGeometry.headNode(in: markRect))
        context.setFillColor(color(0xFFC978))
        context.fillPath()
        context.restoreGState()
    }

    static func png(size: Int) -> Data {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
        context.translateBy(x: 0, y: -1024)
        draw(in: context)
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }

    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try png(size: points).write(to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
            try png(size: points * 2).write(to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
    }
}
