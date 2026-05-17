// Phase 2 simulator — actually renders a RealityKit scene on Mac and
// produces a contact sheet of card-material × lighting variants. Lets
// me iterate on card material (Unlit / PBR / Unlit+overlay) and
// lighting (none / directional / IBL / etc.) WITHOUT per-tweak iOS
// test cycles, just like the env-image sim does for backdrop work.
//
// RealityFoundation + Metal + AVFoundation all work on macOS 15+ so
// the same offline-render pipeline that ships on iOS 18 runs here.
//
// Build + run:
//   cd tools/HeroShotSim
//   swiftc -O sim3d.swift -o sim3d
//   ./sim3d test_card.jpg [output-dir]
//
// Output: sim3d_sweep.png in output dir — contact sheet of all
// (material × lighting) variants rendered at fixed hero-pose camera.

import Foundation
import CoreGraphics
import CoreImage
import RealityKit
import Metal
import MetalKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Variants

enum MaterialMode: String, CaseIterable {
    /// Current iOS ship — UnlitMaterial with alpha-blend. Texture
    /// shows exactly as printed, no lighting interaction.
    case unlit
    /// PhysicallyBasedMaterial, low roughness (0.30), no clearcoat.
    /// Reacts to lights and IBL. Was rejected in v4 because it blew
    /// out — re-testing here with much dimmer lighting.
    case pbr_lowR
    /// PBR with clearcoat 0.30 / clearcoatRoughness 0.10. Simulates
    /// the card's protective varnish layer for a "fresh from pack"
    /// sheen on top of the matte baseColor.
    case pbr_clearcoat
    /// PBR mostly-matte (roughness 0.65) — closer to actual printed
    /// card paper than the glossier variants.
    case pbr_matte
    /// UnlitMaterial + an additive "fake rim glow" plane in front of
    /// the card. Card art shows true to source AND there's a soft
    /// palette-tinted glow halo around the edges. No PBR, no risk of
    /// blowout.
    case unlit_with_glow_plane

    var displayName: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

enum LightingMode: String, CaseIterable {
    /// No lights, no IBL.
    case none
    /// DirectionalLight 10,000 (lumen/m²).
    case dir_10k
    /// DirectionalLight 30,000.
    case dir_30k
    /// DirectionalLight 80,000.
    case dir_80k
    /// IBL at intensityExponent 1.0 (2× default).
    case ibl_1
    /// IBL at intensityExponent 2.0 (4× default).
    case ibl_2
    /// IBL exp 1.0 + DirectionalLight 30k.
    case ibl_1_plus_dir
    /// IBL exp 2.0 + DirectionalLight 30k.
    case ibl_2_plus_dir

