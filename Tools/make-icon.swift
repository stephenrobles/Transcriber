// Renders the Transcriber app icon: an audio waveform turning into lines of text, on a purple tile.
//
// Usage: swift Tools/make-icon.swift <output-dir>
// Writes icon_<size>.png for 16…1024 (rounded macOS tile with shadow) into <output-dir>.
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// macOS-style continuous-corner tile (superellipse) inside the standard 824pt icon grid.
func tilePath() -> CGPath {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGMutablePath()
    let n: CGFloat = 5
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func fill(_ path: CGPath, in context: CGContext, gradient colors: [CGColor], locations: [CGFloat], from start: CGPoint, to end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip(using: .winding)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

/// The glyph: a waveform on the left that rises bar by bar until it is as tall as the block of
/// text lines on the right, so the sound reads as turning into text. Both halves are the same
/// width, and everything is a rounded rectangle so it still reads at 16 px.
func glyphPaths() -> [CGPath] {
    var shapes: [CGPath] = []
    let centerY: CGFloat = 512
    let thickness: CGFloat = 42
    let gapBetweenHalves: CGFloat = 48

    // Text block: four lines, spacing 80 → 282 tall. The waveform's last bar matches that height.
    let lineSpacing: CGFloat = 80
    let lineLengths: [CGFloat] = [234, 176, 214, 136]
    let blockHeight = lineSpacing * CGFloat(lineLengths.count - 1) + thickness

    // Waveform: four bars, each taller than the last, ending at the text block's height.
    let barHeights: [CGFloat] = [96, 164, 228, blockHeight]
    let barGap: CGFloat = 22
    let waveformWidth = CGFloat(barHeights.count) * thickness + CGFloat(barHeights.count - 1) * barGap
    let textWidth = lineLengths.max() ?? 0
    let totalWidth = waveformWidth + gapBetweenHalves + textWidth
    var x = 512 - totalWidth / 2
    for height in barHeights {
        let rect = CGRect(x: x, y: centerY - height / 2, width: thickness, height: height)
        shapes.append(CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
        x += thickness + barGap
    }

    let lineLeft = x - barGap + gapBetweenHalves
    let firstY = centerY + blockHeight / 2 - thickness / 2
    for (i, length) in lineLengths.enumerated() {
        let y = firstY - CGFloat(i) * lineSpacing
        let rect = CGRect(x: lineLeft, y: y - thickness / 2, width: length, height: thickness)
        shapes.append(CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
    }
    return shapes
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    context.setShouldAntialias(true)

    let tile = tilePath()

    // Drop shadow under the tile, as on system icons.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    context.addPath(tile)
    context.setFillColor(color(0x4B22B5))
    context.fillPath()
    context.restoreGState()

    // Purple tile, lighter and warmer at the top.
    fill(tile, in: context, gradient: [color(0xA06CFF), color(0x7B45F2), color(0x4E22C0)], locations: [0, 0.55, 1],
         from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

    // Soft glow behind the glyph.
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xD9C4FF, 0.42), color(0xD9C4FF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540), endRadius: 420, options: [])
    context.restoreGState()

    // Glyph: shadow, then a white → pale lavender gradient.
    for path in glyphPaths() {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x24105E, 0.45))
        context.addPath(path)
        context.setFillColor(color(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
        fill(path, in: context, gradient: [color(0xFFFFFF), color(0xEDE4FF)], locations: [0, 1],
             from: CGPoint(x: 512, y: 800), to: CGPoint(x: 512, y: 224))
    }

    // Subtle inner rim on the tile.
    context.saveGState()
    context.addPath(tile)
    context.setStrokeColor(color(0xFFFFFF, 0.14))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(size: size).write(to: output.appending(path: "icon_\(size).png"))
}
print("Wrote icons to \(output.path)")
