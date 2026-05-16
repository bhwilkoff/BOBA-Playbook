// HeroShotSim — standalone macOS tool for iterating on the Hero Shot
// env-image generator outside of the iOS app. Loads a card art image,
// sweeps env-image parameters, writes a contact-sheet PNG so we can
// compare N variants side-by-side. No UIKit dependency — all rendering
// uses CoreGraphics + CoreImage primitives that work identically on
// iOS and macOS, so what looks good HERE ports back to
// BOBAPlaybook/Views/HeroShot/HeroShotEnvironment.swift verbatim.
//
// Build + run:
//   cd tools/HeroShotSim
//   swiftc -O main.swift -o hero_shot_sim
//   ./hero_shot_sim <card-art.png> [output-dir]
//
// Output: a single PNG `sweep.png` in the output dir (default cwd)
// containing a grid of env-image variants labeled by the params used.

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Params being swept

struct EnvParams: CustomStringConvertible {
    /// Alpha of the blurred-card-art "extension" layer. 0 = invisible,
    /// 1 = fully opaque. v5 used 0.30 (user complaint "takes nothing
    /// from the card"), v5.1 sweeping around 0.55-0.80.
    var blurredArtAlpha: CGFloat = 0.65
    /// Pre-blur saturation lift on the card art.
    var blurredArtSaturation: Float = 1.30
    /// Pre-blur brightness shift on the card art.
    var blurredArtBrightness: Float = -0.05
    /// Gaussian blur radius as a fraction of source max dimension.
    var blurRadiusFraction: CGFloat = 0.21

    /// Center palette glow stop alphas (0..1).
    var glowCenterAlpha: CGFloat = 1.0
    var glowMidAlpha: CGFloat = 0.75
    var glowOuterAlpha: CGFloat = 0.25
    /// Glow radius as a fraction of out-image height.
    var glowRadiusFraction: CGFloat = 0.75

    /// Vignette end-stop alpha (closer to 1.0 = darker corners).
    var vignetteAlpha: CGFloat = 0.30
    var vignetteStartFraction: CGFloat = 0.60
    var vignetteRadiusFraction: CGFloat = 0.70

    /// How black the base layer is (1.0 = pure black, 0 = pure palette).
    var baseDarkening: CGFloat = 0.88

    var description: String {
        // Used as the label under each contact-sheet tile.
        "blurA=\(String(format: "%.2f", blurredArtAlpha)) | "
            + "sat=\(String(format: "%.2f", blurredArtSaturation)) | "
            + "glow=\(String(format: "%.2f", glowCenterAlpha)) "
            + "@\(String(format: "%.2f", glowRadiusFraction)) | "
            + "vig=\(String(format: "%.2f", vignetteAlpha))"
    }
}

// MARK: - Palette extraction (port of HeroShotEnvironment.extractPalette)

/// Returns up to N dominant colors as `(r, g, b)` tuples (0..1 each).
/// HSV bucketing on a 64×64 center-crop, filters near-grey/black pixels.
func extractPalette(from image: CGImage, count: Int = 3) -> [(CGFloat, CGFloat, CGFloat)] {
    // Center-crop to art region (drop top/bottom 12% chrome).
    let cropRect = CGRect(
        x: image.width / 8,
        y: image.height * 12 / 100,
        width: image.width * 3 / 4,
        height: image.height * 76 / 100
    )
    let cropped = image.cropping(to: cropRect) ?? image

    // Downsample to 64×64 for fast pixel iteration.
    let downSize = 64
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: downSize, height: downSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return [(0.5, 0.5, 0.5)] }
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: downSize, height: downSize))
    guard let smallCG = ctx.makeImage(),
          let provider = smallCG.dataProvider,
          let data = provider.data,
          let bytes = CFDataGetBytePtr(data)
    else { return [(0.5, 0.5, 0.5)] }

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

    let sorted = (0..<bins)
        .map { ($0, weights[$0]) }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .prefix(count)
    let result: [(CGFloat, CGFloat, CGFloat)] = sorted.map { (bin, w) in
        (rsum[bin] / w, gsum[bin] / w, bsum[bin] / w)
    }
    return result.isEmpty ? [(0.5, 0.5, 0.5)] : result
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