    var displayName: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

// MARK: - Color helpers (duplicated from main.swift; tiny and self-contained)

typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

func toCGColor(_ c: RGB, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
}

func blendRGB(_ a: RGB, _ b: RGB, t: CGFloat) -> RGB {
    let s = max(0, min(1, t))
    return (a.r + (b.r - a.r) * s,
            a.g + (b.g - a.g) * s,
            a.b + (b.b - a.b) * s)
}

func hueShifted(_ c: RGB, byHue delta: CGFloat, satScale: CGFloat = 1.0) -> RGB {
    let (h, s, v) = rgbToHSV(c.r, c.g, c.b)
    var newH = h + delta
    if newH > 1 { newH -= 1 } else if newH < 0 { newH += 1 }
    let newS = max(0, min(1, s * satScale))
    return hsvToRGB(newH, newS, v)
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
    return (h, mx > 0 ? d / mx : 0, mx)
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

// MARK: - Palette extraction (HSV bucketing, same as main.swift)

func extractPalette(from image: CGImage, count: Int = 3) -> [RGB] {
    let cropRect = CGRect(
        x: image.width / 8, y: image.height * 12 / 100,
        width: image.width * 3 / 4, height: image.height * 76 / 100
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
    let total = downSize * downSize
    let bins = 24
    var weights = [CGFloat](repeating: 0, count: bins)
    var rsum = [CGFloat](repeating: 0, count: bins)
    var gsum = [CGFloat](repeating: 0, count: bins)
    var bsum = [CGFloat](repeating: 0, count: bins)
    for i in 0..<total {
        let r = CGFloat(bytes[i * bpp + 0]) / 255
        let g = CGFloat(bytes[i * bpp + 1]) / 255
        let b = CGFloat(bytes[i * bpp + 2]) / 255
        let (h, s, v) = rgbToHSV(r, g, b)
        if v < 0.15 || s < 0.20 { continue }
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

// MARK: - Generate env image (v6 — sweep multiple approaches)

enum EnvVariant: String, CaseIterable {
    /// v5.3 baseline — dark base + ambient blur + two screen lights.
    case baseline
    /// + 5 hard-edge diagonal stripes in rim color (Battlefoil-cue).
    case diagonalStripes
    /// + 2 converging "stage spotlight" beams from upper corners.
    case spotlightBeams
    /// + Sharper card-art carry-through (less blur, larger copies).
    case sharperAmbient
    /// Single intense centered spotlight, very dark periphery.
    case dramaticSpotlight
    /// Architectural radial-burst lines + chunky vignette frame.
    case architecturalBurst
    /// design tightly concentrated in the camera-visible window
    /// (~13×18% center of the env canvas).
    case tightFocus
    /// v5.5 ship — huge zoomed card art (1.8×), blurred, alpha 0.85.
    case deepDive
    /// **v7 (cleanStudio)** — no card-art carry-through; neutral dark
    /// near-black canvas (#0A0A12) with a single very-subtle palette-
    /// accent radial spot and a complementary rim-color spot. NO
    /// architectural shapes, NO card art zoom. Lets the card's own
    /// art carry all the chroma in the frame — env is pure stage.
    case cleanStudio

    var displayName: String { rawValue }
}

enum FloorVariant: String, CaseIterable {
    /// v5.4 ship — solid palette tint blended 45% to black.
    case solid
    /// Radial gradient: palette primary at card center → near-black.
    case radialSpot
    /// Env image darkened, used as floor texture.
    case envEcho
    /// **v7** — neutral dark radial gradient. NO palette tinting.
    /// Center: charcoal-blue #2A2A36. Edges: near-black #050508.
    /// Removes the "brown floor for warm palettes" failure mode.
    /// Sim with test_card_fire confirmed palette-tinted floors go
    /// muddy brown for warm cards; neutral dark stays clean.
    case neutralDark
    /// **v7 alt** — no floor visible. Backdrop only. Tests whether
    /// the card "floating in dark space" reads as more premium than
    /// any floor at all.
    case none

    var displayName: String { rawValue }
}

/// Sets of real 3D scene elements to add (positioned in world space,
/// visible to the camera as actual geometry — not painted into the env).
enum SceneElements: String, CaseIterable {
    /// v5.5 baseline — no extra scene elements beyond card + backdrop +
    /// floor.
    case none
    /// Rim-light halo plane behind the card. Glowing circle texture
    /// in palette color; peeks out around the card silhouette.
    case rimHalo
    /// Three thin vertical light-beam planes positioned diagonally
    /// behind the card. Glowing palette + rim colors.
    case lightBeams
    /// Six small accent glow spheres at specific 3D positions around
    /// the card. Read as floating specular highlights.
    case accentGlows
    /// Low cylindrical pedestal under the card. Palette-tinted top,
    /// dark sides — the card sits ON a stage instead of floating.
    case pedestal
    /// All elements combined: rim halo + light beams + accent glows
    /// + pedestal. The "premium tech demo" stack.
    case fullStage

    var displayName: String { rawValue }
}

func makeEnvImage(cardArt: CGImage, palette: [RGB],
                  variant: EnvVariant = .baseline) -> CGImage? {
    let envW = 1536, envH = 2048
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: envW, height: envH,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let rim = hueShifted(primary, byHue: 0.42, satScale: 0.85)

    // Dark base — variant-specific darkness.
    let darkT: CGFloat
    let basePalette: RGB
    switch variant {
    case .dramaticSpotlight:
        darkT = 0.95
        basePalette = primary
    case .cleanStudio:
        // v7 — base is BLUE-charcoal, NOT palette-tinted. Mixing the
        // palette into the base is what produced "brown for warm
        // cards" feedback. The base must stay palette-neutral; only
        // the accent spots above tint with palette.
        darkT = 0.0   // not used — direct color
        basePalette = (0.04, 0.04, 0.07)   // #0A0A12 charcoal-blue
    default:
        darkT = 0.85
        basePalette = primary
    }
    let dark: RGB = variant == .cleanStudio
        ? basePalette
        : blendRGB(basePalette, (0, 0, 0), t: darkT)
    ctx.setFillColor(toCGColor(dark))
    ctx.fill(CGRect(x: 0, y: 0, width: envW, height: envH))

    // Card-art ambient layer — alpha + blur varies by variant.
    // deepDive + cleanStudio both skip the default ambient blur:
    //   deepDive draws its own (zoomed, single copy, no tiling)
    //   cleanStudio uses NO card-art carry-through (the whole point —
    //   was the "brown stain" source for warm palettes).
    if variant != .deepDive && variant != .cleanStudio {
        let ambientAlpha: CGFloat
        let ambientBlurFrac: CGFloat
        switch variant {
        case .sharperAmbient: ambientAlpha = 0.65; ambientBlurFrac = 0.10
        case .dramaticSpotlight: ambientAlpha = 0.25; ambientBlurFrac = 0.21
        default: ambientAlpha = 0.45; ambientBlurFrac = 0.21
        }
        if let blurred = ambientBlur(of: cardArt, blurFraction: ambientBlurFrac) {
            ctx.saveGState()
            ctx.setAlpha(ambientAlpha)
            ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: envW, height: envH))
            ctx.restoreGState()
        }
    }

    // Architectural overlays per variant.
    switch variant {
    case .baseline, .sharperAmbient:
        break
    case .diagonalStripes:
        drawDiagonalStripes(ctx: ctx, w: envW, h: envH, color: rim,
                            count: 5, alpha: 0.28)
    case .spotlightBeams:
        drawSpotlightBeams(ctx: ctx, w: envW, h: envH,
                           palette: primary, rim: rim)
    case .dramaticSpotlight:
        // Single intense central spotlight — palette primary.
        drawLightSpot(ctx: ctx, color: primary,
                      center: CGPoint(x: CGFloat(envW) * 0.5,
                                      y: CGFloat(envH) * 0.5),
                      radius: CGFloat(envH) * 0.55,
                      centerAlpha: 1.0, midAlpha: 0.50, midStop: 0.20)
        // Heavy edge vignette pulls periphery to black.
        drawEdgeVignette(ctx: ctx, w: envW, h: envH, strength: 0.65)
    case .architecturalBurst:
        drawRadialBurst(ctx: ctx, w: envW, h: envH,
                        color: rim, rayCount: 12, alpha: 0.22)
        // Thin frame inset (architecture rectangle) inside visible window.
        drawFrameLine(ctx: ctx, w: envW, h: envH,
                      insetFrac: 0.42, color: rim, alpha: 0.45,
                      lineWidthPx: 6)
    case .tightFocus:
        // The camera at hero pose only sees ~13% × 18% of the env at
        // center. Pack the design into that window so the user
        // actually sees it. Three design layers, all tight:
        //  1. Bright palette glow centered (visible behind card)
        //  2. Thin rim-color halo ring around the visible window
        //  3. Two short radial accents (top + bottom of visible window)
        //
        // The rest of the canvas can stay quite dark — only the IBL
        // contribution from off-screen matters at the periphery.
        let cx = CGFloat(envW) * 0.5
        let cy = CGFloat(envH) * 0.5
        let visW = CGFloat(envW) * 0.18  // slightly wider than camera FOV
        let visH = CGFloat(envH) * 0.22
        // (1) Bright palette glow filling the visible window — drives
        // strong color cast on the card area + IBL ambient.
        drawLightSpot(ctx: ctx, color: primary,
                      center: CGPoint(x: cx, y: cy),
                      radius: max(visW, visH) * 1.1,
                      centerAlpha: 1.0, midAlpha: 0.70, midStop: 0.45)
        // (2) Rim halo ring just outside the camera FOV — read as
        // "light coming from behind the card edges."
        let ringRect = CGRect(
            x: cx - visW, y: cy - visH,
            width: visW * 2, height: visH * 2
        )
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.setStrokeColor(toCGColor(rim, alpha: 0.65))
        ctx.setLineWidth(12.0)
        ctx.strokeEllipse(in: ringRect)
        ctx.restoreGState()
        // (3) Two short radial accents from top + bottom of visible
        // window pointing inward — gives the env directional energy.
        drawLightSpot(ctx: ctx, color: rim,
                      center: CGPoint(x: cx, y: cy - visH * 0.85),
                      radius: visW * 1.4,
                      centerAlpha: 0.75, midAlpha: 0.30, midStop: 0.35)
        drawLightSpot(ctx: ctx, color: primary,
                      center: CGPoint(x: cx, y: cy + visH * 0.85),
                      radius: visW * 1.4,
                      centerAlpha: 0.75, midAlpha: 0.30, midStop: 0.35)
    case .deepDive:
        // ONE huge, heavily-blurred copy of the card art that fills
        // and overflows the canvas. No multi-rotated tiling — pure
        // organic watercolor wash. The env IS the card's color world.
        if let blurred = ambientBlur(of: cardArt, blurFraction: 0.35) {
            let cgi = blurred
            // Scale 1.8× and center — the card art "zooms outward" past
            // the canvas edges, so corners get strong color spill.
            let scale: CGFloat = 1.8
            let srcAR = CGFloat(cgi.width) / CGFloat(cgi.height)
            let drawW = CGFloat(envW) * scale
            let drawH = drawW / srcAR
            let x = (CGFloat(envW) - drawW) * 0.5
            let y = (CGFloat(envH) - drawH) * 0.5
            ctx.saveGState()
            ctx.setAlpha(0.85)
            ctx.draw(cgi, in: CGRect(x: x, y: y, width: drawW, height: drawH))
            ctx.restoreGState()
        }
        // Vignette pulls corners toward black, focuses attention.
        drawEdgeVignette(ctx: ctx, w: envW, h: envH, strength: 0.55)
        // Two accents: warm palette above, cool rim below — these
        // are LARGE-radius soft lights that drive IBL contribution.
        drawLightSpot(ctx: ctx, color: primary,
                      center: CGPoint(x: CGFloat(envW) * 0.5,
                                      y: CGFloat(envH) * 0.28),
                      radius: CGFloat(envH) * 0.40,
                      centerAlpha: 0.85, midAlpha: 0.45, midStop: 0.35)
        drawLightSpot(ctx: ctx, color: rim,
                      center: CGPoint(x: CGFloat(envW) * 0.5,
                                      y: CGFloat(envH) * 0.72),
                      radius: CGFloat(envH) * 0.40,
                      centerAlpha: 0.75, midAlpha: 0.40, midStop: 0.35)
    case .cleanStudio:
        // v7 — pure dark studio. No card-art carry-through (that's
        // what produced "brown stains" for warm palettes — confirmed
        // by sim with test_card_fire). The canvas is already filled
        // with the dark base above; we only add a single very-subtle
        // palette accent + complementary rim accent. NO architectural
        // shapes. Let the card's own art carry chroma in the frame.
        drawLightSpot(ctx: ctx, color: primary,
                      center: CGPoint(x: CGFloat(envW) * 0.5,
                                      y: CGFloat(envH) * 0.42),
                      radius: CGFloat(envH) * 0.55,
                      centerAlpha: 0.55, midAlpha: 0.25, midStop: 0.35)
        drawLightSpot(ctx: ctx, color: rim,
                      center: CGPoint(x: CGFloat(envW) * 0.5,
                                      y: CGFloat(envH) * 0.62),
                      radius: CGFloat(envH) * 0.40,
                      centerAlpha: 0.35, midAlpha: 0.18, midStop: 0.35)
        // Subtle inward vignette to focus the eye.
        drawEdgeVignette(ctx: ctx, w: envW, h: envH, strength: 0.45)
    }

    // Two lights (skipped for variants with integrated light design).
    if variant != .dramaticSpotlight
        && variant != .tightFocus
        && variant != .deepDive
        && variant != .cleanStudio {
        drawLightSpot(ctx: ctx, color: primary,
                      center: CGPoint(x: CGFloat(envW) * 0.40,
                                      y: CGFloat(envH) * 0.55),
                      radius: CGFloat(envH) * 0.45,
                      centerAlpha: 1.0, midAlpha: 0.55, midStop: 0.30)
        drawLightSpot(ctx: ctx, color: rim,
                      center: CGPoint(x: CGFloat(envW) * 0.60,
                                      y: CGFloat(envH) * 0.40),
                      radius: CGFloat(envH) * 0.40,
                      centerAlpha: 0.85, midAlpha: 0.40, midStop: 0.32)
    }
    return ctx.makeImage()
}

/// Diagonal hard-edge stripes — Battlefoil architectural cue.
func drawDiagonalStripes(ctx: CGContext, w: Int, h: Int, color: RGB,
                         count: Int, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.setFillColor(toCGColor(color, alpha: alpha))
    let envW = CGFloat(w), envH = CGFloat(h)
    let bandH = envH / CGFloat(count * 3)  // stripe = 1/3 of band cell
    let spacing = envH / CGFloat(count)
    let dx = envW * 0.6                     // diagonal slope
    for i in 0..<count {
        let y = CGFloat(i) * spacing - bandH
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -envW * 0.2, y: y))
        path.addLine(to: CGPoint(x: -envW * 0.2 + dx, y: y - bandH * 4))
        path.addLine(to: CGPoint(x: envW * 1.2 + dx, y: y - bandH * 4 + envH))
        path.addLine(to: CGPoint(x: envW * 1.2, y: y + envH))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
    ctx.restoreGState()
}

/// Two converging triangular "spotlight beams" from upper corners
/// pointing at the card position (center of canvas, where camera frames).
func drawSpotlightBeams(ctx: CGContext, w: Int, h: Int,
                        palette: RGB, rim: RGB) {
    let envW = CGFloat(w), envH = CGFloat(h)
    let target = CGPoint(x: envW * 0.5, y: envH * 0.45)
    func drawBeam(origin: CGPoint, color: RGB, alpha: CGFloat, width: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        // Build a triangle from origin (narrow) widening toward target.
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let len = sqrt(dx * dx + dy * dy)
        let ux = dx / len, uy = dy / len
        // Perpendicular vector
        let px = -uy, py = ux
        // Triangle: apex at origin, two corners at target ± perp * width
        let apex = origin
        let baseL = CGPoint(x: target.x + px * width, y: target.y + py * width)
        let baseR = CGPoint(x: target.x - px * width, y: target.y - py * width)
        let path = CGMutablePath()
        path.move(to: apex)
        path.addLine(to: baseL)
        path.addLine(to: baseR)
        path.closeSubpath()
        // Linear-gradient fill from apex (bright) to base (transparent).
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [
            toCGColor(color, alpha: alpha),
            toCGColor(color, alpha: 0)
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])
        else { ctx.restoreGState(); return }
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(grad,
                               start: apex, end: target,
                               options: [])
        ctx.restoreGState()
    }
    drawBeam(origin: CGPoint(x: envW * 0.10, y: envH * 0.10),
             color: palette, alpha: 0.55, width: envW * 0.22)
    drawBeam(origin: CGPoint(x: envW * 0.90, y: envH * 0.10),
             color: rim, alpha: 0.45, width: envW * 0.22)
}

/// Radial burst of thin lines from center (architectural starburst).
func drawRadialBurst(ctx: CGContext, w: Int, h: Int, color: RGB,
                     rayCount: Int, alpha: CGFloat) {
    let envW = CGFloat(w), envH = CGFloat(h)
    let cx = envW * 0.5, cy = envH * 0.5
    let maxR = sqrt(envW * envW + envH * envH) * 0.6
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.setStrokeColor(toCGColor(color, alpha: alpha))
    ctx.setLineWidth(2.0)
    for i in 0..<rayCount {
        let angle = CGFloat(i) * .pi * 2 / CGFloat(rayCount)
        // Two rays per "ray" (slightly offset) for thicker reading.
        for off in [-0.02, 0.02] as [CGFloat] {
            let a = angle + off
            let x = cx + cos(a) * maxR
            let y = cy + sin(a) * maxR
            ctx.move(to: CGPoint(x: cx, y: cy))
            ctx.addLine(to: CGPoint(x: x, y: y))
            ctx.strokePath()
        }
    }
    ctx.restoreGState()
}

/// A thin rectangular frame inside the canvas — architectural inset.
func drawFrameLine(ctx: CGContext, w: Int, h: Int,
                   insetFrac: CGFloat, color: RGB,
                   alpha: CGFloat, lineWidthPx: CGFloat) {
    let envW = CGFloat(w), envH = CGFloat(h)
    let insetX = envW * insetFrac
    let insetY = envH * insetFrac
    let rect = CGRect(
        x: insetX, y: insetY,
        width: envW - 2 * insetX, height: envH - 2 * insetY
    )
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.setStrokeColor(toCGColor(color, alpha: alpha))
    ctx.setLineWidth(lineWidthPx)
    ctx.stroke(rect)
    ctx.restoreGState()
}

/// Edge vignette — radial gradient pulling corners darker.
func drawEdgeVignette(ctx: CGContext, w: Int, h: Int, strength: CGFloat) {
    let envW = CGFloat(w), envH = CGFloat(h)
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [
        toCGColor((0, 0, 0), alpha: 0),
        toCGColor((0, 0, 0), alpha: 0),
        toCGColor((0, 0, 0), alpha: strength)
    ] as CFArray
    guard let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.50, 1.0])
    else { return }
    ctx.saveGState()
    ctx.drawRadialGradient(g,
                           startCenter: CGPoint(x: envW / 2, y: envH / 2),
                           startRadius: 0,
                           endCenter: CGPoint(x: envW / 2, y: envH / 2),
                           endRadius: max(envW, envH) * 0.70,
                           options: [])
    ctx.restoreGState()
}

func ambientBlur(of image: CGImage, blurFraction: CGFloat = 0.21) -> CGImage? {
    let ci = CIImage(cgImage: image)
    let sat = CIFilter(name: "CIColorControls")!
    sat.setValue(ci, forKey: "inputImage")
    sat.setValue(1.20, forKey: "inputSaturation")
    sat.setValue(-0.05, forKey: "inputBrightness")
    sat.setValue(1.0, forKey: "inputContrast")
    guard let saturated = sat.outputImage else { return nil }
    let blur = CIFilter(name: "CIGaussianBlur")!
    blur.setValue(saturated.clampedToExtent(), forKey: "inputImage")
    blur.setValue(CGFloat(max(image.width, image.height)) * blurFraction, forKey: "inputRadius")
    guard let blurred = blur.outputImage?.cropped(to: ci.extent) else { return nil }
    return CIContext().createCGImage(blurred, from: ci.extent)
}

