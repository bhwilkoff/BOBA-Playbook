// HeroShotSim — standalone macOS tool for iterating on Hero Shot
// env-image aesthetics. Loads a card art image, applies multiple
// generator APPROACHES (different layouts/algorithms, not just
// different params), writes a contact-sheet PNG so we can compare
// approaches side-by-side. Pure CoreGraphics + CoreImage so what
// looks good here ports verbatim back to
// BOBAPlaybook/Views/HeroShot/HeroShotEnvironment.swift.
//
// Build + run:
//   cd tools/HeroShotSim
//   swiftc -O main.swift -o hero_shot_sim
//   ./hero_shot_sim test_card.jpg [output-dir]

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Color tuple type

typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

func toCGColor(_ c: RGB, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
}

func blend(_ a: RGB, _ b: RGB, t: CGFloat) -> RGB {
    let s = max(0, min(1, t))
    return (a.r + (b.r - a.r) * s,
            a.g + (b.g - a.g) * s,
            a.b + (b.b - a.b) * s)
}

let kBlack: RGB = (0, 0, 0)
let kWhite: RGB = (1, 1, 1)

// MARK: - Output dimensions

let envWidth = 2048
let envHeight = 1024

// MARK: - Palette extraction (HSV bucketing on 64×64 center-crop)

func extractPalette(from image: CGImage, count: Int = 3) -> [RGB] {
    let cropRect = CGRect(
        x: image.width / 8,
        y: image.height * 12 / 100,
        width: image.width * 3 / 4,
        height: image.height * 76 / 100
    )
    let cropped = image.cropping(to: cropRect) ?? image
    let downSize = 64
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: downSize, height: downSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return [(0.5, 0.5, 0.5)] }
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: downSize, height: downSize))
    guard let smallCG = ctx.makeImage(),
          let provider = smallCG.dataProvider,
          let data = provider.data,
          let bytes = CFDataGetBytePtr(data) else { return [(0.5, 0.5, 0.5)] }

    let bpp = smallCG.bitsPerPixel / 8
    let totalPixels = downSize * downSize
    let bins = 24
    var weights = [CGFloat](repeating: 0, count: bins)
    var rsum = [CGFloat](repeating: 0, count: bins)
    var gsum = [CGFloat](repeating: 0, count: bins)
    var bsum = [CGFloat](repeating: 0, count: bins)

    for i in 0..<totalPixels {
        let r = CGFloat(bytes[i * bpp + 0]) / 255
        let g = CGFloat(bytes[i * bpp + 1]) / 255
        let b = CGFloat(bytes[i * bpp + 2]) / 255
        let (h, s, v) = rgbToHSV(r, g, b)
        if v < 0.15 { continue }
        if s < 0.20 { continue }
        let bin = min(bins - 1, Int(h * CGFloat(bins)))
        let w: CGFloat = s * v
        weights[bin] += w
        rsum[bin] += r * w
        gsum[bin] += g * w
        bsum[bin] += b * w
    }

    let sorted = (0..<bins).map { ($0, weights[$0]) }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .prefix(count)
    let result: [RGB] = sorted.map { (bin, w) in
        (rsum[bin] / w, gsum[bin] / w, bsum[bin] / w)
    }
    return result.isEmpty ? [(0.5, 0.5, 0.5)] : result
}

/// Hue-rotate a color by `delta` (in [-1, 1] where 1 = 360°) and
/// optionally adjust saturation. Used to derive a complementary
/// rim-light color from the primary palette — premium photo studios
/// always use warm-key/cool-rim (or vice versa), not monochromatic
/// lighting.
func hueShift(_ c: RGB, byHue delta: CGFloat, satScale: CGFloat = 1.0) -> RGB {
    let (h, s, v) = rgbToHSV(c.r, c.g, c.b)
    var newH = h + delta
    if newH > 1 { newH -= 1 } else if newH < 0 { newH += 1 }
    let newS = max(0, min(1, s * satScale))
    return hsvToRGB(newH, newS, v)
}

func hsvToRGB(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) -> RGB {
    let i = floor(h * 6)
    let f = h * 6 - i
    let p = v * (1 - s)
    let q = v * (1 - f * s)
    let t = v * (1 - (1 - f) * s)
    switch Int(i) % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}

