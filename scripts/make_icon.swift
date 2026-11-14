// Generate the VRMC app icon set (assets/branding/*.appiconset) with CoreGraphics.
//
// Usage:  swift scripts/make_icon.swift [assets/branding] [--preview DIR]
//
// Design ("portal"): the round visionOS icon is a lens looking out onto a blocky world: stepped voxel
// hills in three depth layers under a dawn sky with a pixel sun, and one glowing block floating in
// front (the block you are about to pinch). The dark variant is the same scene at night (moon, stars).
// Original art: no game textures or logos, no text. visionOS masks app icons to a circle, so the
// composition and the lens rim are built for the circle; iOS-style variants (dark/tinted) are emitted
// for the Amethyst asset catalog as before.
//
// Outputs (1024x1024 PNG, sRGB):
//   AppIcon-Light.appiconset/1024x1024.png                   dawn scene (default)
//   AppIcon-Light.appiconset/1024x1024-Transparent.png       floating block glyph on transparent (iOS dark)
//   AppIcon-Light.appiconset/1024x1024-Monochrome-White.png  grayscale glyph (iOS tinted)
//   AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png       night scene
//   AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png  dawn scene + amber dev ring
// --preview DIR also writes circle-masked previews (what visionOS shows) and a contact sheet.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let S = CGFloat(size)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xff) / 255,
                                           CGFloat((hex >> 8) & 0xff) / 255,
                                           CGFloat(hex & 0xff) / 255, a])!
}

func makeContext() -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw in a top-left origin space (y down), like the design notes.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
}

func polygon(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * S, y: y * S) }

// MARK: palettes

struct Palette {
    var sky: [UInt32]                 // top -> horizon
    var skyStops: [CGFloat]
    var orb: UInt32                   // sun or moon
    var orbGlow: UInt32
    var orbGlowAlpha: CGFloat
    var hills: [(top: UInt32, bottom: UInt32)]   // far -> near
    var cap: UInt32                   // lit top edge of the near hills
    var stars: Bool
}

let dawn = Palette(
    sky: [0x111845, 0x2E3487, 0x7C4FAE, 0xE7778A, 0xFFB07A],
    skyStops: [0, 0.30, 0.50, 0.62, 0.70],
    orb: 0xFFE7A3, orbGlow: 0xFFB36B, orbGlowAlpha: 0.75,
    hills: [(0x8A5BB0, 0x6E4A9E), (0x3E4C9A, 0x2A3378), (0x0F6F73, 0x0A3C4F)],
    cap: 0x45D6B0, stars: false)

let night = Palette(
    sky: [0x03061A, 0x0A1238, 0x18205A, 0x2B2E72, 0x3A3A86],
    skyStops: [0, 0.30, 0.50, 0.62, 0.70],
    orb: 0xEEF2FF, orbGlow: 0x8FA4FF, orbGlowAlpha: 0.45,
    hills: [(0x2C2F6E, 0x23265C), (0x182052, 0x111741), (0x0A3340, 0x061C28)],
    cap: 0x1F8F86, stars: true)

// MARK: scene

/// Heightmaps (fraction of S from the top, per 64 px column), far -> near. Hand-tuned so the near
/// layer dips in the middle and frames the floating block.
let heights: [[CGFloat]] = [
    [0.600, 0.580, 0.560, 0.560, 0.540, 0.550, 0.570, 0.580, 0.600, 0.590, 0.570, 0.550, 0.540, 0.560, 0.580, 0.600],
    [0.700, 0.680, 0.660, 0.660, 0.680, 0.710, 0.730, 0.730, 0.700, 0.670, 0.650, 0.640, 0.660, 0.680, 0.700, 0.710],
    [0.790, 0.770, 0.760, 0.750, 0.770, 0.800, 0.830, 0.840, 0.840, 0.820, 0.790, 0.770, 0.750, 0.760, 0.780, 0.800],
]
let columns = 16
let colW = S / CGFloat(columns)

let orbCenter = P(0.700, 0.330)
let orbRadius = S * 0.088
let pixel = S * 0.0215            // pixel-art cell for sun/moon/stars

