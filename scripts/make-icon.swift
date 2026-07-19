// Renders the DiskVis app icon (sunburst on a dark squircle) at every size
// macOS wants, as an .iconset folder. Run via scripts/make-icon.sh.
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

/// Slice fractions and ring structure, echoing the in-app chart.
let slices: [(fraction: Double, hue: Double)] = [
    (0.34, 0.08),   // orange
    (0.22, 0.70),   // indigo
    (0.16, 0.33),   // green
    (0.12, 0.93),   // pink
    (0.09, 0.55),   // blue
    (0.07, 0.13),   // yellow
]

func draw(canvas: CGFloat, into ctx: CGContext) {
    let scale = canvas / 1024.0

    // Standard macOS icon grid: content squircle is 824pt of a 1024pt canvas.
    let content: CGFloat = 824 * scale
    let origin = (canvas - content) / 2
    let rect = CGRect(x: origin, y: origin, width: content, height: content)
    let radius = content * 0.2237

    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow like system icons
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10 * scale),
        blur: 24 * scale,
        color: CGColor(gray: 0, alpha: 0.35)
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Dark background gradient
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bgColors = [
        CGColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1),
        CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: canvas / 2, y: rect.maxY),
            end: CGPoint(x: canvas / 2, y: rect.minY),
            options: []
        )
    }

    // Sunburst
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let hole = content * 0.175
    let ringWidth = content * 0.135
    let gapAngle = 0.022  // radians between slices

    func color(hue: Double, ring: Int) -> CGColor {
        NSColor(
            hue: hue,
            saturation: ring == 0 ? 0.72 : 0.58,
            brightness: ring == 0 ? 0.88 : 0.96,
            alpha: 1
        ).cgColor
    }

    // Deterministic subdivision of each slice's outer ring ("children" look)
    let outerParts = [3, 2, 3, 2, 2, 1]

    var angle = Double.pi / 2  // start at 12 o'clock, go clockwise
    for (sliceIndex, slice) in slices.enumerated() {
        let sweep = slice.fraction * 2 * .pi
        for ring in 0..<2 {
            let inner = hole + CGFloat(ring) * (ringWidth + 3 * scale)
            let outer = inner + ringWidth
            let parts = ring == 0 ? 1 : outerParts[sliceIndex]
            var partStart = angle
            for p in 0..<parts {
                let partSweep = sweep / Double(parts)
                // Outer ring slightly shorter arcs, staggered brightness
                let a0 = partStart - (p == 0 ? 0 : gapAngle / 2)
                let a1 = partStart - partSweep + (p == parts - 1 ? 0 : gapAngle / 2)
                let path = CGMutablePath()
                path.addArc(center: center, radius: outer, startAngle: a0 - gapAngle, endAngle: a1 + gapAngle, clockwise: true)
                path.addArc(center: center, radius: inner, startAngle: a1 + gapAngle, endAngle: a0 - gapAngle, clockwise: false)
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(color(hue: slice.hue, ring: ring))
                ctx.fillPath()
                partStart -= partSweep
            }
        }
        angle -= sweep
    }

    // Center dot
    let dotRadius = hole * 0.55
    ctx.setFillColor(CGColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1))
    ctx.fillEllipse(in: CGRect(
        x: center.x - dotRadius, y: center.y - dotRadius,
        width: dotRadius * 2, height: dotRadius * 2
    ))
    ctx.restoreGState()
}

func writePNG(size: Int, name: String) {
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }
    draw(canvas: CGFloat(size), into: ctx)
    guard let image = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png"))
}

for (points, scaleSuffix) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scaleSuffix
    let name = scaleSuffix == 1 ? "icon_\(points)x\(points)" : "icon_\(points)x\(points)@2x"
    writePNG(size: pixels, name: name)
}
print("iconset written to \(outputDir)")