func rgbToHSV(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    let mx = max(r, g, b)
    let mn = min(r, g, b)
    let d = mx - mn
    var h: CGFloat = 0
    if d > 0 {
        if mx == r {
            h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
        if h < 0 { h += 1 }
    }
    let s: CGFloat = mx > 0 ? d / mx : 0
    return (h, s, mx)
}

// MARK: - Shared CG helpers

func newCanvas() -> CGContext? {
    CGContext(
        data: nil,
        width: envWidth, height: envHeight,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

func fillBase(ctx: CGContext, palette: [RGB], darkness: CGFloat = 0.88) {
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let dark = blend(primary, kBlack, t: darkness)
    ctx.setFillColor(toCGColor(dark))
    ctx.fill(CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
}

/// Blur + saturation-boost a CGImage. Used by all art-extraction
/// approaches as the building block.
func ambientBlur(of image: CGImage,
                 saturation: Float = 1.30,
                 brightness: Float = -0.05,
                 blurRadiusFraction: CGFloat = 0.21) -> CGImage? {
    let ci = CIImage(cgImage: image)
    let sat = CIFilter.colorControls()
    sat.inputImage = ci
    sat.saturation = saturation
    sat.brightness = brightness
    sat.contrast = 1.0
    guard let saturated = sat.outputImage else { return nil }
    let blurRadius = CGFloat(max(image.width, image.height)) * blurRadiusFraction
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = saturated.clampedToExtent()
    blur.radius = Float(blurRadius)
    guard let blurred = blur.outputImage?.cropped(to: ci.extent) else { return nil }
    return CIContext().createCGImage(blurred, from: ci.extent)
}

/// Crop a CGImage to a sub-rectangle (in source pixel coords).
func cropImage(_ image: CGImage, _ rect: CGRect) -> CGImage? {
    image.cropping(to: rect)
}

/// Apply centered radial palette glow over whatever's in the context.
/// Used by most approaches as a finishing layer.
func applyCenteredGlow(ctx: CGContext,
                       palette: [RGB],
                       centerAlpha: CGFloat = 1.0,
                       midAlpha: CGFloat = 0.75,
                       outerAlpha: CGFloat = 0.25,
                       radiusFraction: CGFloat = 0.75) {
    let primary = palette.first ?? kWhite
    let cs = CGColorSpaceCreateDeviceRGB()
    let glowCenter = CGPoint(x: envWidth / 2, y: envHeight / 2)
    let glowRadius = CGFloat(envHeight) * radiusFraction
    let glowColors = [
        toCGColor(primary, alpha: centerAlpha),
        toCGColor(primary, alpha: midAlpha),
        toCGColor(primary, alpha: outerAlpha),
        toCGColor(primary, alpha: 0)
    ] as CFArray
    let glowLocs: [CGFloat] = [0.0, 0.30, 0.70, 1.0]
    if let g = CGGradient(colorsSpace: cs, colors: glowColors, locations: glowLocs) {
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.drawRadialGradient(g,
                               startCenter: glowCenter, startRadius: 0,
                               endCenter: glowCenter, endRadius: glowRadius,
                               options: [])
        ctx.restoreGState()
    }
}

func applyVignette(ctx: CGContext,
                   alpha: CGFloat = 0.30,
                   startFraction: CGFloat = 0.60,
                   radiusFraction: CGFloat = 0.70) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let center = CGPoint(x: envWidth / 2, y: envHeight / 2)
    let radius = CGFloat(max(envWidth, envHeight)) * radiusFraction
    let colors = [
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    ] as CFArray
    let locs: [CGFloat] = [0.0, startFraction, 1.0]
    if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.drawRadialGradient(g,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius,
                               options: [])
    }
}

/// Draw a single radial light spot in the given color, blend = screen.
/// Used by all the new combined approaches to compose multi-source
/// premium lighting.
func drawLightSpot(ctx: CGContext,
                   color: RGB,
                   center: CGPoint,
                   radius: CGFloat,
                   centerAlpha: CGFloat,
                   midAlpha: CGFloat = 0.40,
                   midStop: CGFloat = 0.40,
                   blendMode: CGBlendMode = .screen) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [
        toCGColor(color, alpha: centerAlpha),
        toCGColor(color, alpha: centerAlpha * midAlpha),
        toCGColor(color, alpha: 0)
    ] as CFArray
    let locs: [CGFloat] = [0.0, midStop, 1.0]
    if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.saveGState()
        ctx.setBlendMode(blendMode)
        ctx.drawRadialGradient(g,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius,
                               options: [])
        ctx.restoreGState()
    }
}

/// Draw the ambient blurred-art layer using mirror-tiled (A0) layout.
func drawAmbientMirrorTile(ctx: CGContext, image: CGImage, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let tileSize: CGFloat = max(CGFloat(envWidth) / 2.5, 600)
    let tilesX = Int(ceil(CGFloat(envWidth) / tileSize)) + 1
    let tilesY = Int(ceil(CGFloat(envHeight) / tileSize)) + 1
    for ty in 0..<tilesY {
        for tx in 0..<tilesX {
            ctx.saveGState()
            let rect = CGRect(
                x: CGFloat(tx) * tileSize - tileSize / 2,
                y: CGFloat(ty) * tileSize - tileSize / 2,
                width: tileSize, height: tileSize
            )
            let flipX = (tx + ty) % 2 == 1
            let flipY = ty % 2 == 1
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        }
    }
    ctx.restoreGState()
}