// MARK: - Env image generator (port of HeroShotEnvironment.generateImage)

func makeEnvImage(cardArt: CGImage,
                  palette: [(CGFloat, CGFloat, CGFloat)],
                  params: EnvParams) -> CGImage? {
    let outW = 2048
    let outH = 1024
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: outW, height: outH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let outSize = CGSize(width: outW, height: outH)

    // Layer 1: dark base, slightly tinted by palette.
    let dark = blend(primary, (0, 0, 0), t: params.baseDarkening)
    ctx.setFillColor(CGColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: outSize))

    // Layer 2: blurred card art.
    if let ambient = ambientBlur(of: cardArt,
                                 saturation: params.blurredArtSaturation,
                                 brightness: params.blurredArtBrightness,
                                 blurRadiusFraction: params.blurRadiusFraction,
                                 targetSize: outSize) {
        ctx.saveGState()
        ctx.setAlpha(params.blurredArtAlpha)
        // Mirror-tile fill (4 tiles, alternating mirror).
        let tileSize: CGFloat = max(outSize.width / 2.5, 600)
        let tilesX = Int(ceil(outSize.width / tileSize)) + 1
        let tilesY = Int(ceil(outSize.height / tileSize)) + 1
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

    // Layer 3: centered palette glow (screen-blend brightens behind).
    let glowCenter = CGPoint(x: outSize.width / 2, y: outSize.height / 2)
    let glowRadius = outSize.height * params.glowRadiusFraction
    let glowColors = [
        CGColor(srgbRed: primary.0, green: primary.1, blue: primary.2, alpha: params.glowCenterAlpha),
        CGColor(srgbRed: primary.0, green: primary.1, blue: primary.2, alpha: params.glowMidAlpha),
        CGColor(srgbRed: primary.0, green: primary.1, blue: primary.2, alpha: params.glowOuterAlpha),
        CGColor(srgbRed: primary.0, green: primary.1, blue: primary.2, alpha: 0)
    ] as CFArray
    let glowLocs: [CGFloat] = [0.0, 0.30, 0.70, 1.0]
    if let glowGrad = CGGradient(colorsSpace: cs, colors: glowColors, locations: glowLocs) {
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.drawRadialGradient(
            glowGrad,
            startCenter: glowCenter, startRadius: 0,
            endCenter: glowCenter, endRadius: glowRadius,
            options: []
        )
        ctx.restoreGState()
    }

    // Layer 4: edge vignette.
    let vignetteColors = [
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: params.vignetteAlpha)
    ] as CFArray
    let vignetteLocs: [CGFloat] = [0.0, params.vignetteStartFraction, 1.0]
    let vignetteRadius = max(outSize.width, outSize.height) * params.vignetteRadiusFraction
    if let vGrad = CGGradient(colorsSpace: cs, colors: vignetteColors, locations: vignetteLocs) {
        ctx.drawRadialGradient(
            vGrad,
            startCenter: glowCenter, startRadius: 0,
            endCenter: glowCenter, endRadius: vignetteRadius,
            options: []
        )
    }

    return ctx.makeImage()
}

/// Apply CIColorControls + CIGaussianBlur to a card image. Returns the
/// blurred CGImage at `targetSize`.
func ambientBlur(of image: CGImage,
                 saturation: Float,
                 brightness: Float,
                 blurRadiusFraction: CGFloat,
                 targetSize: CGSize) -> CGImage? {
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

    let ciContext = CIContext()
    return ciContext.createCGImage(blurred, from: ci.extent)
}

// MARK: - Contact sheet