func drawSky(_ ctx: CGContext, _ pal: Palette) {
    linear(ctx, pal.sky.map { rgba($0) }, P(0.5, 0), P(0.5, 1), locations: pal.skyStops)
    if pal.stars {
        // Deterministic pixel stars (LCG), kept to the upper sky and away from the moon.
        var seed: UInt32 = 0x5EED
        func next() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
        for _ in 0..<46 {
            let x = 0.08 + next() * 0.84, y = 0.10 + next() * 0.42
            let p = P(x, y)
            if hypot(p.x - orbCenter.x, p.y - orbCenter.y) < orbRadius * 1.9 { continue }
            let s = pixel * (next() < 0.25 ? 0.75 : 0.42)
            ctx.setFillColor(rgba(0xFFFFFF, 0.45 + next() * 0.5))
            ctx.fill(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
        }
    } else {
        // Soft blocky clouds catching the dawn light.
        for (x, y, w) in [(0.16, 0.30, 0.20), (0.24, 0.27, 0.10), (0.40, 0.17, 0.14)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.setFillColor(rgba(0xFFD6E0, 0.16))
            ctx.fill(CGRect(x: x * S, y: y * S, width: w * S, height: pixel * 1.6))
        }
    }
}

/// Pixel-art disc (sun or moon) with a soft glow behind it.
func drawOrb(_ ctx: CGContext, _ pal: Palette) {
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    radial(ctx, [rgba(pal.orbGlow, pal.orbGlowAlpha), rgba(pal.orbGlow, pal.orbGlowAlpha * 0.35), rgba(pal.orbGlow, 0)],
           center: orbCenter, radius: orbRadius * 3.2, locations: [0, 0.35, 1])
    ctx.restoreGState()
    let cells = Int((orbRadius * 2 / pixel).rounded(.up))
    let origin = CGPoint(x: orbCenter.x - CGFloat(cells) * pixel / 2, y: orbCenter.y - CGFloat(cells) * pixel / 2)
    for i in 0..<cells {
        for j in 0..<cells {
            let cx = origin.x + (CGFloat(i) + 0.5) * pixel, cy = origin.y + (CGFloat(j) + 0.5) * pixel
            let d = hypot(cx - orbCenter.x, cy - orbCenter.y)
            guard d <= orbRadius else { continue }
            // Slightly translucent rim cells give the disc a crafted, pixel-art edge.
            let rim = d > orbRadius - pixel * 1.1
            ctx.setFillColor(rgba(pal.orb, rim ? 0.82 : 1))
            ctx.fill(CGRect(x: origin.x + CGFloat(i) * pixel, y: origin.y + CGFloat(j) * pixel,
                            width: pixel + 0.5, height: pixel + 0.5))
        }
    }
}

/// Stepped hill layers, far to near; nearer layers are darker (atmospheric perspective). The nearest
/// layer gets a lit top cap and faint block seams so it reads as voxels.
func drawHills(_ ctx: CGContext, _ pal: Palette) {
    for (layer, profile) in heights.enumerated() {
        let colors = pal.hills[layer]
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: S))
        for c in 0..<columns {
            let y = profile[c] * S
            path.addLine(to: CGPoint(x: CGFloat(c) * colW, y: y))
            path.addLine(to: CGPoint(x: CGFloat(c + 1) * colW, y: y))
        }
        path.addLine(to: CGPoint(x: S, y: S))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let top = (profile.min() ?? 0.5) * S
        linear(ctx, [rgba(colors.top), rgba(colors.bottom)], CGPoint(x: 0, y: top), CGPoint(x: 0, y: S))
        ctx.restoreGState()
        if layer == heights.count - 1 {
            let cap = S * 0.016
            for c in 0..<columns {
                let y = profile[c] * S
                ctx.setFillColor(rgba(pal.cap, 0.95))
                ctx.fill(CGRect(x: CGFloat(c) * colW, y: y, width: colW, height: cap))
                // Vertical seam where a column steps, plus a horizontal seam one block down.
                ctx.setFillColor(rgba(0x000000, 0.16))
                ctx.fill(CGRect(x: CGFloat(c) * colW, y: y + cap, width: S * 0.003, height: S - y))
                ctx.fill(CGRect(x: CGFloat(c) * colW, y: y + colW, width: colW, height: S * 0.003))
            }
        }
    }
}