/// Draw the ambient blurred-art layer using multi-rotated layout (A2).
func drawAmbientMultiRotated(ctx: CGContext, image: CGImage, baseAlpha: CGFloat) {
    let copies: [(scale: CGFloat, rot: CGFloat, x: CGFloat, y: CGFloat, alpha: CGFloat)] = [
        (1.4, .pi * 0.05, 0.3, 0.5, 0.85),
        (1.2, .pi * -0.10, 0.7, 0.55, 0.75),
        (1.6, .pi * 0.20, 0.4, 0.7, 0.60),
        (1.0, .pi * -0.05, 0.6, 0.35, 0.70)
    ]
    for c in copies {
        ctx.saveGState()
        ctx.setAlpha(baseAlpha * c.alpha)
        let cx = c.x * CGFloat(envWidth)
        let cy = c.y * CGFloat(envHeight)
        let drawW = CGFloat(envWidth) * c.scale
        let drawH = drawW * CGFloat(image.height) / CGFloat(image.width)
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: c.rot)
        ctx.translateBy(x: -drawW / 2, y: -drawH / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: drawW, height: drawH))
        ctx.restoreGState()
    }
}

// MARK: - Approach A0: baseline (mirror-tile + centered glow + vignette)

func envBaseline(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette)

    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.65)
        let tileSize: CGFloat = max(CGFloat(envWidth) / 2.5, 600)
        let tilesX = Int(ceil(CGFloat(envWidth) / tileSize)) + 1
        let tilesY = Int(ceil(CGFloat(envHeight) / tileSize)) + 1
        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                ctx.saveGState()
                let rect = CGRect(
                    x: CGFloat(tx) * tileSize - tileSize / 2,
                    y: CGFloat(ty) * tileSize - tileSize / 2,
                    width: tileSize, height: tileSize
                )
                let flipX = (tx + ty) % 2 == 1
                let flipY = ty % 2 == 1
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
                ctx.draw(ambient, in: rect)
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    applyCenteredGlow(ctx: ctx, palette: palette)
    applyVignette(ctx: ctx)
    return ctx.makeImage()
}

// MARK: - Approach A1: single stretch (no tile, no symmetry)

func envSingleStretch(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette)
    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.65)
        // Stretch a SINGLE blurred copy to fill the entire canvas.
        // The card art aspect (5:7) gets stretched to 2:1, distorting
        // the art but eliminating the kaleidoscope symmetry of A0.
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    applyCenteredGlow(ctx: ctx, palette: palette)
    applyVignette(ctx: ctx)
    return ctx.makeImage()
}

// MARK: - Approach A2: multi-rotated copies (Apple Music style)

func envMultiRotated(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette)
    if let ambient = ambientBlur(of: cardArt) {
        // 4 copies at different scales and rotations, no mirroring.
        // The overlapping rotated copies produce an organic non-
        // repeating pattern (closer to Apple Music's animated bg).
        let copies: [(scale: CGFloat, rot: CGFloat, x: CGFloat, y: CGFloat, alpha: CGFloat)] = [
            (1.4, .pi * 0.05, 0.3, 0.5, 0.55),
            (1.2, .pi * -0.10, 0.7, 0.55, 0.50),
            (1.6, .pi * 0.20, 0.4, 0.7, 0.40),
            (1.0, .pi * -0.05, 0.6, 0.35, 0.45)
        ]
        for c in copies {
            ctx.saveGState()
            ctx.setAlpha(c.alpha)
            let cx = c.x * CGFloat(envWidth)
            let cy = c.y * CGFloat(envHeight)
            let drawW = CGFloat(envWidth) * c.scale
            let drawH = drawW * CGFloat(ambient.height) / CGFloat(ambient.width)
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: c.rot)
            ctx.translateBy(x: -drawW / 2, y: -drawH / 2)
            ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: drawW, height: drawH))
            ctx.restoreGState()
        }
    }
    applyCenteredGlow(ctx: ctx, palette: palette)
    applyVignette(ctx: ctx)
    return ctx.makeImage()
}

// MARK: - Approach A3: off-center glow (single source, dramatic side light)

func envOffCenterGlow(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette)
    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.55)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    // Glow positioned upper-left, larger radius — looks like a key light
    // hitting the scene from one direction.
    let primary = palette.first ?? kWhite
    let cs = CGColorSpaceCreateDeviceRGB()
    let glowCenter = CGPoint(x: CGFloat(envWidth) * 0.30, y: CGFloat(envHeight) * 0.70)
    let glowRadius = CGFloat(envHeight) * 1.10
    let glowColors = [
        toCGColor(primary, alpha: 1.0),
        toCGColor(primary, alpha: 0.6),
        toCGColor(primary, alpha: 0.18),
        toCGColor(primary, alpha: 0)
    ] as CFArray
    let glowLocs: [CGFloat] = [0.0, 0.25, 0.65, 1.0]
    if let g = CGGradient(colorsSpace: cs, colors: glowColors, locations: glowLocs) {
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.drawRadialGradient(g,
                               startCenter: glowCenter, startRadius: 0,
                               endCenter: glowCenter, endRadius: glowRadius,
                               options: [])
        ctx.restoreGState()
    }
    applyVignette(ctx: ctx, alpha: 0.35)
    return ctx.makeImage()
}