func drawLightSpot(ctx: CGContext, color: RGB, center: CGPoint, radius: CGFloat,
                   centerAlpha: CGFloat, midAlpha: CGFloat, midStop: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [
        toCGColor(color, alpha: centerAlpha),
        toCGColor(color, alpha: centerAlpha * midAlpha),
        toCGColor(color, alpha: 0)
    ] as CFArray
    guard let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, midStop, 1.0])
    else { return }
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

// MARK: - Build RealityKit scene

let cardW: Float = 0.0635
let cardH: Float = 0.0889
let halfT: Float = 0.00015
let cornerR: Float = 0.0025

// MARK: - Full card-pivot setup (mirrors BOBACardEntity.build, .upright)
//
// Sim parity with iOS BOBACardEntity is essential for diagnosing the
// "card flashes black during rotation" bug — needs front + back + edge
// planes with exact same orientation chain + materials as iOS.

@MainActor
func buildCardPivot(frontTex: TextureResource,
                    backTex: TextureResource?,
                    palette: [RGB]) throws -> (pivot: Entity,
                                                front: ModelEntity,
                                                back: ModelEntity,
                                                edge: ModelEntity) {
    let pivot = Entity()
    pivot.name = "card-pivot"

    // FRONT plane — PhysicallyBasedMaterial, opacityThreshold alpha-test.
    var frontMat = PhysicallyBasedMaterial()
    frontMat.baseColor = .init(tint: .white, texture: .init(frontTex))
    frontMat.metallic = 0.0
    frontMat.roughness = 0.40
    frontMat.clearcoat = 0.30
    frontMat.clearcoatRoughness = 0.10
    frontMat.opacityThreshold = 0.001
    // v5.7.2 — research-validated fix for "card flashes black during
    // rotation": opacityThreshold alone does NOT enable two-sided
    // rendering. Default faceCulling = .back culls the away-from-
    // camera face. Plus the back-plane's R_y(π) inverts winding so
    // its "outward" face is actually being treated as back-face. With
    // faceCulling=.none, neither problem matters — both sides render.
    frontMat.faceCulling = .none
    let front = ModelEntity(
        mesh: MeshResource.generatePlane(width: cardW, depth: cardH),
        materials: [frontMat]
    )
    front.name = "card-front"
    front.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
    front.position = SIMD3<Float>(0, 0, halfT)
    pivot.addChild(front)

    // BACK plane — same material treatment, different orientation chain.
    var backMat = PhysicallyBasedMaterial()
    if let backTex {
        backMat.baseColor = .init(tint: .white, texture: .init(backTex))
    } else {
        backMat.baseColor = .init(tint: NSColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1))
    }
    backMat.metallic = 0.0
    backMat.roughness = 0.55
    backMat.clearcoat = 0.20
    backMat.clearcoatRoughness = 0.15
    backMat.opacityThreshold = 0.001
    backMat.faceCulling = .none
    let back = ModelEntity(
        mesh: MeshResource.generatePlane(width: cardW, depth: cardH),
        materials: [backMat]
    )
    back.name = "card-back"
    back.orientation =
        simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
    back.position = SIMD3<Float>(0, 0, -halfT)
    pivot.addChild(back)

    // EDGE box — cream off-white opaque PBR.
    var edgeMat = PhysicallyBasedMaterial()
    edgeMat.baseColor = .init(tint: NSColor(white: 0.92, alpha: 1))
    edgeMat.metallic = 0.0
    edgeMat.roughness = 0.65
    let edge = ModelEntity(
        mesh: MeshResource.generateBox(size: SIMD3<Float>(
            cardW - 2 * cornerR,
            cardH - 2 * cornerR,
            halfT * 1.5
        )),
        materials: [edgeMat]
    )
    edge.name = "card-edge"
    edge.position = .zero
    pivot.addChild(edge)

    return (pivot, front, back, edge)
}

struct SceneBundle {
    let renderer: RealityRenderer
    let camera: PerspectiveCamera
}

@MainActor
func makeFloorMaterial(variant: FloorVariant,
                       envCG: CGImage?,
                       palette: [RGB]) throws -> any Material {
    switch variant {
    case .solid:
        var mat = UnlitMaterial()
        let primary = palette.first ?? (0.5, 0.5, 0.5)
        let dark = blendRGB(primary, (0, 0, 0), t: 0.45)
        mat.color = .init(tint: UIColorLikeFromRGB(dark))
        return mat
    case .radialSpot:
        // Generate a radial-gradient texture: palette primary bright at
        // center → near-black at edges. Stage spotlight feel.
        let size = 1024
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "sim3d", code: 20) }
        let primary = palette.first ?? (0.5, 0.5, 0.5)
        // Brighter top end — floor center should READ as palette color,
        // not mostly-dark. Was t=0.10 (90% palette + 10% white) — that
        // came through too desaturated against the dark periphery so
        // the floor read as flat grey at sweep view. v5.5: t=-0.20
        // (clamped via blend = 120% palette = brighter than palette
        // alone) so the highlight is a touch warmer than the base.
        let bright = blendRGB(primary, (1, 1, 1), t: 0.25)
        let mid = blendRGB(primary, (0, 0, 0), t: 0.30)
        let darkEdge = blendRGB(primary, (0, 0, 0), t: 0.70)
        let colors = [
            toCGColor(bright, alpha: 1.0),
            toCGColor(mid, alpha: 1.0),
            toCGColor(darkEdge, alpha: 1.0)
        ] as CFArray
        guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                 locations: [0.0, 0.40, 1.0])
        else { throw NSError(domain: "sim3d", code: 21) }
        let cx = CGFloat(size) / 2
        let cy = CGFloat(size) / 2
        ctx.drawRadialGradient(g,
                               startCenter: CGPoint(x: cx, y: cy),
                               startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy),
                               endRadius: CGFloat(size) * 0.65,
                               options: [])
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "sim3d", code: 22)
        }
        var mat = UnlitMaterial()
        let opts = TextureResource.CreateOptions(semantic: .color,
                                                 mipmapsMode: .allocateAndGenerateAll)
        let tex = try TextureResource(image: cg, withName: nil, options: opts)
        mat.color = .init(tint: .white, texture: .init(tex))
        return mat
    case .envEcho:
        // Floor uses a darkened copy of the env image — same world, the
        // floor IS the env. Apply 60% darken via overlay alpha.
        guard let envCG else {
            return try makeFloorMaterial(variant: .solid,
                                          envCG: nil, palette: palette)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let envW = envCG.width, envH = envCG.height
        guard let ctx = CGContext(
            data: nil, width: envW, height: envH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "sim3d", code: 23) }
        ctx.draw(envCG, in: CGRect(x: 0, y: 0, width: envW, height: envH))
        // Darken overlay.
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.fill(CGRect(x: 0, y: 0, width: envW, height: envH))
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "sim3d", code: 24)
        }
        var mat = UnlitMaterial()
        let opts = TextureResource.CreateOptions(semantic: .color,
                                                 mipmapsMode: .allocateAndGenerateAll)
        let tex = try TextureResource(image: cg, withName: nil, options: opts)
        mat.color = .init(tint: .white, texture: .init(tex))
        return mat
    case .neutralDark:
        // v7 — radial gradient using NEUTRAL DARK colors, not palette.
        // Center: #2A2A36 (charcoal-blue). Edges: #050508 (near-black).
        // Fixes the "warm palette → muddy brown floor" bug confirmed
        // in sim with test_card_fire.
        let size = 1024
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "sim3d", code: 25) }
        let colors = [
            CGColor(srgbRed: 0.165, green: 0.165, blue: 0.213, alpha: 1),  // #2A2A36
            CGColor(srgbRed: 0.078, green: 0.078, blue: 0.110, alpha: 1),  // #14141C
            CGColor(srgbRed: 0.020, green: 0.020, blue: 0.031, alpha: 1)   // #050508
        ] as CFArray
        guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                 locations: [0.0, 0.45, 1.0])
        else { throw NSError(domain: "sim3d", code: 26) }
        ctx.drawRadialGradient(g,
                               startCenter: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2),
                               startRadius: 0,
                               endCenter: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2),
                               endRadius: CGFloat(size) * 0.65,
                               options: [])
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "sim3d", code: 27)
        }
        var mat = UnlitMaterial()
        let opts = TextureResource.CreateOptions(semantic: .color,
                                                 mipmapsMode: .allocateAndGenerateAll)
        let tex = try TextureResource(image: cg, withName: nil, options: opts)
        mat.color = .init(tint: .white, texture: .init(tex))
        return mat
    case .none:
        // No floor — caller should skip adding floor entity. Return
        // a fully-transparent material as a fallback if caller doesn't
        // check.
        var mat = UnlitMaterial()
        mat.color = .init(tint: NSColor(white: 0, alpha: 0))
        mat.blending = .transparent(opacity: 0.0)
        return mat
    }
}

/// Helper to convert our RGB tuple to a sim-side UIColor analog. AppKit
/// on macOS doesn't have UIColor; RealityKit's MaterialColorParameter
/// uses NSColor on Mac. Use sRGB-init NSColor.
func UIColorLikeFromRGB(_ c: RGB) -> NSColor {
    return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
}

/// Locate the card-back PNG in this sim directory.
func locateCardBack() -> String? {
    let path = "test_card_back.png"
    if FileManager.default.fileExists(atPath: path) { return path }
    return nil
}