// Floating block: small isometric cube with an emissive top, hovering over the dip in the near hills.
let blockCenter = P(0.5, 0.560)
let blockEdge = S * 0.150
let c30 = cos(CGFloat.pi / 6)

func blockPoints(_ c: CGPoint, _ e: CGFloat) -> (top: CGPoint, ur: CGPoint, lr: CGPoint, bottom: CGPoint, ll: CGPoint, ul: CGPoint) {
    (CGPoint(x: c.x, y: c.y - e), CGPoint(x: c.x + e * c30, y: c.y - e / 2), CGPoint(x: c.x + e * c30, y: c.y + e / 2),
     CGPoint(x: c.x, y: c.y + e), CGPoint(x: c.x - e * c30, y: c.y + e / 2), CGPoint(x: c.x - e * c30, y: c.y - e / 2))
}

func drawBlock(_ ctx: CGContext, center c: CGPoint, edge e: CGFloat, mono: Bool, halo: Bool, shadowY: CGFloat?) {
    let b = blockPoints(c, e)
    if let shadowY, !mono {
        // Soft contact shadow on the hills below: the block floats.
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: shadowY)
        ctx.scaleBy(x: 1, y: 0.22)
        radial(ctx, [rgba(0x000000, 0.45), rgba(0x000000, 0)], center: .zero, radius: e * 1.15)
        ctx.restoreGState()
    }
    if halo {
        // Emissive halo: the block is the selected/interactive object in the scene.
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        radial(ctx, [rgba(0x7CFFE0, 0.55), rgba(0x7CFFE0, 0)], center: CGPoint(x: c.x, y: c.y - e * 0.2), radius: e * 2.3)
        ctx.restoreGState()
    }
    let faces: [([CGPoint], UInt32, UInt32)] = [
        ([b.ul, c, b.bottom, b.ll], mono ? 0xB0B0B0 : 0x2AC7A7, mono ? 0x8C8C8C : 0x168F86),     // left
        ([c, b.ur, b.lr, b.bottom], mono ? 0x7A7A7A : 0x137A80, mono ? 0x5C5C5C : 0x0B4F5E),     // right
        ([b.top, b.ur, c, b.ul], mono ? 0xFFFFFF : 0xE9FFF7, mono ? 0xE2E2E2 : 0x8FF5D6),        // top (lit)
    ]
    for (pts, light, dark) in faces {
        ctx.saveGState()
        ctx.addPath(polygon(pts))
        ctx.clip()
        linear(ctx, [rgba(light), rgba(dark)], pts[0], pts[2])
        ctx.restoreGState()
    }
    // Inner tile seams (2x2 per face) so the block matches the voxel hills.
    ctx.saveGState()
    ctx.setStrokeColor(mono ? rgba(0x000000, 0.18) : rgba(0x063A44, 0.45))
    ctx.setLineWidth(S * 0.0035)
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    for (a0, a1, b0, b1) in [(b.ul, b.top, c, b.ur), (b.ul, c, b.ll, b.bottom), (c, b.ur, b.bottom, b.lr)] {
        ctx.move(to: mid(a0, b0)); ctx.addLine(to: mid(a1, b1))
        ctx.move(to: mid(a0, a1)); ctx.addLine(to: mid(b0, b1))
    }
    ctx.strokePath()
    // Rim light along the top edges.
    ctx.setStrokeColor(rgba(0xFFFFFF, mono ? 0.9 : 0.85))
    ctx.setLineWidth(S * 0.005)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addLines(between: [b.ul, b.top, b.ur])
    ctx.strokePath()
    ctx.restoreGState()
}