// MARK: - Approach A4: multi-glow (3 small palette glows, color variation)

func envMultiGlow(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette)
    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.50)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    // Three glows using palette colors (or shifted variants).
    let primary = palette.first ?? kWhite
    let secondary = palette.count > 1 ? palette[1] : primary
    let tertiary = palette.count > 2 ? palette[2] : primary
    let cs = CGColorSpaceCreateDeviceRGB()
    let glows: [(c: RGB, x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
        (primary,   0.30, 0.65, 0.55, 1.0),   // upper-left
        (secondary, 0.75, 0.40, 0.45, 0.85),  // mid-right
        (tertiary,  0.50, 0.20, 0.40, 0.70)   // lower-center
    ]
    for spot in glows {
        let cx = spot.x * CGFloat(envWidth)
        let cy = spot.y * CGFloat(envHeight)
        let r = CGFloat(envHeight) * spot.r
        let colors = [
            toCGColor(spot.c, alpha: spot.a),
            toCGColor(spot.c, alpha: 0.35 * spot.a),
            toCGColor(spot.c, alpha: 0)
        ] as CFArray
        let locs: [CGFloat] = [0.0, 0.45, 1.0]
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                                   options: [])
            ctx.restoreGState()
        }
    }
    applyVignette(ctx: ctx, alpha: 0.25)
    return ctx.makeImage()
}

// MARK: - Approach A5: diagonal gradient (two palette colors)

func envDiagonalGradient(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    let primary = palette.first ?? (0.3, 0.3, 0.3)
    let secondary = palette.count > 1 ? palette[1] : primary
    let cs = CGColorSpaceCreateDeviceRGB()
    // Diagonal from upper-left to lower-right, palette colors.
    let colors = [
        toCGColor(blend(primary, kBlack, t: 0.30)),
        toCGColor(blend(secondary, kBlack, t: 0.60)),
        toCGColor(blend(kBlack, kBlack, t: 0))
    ] as CFArray
    let locs: [CGFloat] = [0.0, 0.55, 1.0]
    if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: 0, y: CGFloat(envHeight)),
                               end: CGPoint(x: CGFloat(envWidth), y: 0),
                               options: [])
    }
    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.40)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    applyVignette(ctx: ctx, alpha: 0.20)
    return ctx.makeImage()
}

// MARK: - Approach A6: directional regions (card top → env top, etc.)

func envDirectionalRegions(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.78)
    // Split card art into top/middle/bottom regions, blur each, place
    // in the corresponding stripe of the env. So the env's top has
    // the colors of the card's top, etc — feels like the card's
    // composition extends out into the scene.
    let cardH = cardArt.height
    let cardW = cardArt.width
    let regions: [(srcRect: CGRect, dstRect: CGRect, alpha: CGFloat)] = [
        // Top of source → top of env (upper third)
        (CGRect(x: 0, y: 0, width: cardW, height: cardH / 3),
         CGRect(x: 0, y: Int(Double(envHeight) * 2.0 / 3.0),
                width: envWidth, height: envHeight / 3 + 1),
         0.65),
        // Middle of source → middle of env
        (CGRect(x: 0, y: cardH / 3, width: cardW, height: cardH / 3),
         CGRect(x: 0, y: envHeight / 3,
                width: envWidth, height: envHeight / 3 + 1),
         0.60),
        // Bottom of source → bottom of env
        (CGRect(x: 0, y: 2 * cardH / 3, width: cardW, height: cardH / 3 + 1),
         CGRect(x: 0, y: 0, width: envWidth, height: envHeight / 3 + 1),
         0.65)
    ]
    for region in regions {
        guard let cropped = cropImage(cardArt, region.srcRect),
              let blurred = ambientBlur(of: cropped, blurRadiusFraction: 0.35) else { continue }
        ctx.saveGState()
        ctx.setAlpha(region.alpha)
        ctx.draw(blurred, in: region.dstRect)
        ctx.restoreGState()
    }
    applyCenteredGlow(ctx: ctx, palette: palette,
                      centerAlpha: 0.55, midAlpha: 0.35, outerAlpha: 0.10,
                      radiusFraction: 0.50)
    applyVignette(ctx: ctx, alpha: 0.20)
    return ctx.makeImage()
}

// MARK: - Approach A7: bokeh (palette-sampled out-of-focus orbs)