@MainActor
func buildScene(cardCG: CGImage,
                cardBackCG: CGImage? = nil,
                envCG: CGImage?,
                palette: [RGB],
                material: MaterialMode,
                lighting: LightingMode,
                floor: FloorVariant = .solid,
                backdropZ: Float = -0.85,
                elements: SceneElements = .none,
                cardYaw: Float = 0,
                useFullCard: Bool = false) throws -> SceneBundle {
    let renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

    let root = Entity()
    renderer.entities.append(root)

    // Backdrop with env image (so the card has something behind it to
    // interact with).
    if let envCG = envCG {
        let backdrop = ModelEntity(
            mesh: MeshResource.generatePlane(width: 2.4, depth: 3.2),
            materials: [try makeBackdropMaterial(envCG: envCG)]
        )
        backdrop.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        backdrop.position = SIMD3<Float>(0, 0.10, backdropZ)
        root.addChild(backdrop)
    }

    // Floor plane — beneath the card. Match iOS HeroShotRenderer
    // geometry: 1.6 × 1.6m at Y = -cardH * 0.5 - 0.003. Skip entirely
    // for FloorVariant.none (research: premium reels often have NO
    // visible floor — subject floats in dark space with rim lighting).
    if floor != .none {
        let floorEntity = ModelEntity(
            mesh: MeshResource.generatePlane(width: 1.6, depth: 1.6),
            materials: [try makeFloorMaterial(variant: floor, envCG: envCG, palette: palette)]
        )
        floorEntity.position = SIMD3<Float>(0, -cardH * 0.5 - 0.003, 0)
        root.addChild(floorEntity)
    }

    // Card setup — single front plane (simple, for env iteration) OR
    // full pivot with front + back + edge (matches iOS BOBACardEntity,
    // used for rotation diagnostics).
    let texOpts = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
    let cardTex = try TextureResource(image: cardCG, withName: nil, options: texOpts)
    let frontEntity: ModelEntity
    if useFullCard {
        let backTex: TextureResource?
        if let cbCG = cardBackCG {
            backTex = try? TextureResource(image: cbCG, withName: nil, options: texOpts)
        } else { backTex = nil }
        let card = try buildCardPivot(frontTex: cardTex, backTex: backTex,
                                       palette: palette)
        card.pivot.orientation = simd_quatf(angle: cardYaw,
                                             axis: SIMD3<Float>(0, 1, 0))
        root.addChild(card.pivot)
        frontEntity = card.front   // used as IBL receiver target
    } else {
        let frontMesh = MeshResource.generatePlane(width: cardW, depth: cardH)
        let frontMaterial: any Material = try makeFrontMaterial(material: material, texture: cardTex)
        frontEntity = ModelEntity(mesh: frontMesh, materials: [frontMaterial])
        frontEntity.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        frontEntity.position = SIMD3<Float>(0, 0, halfT)
        root.addChild(frontEntity)
    }

    // Optional: additive front-glow plane (for unlit_with_glow_plane).
    if material == .unlit_with_glow_plane {
        let glowPlane = ModelEntity(
            mesh: MeshResource.generatePlane(width: cardW * 1.4, depth: cardH * 1.4),
            materials: [try makeAdditiveGlowMaterial(palette: palette)]
        )
        glowPlane.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        // Position the glow plane just BEHIND the card (negative Z),
        // so it shows as a halo around the card edges.
        glowPlane.position = SIMD3<Float>(0, 0, -halfT * 4)
        root.addChild(glowPlane)
    }

    // ── 3D scene elements (v5.6) ─────────────────────────────────────
    // Real geometry positioned in world space — visible to the camera
    // as actual scene objects, not painted into the env image. Designed
    // so heroPose camera sees them around/behind the card silhouette.
    try addSceneElements(set: elements, root: root, palette: palette)

    // Lighting setup.
    try applyLighting(mode: lighting, root: root, renderer: renderer,
                      envCG: envCG, palette: palette,
                      receivers: [frontEntity])

    // Camera at hero pose.
    let camera = PerspectiveCamera()
    renderer.entities.append(camera)
    renderer.activeCamera = camera
    camera.look(at: .zero, from: SIMD3<Float>(0, 0.018, 0.21),
                upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
    camera.camera.fieldOfViewInDegrees = 30

    return SceneBundle(renderer: renderer, camera: camera)
}

@MainActor
func makeBackdropMaterial(envCG: CGImage) throws -> any Material {
    var mat = UnlitMaterial()
    let opts = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
    let tex = try TextureResource(image: envCG, withName: nil, options: opts)
    mat.color = .init(tint: .white, texture: .init(tex))
    return mat
}

@MainActor
func makeFrontMaterial(material: MaterialMode, texture: TextureResource) throws -> any Material {
    switch material {
    case .unlit, .unlit_with_glow_plane:
        var mat = UnlitMaterial()
        mat.color = .init(tint: .white, texture: .init(texture))
        mat.blending = .transparent(opacity: 1.0)
        return mat
    case .pbr_lowR:
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .white, texture: .init(texture))
        mat.metallic = 0.0
        mat.roughness = 0.30
        mat.blending = .transparent(opacity: 1.0)
        return mat
    case .pbr_clearcoat:
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .white, texture: .init(texture))
        mat.metallic = 0.0
        mat.roughness = 0.40
        mat.clearcoat = 0.30
        mat.clearcoatRoughness = 0.10
        mat.blending = .transparent(opacity: 1.0)
        return mat
    case .pbr_matte:
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .white, texture: .init(texture))
        mat.metallic = 0.0
        mat.roughness = 0.65
        mat.blending = .transparent(opacity: 1.0)
        return mat
    }
}

@MainActor
func makeAdditiveGlowMaterial(palette: [RGB]) throws -> any Material {
    // Generate a small radial-glow texture in the primary palette
    // color, then apply with transparent blending.
    let size = 512
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "sim3d", code: 1) }
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    // Fully transparent base.
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let center = CGPoint(x: size / 2, y: size / 2)
    let colors = [
        toCGColor(primary, alpha: 0.55),
        toCGColor(primary, alpha: 0.30),
        toCGColor(primary, alpha: 0)
    ] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.30, 1.0]) {
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: CGFloat(size) / 2,
                               options: [])
    }
    guard let cg = ctx.makeImage() else { throw NSError(domain: "sim3d", code: 2) }
    var mat = UnlitMaterial()
    let opts = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
    let tex = try TextureResource(image: cg, withName: nil, options: opts)
    mat.color = .init(tint: .white, texture: .init(tex))
    mat.blending = .transparent(opacity: 1.0)
    return mat
}

// MARK: - 3D scene element builders (v5.6)

@MainActor
func addSceneElements(set: SceneElements, root: Entity, palette: [RGB]) throws {
    switch set {
    case .none:
        return
    case .rimHalo:
        try addRimHalo(to: root, palette: palette)
    case .lightBeams:
        try addLightBeams(to: root, palette: palette)
    case .accentGlows:
        try addAccentGlows(to: root, palette: palette)
    case .pedestal:
        try addPedestal(to: root, palette: palette)
    case .fullStage:
        try addPedestal(to: root, palette: palette)
        try addRimHalo(to: root, palette: palette)
        try addLightBeams(to: root, palette: palette)
        try addAccentGlows(to: root, palette: palette)
    }
}

/// Glow-circle plane positioned just behind the card. The card occludes
/// the bright center; the outer falloff peeks around the silhouette as
/// a halo backlight. ~3× card size so the falloff is visible on all
/// edges. Texture: bright-center radial gradient.
@MainActor
func addRimHalo(to root: Entity, palette: [RGB]) throws {
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let texSize = 512
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: texSize, height: texSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "sim3d", code: 30) }
    let colors = [
        toCGColor(primary, alpha: 0.95),
        toCGColor(primary, alpha: 0.55),
        toCGColor(primary, alpha: 0)
    ] as CFArray
    guard let g = CGGradient(colorsSpace: cs, colors: colors,
                             locations: [0.0, 0.40, 1.0])
    else { throw NSError(domain: "sim3d", code: 31) }
    let cx = CGFloat(texSize) / 2
    ctx.drawRadialGradient(g,
                           startCenter: CGPoint(x: cx, y: cx),
                           startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cx),
                           endRadius: cx,
                           options: [])
    guard let cg = ctx.makeImage() else {
        throw NSError(domain: "sim3d", code: 32)
    }
    var mat = UnlitMaterial()
    let opts = TextureResource.CreateOptions(semantic: .color,
                                              mipmapsMode: .allocateAndGenerateAll)
    let tex = try TextureResource(image: cg, withName: nil, options: opts)
    mat.color = .init(tint: .white, texture: .init(tex))
    mat.blending = .transparent(opacity: 1.0)
    let halo = ModelEntity(
        mesh: MeshResource.generatePlane(width: cardW * 3.0, depth: cardH * 3.0),
        materials: [mat]
    )
    halo.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
    // Just behind the card, but not so far that perspective shrinks it.
    halo.position = SIMD3<Float>(0, 0, -0.015)
    root.addChild(halo)
}

/// Three thin vertical light-beam planes positioned diagonally behind
/// the card. Glowing palette + rim colors with low alpha. Read as
/// "light shafts from off-screen spotlights cutting through the scene."
@MainActor
func addLightBeams(to root: Entity, palette: [RGB]) throws {
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let rim = hueShifted(primary, byHue: 0.42, satScale: 0.85)

    func makeBeam(color: RGB, alpha: CGFloat) throws -> ModelEntity {
        // Beam texture: vertical bright-line gradient (bright center
        // fading to transparent at left/right edges).
        let w = 64, h = 512
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "sim3d", code: 33) }
        let colors = [
            toCGColor(color, alpha: 0),
            toCGColor(color, alpha: alpha),
            toCGColor(color, alpha: 0)
        ] as CFArray
        guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                 locations: [0.0, 0.5, 1.0])
        else { throw NSError(domain: "sim3d", code: 34) }
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: CGFloat(w), y: 0),
                               options: [])
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "sim3d", code: 35)
        }
        var mat = UnlitMaterial()
        let opts = TextureResource.CreateOptions(semantic: .color,
                                                  mipmapsMode: .allocateAndGenerateAll)
        let tex = try TextureResource(image: cg, withName: nil, options: opts)
        mat.color = .init(tint: .white, texture: .init(tex))
        mat.blending = .transparent(opacity: 1.0)
        let beam = ModelEntity(
            mesh: MeshResource.generatePlane(width: 0.02, depth: 0.30),
            materials: [mat]
        )
        beam.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        return beam
    }

    let beamL = try makeBeam(color: primary, alpha: 0.65)
    beamL.position = SIMD3<Float>(-0.09, 0.02, -0.08)
    beamL.orientation = simd_quatf(angle: .pi / 2,
                                    axis: SIMD3<Float>(1, 0, 0)) *
                        simd_quatf(angle: -0.18,
                                    axis: SIMD3<Float>(0, 0, 1))
    root.addChild(beamL)

    let beamR = try makeBeam(color: rim, alpha: 0.55)
    beamR.position = SIMD3<Float>(0.09, 0.02, -0.08)
    beamR.orientation = simd_quatf(angle: .pi / 2,
                                    axis: SIMD3<Float>(1, 0, 0)) *
                        simd_quatf(angle: 0.18,
                                    axis: SIMD3<Float>(0, 0, 1))
    root.addChild(beamR)

    let beamC = try makeBeam(color: primary, alpha: 0.45)
    beamC.position = SIMD3<Float>(0, 0.03, -0.12)
    beamC.orientation = simd_quatf(angle: .pi / 2,
                                    axis: SIMD3<Float>(1, 0, 0))
    root.addChild(beamC)
}

/// Six small bright glow spheres scattered behind/beside the card.
/// Read as floating specular highlights or particles, adding depth.
@MainActor
func addAccentGlows(to root: Entity, palette: [RGB]) throws {
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let rim = hueShifted(primary, byHue: 0.42, satScale: 0.85)

    let positions: [(SIMD3<Float>, RGB)] = [
        (SIMD3<Float>(-0.08,  0.05, -0.04), primary),
        (SIMD3<Float>( 0.08,  0.04, -0.04), rim),
        (SIMD3<Float>(-0.07, -0.04, -0.06), rim),
        (SIMD3<Float>( 0.07, -0.05, -0.06), primary),
        (SIMD3<Float>(-0.04,  0.07, -0.10), primary),
        (SIMD3<Float>( 0.04, -0.07, -0.10), rim),
    ]
    for (pos, color) in positions {
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColorLikeFromRGB(color))
        // sphere mesh — small glowing dot
        let glow = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.004),
            materials: [mat]
        )
        glow.position = pos
        root.addChild(glow)
    }
}

