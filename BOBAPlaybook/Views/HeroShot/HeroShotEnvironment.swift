import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import RealityKit

/// Generates the "ambient extended" environment image used for Hero
/// Shot's IBL AND its visible backdrop plane. The technique mirrors
/// what music apps (Apple Music, Spotify "now playing") use to make
/// album art feel like it extends into the room: heavy Gaussian blur
/// + saturation boost + mirror tile of the source image. Plus a
/// treatment-keyed procedural overlay (Battlefoil stripes, Superfoil
/// rainbow, Blizzard crackle, etc.) so the card's foil signature
/// reads in the environment too.
///
/// Output is a 2048×1024 equirectangular CGImage suitable for both:
/// - `EnvironmentResource(equirectangular:)` for IBL
/// - `TextureResource(image:)` on a backdrop plane
@available(iOS 18.0, *)
enum HeroShotEnvironment {

    /// Equirectangular dimensions — 2:1 ratio as RealityKit's IBL
    /// expects. 2048×1024 is a good balance of detail vs memory.
    static let envWidth = 2048
    static let envHeight = 1024

    /// Generate the env-extension image from a card. Returns a CGImage
    /// safe to pass to `EnvironmentResource(equirectangular:)` AND
    /// `TextureResource(image:)`.
    static func generateImage(frontArt: UIImage,
                              treatment: String?,
                              palette: [UIColor]) -> CGImage? {
        let outSize = CGSize(width: envWidth, height: envHeight)
        let renderer = UIGraphicsImageRenderer(size: outSize)
        let composed = renderer.image { ctx in
            // ── Step 1: ambient blur ────────────────────────────────
            // The "Apple Music technique": saturate the source image,
            // then blur it heavily, then mirror-tile to fill the
            // canvas. The result reads as "the same colors/vibe as
            // the card, extended through space."
            if let ambient = ambientBlur(of: frontArt, targetSize: outSize) {
                ambient.draw(in: CGRect(origin: .zero, size: outSize))
            } else {
                // Fallback: fill with the dominant palette color.
                ctx.cgContext.setFillColor((palette.first ?? .darkGray).cgColor)
                ctx.cgContext.fill(CGRect(origin: .zero, size: outSize))
            }

            // ── Step 2: treatment overlay ───────────────────────────
            // Procedurally drawn pattern keyed by `treatment`. Blended
            // ON TOP of the ambient layer so the card's foil signature
            // (battlefoil stripes, superfoil rainbow, etc.) shows in
            // the environment too. Each overlay knows what blend mode
            // best preserves the ambient color.
            drawTreatmentOverlay(treatment: treatment,
                                 palette: palette,
                                 in: ctx.cgContext,
                                 size: outSize)
        }
        return composed.cgImage
    }

    // MARK: - Ambient blur (Apple Music technique)