func envBokeh(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.85)
    // Background: a very-soft blurred card art at low alpha for color.
    if let ambient = ambientBlur(of: cardArt, blurRadiusFraction: 0.40) {
        ctx.saveGState()
        ctx.setAlpha(0.30)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    // Foreground bokeh: ~12 large soft orbs in palette colors,
    // additive-blended, randomly positioned across the canvas.
    var rng = SystemRandomNumberGenerator()
    let cs = CGColorSpaceCreateDeviceRGB()
    let orbCount = 14
    for i in 0..<orbCount {
        let color = palette[i % palette.count]
        let cx = CGFloat.random(in: 0..<CGFloat(envWidth), using: &rng)
        let cy = CGFloat.random(in: 0..<CGFloat(envHeight), using: &rng)
        let r = CGFloat.random(in: 80...260, using: &rng)
        let alpha = CGFloat.random(in: 0.35...0.85, using: &rng)
        let colors = [
            toCGColor(color, alpha: alpha),
            toCGColor(color, alpha: alpha * 0.4),
            toCGColor(color, alpha: 0)
        ] as CFArray
        let locs: [CGFloat] = [0.0, 0.45, 1.0]
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                                   options: [])
            ctx.restoreGState()
        }
    }
    applyVignette(ctx: ctx, alpha: 0.25)
    return ctx.makeImage()
}

// ════════════════════════════════════════════════════════════════════
// ROUND 2 — COMBINED APPROACHES (build on A3's off-center keylight)
// ════════════════════════════════════════════════════════════════════

// MARK: - Approach B1: A3 keylight + multi-rotated ambient (A2+A3)

func envB1_KeylightOverMultiRotated(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.90)
    if let ambient = ambientBlur(of: cardArt) {
        drawAmbientMultiRotated(ctx: ctx, image: ambient, baseAlpha: 0.55)
    }
    let primary = palette.first ?? kWhite
    drawLightSpot(ctx: ctx,
                  color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.30, y: CGFloat(envHeight) * 0.70),
                  radius: CGFloat(envHeight) * 1.10,
                  centerAlpha: 0.95,
                  midAlpha: 0.55,
                  midStop: 0.30)
    applyVignette(ctx: ctx, alpha: 0.30)
    return ctx.makeImage()
}

// MARK: - Approach B2: A3 keylight + directional regions (A6+A3)

func envB2_KeylightOverDirectional(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.85)
    let cardH = cardArt.height
    let cardW = cardArt.width
    let regions: [(srcRect: CGRect, dstRect: CGRect, alpha: CGFloat)] = [
        (CGRect(x: 0, y: 0, width: cardW, height: cardH / 3),
         CGRect(x: 0, y: Int(Double(envHeight) * 2.0 / 3.0),
                width: envWidth, height: envHeight / 3 + 1), 0.65),
        (CGRect(x: 0, y: cardH / 3, width: cardW, height: cardH / 3),
         CGRect(x: 0, y: envHeight / 3,
                width: envWidth, height: envHeight / 3 + 1), 0.60),
        (CGRect(x: 0, y: 2 * cardH / 3, width: cardW, height: cardH / 3 + 1),
         CGRect(x: 0, y: 0, width: envWidth, height: envHeight / 3 + 1), 0.65)
    ]
    for region in regions {
        guard let cropped = cropImage(cardArt, region.srcRect),
              let blurred = ambientBlur(of: cropped, blurRadiusFraction: 0.35) else { continue }
        ctx.saveGState()
        ctx.setAlpha(region.alpha)
        ctx.draw(blurred, in: region.dstRect)
        ctx.restoreGState()
    }
    let primary = palette.first ?? kWhite
    drawLightSpot(ctx: ctx,
                  color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.30, y: CGFloat(envHeight) * 0.70),
                  radius: CGFloat(envHeight) * 1.00,
                  centerAlpha: 0.75,
                  midAlpha: 0.40,
                  midStop: 0.35)
    applyVignette(ctx: ctx, alpha: 0.25)
    return ctx.makeImage()
}

// MARK: - Approach B3: 3-light translated to 2D (warm key + cool rim + floor glow)