/// Low, wide box pedestal beneath the card. The card visibly sits ON
/// something instead of floating in space. Top surface palette-tinted
/// brighter, sides darker (faux ambient occlusion).
@MainActor
func addPedestal(to root: Entity, palette: [RGB]) throws {
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let top = blendRGB(primary, (1, 1, 1), t: 0.20)
    let side = blendRGB(primary, (0, 0, 0), t: 0.55)

    // Top: thin wide plate, palette-bright.
    var topMat = UnlitMaterial()
    topMat.color = .init(tint: UIColorLikeFromRGB(top))
    let pedestalTop = ModelEntity(
        mesh: MeshResource.generatePlane(width: 0.12, depth: 0.10),
        materials: [topMat]
    )
    pedestalTop.position = SIMD3<Float>(0, -cardH * 0.5 + 0.001, 0)
    root.addChild(pedestalTop)

    // Front face — short rectangle visible from camera-front.
    var sideMat = UnlitMaterial()
    sideMat.color = .init(tint: UIColorLikeFromRGB(side))
    let pedestalFront = ModelEntity(
        mesh: MeshResource.generatePlane(width: 0.12, depth: 0.012),
        materials: [sideMat]
    )
    // Stand it upright facing camera (+Z).
    pedestalFront.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
    pedestalFront.position = SIMD3<Float>(0, -cardH * 0.5 - 0.005, 0.050)
    root.addChild(pedestalFront)
}

@MainActor
func applyLighting(mode: LightingMode,
                   root: Entity,
                   renderer: RealityRenderer,
                   envCG: CGImage?,
                   palette: [RGB],
                   receivers: [Entity]) throws {
    // DirectionalLight
    let dirIntensity: Float
    switch mode {
    case .none, .ibl_1, .ibl_2:
        dirIntensity = 0
    case .dir_10k:
        dirIntensity = 10_000
    case .dir_30k, .ibl_2_plus_dir:
        dirIntensity = 30_000
    case .ibl_1_plus_dir:
        // v6.0.6: 15k. iOS HeroShotRenderer ships 22.5k, but
        // RealityFoundation on macOS overexposes the card at that
        // intensity vs RealityKit on iOS (the two renderers seem to
        // tonemap differently). Empirically 15k in sim produces an
        // image matching iOS's 22.5k exposure. The point of the sim
        // here is visual validation of the SHIMMER effect, not iOS
        // lighting parity — the shimmer overlay is a pure post-
        // process and looks the same regardless of base exposure.
        dirIntensity = 15_000
    case .dir_80k:
        dirIntensity = 80_000
    }
    if dirIntensity > 0 {
        // KEY light — upper-front-right (current, casts main shadows).
        let key = DirectionalLight()
        key.light.intensity = dirIntensity
        key.light.color = .white
        key.look(at: .zero, from: SIMD3<Float>(0.3, 0.4, 0.5),
                 relativeTo: nil)
        root.addChild(key)
        // FILL light — from camera-direction at ~40% intensity. Ensures
        // any plane visible to the camera receives some direct
        // illumination, eliminating the "black flash" failure mode I
        // diagnosed in sim — at yaw=120° the back plane's front face
        // had Lambert ≈ 0 against the upper-front key, rendering black.
        // Fill from camera direction guarantees lambert > 0 whenever
        // a surface is visible.
        let fill = DirectionalLight()
        fill.light.intensity = dirIntensity * 0.40
        fill.light.color = .white
        fill.look(at: .zero, from: SIMD3<Float>(0, 0.05, 0.5),
                  relativeTo: nil)
        root.addChild(fill)
        // RIM light — upper-back, opposite the key. Lights the back of
        // the card when it rotates past 90° so the back image isn't
        // shadowed from the key OR the fill. Intensity matches key
        // (rim is the smaller surface area; per cinematography
        // research key:fill≈3:1, key:rim≈1:1).
        let rim = DirectionalLight()
        rim.light.intensity = dirIntensity * 1.0
        rim.light.color = .white
        rim.look(at: .zero, from: SIMD3<Float>(-0.3, 0.4, -0.5),
                 relativeTo: nil)
        root.addChild(rim)
    }

    // IBL
    let iblExp: Float?
    switch mode {
    case .none, .dir_10k, .dir_30k, .dir_80k:
        iblExp = nil
    case .ibl_1:
        iblExp = 1.0
    case .ibl_1_plus_dir:
        // v6.0.6: match iOS HeroShotRenderer's IBL exp = 0.6.
        iblExp = 0.6
    case .ibl_2, .ibl_2_plus_dir:
        iblExp = 2.0
    }
    if let exp = iblExp, let envCG = envCG {
        if let env = try? EnvironmentResource(equirectangular: envCG, withName: nil) {
            let iblComp = ImageBasedLightComponent(source: .single(env),
                                                   intensityExponent: exp)
            root.components.set(iblComp)
            for receiver in receivers {
                receiver.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
            }
        }
    }
}

// MARK: - Render one frame to CGImage

@MainActor
func renderFrame(scene: SceneBundle, size: CGSize, device: MTLDevice) throws -> CGImage {
    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: Int(size.width), height: Int(size.height),
        mipmapped: false
    )
    texDesc.usage = [.renderTarget, .shaderRead]
    texDesc.storageMode = .shared
    guard let outTex = device.makeTexture(descriptor: texDesc) else {
        throw NSError(domain: "sim3d", code: 10)
    }
    let camOutput = try RealityRenderer.CameraOutput(
        .singleProjection(colorTexture: outTex)
    )
    let group = DispatchGroup()
    group.enter()
    try scene.renderer.updateAndRender(
        deltaTime: 1.0 / 60.0,
        cameraOutput: camOutput,
        onComplete: { _ in group.leave() }
    )
    group.wait()

    // Convert MTLTexture → CGImage via CIImage.
    guard let ci = CIImage(mtlTexture: outTex, options: nil) else {
        throw NSError(domain: "sim3d", code: 11)
    }
    let ciCtx = CIContext(mtlDevice: device)
    // CIImage from MTLTexture is flipped — flip back.
    let transformed = ci.oriented(.downMirrored)
    guard let cg = ciCtx.createCGImage(transformed, from: transformed.extent) else {
        throw NSError(domain: "sim3d", code: 12)
    }
    return cg
}

// MARK: - Contact sheet (same shape as main.swift)

func makeContactSheet(tiles: [(image: CGImage, label: String)], cols: Int,
                      tileW: Int = 304, tileH: Int = 540) -> CGImage? {
    let rows = (tiles.count + cols - 1) / cols
    let labelH = 36
    let padding = 12

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
        ctx.draw(tile.image, in: CGRect(x: x, y: y + labelH, width: tileW, height: tileH))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: tile.label, attributes: attrs)
            .draw(in: CGRect(x: x + 6, y: y + 6, width: tileW - 12, height: labelH - 12))
        NSGraphicsContext.restoreGraphicsState()
    }
    return ctx.makeImage()
}

/// v6.6 — mirror of HeroShotRenderer.makeRimHaloTexture.
/// Bright palette glow with radial alpha falloff.
func makeRimHaloCG(palette: [RGB]) -> CGImage? {
    let size = 512
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    let primary = palette.first ?? (0.5, 0.5, 0.5)
    let colors: [CGColor] = [
        toCGColor(primary, alpha: 0.85),
        toCGColor(primary, alpha: 0.45),
        toCGColor(primary, alpha: 0)
    ]
    if let g = CGGradient(colorsSpace: cs, colors: colors as CFArray,
                          locations: [0.0, 0.40, 1.0]) {
        let cx = CGFloat(size) / 2
        ctx.drawRadialGradient(g,
            startCenter: CGPoint(x: cx, y: cx), startRadius: 0,
            endCenter: CGPoint(x: cx, y: cx), endRadius: cx,
            options: [])
    }
    return ctx.makeImage()
}

/// v6.5 — generate the rainbow LUT texture used by the holofoil
/// shaders. Matches BOBACardEntity.rainbowLUTTexture: 256×2, hue
/// wheel at sat 1.0 brightness 0.55.
@MainActor
func holofoilRainbowLUTTexture(device: MTLDevice) -> TextureResource? {
    let width = 256, height = 2
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    let colors: [CGColor] = (0..<7).map { i in
        let rgb = hsvToRGB(CGFloat(i) / 6.0, 1.0, 0.55)
        return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
    let locs: [CGFloat] = (0..<7).map { CGFloat($0) / 6.0 }
    guard let g = CGGradient(colorsSpace: cs, colors: colors as CFArray,
                              locations: locs) else { return nil }
    ctx.drawLinearGradient(g,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: CGFloat(width), y: 0),
        options: [])
    guard let cg = ctx.makeImage() else { return nil }
    let opts = TextureResource.CreateOptions(semantic: .color,
                                             mipmapsMode: .allocateAndGenerateAll)
    _ = device  // suppress unused warning
    return try? TextureResource(image: cg, withName: "rainbowLUT", options: opts)
}

@MainActor
func holofoilPerturbTexture(device: MTLDevice) async throws -> TextureResource? {
    let size = 256
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<24 {
        let cx = CGFloat.random(in: -0.2...1.2, using: &rng) * CGFloat(size)
        let cy = CGFloat.random(in: -0.2...1.2, using: &rng) * CGFloat(size)
        let r = CGFloat.random(in: 0.15...0.45, using: &rng) * CGFloat(size)
        let dx = CGFloat.random(in: -1...1, using: &rng)
        let dy = CGFloat.random(in: -1...1, using: &rng)
        let center = CGColor(srgbRed: 0.5 + dx * 0.45,
                              green: 0.5 + dy * 0.45,
                              blue: 0.5, alpha: 0.5)
        let edge = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0)
        let colors = [center, edge] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors,
                              locations: [0, 1]) {
            ctx.drawRadialGradient(g,
                startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                options: [])
        }
    }
    guard let cg = ctx.makeImage() else { return nil }
    let opts = TextureResource.CreateOptions(semantic: .raw,
                                             mipmapsMode: .allocateAndGenerateAll)
    _ = device
    return try? await TextureResource(image: cg, withName: "perturb",
                                       options: opts)
}

@MainActor
func holofoilFoilMaskTexture(device: MTLDevice) async throws -> TextureResource? {
    let size = 8
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    guard let cg = ctx.makeImage() else { return nil }
    let opts = TextureResource.CreateOptions(semantic: .raw, mipmapsMode: .none)
    _ = device
    return try? await TextureResource(image: cg, withName: "foilMask", options: opts)
}

/// v6.4 — mirror of HeroShotRenderer.makeShimmerOverlayTexture.
/// Produces a static diagonal-rainbow + vignette overlay texture.
func makeShimmerOverlayCG() -> CGImage? {
    let size = 512
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    // Diagonal rainbow
    let cgRainbow: [CGColor] = (0..<7).map { i in
        let h = CGFloat(i) / 6.0
        let rgb = hsvToRGB(h, 0.85, 1.0)
        return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.18)
    }
    let locs: [CGFloat] = (0..<7).map { CGFloat($0) / 6.0 }
    if let g = CGGradient(colorsSpace: cs, colors: cgRainbow as CFArray, locations: locs) {
        let diag = CGFloat(size) * 1.414
        ctx.drawLinearGradient(g,
            start: CGPoint(x: -CGFloat(size)/2, y: -CGFloat(size)/2),
            end: CGPoint(x: diag, y: diag),
            options: [])
    }
    // Radial vignette (alpha fades at edges)
    let vColors: [CGColor] = [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
    ]
    if let vg = CGGradient(colorsSpace: cs, colors: vColors as CFArray,
                            locations: [0.0, 0.40, 1.0]) {
        ctx.setBlendMode(.destinationOut)
        ctx.drawRadialGradient(vg,
            startCenter: CGPoint(x: CGFloat(size)/2, y: CGFloat(size)/2),
            startRadius: 0,
            endCenter: CGPoint(x: CGFloat(size)/2, y: CGFloat(size)/2),
            endRadius: CGFloat(size) * 0.65,
            options: [])
        ctx.setBlendMode(.normal)
    }
    return ctx.makeImage()
}