    /// Saturate + Gaussian-blur the source, then mirror-tile to fill
    /// the equirectangular canvas. Returns a UIImage at `targetSize`.
    private static func ambientBlur(of image: UIImage,
                                    targetSize: CGSize) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)

        // Saturation boost — raw card art washes out under heavy blur.
        // v4 used 1.7 + brightness 0.05 — too aggressive, env became a
        // yellow/pale wash competing with the card. v4.1 tunes for
        // "tinted ambient frame" not "saturated centerpiece": modest
        // sat lift + slight brightness DROP so the env is dim enough
        // to let the card pop.
        let saturate = CIFilter.colorControls()
        saturate.inputImage = ci
        saturate.saturation = 1.20
        saturate.brightness = -0.10    // slight DIM so env recedes
        saturate.contrast = 1.0
        guard let saturated = saturate.outputImage else { return nil }

        // Massive Gaussian blur — radius scaled to the source image
        // so the falloff looks the same on different card dimensions.
        // The 250 radius reference from the research is for a 1200px
        // source; scale to ours.
        let sourceMaxDim = CGFloat(max(cg.width, cg.height))
        let blurRadius = sourceMaxDim * 0.21   // ~250 at 1200px

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = saturated.clampedToExtent()  // prevent edge bleed
        blur.radius = Float(blurRadius)
        guard let blurred = blur.outputImage?.cropped(to: ci.extent) else { return nil }

        // Render the blurred CIImage to a CGImage so we can tile it.
        let ciContext = CIContext()
        guard let blurredCG = ciContext.createCGImage(blurred, from: ci.extent) else { return nil }

        // Mirror-tile the blurred image to fill the equirectangular
        // canvas. UIGraphicsImageRenderer + repeated draws with
        // alternating mirror flips = the Apple Music "halo" feel.
        let tileSize: CGFloat = max(targetSize.width / 2.5, 600)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            let blurredUI = UIImage(cgImage: blurredCG)
            let tilesX = Int(ceil(targetSize.width / tileSize)) + 1
            let tilesY = Int(ceil(targetSize.height / tileSize)) + 1
            for ty in 0..<tilesY {
                for tx in 0..<tilesX {
                    cgCtx.saveGState()
                    let rect = CGRect(
                        x: CGFloat(tx) * tileSize - tileSize / 2,
                        y: CGFloat(ty) * tileSize - tileSize / 2,
                        width: tileSize, height: tileSize
                    )
                    // Mirror every-other tile for a softer continuous
                    // pattern without obvious seams.
                    let flipX = (tx + ty) % 2 == 1
                    let flipY = ty % 2 == 1
                    cgCtx.translateBy(x: rect.midX, y: rect.midY)
                    cgCtx.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
                    cgCtx.translateBy(x: -rect.midX, y: -rect.midY)
                    blurredUI.draw(in: rect)
                    cgCtx.restoreGState()
                }
            }
        }
    }

    // MARK: - Treatment overlays

    /// Draw a treatment-specific procedural overlay (stripes for
    /// Battlefoil, rainbow for Superfoil, crackle for Blizzard, etc.)
    /// onto the given context. Uses extracted palette colors so the
    /// pattern matches the card's color identity.
    private static func drawTreatmentOverlay(treatment: String?,
                                             palette: [UIColor],
                                             in cg: CGContext,
                                             size: CGSize) {
        let kind = treatmentKind(for: treatment)
        let primary = palette.first ?? .gray

        switch kind {
        case .none:
            // No overlay for base set — just the ambient blur.
            return

        // Treatment overlays in v4.1 are SUBTLE — they hint at the
        // treatment without competing with the card. v4's 0.55 / 0.40
        // / 0.55 alphas were too aggressive given the env-extension
        // backdrop is already prominent.

        case .battlefoil:
            // Diagonal stripes at 30°, primary palette color.
            cg.saveGState()
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: CGFloat.pi / 6)
            cg.translateBy(x: -size.width, y: -size.height)
            cg.setBlendMode(.softLight)
            cg.setFillColor(primary.withAlphaComponent(0.28).cgColor)
            let stripeW: CGFloat = 80
            let gap: CGFloat = 140
            var x: CGFloat = 0
            while x < size.width * 2 {
                cg.fill(CGRect(x: x, y: 0, width: stripeW, height: size.height * 2))
                x += stripeW + gap
            }
            cg.restoreGState()

        case .superfoil:
            cg.saveGState()
            cg.setBlendMode(.softLight)
            let colors: [UIColor] = palette.count >= 3
                ? Array(palette.prefix(3))
                : [primary, primary.shifted(hue: 0.33), primary.shifted(hue: -0.33)]
            for (i, color) in colors.enumerated() {
                cg.setFillColor(color.withAlphaComponent(0.18).cgColor)
                let offset = CGFloat(i) * size.height / CGFloat(colors.count + 1)
                cg.fill(CGRect(
                    x: 0,
                    y: offset + size.height * 0.1,
                    width: size.width,
                    height: size.height / CGFloat(colors.count + 1) * 0.9
                ))
            }
            cg.restoreGState()

        case .blizzard:
            cg.saveGState()
            cg.setBlendMode(.screen)
            cg.setStrokeColor(UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.28).cgColor)
            cg.setLineWidth(1.5)
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<100 {
                let cx = CGFloat.random(in: 0..<size.width, using: &rng)
                let cy = CGFloat.random(in: 0..<size.height, using: &rng)
                let spokes = Int.random(in: 3...5, using: &rng)
                for i in 0..<spokes {
                    let angle = CGFloat(i) * (2 * .pi / CGFloat(spokes))
                        + CGFloat.random(in: -0.4...0.4, using: &rng)
                    let len = CGFloat.random(in: 40...120, using: &rng)
                    cg.move(to: CGPoint(x: cx, y: cy))
                    cg.addLine(to: CGPoint(x: cx + cos(angle) * len, y: cy + sin(angle) * len))
                }
            }
            cg.strokePath()
            cg.restoreGState()

        case .inspiredInk:
            cg.saveGState()
            cg.setBlendMode(.softLight)
            let colors = palette.prefix(2).map { $0 } + [primary]
            let bands = 12
            let bandW = size.width / CGFloat(bands)
            for i in 0..<bands {
                let color = colors[i % colors.count]
                cg.setFillColor(color.withAlphaComponent(0.22).cgColor)
                cg.fill(CGRect(x: CGFloat(i) * bandW, y: 0, width: bandW * 0.6, height: size.height))
            }
            cg.restoreGState()
        }
    }

    private enum TreatmentKind {
        case none, battlefoil, superfoil, blizzard, inspiredInk
    }

    private static func treatmentKind(for treatment: String?) -> TreatmentKind {
        guard let t = treatment?.lowercased(), !t.isEmpty else { return .none }
        if t == "base" || t == "base set" || t == "standard" { return .none }
        if t.contains("superfoil") || t.contains("logofoil") { return .superfoil }
        if t.contains("blizzard")  { return .blizzard }
        if t.contains("inspired") || t.contains("ink") { return .inspiredInk }
        if t.contains("battlefoil") { return .battlefoil }
        if t.contains("blast") || t.contains("paper") { return .none }
        return .battlefoil  // unknown foil → diagonal stripes
    }

    // MARK: - Palette extraction

    /// Extract up to N dominant colors from a card image using
    /// downsampling + per-pixel HSV sorting. Targets ~30ms on a
    /// modern iPhone. Filters out near-grey / near-black pixels
    /// (typically chrome/border, not card art).
    ///
    /// Returns colors ordered by `saturation × brightness × count` so
    /// vivid colors beat populous-but-dull greys.
    static func extractPalette(from image: UIImage, count: Int = 3) -> [UIColor] {
        // Center-crop to the art area (drop top/bottom 12% chrome).
        guard let cg = image.cgImage else { return [.gray] }
        let cropRect = CGRect(
            x: cg.width / 8,
            y: cg.height * 12 / 100,
            width: cg.width * 3 / 4,
            height: cg.height * 76 / 100
        )
        let cropped = cg.cropping(to: cropRect) ?? cg

        // Resize to a small buffer for fast pixel iteration.
        let downSize = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: downSize)
        let small = renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: downSize))
        }
        guard let smallCG = small.cgImage,
              let provider = smallCG.dataProvider,
              let pixelData = provider.data,
              let bytes = CFDataGetBytePtr(pixelData) else {
            return [.gray]
        }

        // Bucket pixels by quantized hue, weight by sat × val.
        // 24 hue bins is enough to distinguish reds/oranges/blues/etc.
        let bins = 24
        var weights = [CGFloat](repeating: 0, count: bins)
        var rsum = [CGFloat](repeating: 0, count: bins)
        var gsum = [CGFloat](repeating: 0, count: bins)
        var bsum = [CGFloat](repeating: 0, count: bins)

        let bpp = smallCG.bitsPerPixel / 8
        let totalPixels = Int(downSize.width) * Int(downSize.height)
        for i in 0..<totalPixels {
            let r: CGFloat = CGFloat(bytes[i * bpp + 0]) / 255
            let g: CGFloat = CGFloat(bytes[i * bpp + 1]) / 255
            let b: CGFloat = CGFloat(bytes[i * bpp + 2]) / 255
            let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
            if v < 0.15 { continue }   // too dark
            if s < 0.20 { continue }   // too grey
            let bin = min(bins - 1, Int(h * CGFloat(bins)))
            let w: CGFloat = s * v
            weights[bin] += w
            rsum[bin] += r * w
            gsum[bin] += g * w
            bsum[bin] += b * w
        }

        // Sort bins by weight, take the top `count` with non-zero weight.
        let indexed = (0..<bins).map { ($0, weights[$0]) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
        let colors: [UIColor] = indexed.map { (bin, w) in
            UIColor(
                red:   rsum[bin] / w,
                green: gsum[bin] / w,
                blue:  bsum[bin] / w,
                alpha: 1.0
            )
        }
        return colors.isEmpty ? [.gray] : colors
    }

    private static func rgbToHSV(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
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
}

private extension UIColor {
    /// Shift hue by a delta in [-1, 1]. Wraps around.
    func shifted(hue delta: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 1
        getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        var newH = h + delta
        if newH > 1 { newH -= 1 } else if newH < 0 { newH += 1 }
        return UIColor(hue: newH, saturation: s, brightness: v, alpha: a)
    }
}