func envB3_ThreeLightStudio(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.92)
    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.30)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    let primary = palette.first ?? kWhite
    // Derive a complementary RIM color (hue rotated ~150°, mild
    // desaturation). For purple primary → green-yellow rim, for orange
    // → teal, etc. Premium photo studios always use warm/cool contrast.
    let rim = hueShift(primary, byHue: 0.42, satScale: 0.85)
    // KEY light — palette primary, upper-left, large/bright.
    drawLightSpot(ctx: ctx,
                  color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.30, y: CGFloat(envHeight) * 0.70),
                  radius: CGFloat(envHeight) * 1.05,
                  centerAlpha: 1.0,
                  midAlpha: 0.55,
                  midStop: 0.30)
    // RIM light — complementary, lower-right, smaller/dimmer.
    drawLightSpot(ctx: ctx,
                  color: rim,
                  center: CGPoint(x: CGFloat(envWidth) * 0.75, y: CGFloat(envHeight) * 0.30),
                  radius: CGFloat(envHeight) * 0.85,
                  centerAlpha: 0.80,
                  midAlpha: 0.35,
                  midStop: 0.35)
    // FLOOR glow — palette primary, bottom-center, small/warm.
    drawLightSpot(ctx: ctx,
                  color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.50, y: CGFloat(envHeight) * 0.12),
                  radius: CGFloat(envHeight) * 0.50,
                  centerAlpha: 0.55,
                  midAlpha: 0.25,
                  midStop: 0.30)
    applyVignette(ctx: ctx, alpha: 0.28)
    return ctx.makeImage()
}

// MARK: - Approach B4: full premium stage (everything combined)

func envB4_PremiumStage(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.90)
    if let ambient = ambientBlur(of: cardArt) {
        drawAmbientMultiRotated(ctx: ctx, image: ambient, baseAlpha: 0.50)
    }
    let primary = palette.first ?? kWhite
    let rim = hueShift(primary, byHue: 0.42, satScale: 0.80)
    let secondary = palette.count > 1 ? palette[1] : primary
    // KEY + RIM (3-light translated to 2D)
    drawLightSpot(ctx: ctx,
                  color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.28, y: CGFloat(envHeight) * 0.72),
                  radius: CGFloat(envHeight) * 1.10,
                  centerAlpha: 1.0, midAlpha: 0.55, midStop: 0.28)
    drawLightSpot(ctx: ctx,
                  color: rim,
                  center: CGPoint(x: CGFloat(envWidth) * 0.78, y: CGFloat(envHeight) * 0.28),
                  radius: CGFloat(envHeight) * 0.80,
                  centerAlpha: 0.70, midAlpha: 0.30, midStop: 0.35)
    // SMALL ACCENTS — 3 bokeh-style orbs in palette colors
    var rng = SystemRandomNumberGenerator()
    let accentColors = [primary, secondary, rim]
    for color in accentColors {
        let cx = CGFloat.random(in: 0.10..<0.90, using: &rng) * CGFloat(envWidth)
        let cy = CGFloat.random(in: 0.15..<0.85, using: &rng) * CGFloat(envHeight)
        let r = CGFloat.random(in: 80...160, using: &rng)
        drawLightSpot(ctx: ctx,
                      color: color,
                      center: CGPoint(x: cx, y: cy),
                      radius: r,
                      centerAlpha: 0.45, midAlpha: 0.25, midStop: 0.40)
    }
    applyVignette(ctx: ctx, alpha: 0.30)
    return ctx.makeImage()
}

// MARK: - Approach B5: two-tone backdrop (warm/cool linear split)

func envB5_TwoTone(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    let primary = palette.first ?? (0.3, 0.3, 0.3)
    let cool = hueShift(primary, byHue: 0.42, satScale: 0.70)
    // Vertical linear gradient: cool at top, warm (palette) at bottom.
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [
        toCGColor(blend(cool, kBlack, t: 0.55)),
        toCGColor(blend(primary, kBlack, t: 0.50)),
        toCGColor(blend(primary, kBlack, t: 0.78))
    ] as CFArray
    let locs: [CGFloat] = [0.0, 0.50, 1.0]
    if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: 0, y: CGFloat(envHeight)),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
    }
    if let ambient = ambientBlur(of: cardArt) {
        ctx.saveGState()
        ctx.setAlpha(0.35)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    applyVignette(ctx: ctx, alpha: 0.18)
    return ctx.makeImage()
}

// MARK: - Approach B7: B3 + multi-rotated ambient art (best of both)
//
// Round 2 showed B3 (warm/cool 3-light) is dramatically the most
// cinematic, but B1 (multi-rotated ambient art) carries the most
// "extension of card art." B7 combines them: B3's lighting stack
// over visible card-art-derived ambient.

func envB7_ThreeLightOverAmbient(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.85)
    if let ambient = ambientBlur(of: cardArt) {
        drawAmbientMultiRotated(ctx: ctx, image: ambient, baseAlpha: 0.45)
    }
    let primary = palette.first ?? kWhite
    let rim = hueShift(primary, byHue: 0.42, satScale: 0.85)
    // KEY
    drawLightSpot(ctx: ctx, color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.28, y: CGFloat(envHeight) * 0.72),
                  radius: CGFloat(envHeight) * 1.10,
                  centerAlpha: 1.0, midAlpha: 0.55, midStop: 0.30)
    // RIM
    drawLightSpot(ctx: ctx, color: rim,
                  center: CGPoint(x: CGFloat(envWidth) * 0.78, y: CGFloat(envHeight) * 0.28),
                  radius: CGFloat(envHeight) * 0.85,
                  centerAlpha: 0.80, midAlpha: 0.35, midStop: 0.35)
    applyVignette(ctx: ctx, alpha: 0.25)
    return ctx.makeImage()
}