// MARK: - 4-variant iOS material comparison grid (v6.2 — REAL renders)
//
// Renders the SAME 4 material variants that iOS BOBACardEntity exposes
// (holofoilLit / pbrMatte / pbrEmissive / unlitTexture) using the
// compiled /tmp/Holofoil.metallib produced from BOBAPlaybook/Shaders/
// Holofoil.metal. Output is a 2x2 grid PNG identifying which variant
// produces the most-vivid card art.

/// CoreImage post-process matching iOS HeroShotRenderer's
/// applyExposurePass / applyExposureEV. Lets sim renders look the
/// same as iOS output so we can tune meaningfully.
func applyiOSPostProcess(_ source: CGImage, ev: Float, saturation: Float,
                          contrast: Float) -> CGImage? {
    let ci = CIImage(cgImage: source)
    let exp = CIFilter(name: "CIExposureAdjust")!
    exp.setValue(ci, forKey: kCIInputImageKey)
    exp.setValue(ev, forKey: "inputEV")
    let exposed = exp.outputImage ?? ci
    let col = CIFilter(name: "CIColorControls")!
    col.setValue(exposed, forKey: kCIInputImageKey)
    col.setValue(saturation, forKey: "inputSaturation")
    col.setValue(contrast, forKey: "inputContrast")
    col.setValue(0, forKey: "inputBrightness")
    guard let out = col.outputImage else { return nil }
    return CIContext().createCGImage(out, from: ci.extent)
}

@MainActor
func renderIOSVariant4Grid(cardCG: CGImage,
                            cardBackCG: CGImage?,
                            envCG: CGImage?,
                            palette: [RGB],
                            device: MTLDevice,
                            postEV: Float = -1.0,
                            postSaturation: Float = 1.40,
                            postContrast: Float = 1.20) async throws -> CGImage? {
    // Load the compiled holofoil shader.
    var holofoilShader: CustomMaterial.SurfaceShader?
    let libURL = URL(fileURLWithPath: "/tmp/Holofoil.metallib")
    if let lib = try? device.makeLibrary(URL: libURL) {
        holofoilShader = CustomMaterial.SurfaceShader(named: "holofoilSurface", in: lib)
    } else {
        print("[Variant4] WARN: could not load /tmp/Holofoil.metallib — variant A will fall back")
    }

    let texOpts = TextureResource.CreateOptions(semantic: .color,
                                                 mipmapsMode: .allocateAndGenerateAll)
    let cardTex = try await TextureResource(image: cardCG, withName: nil, options: texOpts)

    // Variant A — Holofoil .lit (current ship v6.2.0)
    func makeVariantA() -> any Material {
        guard let shader = holofoilShader,
              let mat = try? CustomMaterial(surfaceShader: shader,
                                             lightingModel: .lit) else {
            // Fallback to PBR matte.
            var fb = PhysicallyBasedMaterial()
            fb.baseColor = .init(tint: .white, texture: .init(cardTex))
            fb.metallic = 0.0
            fb.roughness = 0.4
            return fb
        }
        var m = mat
        m.baseColor = .init(tint: .white, texture: .init(cardTex))
        m.faceCulling = .none
        return m
    }
    // Variant B — PBR matte (no clearcoat, no spec)
    func makeVariantB() -> any Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(cardTex))
        m.metallic = 0.0
        m.roughness = 0.95
        m.opacityThreshold = 0.001
        m.faceCulling = .none
        return m
    }
    // Variant C — PBR emissive (base=black, art on emissive channel)
    func makeVariantC() -> any Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .black)
        m.emissiveColor = .init(color: .white, texture: .init(cardTex))
        m.emissiveIntensity = 1.0
        m.metallic = 0.0
        m.roughness = 1.0
        m.opacityThreshold = 0.001
        m.faceCulling = .none
        return m
    }
    // Variant D — UnlitMaterial
    func makeVariantD() -> any Material {
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(cardTex))
        m.blending = .transparent(opacity: 1.0)
        return m
    }
    // Variant E — CustomMaterial (.unlit) + holofoil shader. Tests
    // whether the shader can run on an unlit pipeline. v6.1.0 ship
    // this exactly and the card came out BLACK on iOS — but that
    // was on-device. Let me see what the sim does.
    func makeVariantE() -> any Material {
        guard let shader = holofoilShader,
              let mat = try? CustomMaterial(surfaceShader: shader,
                                             lightingModel: .unlit) else {
            return makeVariantD()
        }
        var m = mat
        m.baseColor = .init(tint: .white, texture: .init(cardTex))
        m.faceCulling = .none
        return m
    }
    // Variant F — Unlit card + transparent shimmer overlay plane.
    // The shimmer overlay uses CustomMaterial(.lit) with the holofoil
    // shader BUT the underlying card uses UnlitMaterial. The shimmer
    // plane is positioned at z=halfT+0.001 (1mm in front of card)
    // and uses .transparent blending so the unlit card shows through.
    //
    // Implementation note: variants A-E are MaterialMode that swap on
    // a single mesh. Variant F is structurally different — it adds a
    // SECOND mesh in front of the card. We render it via a special
    // path below.

    let labels = ["A · holofoilLit", "B · pbrMatte", "C · pbrEmissive",
                  "D · unlitTexture", "E · custom(unlit)+shader",
                  "F · unlit+shimmerOverlay"]
    let materials: [any Material] = [makeVariantA(), makeVariantB(),
                                      makeVariantC(), makeVariantD(),
                                      makeVariantE(), makeVariantD()]
                                      // F's base is unlit; overlay added below
    var rendered: [(img: CGImage, label: String)] = []

    let frameSize = CGSize(width: 540, height: 960)
    for (i, material) in materials.enumerated() {
        // Render one scene per variant — match v5.7.2 3-point lighting +
        // env backdrop. Card front material is swapped per iteration;
        // back + edge stay PBR.
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let root = Entity()
        renderer.entities.append(root)

        // Backdrop
        if let envCG = envCG {
            let bd = ModelEntity(
                mesh: MeshResource.generatePlane(width: 2.4, depth: 3.2),
                materials: [try makeBackdropMaterial(envCG: envCG)]
            )
            bd.orientation = simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1,0,0))
            bd.position = SIMD3<Float>(0, 0.10, -0.40)
            root.addChild(bd)
        }

        // v6.6 — rim halo behind card (matches iOS v6.6 setup).
        if let haloCG = makeRimHaloCG(palette: palette) {
            do {
                let haloTex = try await TextureResource(image: haloCG,
                    withName: "halo",
                    options: TextureResource.CreateOptions(
                        semantic: .color,
                        mipmapsMode: .allocateAndGenerateAll))
                var haloMat = UnlitMaterial()
                haloMat.color = .init(tint: .white, texture: .init(haloTex))
                haloMat.blending = .transparent(opacity: 1.0)
                let halo = ModelEntity(
                    mesh: MeshResource.generatePlane(width: cardW * 1.8,
                                                      depth: cardH * 1.8),
                    materials: [haloMat]
                )
                halo.orientation = simd_quatf(angle: .pi/2,
                                                axis: SIMD3<Float>(1,0,0))
                halo.position = SIMD3<Float>(0, 0, -0.012)
                root.addChild(halo)
            } catch {}
        }

        // Card front using this variant's material
        let front = ModelEntity(
            mesh: MeshResource.generatePlane(width: cardW, depth: cardH),
            materials: [material]
        )
        front.orientation = simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1,0,0))
        front.position = SIMD3<Float>(0, 0, halfT)
        root.addChild(front)

        // v6.5 — sim's variant D is plain UnlitMaterial (matches what
        // ships in iOS) — no overlay. Variant F is unlit + sparkle
        // shader overlay which is the v6.5 ship.

        // Variant F: shimmer overlay plane using the NEW shader
        // `holofoilOverlaySparkle` which outputs shimmer with discard
        // for dim pixels, producing sparkle behavior.
        if i == 5 {
            do {
                let libURL = URL(fileURLWithPath: "/tmp/Holofoil.metallib")
                if let lib = try? device.makeLibrary(URL: libURL) {
                    let sparkleShader = CustomMaterial.SurfaceShader(
                        named: "holofoilOverlaySparkle", in: lib)
                    var overlayMat = try CustomMaterial(
                        surfaceShader: sparkleShader, lightingModel: .lit)
                    // Need a base color texture (any non-empty) for
                    // the shader to load; it doesn't actually sample
                    // it. Use a 1×1 white pixel.
                    let whiteData = Data([255, 255, 255, 255])
                    let cs = CGColorSpaceCreateDeviceRGB()
                    let providerRef = CGDataProvider(data: whiteData as CFData)!
                    if let whiteCG = CGImage(width: 1, height: 1,
                                              bitsPerComponent: 8, bitsPerPixel: 32,
                                              bytesPerRow: 4, space: cs,
                                              bitmapInfo: CGBitmapInfo(
                                                  rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                              provider: providerRef,
                                              decode: nil, shouldInterpolate: false,
                                              intent: .defaultIntent),
                       let wTex = try? await TextureResource(
                           image: whiteCG, withName: "white1px",
                           options: TextureResource.CreateOptions(semantic: .color)),
                       let rainbowLUT = holofoilRainbowLUTTexture(device: device),
                       let perturbTex = try? await holofoilPerturbTexture(device: device),
                       let maskTex = try? await holofoilFoilMaskTexture(device: device) {
                        overlayMat.baseColor = .init(tint: .white,
                                                      texture: .init(wTex))
                        overlayMat.normal = .init(texture: .init(rainbowLUT))
                        overlayMat.emissiveColor = .init(color: .black,
                                                         texture: .init(perturbTex))
                        overlayMat.ambientOcclusion = .init(texture: .init(maskTex))
                        overlayMat.faceCulling = .none
                    }
                    let overlay = ModelEntity(
                        mesh: MeshResource.generatePlane(width: cardW * 0.88,
                                                          depth: cardH * 0.92),
                        materials: [overlayMat]
                    )
                    overlay.orientation = simd_quatf(angle: .pi/2,
                                                      axis: SIMD3<Float>(1,0,0))
                    overlay.position = SIMD3<Float>(0, 0, halfT + 0.0008)
                    root.addChild(overlay)
                }
            } catch {
                print("[Variant4] F overlay failed: \(error)")
            }
        }

        // 3-point lights matching iOS v5.7.2
        let key = DirectionalLight()
        key.light.intensity = 22_500
        key.light.color = .white
        key.look(at: .zero, from: SIMD3<Float>(0.3, 0.4, 0.5), relativeTo: nil)
        root.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 22_500 * 0.40
        fill.light.color = .white
        fill.look(at: .zero, from: SIMD3<Float>(0, 0.05, 0.5), relativeTo: nil)
        root.addChild(fill)
        let rim = DirectionalLight()
        rim.light.intensity = 22_500
        rim.light.color = .white
        rim.look(at: .zero, from: SIMD3<Float>(-0.3, 0.4, -0.5), relativeTo: nil)
        root.addChild(rim)

        // IBL matching iOS v6.0.7 (-3.0 EV)
        if let envCG,
           let env = try? await EnvironmentResource(equirectangular: envCG, withName: nil) {
            let ibl = ImageBasedLightComponent(source: .single(env),
                                                intensityExponent: -3.0)
            root.components.set(ibl)
            front.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        }

        // Hero pose camera
        let camera = PerspectiveCamera()
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        camera.look(at: .zero, from: SIMD3<Float>(0, 0.015, 0.32),
                    upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
        camera.camera.fieldOfViewInDegrees = 30

        // Render + APPLY iOS POST-PROCESS (EV/sat/contrast matching
        // HeroShotRenderer.applyExposurePass v6.0.9 settings). Without
        // this, sim output != iOS output and we can't tune correctly.
        let bundle = SceneBundle(renderer: renderer, camera: camera)
        let rawFrame = try renderFrame(scene: bundle, size: frameSize, device: device)
        let frame = applyiOSPostProcess(rawFrame,
                                         ev: postEV,
                                         saturation: postSaturation,
                                         contrast: postContrast) ?? rawFrame
        rendered.append((img: frame, label: labels[i]))
        print("[Variant4] rendered \(labels[i])")
        _ = cardBackCG  // suppress unused
    }

    // 3x2 composite (3 cols × 2 rows = 6 tiles) with labels
    let tileW: CGFloat = 360
    let tileH: CGFloat = 640
    let labelH: CGFloat = 36
    let pad: CGFloat = 8
    let cols = 3
    let rows = (rendered.count + cols - 1) / cols
    let sheetW = Int(tileW * CGFloat(cols) + pad * CGFloat(cols + 1))
    let sheetH = Int((tileH + labelH) * CGFloat(rows) + pad * CGFloat(rows + 1))
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: sheetW, height: sheetH,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

    for (idx, r) in rendered.enumerated() {
        let col = CGFloat(idx % cols)
        let row = CGFloat(idx / cols)
        let rowFromTop = CGFloat(rows - 1) - row
        let x = pad + col * (tileW + pad)
        let y = pad + rowFromTop * (tileH + labelH + pad)
        ctx.draw(r.img, in: CGRect(x: x, y: y + labelH, width: tileW, height: tileH))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.white
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: r.label, attributes: attrs)
            .draw(in: CGRect(x: x + 8, y: y + 4, width: tileW - 12, height: labelH - 6))
        NSGraphicsContext.restoreGraphicsState()
    }
    return ctx.makeImage()
}

