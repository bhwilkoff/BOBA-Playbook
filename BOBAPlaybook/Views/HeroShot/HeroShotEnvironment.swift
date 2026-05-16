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

    /// Generate the env-extension image from a card.
    ///
    /// v5 layout: dark cinematic stage with a centered palette-color
    /// glow halo behind the card. The card-art-extension is present
    /// as a SUBTLE blurred underlayer (alpha 0.30) — the colors carry
    /// through but don't compete with the card itself. Drops the
    /// treatment overlay (was too aggressive — particles + glow now
    /// carry the treatment energy instead).
    ///
    /// Net effect: looking past the card, you see a dark gallery with
    /// soft palette-color light spilling from BEHIND the card. The card
    /// itself remains the only fully-saturated thing in the frame.
    static func generateImage(frontArt: UIImage,
                              treatment _: String?,
                              palette: [UIColor]) -> CGImage? {
        let outSize = CGSize(width: envWidth, height: envHeight)
        let renderer = UIGraphicsImageRenderer(size: outSize)
        let composed = renderer.image { ctx in
            let cg = ctx.cgContext

            // ── Layer 1: dark cinematic base ────────────────────────
            // Near-black, slightly tinted by the palette so the whole
            // scene has a unified color identity.
            let baseDark = blendColor(palette.first ?? .darkGray, with: .black, t: 0.88)
            cg.setFillColor(baseDark.cgColor)
            cg.fill(CGRect(origin: .zero, size: outSize))

            // ── Layer 2: visible blurred card art ───────────────────
            // The "extension of the card art" cue. v5 had this at 30%
            // alpha — user couldn't see it at all, env read as "just
            // a gradient." v5.1 raises to 65% so the card art clearly
            // extends into the env. Ambient-blur saturation also
            // raised so the colors are vivid (see `ambientBlur`).
            if let ambient = ambientBlur(of: frontArt, targetSize: outSize) {
                cg.saveGState()
                cg.setAlpha(0.65)
                ambient.draw(in: CGRect(origin: .zero, size: outSize))
                cg.restoreGState()
            }

            // ── Layer 3: centered palette glow ──────────────────────
            // The "backlight" behind the card. v5 was too dim
            // (peak alpha 0.85, radius 55%). v5.1 boosts to alpha 1.0
            // at center and radius 75% so the glow actually fills the
            // visible frame at every camera framing.
            let glowCenter = CGPoint(x: outSize.width / 2, y: outSize.height / 2)
            let glowRadius = outSize.height * 0.75
            let primary = palette.first ?? .white
            let glowColors = [
                primary.cgColor,                              // full alpha at center
                primary.withAlphaComponent(0.75).cgColor,
                primary.withAlphaComponent(0.25).cgColor,
                primary.withAlphaComponent(0.0).cgColor
            ] as CFArray
            let glowLocs: [CGFloat] = [0.0, 0.30, 0.70, 1.0]
            let space = CGColorSpaceCreateDeviceRGB()
            if let glowGrad = CGGradient(colorsSpace: space,
                                         colors: glowColors,
                                         locations: glowLocs) {
                cg.saveGState()
                cg.setBlendMode(.screen)
                cg.drawRadialGradient(
                    glowGrad,
                    startCenter: glowCenter, startRadius: 0,
                    endCenter:   glowCenter, endRadius:   glowRadius,
                    options: []
                )
                cg.restoreGState()
            }

            // ── Layer 4: edge vignette (lighter) ────────────────────
            // v5's vignette at alpha 0.55 was crushing the env into
            // darkness. v5.1 drops to 0.30 so vignette frames the
            // composition without dimming the whole stage.
            let vignetteColors = [
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.30).cgColor
            ] as CFArray
            let vignetteLocs: [CGFloat] = [0.0, 0.60, 1.0]
            let vignetteRadius = max(outSize.width, outSize.height) * 0.70
            if let vGrad = CGGradient(colorsSpace: space,
                                      colors: vignetteColors,
                                      locations: vignetteLocs) {
                cg.drawRadialGradient(
                    vGrad,
                    startCenter: glowCenter, startRadius: 0,
                    endCenter:   glowCenter, endRadius:   vignetteRadius,
                    options: []
                )
            }
        }
        return composed.cgImage
    }

    /// Linear blend of two UIColors in sRGB.
    private static func blendColor(_ a: UIColor, with b: UIColor, t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 1
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 1
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let s = max(0, min(1, t))
        return UIColor(
            red:   ar + (br - ar) * s,
            green: ag + (bg - ag) * s,
            blue:  ab + (bb - ab) * s,
            alpha: aa + (ba - aa) * s
        )
    }

    // MARK: - Ambient blur (Apple Music technique)

    /// Saturate + Gaussian-blur the source, then mirror-tile to fill
    /// the equirectangular canvas. Returns a UIImage at `targetSize`.
    private static func ambientBlur(of image: UIImage,
                                    targetSize: CGSize) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)

        // v5.1 — ambient layer is rendered at 65% alpha (was 30%) so
        // we want the colors VIVID, not muted. Saturation 1.30 lifts
        // the card art's hues; brightness -0.05 (barely below neutral)
        // so the blurred art carries its own light into the env.
        let saturate = CIFilter.colorControls()
        saturate.inputImage = ci
        saturate.saturation = 1.30
        saturate.brightness = -0.05
        saturate.contrast = 1.00
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

    // v5 dropped the per-treatment procedural overlay (stripes / rainbow
    // / crackle / bands). It read as noise that competed with the card
    // instead of complementing it. The treatment SIGNATURE now comes
    // from the (a) blurred-art ambient layer and (b) particle color in
    // the foreground — both of which inherit from the same palette as
    // the treatment they're trying to evoke.

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