// MARK: - Approach B8: B3 + directional regions ambient

func envB8_ThreeLightOverDirectional(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.85)
    let cardH = cardArt.height
    let cardW = cardArt.width
    let regions: [(srcRect: CGRect, dstRect: CGRect, alpha: CGFloat)] = [
        (CGRect(x: 0, y: 0, width: cardW, height: cardH / 3),
         CGRect(x: 0, y: Int(Double(envHeight) * 2.0 / 3.0),
                width: envWidth, height: envHeight / 3 + 1), 0.50),
        (CGRect(x: 0, y: cardH / 3, width: cardW, height: cardH / 3),
         CGRect(x: 0, y: envHeight / 3,
                width: envWidth, height: envHeight / 3 + 1), 0.45),
        (CGRect(x: 0, y: 2 * cardH / 3, width: cardW, height: cardH / 3 + 1),
         CGRect(x: 0, y: 0, width: envWidth, height: envHeight / 3 + 1), 0.50)
    ]
    for region in regions {
        guard let cropped = cropImage(cardArt, region.srcRect),
              let blurred = ambientBlur(of: cropped, blurRadiusFraction: 0.35) else { continue }
        ctx.saveGState()
        ctx.setAlpha(region.alpha)
        ctx.draw(blurred, in: region.dstRect)
        ctx.restoreGState()
    }
    let primary = palette.first ?? kWhite
    let rim = hueShift(primary, byHue: 0.42, satScale: 0.85)
    drawLightSpot(ctx: ctx, color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.28, y: CGFloat(envHeight) * 0.72),
                  radius: CGFloat(envHeight) * 1.05,
                  centerAlpha: 0.95, midAlpha: 0.50, midStop: 0.32)
    drawLightSpot(ctx: ctx, color: rim,
                  center: CGPoint(x: CGFloat(envWidth) * 0.78, y: CGFloat(envHeight) * 0.28),
                  radius: CGFloat(envHeight) * 0.80,
                  centerAlpha: 0.75, midAlpha: 0.32, midStop: 0.35)
    applyVignette(ctx: ctx, alpha: 0.22)
    return ctx.makeImage()
}

// MARK: - Approach B9: B3 with stronger rim contrast (more dramatic)

func envB9_HighContrastThreeLight(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.92)
    if let ambient = ambientBlur(of: cardArt) {
        drawAmbientMultiRotated(ctx: ctx, image: ambient, baseAlpha: 0.40)
    }
    let primary = palette.first ?? kWhite
    // Higher saturation rim for more dramatic warm/cool contrast.
    let rim = hueShift(primary, byHue: 0.42, satScale: 1.10)
    drawLightSpot(ctx: ctx, color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.25, y: CGFloat(envHeight) * 0.75),
                  radius: CGFloat(envHeight) * 1.15,
                  centerAlpha: 1.10, midAlpha: 0.60, midStop: 0.28)
    drawLightSpot(ctx: ctx, color: rim,
                  center: CGPoint(x: CGFloat(envWidth) * 0.80, y: CGFloat(envHeight) * 0.25),
                  radius: CGFloat(envHeight) * 0.95,
                  centerAlpha: 1.0, midAlpha: 0.45, midStop: 0.30)
    applyVignette(ctx: ctx, alpha: 0.30)
    return ctx.makeImage()
}

// MARK: - Approach B6: minimal premium (key + rim + nothing else)

func envB6_MinimalPremium(cardArt: CGImage, palette: [RGB]) -> CGImage? {
    guard let ctx = newCanvas() else { return nil }
    fillBase(ctx: ctx, palette: palette, darkness: 0.94)
    if let ambient = ambientBlur(of: cardArt, blurRadiusFraction: 0.35) {
        ctx.saveGState()
        ctx.setAlpha(0.22)
        ctx.draw(ambient, in: CGRect(x: 0, y: 0, width: envWidth, height: envHeight))
        ctx.restoreGState()
    }
    let primary = palette.first ?? kWhite
    let rim = hueShift(primary, byHue: 0.42, satScale: 0.75)
    drawLightSpot(ctx: ctx,
                  color: primary,
                  center: CGPoint(x: CGFloat(envWidth) * 0.30, y: CGFloat(envHeight) * 0.70),
                  radius: CGFloat(envHeight) * 1.00,
                  centerAlpha: 0.95, midAlpha: 0.50, midStop: 0.32)
    drawLightSpot(ctx: ctx,
                  color: rim,
                  center: CGPoint(x: CGFloat(envWidth) * 0.78, y: CGFloat(envHeight) * 0.28),
                  radius: CGFloat(envHeight) * 0.75,
                  centerAlpha: 0.55, midAlpha: 0.25, midStop: 0.40)
    applyVignette(ctx: ctx, alpha: 0.32)
    return ctx.makeImage()
}