/// Lens: darken toward the rim and add a thin glass ring with a top-left highlight, so the circle
/// reads as a window into the world rather than a flat crop.
func drawLens(_ ctx: CGContext) {
    let c = P(0.5, 0.5)
    radial(ctx, [rgba(0x000000, 0), rgba(0x000000, 0), rgba(0x000000, 0.38)], center: c, radius: S * 0.5,
           locations: [0, 0.72, 1])
    let r = S * 0.478
    ctx.saveGState()
    ctx.setStrokeColor(rgba(0xFFFFFF, 0.22))
    ctx.setLineWidth(S * 0.010)
    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.setStrokeColor(rgba(0xFFFFFF, 0.55))
    ctx.setLineWidth(S * 0.012)
    ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: r, startAngle: .pi * 1.08, endAngle: .pi * 1.42, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: variants

enum Variant { case dawn, night, development, glyph, tinted }

func render(_ variant: Variant) -> CGImage {
    let ctx = makeContext()
    switch variant {
    case .glyph, .tinted:
        // Glyph-only variants: the floating block, larger and centred, on transparency.
        drawBlock(ctx, center: P(0.5, 0.52), edge: S * 0.30, mono: variant == .tinted, halo: false, shadowY: nil)
    case .dawn, .night, .development:
        let pal = variant == .night ? night : dawn
        drawSky(ctx, pal)
        drawOrb(ctx, pal)
        drawHills(ctx, pal)
        drawBlock(ctx, center: blockCenter, edge: blockEdge, mono: false, halo: true, shadowY: S * 0.815)
        drawLens(ctx)
        if variant == .development {
            // Amber ring inside the visionOS circular mask: unmistakable on a dev build, no text.
            ctx.setStrokeColor(rgba(0xFFB020))
            ctx.setLineWidth(S * 0.03)
            let r = S * 0.455
            ctx.strokeEllipse(in: CGRect(x: S / 2 - r, y: S / 2 - r, width: 2 * r, height: 2 * r))
        }
    }
    return ctx.makeImage()!
}

// MARK: output

/// What visionOS shows: the square icon masked to a circle (preview only).
func circleMasked(_ image: CGImage, backdrop: CGColor) -> CGImage {
    // Plain (y-up) context: CGContext.draw(image) in the flipped design space would mirror it.
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(backdrop)
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    ctx.addEllipse(in: CGRect(x: 0, y: 0, width: S, height: S))
    ctx.clip()
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
    return ctx.makeImage()!
}

func contactSheet(_ images: [CGImage], cell: Int = 300) -> CGImage {
    let pad = 24
    let w = images.count * cell + (images.count + 1) * pad, h = cell + 2 * pad
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(rgba(0x8A8F98))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    for (i, img) in images.enumerated() {
        ctx.draw(img, in: CGRect(x: pad + i * (cell + pad), y: pad, width: cell, height: cell))
    }
    return ctx.makeImage()!
}

/// Full-background icons are written without an alpha channel (asset-catalog app icons must be opaque).
func flattened(_ image: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ url: URL, opaque: Bool = false) {
    let image = opaque ? flattened(image) : image
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
    print("wrote \(url.path)")
}

// MARK: main

var args = Array(CommandLine.arguments.dropFirst())
var previewDir: URL?
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    previewDir = URL(fileURLWithPath: args[i + 1])
    args.removeSubrange(i...(i + 1))
}
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let out = URL(fileURLWithPath: args.first ?? scriptDir.appendingPathComponent("../assets/branding").path).standardized

let dawnIcon = render(.dawn)
let nightIcon = render(.night)
let devIcon = render(.development)
let glyph = render(.glyph)
let tinted = render(.tinted)
write(dawnIcon, out.appendingPathComponent("AppIcon-Light.appiconset/1024x1024.png"), opaque: true)
write(glyph, out.appendingPathComponent("AppIcon-Light.appiconset/1024x1024-Transparent.png"))
write(tinted, out.appendingPathComponent("AppIcon-Light.appiconset/1024x1024-Monochrome-White.png"))
write(nightIcon, out.appendingPathComponent("AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png"), opaque: true)
write(devIcon, out.appendingPathComponent("AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png"), opaque: true)

if let previewDir {
    let backdrop = rgba(0x8A8F98)
    let masked = [dawnIcon, nightIcon, devIcon].map { circleMasked($0, backdrop: backdrop) }
    write(masked[0], previewDir.appendingPathComponent("visionos-dawn.png"))
    write(masked[1], previewDir.appendingPathComponent("visionos-night.png"))
    write(contactSheet(masked + [glyph, tinted]), previewDir.appendingPathComponent("contact-sheet.png"))
    // Small sizes: how it reads on the Home View grid.
    write(contactSheet([masked[0], masked[1]], cell: 96), previewDir.appendingPathComponent("small.png"))
}