// MARK: - Holofoil shader emulator
//
// The Metal surface shader in BOBAPlaybook/Shaders/Holofoil.metal
// cannot run in this sim (CustomMaterial requires Xcode's metallib
// build). This CPU-side function applies the SAME screen-blend
// formula to each pixel of an already-rendered frame, so I can see
// how the shader's output varies across yaw angles BEFORE shipping
// to iOS. Approximation only — the actual shader has access to
// per-fragment normals and tangents; we synthesize an approximate
// fresnel from the global yaw angle.

struct HolofoilParams {
    var intensity: Float = 0.55
    var fresnelExponent: Float = 7.0
    var lutBrightness: Float = 0.55     // matches Swift LUT V
    var perturbStrength: Float = 0.15
}

/// Cached rainbow LUT: 256 RGB samples across the hue wheel at the
/// given brightness. Hue 0 → red, 1/6 → yellow, 2/6 → green, etc.
private var _cachedRainbowLUT: [RGB] = []
private var _cachedRainbowLUTBrightness: Float = -1

func rainbowLUTArray(brightness: Float) -> [RGB] {
    if abs(_cachedRainbowLUTBrightness - brightness) < 0.001
       && _cachedRainbowLUT.count == 256 {
        return _cachedRainbowLUT
    }
    var lut: [RGB] = []
    lut.reserveCapacity(256)
    for i in 0..<256 {
        let h = CGFloat(i) / 255.0
        let rgb = hsvToRGB(h, 1.0, CGFloat(brightness))
        lut.append(rgb)
    }
    _cachedRainbowLUT = lut
    _cachedRainbowLUTBrightness = brightness
    return lut
}

/// Cached perturbation map: 256x256 noise array. Two channels used
/// (x and y) as float values in [-1, 1].
private var _cachedPerturb: [[(x: Float, y: Float)]] = []

func perturbationArray() -> [[(x: Float, y: Float)]] {
    if !_cachedPerturb.isEmpty { return _cachedPerturb }
    let size = 256
    var noise: [[(x: Float, y: Float)]] = Array(
        repeating: Array(repeating: (x: 0.0 as Float, y: 0.0 as Float),
                         count: size),
        count: size
    )
    var rng = SystemRandomNumberGenerator()
    // 24 overlapping radial gradients with random offsets, summed.
    for _ in 0..<24 {
        let cx = Float.random(in: -50...Float(size + 50), using: &rng)
        let cy = Float.random(in: -50...Float(size + 50), using: &rng)
        let r = Float.random(in: 50...140, using: &rng)
        let dx = Float.random(in: -1...1, using: &rng)
        let dy = Float.random(in: -1...1, using: &rng)
        for y in 0..<size {
            for x in 0..<size {
                let dxp = Float(x) - cx, dyp = Float(y) - cy
                let dist = sqrt(dxp * dxp + dyp * dyp)
                if dist < r {
                    let falloff = 1.0 - dist / r
                    noise[y][x].x += dx * falloff * 0.18
                    noise[y][x].y += dy * falloff * 0.18
                }
            }
        }
    }
    // Clamp to [-1, 1].
    for y in 0..<size {
        for x in 0..<size {
            noise[y][x].x = max(-1, min(1, noise[y][x].x))
            noise[y][x].y = max(-1, min(1, noise[y][x].y))
        }
    }
    _cachedPerturb = noise
    return noise
}

/// Approximate the Metal Holofoil shader on a rendered frame. Applies
/// to ALL pixels — the rendered frame has the env in the background,
/// so the shimmer effect will subtly tint env pixels too, but at the
/// fresnel/intensity levels we use the visual difference is minor.
/// The dominant effect is visible on the bright card pixels.
func applyHolofoilOverlay(_ source: CGImage,
                           yawDeg: Float,
                           params: HolofoilParams = HolofoilParams()) -> CGImage? {
    let width = source.width, height = source.height
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let inCtx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    inCtx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = inCtx.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self,
                                  capacity: width * height * 4)

    // Shader math:
    //   yaw rotation around Y. Card normal in world: (sin(yaw), 0, cos(yaw))
    //   View dir (world, camera at +Z): ~(0, 0, 1)
    //   dot(N, V) = cos(yaw)
    //   fresnel = pow(1 - |cos(yaw)|, k)
    //
    //   Tangent-space view dir for rainbow lookup:
    //     V_tangent.x = V · card_tangent_x = -sin(yaw) (after Y rotation)
    //     t_base = dot(V_tangent.xy, (0.707, 0.707)) = -0.707 * sin(yaw)
    //   lutU = (t_base + perturb_x * perturbStrength) * 0.5 + 0.5
    let yawRad = yawDeg * .pi / 180
    let cosYaw = cos(yawRad)
    let fresnel = pow(1.0 - abs(cosYaw), params.fresnelExponent)
    let tBase = -0.707 * sin(yawRad)

    let lut = rainbowLUTArray(brightness: params.lutBrightness)
    let perturb = perturbationArray()
    let pSize = perturb.count

    for y in 0..<height {
        let perturbY = (y * pSize / height) % pSize
        // UV varies across the card; we use uv.x + uv.y * 0.5 as the
        // primary LUT driver so DIFFERENT REGIONS of the card show
        // DIFFERENT rainbow hues simultaneously. View angle (tBase)
        // shifts the whole rainbow over time. This is how real
        // holofoil reads: the rainbow flows across the card surface
        // as you tilt, instead of every pixel showing one fixed hue.
        let uvY = Float(y) / Float(height)
        for x in 0..<width {
            let perturbX = (x * pSize / width) % pSize
            let p = perturb[perturbY][perturbX]
            let uvX = Float(x) / Float(width)
            let t = uvX * 1.5 + uvY * 0.7 + tBase + p.x * params.perturbStrength
            // Wrap to [0, 1) so the rainbow tiles cleanly.
            let lutU = t - floor(t)
            let rainbow = lut[Int(min(0.999, Float(lutU)) * 255.0)]

            let shimmerR = Float(rainbow.r) * fresnel * params.intensity
            let shimmerG = Float(rainbow.g) * fresnel * params.intensity
            let shimmerB = Float(rainbow.b) * fresnel * params.intensity

            let idx = (y * width + x) * 4
            let baseR = Float(pixels[idx + 0]) / 255.0
            let baseG = Float(pixels[idx + 1]) / 255.0
            let baseB = Float(pixels[idx + 2]) / 255.0

            // SCREEN blend: 1 - (1 - a)(1 - b)
            let finalR = 1.0 - (1.0 - baseR) * (1.0 - shimmerR)
            let finalG = 1.0 - (1.0 - baseG) * (1.0 - shimmerG)
            let finalB = 1.0 - (1.0 - baseB) * (1.0 - shimmerB)

            pixels[idx + 0] = UInt8(max(0, min(255, finalR * 255.0)))
            pixels[idx + 1] = UInt8(max(0, min(255, finalG * 255.0)))
            pixels[idx + 2] = UInt8(max(0, min(255, finalB * 255.0)))
            // pixels[idx + 3] stays the same (alpha unchanged)
        }
    }

    return inCtx.makeImage()
}

// MARK: - I/O