// MARK: - Contact sheet

func makeContactSheet(tiles: [(image: CGImage, label: String)], cols: Int) -> CGImage? {
    let rows = (tiles.count + cols - 1) / cols
    let tileW: Int = 512
    let tileH: Int = 256
    let labelH: Int = 28
    let padding: Int = 10

    let sheetW = cols * (tileW + padding) + padding
    let sheetH = rows * (tileH + labelH + padding) + padding

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: sheetW, height: sheetH,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

    for (idx, tile) in tiles.enumerated() {
        let col = idx % cols
        let row = idx / cols
        let rowFromTop = rows - 1 - row
        let x = padding + col * (tileW + padding)
        let y = padding + rowFromTop * (tileH + labelH + padding)
        let imageRect = CGRect(x: x, y: y + labelH, width: tileW, height: tileH)
        ctx.draw(tile.image, in: imageRect)

        // Label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelRect = CGRect(x: x, y: y, width: tileW, height: labelH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = NSAttributedString(string: tile.label, attributes: attrs)
        text.draw(in: labelRect.insetBy(dx: 6, dy: 6))
        NSGraphicsContext.restoreGraphicsState()
    }
    return ctx.makeImage()
}

// MARK: - Image I/O

func loadImage(at path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func savePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1, nil
    ) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// MARK: - Sweep

typealias EnvGen = (CGImage, [RGB]) -> CGImage?

/// Round 3 sweep — finalist contenders. B3 (3-light warm/cool) was
/// the round-2 winner; this round tries variants that add ambient
/// card-art visibility (B7/B8) and a higher-contrast variant (B9).
let approaches: [(label: String, gen: EnvGen)] = [
    ("B3 baseline 3-light",                    envB3_ThreeLightStudio),
    ("B7 3-light + multi-rotated ambient",     envB7_ThreeLightOverAmbient),
    ("B8 3-light + directional regions",       envB8_ThreeLightOverDirectional),
    ("B9 high-contrast 3-light",               envB9_HighContrastThreeLight)
]

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: hero_shot_sim <card1> [card2 card3 ...] [--out <dir>]")
    print("       Pass multiple card paths to render one mega contact-sheet")
    print("       comparing all approaches × all cards (rows = approaches,")
    print("       cols = cards). Useful for verifying that an approach")
    print("       works across different palettes (Fire/Ice/Hex/etc).")
    exit(1)
}

// Parse args: positional card paths + optional --out flag.
var cardPaths: [String] = []
var outDir = FileManager.default.currentDirectoryPath
var i = 1
while i < args.count {
    if args[i] == "--out" && i + 1 < args.count {
        outDir = args[i + 1]
        i += 2
    } else {
        cardPaths.append(args[i])
        i += 1
    }
}

print("Loading \(cardPaths.count) card(s)…")
var cards: [(name: String, image: CGImage, palette: [RGB])] = []
for path in cardPaths {
    guard let img = loadImage(at: path) else {
        print("  ✗ \(path) — failed to load")
        continue
    }
    let name = (path as NSString).lastPathComponent
    let palette = extractPalette(from: img, count: 3)
    cards.append((name: name, image: img, palette: palette))
    print("  ✓ \(name) \(img.width)×\(img.height) palette \(palette.map { String(format: "(%.2f,%.2f,%.2f)", $0.r, $0.g, $0.b) }.joined(separator: " "))")
}
guard !cards.isEmpty else { print("No cards loaded"); exit(1) }

print("Rendering \(approaches.count) approaches × \(cards.count) cards = \(approaches.count * cards.count) tiles…")
// Contact-sheet layout: rows = approaches, cols = cards.
// Tiles ordered approach-first so they render correctly.
var tiles: [(image: CGImage, label: String)] = []
for (approachLabel, gen) in approaches {
    for card in cards {
        if let img = gen(card.image, card.palette) {
            let cardTag = (card.name as NSString).deletingPathExtension
                .replacingOccurrences(of: "test_card_", with: "")
                .replacingOccurrences(of: "test_card", with: "card")
            tiles.append((image: img, label: "\(approachLabel)  [\(cardTag)]"))
            print("  ✓ \(approachLabel) × \(card.name)")
        } else {
            print("  ✗ \(approachLabel) × \(card.name)")
        }
    }
}

print("Building contact sheet (\(tiles.count) tiles, \(cards.count) cols)…")
guard let sheet = makeContactSheet(tiles: tiles, cols: cards.count) else {
    print("Failed contact sheet")
    exit(1)
}
let outPath = (outDir as NSString).appendingPathComponent("sweep.png")
if savePNG(sheet, to: outPath) {
    print("→ \(outPath)")
} else {
    print("Failed to save")
    exit(1)
}