/// Render `tiles` arranged in a `cols × rows` grid. Each tile is the
/// env image (already generated) with a label below it.
func makeContactSheet(tiles: [(image: CGImage, label: String)],
                      cols: Int) -> CGImage? {
    let rows = (tiles.count + cols - 1) / cols
    let tileW: Int = 512    // ~quarter of 2048, fits nicely
    let tileH: Int = 256    // ~quarter of 1024
    let labelH: Int = 24
    let padding: Int = 8

    let sheetW = cols * (tileW + padding) + padding
    let sheetH = rows * (tileH + labelH + padding) + padding

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: sheetW, height: sheetH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Background = pure black.
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

    // Draw each tile.
    for (idx, tile) in tiles.enumerated() {
        let col = idx % cols
        let row = idx / cols
        // Flip Y so row 0 is top.
        let rowFromTop = rows - 1 - row
        let x = padding + col * (tileW + padding)
        let y = padding + rowFromTop * (tileH + labelH + padding)
        let imageRect = CGRect(x: x, y: y + labelH, width: tileW, height: tileH)
        ctx.draw(tile.image, in: imageRect)

        // Label (white text on black).
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let labelRect = CGRect(x: x, y: y, width: tileW, height: labelH)

        // Draw label via NSGraphicsContext.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = NSAttributedString(string: tile.label, attributes: attrs)
        text.draw(in: labelRect.insetBy(dx: 4, dy: 4))
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
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// MARK: - Sweep definitions

/// Define the parameter sweep. Each tuple = (label, mutator) that
/// modifies a base EnvParams. Producing a 4×3 = 12-variant grid.
let sweep: [(String, (inout EnvParams) -> Void)] = [
    ("baseline v5.1", { _ in }),

    // Vary blurred-art alpha (visibility of card-art extension).
    ("blurA=0.40", { $0.blurredArtAlpha = 0.40 }),
    ("blurA=0.80", { $0.blurredArtAlpha = 0.80 }),
    ("blurA=1.00", { $0.blurredArtAlpha = 1.00 }),

    // Vary glow brightness.
    ("glow dim",       { $0.glowCenterAlpha = 0.60; $0.glowMidAlpha = 0.40 }),
    ("glow bright",    { $0.glowCenterAlpha = 1.20; $0.glowMidAlpha = 0.95 }),

    // Vary glow radius.
    ("glow tight 0.45", { $0.glowRadiusFraction = 0.45 }),
    ("glow huge 1.10",  { $0.glowRadiusFraction = 1.10 }),

    // Vary vignette intensity.
    ("vignette 0.15", { $0.vignetteAlpha = 0.15 }),
    ("vignette 0.50", { $0.vignetteAlpha = 0.50 }),

    // Vary base darkness.
    ("base dark 0.95", { $0.baseDarkening = 0.95 }),  // very dark
    ("base light 0.65", { $0.baseDarkening = 0.65 }), // more palette tint visible
]

// MARK: - Color helpers

func blend(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat), t: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    let s = max(0, min(1, t))
    return (
        a.0 + (b.0 - a.0) * s,
        a.1 + (b.1 - a.1) * s,
        a.2 + (b.2 - a.2) * s
    )
}

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: hero_shot_sim <card-art.png> [output-dir]")
    exit(1)
}

let cardPath = args[1]
let outDir = args.count >= 3 ? args[2] : FileManager.default.currentDirectoryPath

guard let cardArt = loadImage(at: cardPath) else {
    print("Failed to load \(cardPath)")
    exit(1)
}

print("Card art loaded: \(cardArt.width)×\(cardArt.height)")

let palette = extractPalette(from: cardArt, count: 3)
print("Palette: \(palette.map { (String(format: "(%.2f,%.2f,%.2f)", $0.0, $0.1, $0.2)) }.joined(separator: " "))")

print("Rendering \(sweep.count) env-image variants…")

var tiles: [(image: CGImage, label: String)] = []
for (label, mutator) in sweep {
    var params = EnvParams()
    mutator(&params)
    if let img = makeEnvImage(cardArt: cardArt, palette: palette, params: params) {
        tiles.append((image: img, label: label))
    } else {
        print("  ✗ \(label)")
    }
}

print("Building contact sheet (\(tiles.count) tiles, 4 cols)…")
guard let sheet = makeContactSheet(tiles: tiles, cols: 4) else {
    print("Failed to build contact sheet")
    exit(1)
}

let outPath = (outDir as NSString).appendingPathComponent("sweep.png")
if savePNG(sheet, to: outPath) {
    print("→ \(outPath)")
} else {
    print("Failed to save \(outPath)")
    exit(1)
}