func loadImage(at path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func savePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// MARK: - Entry

@MainActor
func run() async throws {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        print("Usage: sim3d <card-art> [output-dir]")
        exit(1)
    }
    let cardPath = args[1]
    let outDir = args.count >= 3 ? args[2] : FileManager.default.currentDirectoryPath
    guard let cardCG = loadImage(at: cardPath) else {
        print("Failed to load \(cardPath)"); exit(1)
    }
    print("Card: \(cardCG.width)×\(cardCG.height)")
    let palette = extractPalette(from: cardCG)
    print("Palette: \(palette.map { String(format: "(%.2f,%.2f,%.2f)", $0.r, $0.g, $0.b) }.joined(separator: " "))")
    let envCG = makeEnvImage(cardArt: cardCG, palette: palette)
    print("Env image generated: \(envCG != nil)")

    guard let device = MTLCreateSystemDefaultDevice() else {
        print("No Metal device"); exit(1)
    }
    print("Metal: \(device.name)")

    let frameSize = CGSize(width: 720, height: 1280)
    let material: MaterialMode = .pbr_clearcoat
    let lighting: LightingMode = .ibl_1_plus_dir
    let envVariants: [EnvVariant] = EnvVariant.allCases

    // Step 1: render the raw env images themselves so we can verify the
    // variants are actually producing different output. Each env image
    // is 1536×2048 — too big to view raw, so tile them at ~360×480.
    print("Rendering env-image sheet (\(envVariants.count) variants)…")
    var envTiles: [(image: CGImage, label: String)] = []
    var envByVariant: [EnvVariant: CGImage] = [:]
    for envV in envVariants {
        if let cg = makeEnvImage(cardArt: cardCG, palette: palette, variant: envV) {
            envTiles.append((image: cg, label: "env: \(envV.displayName)"))
            envByVariant[envV] = cg
            print("  ✓ env=\(envV.displayName) (\(cg.width)×\(cg.height))")
        }
    }
    if let envSheet = makeContactSheet(tiles: envTiles, cols: 3,
                                       tileW: 360, tileH: 480) {
        let envSheetPath = (outDir as NSString).appendingPathComponent("sim3d_env_sheet.png")
        _ = savePNG(envSheet, to: envSheetPath)
        print("→ \(envSheetPath)")
    }

    // Step 2: focused 2×2 sweep — baseline (current ship) vs the
    // most promising new variant (tightFocus, with design tightly
    // concentrated in the camera-visible window), at two backdrop
    // distances. Hero pose only. Tiles big enough that the contact
    // sheet survives chat's downsample.
    // v5.7 sweep — research-driven minimal recipe:
    //   env=cleanStudio (apple-style radial gradient, NO card-art zoom)
    //   floor=neutralDark (no palette tinting; fixes "brown for warm")
    //   elements=.none (no pedestal, no beams, no glows — element budget)
    //   camera pulled back so card is ~50% of frame (research: 35-55%)
    // Compares against v5.6 deepDive+radialSpot+fullStage at same pose.
    let v57EnvCG = envByVariant[.cleanStudio]
    let v56EnvCG = envByVariant[.deepDive]
    let elementSets: [SceneElements] = SceneElements.allCases
    let backdropZ: Float = -0.40
    // Pulled-back hero pose — card occupies ~50% of frame.
    let heroPose = (camPos: SIMD3<Float>(0, 0.018, 0.32),
                    lookAt: SIMD3<Float>(0, 0, 0),
                    fov: Float(30))

    // v6.4 — post-process parameter sweep with UnlitMaterial card
    // (variant D, our v6.3 ship). User after v6.3: "so dark that it
    // is incredibly hard to see." The unlit card doesn't need EV
    // reduction — that was for the PBR variants. Sweep over
    // (EV, sat, contrast) to find the right combination.
    print("Rendering 4-variant iOS comparison grid…")
    let envForGrid = envByVariant[.cleanStudio]
    do {
        if let grid = try await renderIOSVariant4Grid(
            cardCG: cardCG,
            cardBackCG: nil,
            envCG: envForGrid,
            palette: palette,
            device: device,
            postEV: 0.0, postSaturation: 1.15, postContrast: 1.10
        ) {
            let p = (outDir as NSString).appendingPathComponent("sim3d_variant4_grid.png")
            _ = savePNG(grid, to: p)
            print("→ \(p)")
        }
    } catch {
        print("[Variant4] failed: \(error)")
    }

    print("Rendering post-process sweep on UnlitMaterial card…")
    let postParamSets: [(label: String, ev: Float, sat: Float, con: Float)] = [
        ("EV 0 sat1.15",     0.0, 1.15, 1.10),
        ("EV+0.3 sat1.20",   0.3, 1.20, 1.10),
        ("EV+0.5 sat1.20",   0.5, 1.20, 1.10),
        ("EV+0.7 sat1.20",   0.7, 1.20, 1.10),
        ("EV+1.0 sat1.15",   1.0, 1.15, 1.05),
        ("EV+0.5 sat1.30",   0.5, 1.30, 1.10)
    ]
    var postTiles: [(image: CGImage, label: String)] = []
    for s in postParamSets {
        if let g = try? await renderIOSVariant4Grid(
            cardCG: cardCG, cardBackCG: nil, envCG: envForGrid,
            palette: palette, device: device,
            postEV: s.ev, postSaturation: s.sat, postContrast: s.con
        ) {
            // Crop to just variant D — at bottom-left in our 3×2 grid.
            // Tiles are 360w × 640h with 8px padding around each.
            let w = g.width, h = g.height
            let dW = w / 3, dH = h / 2
            if let dQuad = g.cropping(to: CGRect(
                x: 0, y: dH, width: dW, height: dH
            )) {
                postTiles.append((image: dQuad, label: s.label))
                print("  ✓ \(s.label) ev=\(s.ev) sat=\(s.sat) con=\(s.con)")
            }
        }
    }
    if let postSheet = makeContactSheet(tiles: postTiles, cols: 3,
                                         tileW: 320, tileH: 460) {
        let p = (outDir as NSString).appendingPathComponent("sim3d_post_sweep.png")
        _ = savePNG(postSheet, to: p)
        print("→ \(p)")
    }

    let cardBackCG: CGImage?
    if let backPath = locateCardBack(),
       let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: backPath) as CFURL, nil) {
        cardBackCG = CGImageSourceCreateImageAtIndex(src, 0, nil)
    } else {
        cardBackCG = nil
        print("WARN: card-back image not found; will use placeholder color")
    }
    let yawAngles: [Float] = stride(from: Float(0), to: Float(360), by: 30).map { $0 }
    // v6.0.6: clean-source emulator test — apply the holofoil
    // emulator DIRECTLY to the raw card art (no 3D render). This
    // isolates the shimmer effect from the sim's RealityFoundation
    // tonemapping. Saved as sim3d_holo_raw_yaw_NNN.png.
    let holoParams = HolofoilParams(
        intensity: 0.55,
        fresnelExponent: 7.0,
        lutBrightness: 0.55,
        perturbStrength: 0.15
    )
    print("Rendering RAW-CARD holo sweep (\(yawAngles.count) yaw)…")
    for yawDeg in yawAngles {
        if let holoFrame = applyHolofoilOverlay(cardCG, yawDeg: yawDeg,
                                                  params: holoParams) {
            let safeName = String(format: "yaw_%03.0f", yawDeg)
            _ = savePNG(holoFrame,
                        to: (outDir as NSString)
                          .appendingPathComponent("sim3d_holo_raw_\(safeName).png"))
            print("  ✓ raw card @ yaw=\(Int(yawDeg))°")
        }
    }

    // Parameter sweep at TWO yaws (50° and 70°). Want shimmer visible
    // at moderate angles, not just edge-on. v6.0.5 ship was invisible
    // at yaw=70°; want to find a combo that's CLEARLY visible there
    // but not WASHING the head-on view.
    print("Parameter sweep @ yaw=50° and yaw=70°…")
    let testYaw: Float = 50
    let sweepTiles: [(label: String, params: HolofoilParams)] = [
        ("v6.0.5_ship", HolofoilParams(intensity: 0.55, fresnelExponent: 7, lutBrightness: 0.55, perturbStrength: 0.15)),
        ("exp_3_int_70", HolofoilParams(intensity: 0.70, fresnelExponent: 3, lutBrightness: 0.55, perturbStrength: 0.20)),
        ("exp_2_int_85", HolofoilParams(intensity: 0.85, fresnelExponent: 2, lutBrightness: 0.55, perturbStrength: 0.20)),
        ("exp_2_int_60", HolofoilParams(intensity: 0.60, fresnelExponent: 2, lutBrightness: 0.55, perturbStrength: 0.20)),
        ("exp_1_5_int_60", HolofoilParams(intensity: 0.60, fresnelExponent: 1.5, lutBrightness: 0.55, perturbStrength: 0.20)),
        ("exp_1_int_50", HolofoilParams(intensity: 0.50, fresnelExponent: 1.0, lutBrightness: 0.50, perturbStrength: 0.20))
    ]
    var paramTiles: [(image: CGImage, label: String)] = []
    for cfg in sweepTiles {
        if let holoFrame = applyHolofoilOverlay(cardCG, yawDeg: testYaw,
                                                  params: cfg.params) {
            paramTiles.append((image: holoFrame, label: cfg.label))
            let path = (outDir as NSString)
                .appendingPathComponent("sim3d_holo_param_\(cfg.label).png")
            _ = savePNG(holoFrame, to: path)
            print("  ✓ \(cfg.label) (int=\(cfg.params.intensity) exp=\(cfg.params.fresnelExponent) LUT=\(cfg.params.lutBrightness))")
        }
    }
    // Also save the source for reference.
    if let src = applyHolofoilOverlay(cardCG, yawDeg: 0,
                                         params: HolofoilParams(intensity: 0, fresnelExponent: 1, lutBrightness: 1, perturbStrength: 0)) {
        paramTiles.insert((image: src, label: "SOURCE"), at: 0)
    }
    if let sheet = makeContactSheet(tiles: paramTiles, cols: 4,
                                     tileW: 320, tileH: 448) {
        let path = (outDir as NSString)
            .appendingPathComponent("sim3d_holo_param_sweep.png")
        _ = savePNG(sheet, to: path)
        print("  → \(path)")
    }
    print("Rendering rotation+holo sweep (\(yawAngles.count) yaw × 2 = \(yawAngles.count * 2) frames)…")
    var renderTiles: [(image: CGImage, label: String)] = []
    for yawDeg in yawAngles {
        do {
            let scene = try buildScene(
                cardCG: cardCG, cardBackCG: cardBackCG,
                envCG: v57EnvCG, palette: palette,
                material: material, lighting: lighting,
                floor: .none, backdropZ: backdropZ,
                elements: .none,
                cardYaw: yawDeg * .pi / 180,
                useFullCard: true
            )
            scene.camera.look(at: heroPose.lookAt, from: heroPose.camPos,
                               upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
            scene.camera.camera.fieldOfViewInDegrees = heroPose.fov
            let baseFrame = try renderFrame(scene: scene, size: frameSize, device: device)
            let holoFrame = applyHolofoilOverlay(baseFrame, yawDeg: yawDeg,
                                                  params: holoParams) ?? baseFrame
            let baseLabel = String(format: "yaw=%3.0f° base", yawDeg)
            let holoLabel = String(format: "yaw=%3.0f° holo", yawDeg)
            renderTiles.append((image: baseFrame, label: baseLabel))
            renderTiles.append((image: holoFrame, label: holoLabel))
            let safeName = String(format: "yaw_%03.0f", yawDeg)
            _ = savePNG(baseFrame,
                        to: (outDir as NSString).appendingPathComponent("sim3d_rot_\(safeName)_base.png"))
            _ = savePNG(holoFrame,
                        to: (outDir as NSString).appendingPathComponent("sim3d_rot_\(safeName)_holo.png"))
            print("  ✓ yaw=\(Int(yawDeg))° rendered (base + holo)")
        } catch {
            print("  ✗ yaw=\(yawDeg): \(error)")
        }
    }
    _ = (elementSets, v56EnvCG)  // suppress unused
    print("Building render contact sheet (\(renderTiles.count) tiles, 2 cols base|holo)…")
    guard let sheet = makeContactSheet(tiles: renderTiles, cols: 2,
                                       tileW: 432, tileH: 768) else {
        print("Failed to build sheet"); exit(1)
    }
    let outPath = (outDir as NSString).appendingPathComponent("sim3d_sweep.png")
    if savePNG(sheet, to: outPath) {
        print("→ \(outPath)")
    } else {
        print("Failed to save")
        exit(1)
    }
}

// Pattern explanation: a single-file Swift CLI compiled with `swiftc`
// runs top-level code synchronously on the main thread, but main is
// NOT MainActor-isolated. `Task { @MainActor in ... }` schedules onto
// the MainActor executor, which needs the main thread's run loop to
// be active. If we block main with `semaphore.wait()`, the executor
// can't run and the task deadlocks. `RunLoop.main.run()` keeps main
// processing events instead; `exit(0)` from within the task ends the
// process when the work is done.
Task { @MainActor in
    do {
        try await run()
        exit(0)
    } catch {
        print("Top-level error: \(error)")
        exit(1)
    }
}
RunLoop.main.run()
