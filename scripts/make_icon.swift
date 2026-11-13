// Generate the VRMC app icon set (assets/branding/*.appiconset) with CoreGraphics.
//
// Usage:  swift scripts/make_icon.swift [assets/branding] [--preview DIR]
//
// Design ("spatial block"): an isometric voxel block (2x2 tiles per face, original art, no game
// textures) floating in a deep teal sphere, wrapped by a tilted orbit ring that passes behind and in
// front of it (spatial computing), with one glowing top tile as the pinch-selected block (hand input).
// No text. visionOS masks app icons to a circle, so every element stays inside the central circle;
// iOS-style variants (dark/tinted) are emitted for the Amethyst asset catalog as before.
//
// Outputs (1024x1024 PNG, sRGB):
//   AppIcon-Light.appiconset/1024x1024.png                   full icon (default)
//   AppIcon-Light.appiconset/1024x1024-Transparent.png       glyph on transparent (iOS dark)
//   AppIcon-Light.appiconset/1024x1024-Monochrome-White.png  grayscale glyph (iOS tinted)
//   AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png       full icon, deeper background
//   AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png  full icon + amber dev ring
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

// MARK: geometry

let center = CGPoint(x: S * 0.5, y: S * 0.53)   // block sits slightly low; the ring lifts the eye
let edge = S * 0.235                             // hexagon "radius" (vertex distance)
let c30 = cos(CGFloat.pi / 6)

func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
func mul(_ a: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { add(a, mul(CGPoint(x: b.x - a.x, y: b.y - a.y), t)) }

let top = CGPoint(x: center.x, y: center.y - edge)
let upperRight = CGPoint(x: center.x + edge * c30, y: center.y - edge / 2)
let lowerRight = CGPoint(x: center.x + edge * c30, y: center.y + edge / 2)
let bottom = CGPoint(x: center.x, y: center.y + edge)
let lowerLeft = CGPoint(x: center.x - edge * c30, y: center.y + edge / 2)
let upperLeft = CGPoint(x: center.x - edge * c30, y: center.y - edge / 2)

struct Face {
    var origin: CGPoint
    var u: CGPoint   // full edge vector along one axis
    var v: CGPoint   // full edge vector along the other axis
    var light: CGColor
    var dark: CGColor
}

// Faces as parallelograms origin + s*u + t*v, s,t in [0,1].
let topFace = Face(origin: upperLeft, u: CGPoint(x: top.x - upperLeft.x, y: top.y - upperLeft.y),
                   v: CGPoint(x: center.x - upperLeft.x, y: center.y - upperLeft.y),
                   light: rgba(0xB8FFE9), dark: rgba(0x5FE3C2))
let leftFace = Face(origin: upperLeft, u: CGPoint(x: center.x - upperLeft.x, y: center.y - upperLeft.y),
                    v: CGPoint(x: lowerLeft.x - upperLeft.x, y: lowerLeft.y - upperLeft.y),
                    light: rgba(0x2CC2A8), dark: rgba(0x158C86))
let rightFace = Face(origin: center, u: CGPoint(x: upperRight.x - center.x, y: upperRight.y - center.y),
                     v: CGPoint(x: bottom.x - center.x, y: bottom.y - center.y),
                     light: rgba(0x167A80), dark: rgba(0x0B4C5A))

func tile(_ f: Face, _ i: Int, _ j: Int, n: Int = 2, gap: CGFloat = 0.03) -> [CGPoint] {
    let s0 = CGFloat(i) / CGFloat(n) + gap, s1 = CGFloat(i + 1) / CGFloat(n) - gap
    let t0 = CGFloat(j) / CGFloat(n) + gap, t1 = CGFloat(j + 1) / CGFloat(n) - gap
    func at(_ s: CGFloat, _ t: CGFloat) -> CGPoint { add(f.origin, add(mul(f.u, s), mul(f.v, t))) }
    return [at(s0, t0), at(s1, t0), at(s1, t1), at(s0, t1)]
}

// MARK: layers

enum Variant { case full, deep, development, glyph, tinted }

func drawBackground(_ ctx: CGContext, deep: Bool) {
    ctx.saveGState()
    let inner: UInt32 = deep ? 0x0F4B57 : 0x17707A
    let mid: UInt32 = deep ? 0x0A2C3D : 0x0D3B4E
    let outer: UInt32 = deep ? 0x050E1A : 0x061524
    radial(ctx, [rgba(inner), rgba(mid), rgba(outer)], center: CGPoint(x: S * 0.5, y: S * 0.40),
           radius: S * 0.72, locations: [0, 0.48, 1])
    // Soft top sheen, like light on glass.
    ctx.setBlendMode(.screen)
    linear(ctx, [rgba(0xFFFFFF, 0.10), rgba(0xFFFFFF, 0)], CGPoint(x: S * 0.5, y: 0), CGPoint(x: S * 0.5, y: S * 0.45))
    ctx.restoreGState()
    // Halo behind the block.
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    radial(ctx, [rgba(0x4FF2CF, deep ? 0.22 : 0.28), rgba(0x4FF2CF, 0)], center: CGPoint(x: center.x, y: center.y - S * 0.02),
           radius: S * 0.36)
    ctx.restoreGState()
}

/// Tilted ellipse orbit. The ring is one stroked outline filled with an alpha gradient along its depth
/// axis (y = ry*sin t in the rotated frame), so it brightens smoothly from the far side (behind the
/// block) to the near side (over it) with no overlapping translucent strokes. `front` draws only the
/// near half; the swap happens at the ellipse's left/right extremes, outside the block, so it is
/// invisible.
func drawOrbit(_ ctx: CGContext, front: Bool, mono: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y + S * 0.035)
    ctx.rotate(by: -0.26)
    let rx = S * 0.385, ry = S * 0.118
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    ctx.setLineWidth(S * 0.012)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.clip(to: front ? CGRect(x: -S, y: 0, width: 2 * S, height: S) : CGRect(x: -S, y: -S, width: 2 * S, height: S))
    let hex: UInt32 = mono ? 0xFFFFFF : 0xCFFFF3
    linear(ctx, [rgba(hex, 0.30), rgba(hex, 0.62), rgba(hex, 0.92)],
           CGPoint(x: 0, y: -ry), CGPoint(x: 0, y: ry), locations: [0, 0.5, 1])
    ctx.restoreGState()
    if front {
        // A small bright "satellite" on the near arc: the tracked fingertip.
        let a: CGFloat = 0.62 * .pi
        let p = CGPoint(x: rx * cos(a), y: ry * sin(a))
        ctx.setShadow(offset: .zero, blur: S * 0.03, color: rgba(0xFFFFFF, 0.9))
        ctx.setFillColor(rgba(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: p.x - S * 0.018, y: p.y - S * 0.018, width: S * 0.036, height: S * 0.036))
    }
    ctx.restoreGState()
}

