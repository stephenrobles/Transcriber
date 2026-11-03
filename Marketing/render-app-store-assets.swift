import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// App Store product page header (3840x1646), search results (3840x2560) and Apple's 16:9
// universal size (5244x2950) for Transcriber, in the house style set by Kan Do, Stash and
// Captioner: the app's own gradient, one bold headline, an iPhone and an iPad in Apple's
// bezels running off the bottom edge. Canvas and bezel code is Kan Do's.
// Usage: swift Marketing/render-app-store-assets.swift   (from the repo root)

final class Canvas {
    let w: Int, h: Int
    let ctx: CGContext
    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
    }
    func cg(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height) }

    func fillGradient(_ colors: [NSColor], locations: [CGFloat], from p1: CGPoint, to p2: CGPoint) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: colors.map(\.cgColor) as CFArray, locations: locations)!
        ctx.drawLinearGradient(g, start: cg(CGRect(origin: p1, size: .zero)).origin,
                               end: cg(CGRect(origin: p2, size: .zero)).origin, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Apple's official Product Bezel (PNG with a transparent screen cutout) over a capture.
    func appleDevice(bezel: CGImage, capture: CGImage, cutout: CGRect, screenRadius: CGFloat, in rect: CGRect, bodyInset: CGFloat, bodyRadius: CGFloat) {
        let k = rect.width / CGFloat(bezel.width)
        let body = rect.insetBy(dx: bodyInset * k, dy: bodyInset * k)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -40), blur: 110, color: NSColor.black.withAlphaComponent(0.40).cgColor)
        ctx.addPath(CGPath(roundedRect: cg(body), cornerWidth: bodyRadius * k, cornerHeight: bodyRadius * k, transform: nil))
        ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor); ctx.fillPath()
        ctx.restoreGState()
        let screen = CGRect(x: rect.minX + cutout.minX * k, y: rect.minY + cutout.minY * k,
                            width: cutout.width * k, height: cutout.height * k)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: cg(screen), cornerWidth: screenRadius * k, cornerHeight: screenRadius * k, transform: nil))
        ctx.clip()
        ctx.draw(capture, in: cg(screen))
        ctx.restoreGState()
        ctx.draw(bezel, in: cg(rect))
    }

    func text(_ s: String, font: NSFont, color: NSColor, at origin: CGPoint, align: NSTextAlignment = .left, maxWidth: CGFloat = 10_000, lineSpacing: CGFloat = 0) -> CGSize {
        let para = NSMutableParagraphStyle(); para.alignment = align; para.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let str = NSAttributedString(string: s, attributes: attrs)
        let size = str.boundingRect(with: CGSize(width: maxWidth, height: 5000), options: [.usesLineFragmentOrigin]).size
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        var x = origin.x
        if align == .center { x = origin.x - size.width / 2 }
        let rect = CGRect(x: x, y: origin.y, width: size.width, height: size.height)
        str.draw(with: cg(rect), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        return size
    }

    func save(_ path: String) {
        let img = ctx.makeImage()!
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for (type, ext) in [(UTType.png, "png"), (UTType.jpeg, "jpg")] {
            let dest = CGImageDestinationCreateWithURL(url.deletingPathExtension().appendingPathExtension(ext) as CFURL, type.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
        print("wrote \(path) (+.jpg) \(img.width)x\(img.height)")
    }
}

func load(_ path: String) -> CGImage {
    guard let img = NSImage(contentsOfFile: path) else { fatalError("missing \(path)") }
    var rect = CGRect(origin: .zero, size: img.size)
    return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

/// Apple ships the 13" iPad Pro bezel in landscape; rotating it puts the camera on the long edge, as in portrait.
func rotatedCCW(_ image: CGImage) -> CGImage {
    let w = image.height, h = image.width
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(h))
    c.rotate(by: -.pi / 2)
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return c.makeImage()!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().path
let white = NSColor.white
func display(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont { NSFont.systemFont(ofSize: size, weight: weight) }
func hex(_ v: UInt32) -> NSColor { NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1) }

let bezelPhone = load("\(root)/Marketing/Bezels/iphone17pro-silver-portrait.png")   // 1350x2760, screen at (72,69) 1206x2622
let phoneCut = CGRect(x: 72, y: 69, width: 1206, height: 2622)
let bezelPad13 = rotatedCCW(load("\(root)/Marketing/Bezels/ipadpro13-silver-landscape.png")) // 2300x3000, screen at (118,124) 2064x2752
let pad13Cut = CGRect(x: 118, y: 124, width: 2064, height: 2752)

// Transcriber's icon gradient (Tools/make-icon.swift): lavender → violet → deep purple.
let gradient = [hex(0xA06CFF), hex(0x7B45F2), hex(0x4E22C0)]
let stops: [CGFloat] = [0, 0.55, 1]
let headline = "Every word,\non your device."
let searchHeadline = "Transcripts and subtitles, made on your device"
let phone = load("\(root)/AppStore/screenshots/iphone-1-player.png")   // 1206x2622
let pad = load("\(root)/AppStore/screenshots/ipad-1-player.png")       // 2064x2752

do { // Header 21:9: headline left, iPad behind on the right, iPhone in front, both off the bottom.
    let c = Canvas(3840, 1646)
    c.fillGradient(gradient, locations: stops, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 3840, y: 1646))
    c.ctx.saveGState()
    c.ctx.setFillColor(NSColor(white: 1, alpha: 0.06).cgColor)
    c.ctx.fillEllipse(in: c.cg(CGRect(x: 1500, y: -300, width: 2600, height: 2400)))
    c.ctx.restoreGState()
    _ = c.text(headline, font: display(150, .bold), color: white, at: CGPoint(x: 400, y: 640), maxWidth: 1300, lineSpacing: 4)
    let padW: CGFloat = 1500
    c.appleDevice(bezel: bezelPad13, capture: pad, cutout: pad13Cut, screenRadius: 54,
                  in: CGRect(x: 2300, y: 230, width: padW, height: padW * 3000 / 2300), bodyInset: 28, bodyRadius: 160)
    let phW: CGFloat = 840
    c.appleDevice(bezel: bezelPhone, capture: phone, cutout: phoneCut, screenRadius: 186,
                  in: CGRect(x: 1760, y: 380, width: phW, height: phW * 2760 / 1350), bodyInset: 16, bodyRadius: 215)
    c.save("\(root)/Marketing/AppStore/Transcriber-ProductPageHeader-3840x1646.png")
}
// Search results 3:2, and Apple's 16:9 "universal" size that can fill both placements.
for (W, H, suffix) in [(3840, 2560, "SearchResults-3840x2560"), (5244, 2950, "Universal-16x9-5244x2950")] {
    let c = Canvas(W, H)
    let w = CGFloat(W), h = CGFloat(H)
    c.fillGradient(gradient, locations: stops, from: CGPoint(x: 0, y: 0), to: CGPoint(x: w, y: h))
    c.ctx.saveGState()
    c.ctx.setFillColor(NSColor(white: 1, alpha: 0.06).cgColor)
    c.ctx.fillEllipse(in: c.cg(CGRect(x: w * 0.135, y: h * 0.35, width: w * 0.73, height: h * 1.02)))
    c.ctx.restoreGState()
    _ = c.text(searchHeadline, font: display(w * 0.0406, .bold), color: white, at: CGPoint(x: w / 2, y: h * 0.12), align: .center)
    let padW = w * 0.58
    c.appleDevice(bezel: bezelPad13, capture: pad, cutout: pad13Cut, screenRadius: 54,
                  in: CGRect(x: w * 0.33, y: h * 0.30, width: padW, height: padW * 3000 / 2300), bodyInset: 28, bodyRadius: 160)
    let phW = w * 0.30
    c.appleDevice(bezel: bezelPhone, capture: phone, cutout: phoneCut, screenRadius: 186,
                  in: CGRect(x: w * 0.10, y: h * 0.40, width: phW, height: phW * 2760 / 1350), bodyInset: 16, bodyRadius: 215)
    c.save("\(root)/Marketing/AppStore/Transcriber-\(suffix).png")
}