func drawBlock(_ ctx: CGContext, mono: Bool) {
    // Contact shadow under the block.
    if !mono {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: bottom.y + S * 0.03)
        ctx.scaleBy(x: 1, y: 0.16)
        radial(ctx, [rgba(0x000000, 0.55), rgba(0x000000, 0)], center: .zero, radius: edge * 0.95)
        ctx.restoreGState()
    }
    // Base silhouette (fills the gaps between tiles so the block reads as one solid).
    ctx.saveGState()
    ctx.addPath(polygon([top, upperRight, lowerRight, bottom, lowerLeft, upperLeft]))
    ctx.setFillColor(mono ? rgba(0x3A3A3A) : rgba(0x06303A))
    ctx.fillPath()
    ctx.restoreGState()

    let selected = (0, 0)   // top-face tile nearest the viewer's left: the pinch-selected block
    for (face, isTop) in [(leftFace, false), (rightFace, false), (topFace, true)] {
        for i in 0..<2 {
            for j in 0..<2 {
                let pts = tile(face, i, j)
                let isSelected = isTop && (i, j) == selected
                ctx.saveGState()
                ctx.addPath(polygon(pts))
                ctx.clip()
                let start = pts[0], end = pts[2]
                if mono {
                    let l: UInt32 = isTop ? (isSelected ? 0xFFFFFF : 0xE6E6E6) : (face.origin == center ? 0x8A8A8A : 0xB4B4B4)
                    ctx.setFillColor(rgba(l))
                    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
                } else if isSelected {
                    linear(ctx, [rgba(0xFFFFFF), rgba(0xFFE7A8)], start, end)
                } else {
                    linear(ctx, [face.light, face.dark], start, end)
                }
                ctx.restoreGState()
                if isSelected && !mono {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: S * 0.045, color: rgba(0xFFD36B, 0.95))
                    ctx.addPath(polygon(pts))
                    ctx.setStrokeColor(rgba(0xFFF4D6))
                    ctx.setLineWidth(S * 0.006)
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            }
        }
    }
    // Specular rim along the top edges and the front vertical edge.
    if !mono {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(rgba(0xFFFFFF, 0.75))
        ctx.setLineWidth(S * 0.005)
        ctx.addLines(between: [upperLeft, top, upperRight])
        ctx.strokePath()
        ctx.setStrokeColor(rgba(0xFFFFFF, 0.28))
        ctx.addLines(between: [lerp(center, bottom, 0.04), lerp(center, bottom, 0.96)])
        ctx.strokePath()
        ctx.restoreGState()
    }
}

func render(_ variant: Variant) -> CGImage {
    let ctx = makeContext()
    let mono = variant == .tinted
    let glyphOnly = variant == .glyph || variant == .tinted
    if !glyphOnly { drawBackground(ctx, deep: variant == .deep) }
    drawOrbit(ctx, front: false, mono: mono)
    drawBlock(ctx, mono: mono)
    drawOrbit(ctx, front: true, mono: mono)
    if variant == .development {
        // Amber ring inside the visionOS circular mask: unmistakable on a dev build, no text.
        ctx.saveGState()
        ctx.setStrokeColor(rgba(0xFFB020))
        ctx.setLineWidth(S * 0.03)
        let r = S * 0.455
        ctx.strokeEllipse(in: CGRect(x: S / 2 - r, y: S / 2 - r, width: 2 * r, height: 2 * r))
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

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

func contactSheet(_ images: [CGImage]) -> CGImage {
    let cell = 300, pad = 24
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

let full = render(.full)
let deep = render(.deep)
let dev = render(.development)
let glyph = render(.glyph)
let tinted = render(.tinted)
write(full, out.appendingPathComponent("AppIcon-Light.appiconset/1024x1024.png"), opaque: true)
write(glyph, out.appendingPathComponent("AppIcon-Light.appiconset/1024x1024-Transparent.png"))
write(tinted, out.appendingPathComponent("AppIcon-Light.appiconset/1024x1024-Monochrome-White.png"))
write(deep, out.appendingPathComponent("AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png"), opaque: true)
write(dev, out.appendingPathComponent("AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png"), opaque: true)

if let previewDir {
    let backdrop = rgba(0x8A8F98)
    let masked = [full, deep, dev].map { circleMasked($0, backdrop: backdrop) }
    write(masked[0], previewDir.appendingPathComponent("visionos-full.png"))
    write(contactSheet(masked + [glyph, tinted]), previewDir.appendingPathComponent("contact-sheet.png"))
}
