import Foundation
import RealityKit
import Metal
import MetalKit
import AVFoundation
import CoreVideo
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import SwiftUI

/// Offline RealityKit → MP4 pipeline for the Hero Shot sizzle reel.
///
/// Renders a small 3D card scene (front + back planes + animated foil
/// sheen quad) with a preset camera arc, frame-by-frame via
/// `RealityRenderer.updateAndRender`, bridging each rendered
/// `MTLTexture` to a `CVPixelBuffer` (zero copy via IOSurface +
/// `CVMetalTextureCache`) and appending to an
/// `AVAssetWriterInputPixelBufferAdaptor`. Optional BOBA wordmark is
/// composited via CoreImage `sourceOverCompositing` before the buffer
/// is appended.
///
/// iOS 18+ — `RealityRenderer` is the canonical offline render API and
/// is not available on iOS 17. The Hero Shot toolbar button is gated
/// at the call site.
@available(iOS 18.0, *)
@MainActor
final class HeroShotRenderer {

    // MARK: - Configuration

    /// Hero-shot camera preset. Each preset crosses 2-3 framing scales
    /// (wide context → intimate detail) and ends with the camera close
    /// enough to see foil, hero face, set marks. The user's v3
    /// complaint ("camera too far the whole clip") was the symptom of
    /// a single-scale single-preset model — v4 fixes by making
    /// multi-scale composition mandatory.
    enum ArcPreset: String, CaseIterable, Identifiable {
        /// Card slides in from off-axis (tilted 30°, partly out of
        /// frame), settles into hero pose, then camera pushes in for
        /// the detail climax. The classic "Apple keynote reveal."
        case reveal
        /// Slow orbital arc at wide framing showing the card's 3D
        /// nature, then dolly-pushes inward on the final beat for a
        /// close-up. Card stays at yaw=0 — the camera does the work.
        case showcase
        /// Static wide opening to establish, then match-cuts to an
        /// extreme close-up orbit of the card's center 60% — the
        /// "macro inspection" pattern. Best for foil/treatment cards
        /// where the texture detail is the story.
        case detail
        /// MKBHD-style three-beat tech demo. Beat 1: pulled-back
        /// crane-up (3s) showing pedestal + halo + light beams.
        /// Beat 2: partial orbit at hero-wide distance (4s). Beat 3:
        /// slow push-in to hero pose with dead-still final hold (3s).
        /// v5.6 — designed against the research-agent synthesis on
        /// what separates premium product reveal from hobbyist 3D.
        case techDemo

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .reveal:   return "Reveal"
            case .showcase: return "Showcase"
            case .detail:   return "Detail"
            case .techDemo: return "Tech Demo"
            }
        }

        var caption: String {
            switch self {
            case .reveal:
                return "Slides in, settles into the hero pose"
            case .showcase:
                return "A slow orbit around the card, then settles"
            case .detail:
                return "Pushes in to frame the hero portrait"
            case .techDemo:
                return "Three-beat reveal · stage · orbit · push-in"
            }
        }

        /// Per-frame animation state. Phase boundaries scale with
        /// `duration` so the shape is identical at 5s / 10s / 30s.
        /// All three presets END inside ~10cm framing distance with
        /// the card filling most of the frame — viewers leave with
        /// texture, not silhouette.
        func cameraFrame(at time: Double,
                         duration: Double,
                         cardW: Float, cardH: Float, halfT: Float) -> CameraPose {
            switch self {
            case .reveal:
                return HeroShotRenderer.revealFrame(at: time, duration: duration)
            case .showcase:
                return HeroShotRenderer.showcaseFrame(at: time, duration: duration)
            case .detail:
                return HeroShotRenderer.detailFrame(at: time, duration: duration)
            case .techDemo:
                return HeroShotRenderer.techDemoFrame(at: time, duration: duration)
            }
        }
    }

    // MARK: - Camera-arc keyframe functions
    //
    // Each preset is a piecewise time function. Pure of `time` — same
    // input → same output every frame, deterministic for offline
    // render. All distances in meters. Camera FOV 26-50° depending on
    // phase (narrow = tight close-up, wide = establishing).
    //
    // CARD MOTION is independent (config.cardMotion). The presets
    // produce camera transforms only; card yaw is computed separately.

    /// "Reveal" — slide-in → settle → push-in close-up.
    ///   0.00 → 0.25  SLIDE IN  — off-axis dolly to hero-wide.
    ///                            Card ~35% of frame, FOV 36°.
    ///   0.25 → 0.65  SETTLE    — small drift; absorb the card.
    ///   0.65 → 0.95  PUSH IN   — camera + FOV both close on detail.
    ///                            Card fills most of frame at climax.
    ///   0.95 → 1.00  HOLD
    static func revealFrame(at time: Double, duration: Double) -> CameraPose {
        let slideEnd:  Double = duration * 0.25
        let settleEnd: Double = duration * 0.55
        let pushEnd:   Double = duration * 0.92

        // v5 — full card visible throughout. Closest the camera ever
        // gets is z=0.21m (FOV 30°), which puts the card at ~70%
        // vertical fill while keeping the 1200px source texture
        // downsampling (sharp), not upsampling (blurry). Hero pose
        // is the climax — no macro center-crop.
        let slideStart = CameraPose(
            position: SIMD3<Float>(-0.16, -0.04, 0.32),
            lookAt:   SIMD3<Float>(-0.025, -0.01, 0),
            fovDeg:   38
        )
        // v5.7 — pull back so card occupies ~50% of frame (research:
        // 35-55% is the cinema sweet spot; 70%+ leaves no room for
        // the env to do its work). Was z=0.25 → ~67%, push z=0.21 →
        // ~75%. New z=0.34 settle, z=0.30 push climax → ~46% and ~53%.
        let heroPose = CameraPose(
            position: SIMD3<Float>(0.0, 0.015, 0.34),
            lookAt:   .zero,
            fovDeg:   32
        )
        let pushPose = CameraPose(
            position: SIMD3<Float>(0.0, 0.018, 0.30),
            lookAt:   .zero,
            fovDeg:   30
        )

        if time <= slideEnd {
            // SLIDE — ease-out arrival into the hero pose. Camera
            // decelerates into the pose, doesn't lerp linearly.
            let t = easeOutCubic(slideEnd == 0 ? 1.0 : time / slideEnd)
            return lerpPose(slideStart, heroPose, Float(t))
        } else if time <= settleEnd {
            // SETTLE — hold on the hero pose with subtle breathing.
            return breathing(heroPose, at: time)
        } else if time <= pushEnd {
            // PUSH — slow ease-out push to the climax framing. Not
            // a zoom-into-detail; just a tasteful closing of distance.
            let raw = (time - settleEnd) / (pushEnd - settleEnd)
            let eased = Float(easeOutCubic(raw))
            return lerpPose(heroPose, pushPose, eased)
        } else {
            return breathing(pushPose, at: time)
        }
    }

    /// "Showcase" — slow arc → dolly-push climax. Card stays static.
    ///   0.00 → 0.85  ARC       — orbit -25° → +25° at constant 0.22m.
    ///                            Card ~40% of frame at FOV 32°.
    ///   0.85 → 0.96  PUSH IN   — dolly forward to 0.09m + FOV tightens.
    ///   0.96 → 1.00  HOLD
    static func showcaseFrame(at time: Double, duration: Double) -> CameraPose {
        let arcEnd:    Double = duration * 0.80
        let settleEnd: Double = duration * 0.95

        // v5 — orbit stays at constant 0.25m so the card sits at ~65%
        // vertical fill the WHOLE arc. The "push to detail" climax is
        // gone — premium reveals don't punch in past the subject's
        // edges. Instead, after the orbit completes, settle onto a
        // slight 3/4 hero pose at ~70% fill and breathe.
        let arcDistance: Float = 0.25
        let arcElev:     Float = 5 * .pi / 180
        let arcAzMin:    Float = -22 * .pi / 180
        let arcAzMax:    Float =  22 * .pi / 180
        let arcR: Float = arcDistance * cos(arcElev)
        let arcY: Float = arcDistance * sin(arcElev)
        let orbital: (Float) -> SIMD3<Float> = { az in
            SIMD3<Float>(arcR * sin(az), arcY, arcR * cos(az))
        }

        if time <= arcEnd {
            // Linear orbit — constant angular velocity reads as a real
            // dolly track around the subject, not a lerp between two
            // points. The "decelerated landing" feel comes from the
            // settle phase, not from easing the orbit itself.
            let t = Float(arcEnd == 0 ? 1.0 : time / arcEnd)
            let az = lerp(arcAzMin, arcAzMax, t)
            return CameraPose(position: orbital(az), lookAt: .zero, fovDeg: 32)
        } else if time <= settleEnd {
            // SETTLE — ease-out arrival from arc-end to slight 3/4
            // hero pose at ~70% fill, closer than the orbit.
            let arcEndPose = CameraPose(
                position: orbital(arcAzMax),
                lookAt: .zero,
                fovDeg: 32
            )
            // v5.7 — pull back to ~50% framing.
            let heroPose = CameraPose(
                position: SIMD3<Float>(0.05, 0.018, 0.31),
                lookAt: .zero,
                fovDeg: 30
            )
            let t = easeOutCubic((time - arcEnd) / (settleEnd - arcEnd))
            return lerpPose(arcEndPose, heroPose, Float(t))
        } else {
            // v5.7 — pull back to ~50% framing.
            let heroPose = CameraPose(
                position: SIMD3<Float>(0.05, 0.018, 0.31),
                lookAt: .zero,
                fovDeg: 30
            )
            return breathing(heroPose, at: time)
        }
    }

    /// "Detail" — wide opener → push to UPPER region of the card
    /// (where the hero portrait sits). The card stays in frame the
    /// whole time; the camera shifts its lookAt UP so the final pose
    /// frames the hero's face, not the dead center of the card.
    ///   0.00 → 0.20  WIDE       — full card at ~50% fill, FOV 36°.
    ///   0.20 → 0.55  DOLLY UP   — camera pushes IN + lookAt drifts UP.
    ///                             Card stays mostly visible; framing
    ///                             centers on upper third (face).
    ///   0.55 → 0.90  DRIFT      — slow horizontal drift across the
    ///                             face, micro-amplitude.
    ///   0.90 → 1.00  HOLD       — locked on upper-third hero pose.
    static func detailFrame(at time: Double, duration: Double) -> CameraPose {
        let wideEnd:  Double = duration * 0.20
        let dollyEnd: Double = duration * 0.55
        let driftEnd: Double = duration * 0.90

        // The "upper third" lookAt — y = +0.022 puts the camera's gaze
        // on the hero portrait region of the card (top quarter to top
        // third on most BoBA cards). The push-in keeps the card 80%
        // visible at the closest framing.
        let upperLookAt = SIMD3<Float>(0, 0.022, 0)

        let wide = CameraPose(
            position: SIMD3<Float>(-0.05, 0.020, 0.30),
            lookAt:   SIMD3<Float>(0, -0.005, 0),
            fovDeg:   36
        )
        let upperFramed = CameraPose(
            position: SIMD3<Float>(0.02, 0.04, 0.22),
            lookAt:   upperLookAt,
            fovDeg:   28
        )
        let driftEndPose = CameraPose(
            position: SIMD3<Float>(-0.025, 0.04, 0.22),
            lookAt:   upperLookAt,
            fovDeg:   28
        )

        if time <= wideEnd {
            return breathing(wide, at: time)
        } else if time <= dollyEnd {
            let t = easeOutCubic((time - wideEnd) / (dollyEnd - wideEnd))
            return lerpPose(wide, upperFramed, Float(t))
        } else if time <= driftEnd {
            // Gentle horizontal drift across the hero portrait,
            // linear (constant velocity reads as a real dolly).
            let t = Float((time - dollyEnd) / (driftEnd - dollyEnd))
            return lerpPose(upperFramed, driftEndPose, t)
        } else {
            return breathing(driftEndPose, at: time)
        }
    }

    /// "Tech Demo" — MKBHD-style 3-beat reveal.
    ///   0.00 → 0.30  ESTABLISH  — pulled-back crane-up showing the
    ///                              full stage: pedestal, halo, light
    ///                              beams, env spilling around the card.
    ///                              Ease-out cubic into Beat 2 start pose.
    ///   0.30 → 0.65  ORBIT      — partial 25° arc on Y at hero-wide
    ///                              distance, shows card's dimension +
    ///                              keeps stage elements peeking in
    ///                              from frame edges. Smoothstep both
    ///                              ends.
    ///   0.65 → 0.95  PUSH-IN    — slow dolly to hero pose. Card fills
    ///                              the frame for the texture climax.
    ///                              Ease-out cubic (decelerate into hero).
    ///   0.95 → 1.00  HOLD       — dead still on hero pose. Per the
    ///                              research synthesis: the last 0.4-
    ///                              0.5s must NOT move — that's where
    ///                              the eye lands and locks in.
    static func techDemoFrame(at time: Double, duration: Double) -> CameraPose {
        let establishEnd: Double = duration * 0.30
        let orbitEnd:     Double = duration * 0.65
        let pushEnd:      Double = duration * 0.95

        // Beat 1 keyframes — pulled-back crane-up. Start lower-left,
        // end slightly higher and centered. Wide FOV reveals stage.
        let establishStart = CameraPose(
            position: SIMD3<Float>(-0.06, -0.030, 0.34),
            lookAt:   SIMD3<Float>(0, 0.005, 0),
            fovDeg:   38
        )
        let establishEndPose = CameraPose(
            position: SIMD3<Float>(0.06, 0.035, 0.32),
            lookAt:   .zero,
            fovDeg:   34
        )
        // Beat 2 keyframes — partial orbit at hero-wide distance.
        // Same radius as establishEnd, rotates around Y from +12° to -10°.
        let orbitRadius: Float = 0.30
        let orbitElevation: Float = 0.025
        func orbital(azDeg: Float) -> SIMD3<Float> {
            let az = azDeg * .pi / 180
            return SIMD3<Float>(sin(az) * orbitRadius,
                                orbitElevation,
                                cos(az) * orbitRadius)
        }
        let orbitStart = CameraPose(
            position: orbital(azDeg: 12),
            lookAt:   .zero,
            fovDeg:   34
        )
        let orbitEndPose = CameraPose(
            position: orbital(azDeg: -10),
            lookAt:   .zero,
            fovDeg:   34
        )
        // Beat 3 keyframe — v5.7 pulled back to ~50% framing (was 0.22
        // → ~75%). Card no longer dominates; env breathes around it.
        let heroPose = CameraPose(
            position: SIMD3<Float>(0, 0.015, 0.32),
            lookAt:   .zero,
            fovDeg:   30
        )

        if time <= establishEnd {
            // Ease-out cubic: decelerate into Beat 1 end (the "arrive"
            // beat the research called out — never constant velocity).
            let t = easeOutCubic(time / establishEnd)
            return breathing(lerpPose(establishStart, establishEndPose, Float(t)),
                              at: time)
        } else if time <= orbitEnd {
            let t = easedProgress((time - establishEnd) / (orbitEnd - establishEnd))
            // Orbit start ≈ Beat 1 end, so this cuts smoothly into the orbit.
            return lerpPose(orbitStart, orbitEndPose, Float(t))
        } else if time <= pushEnd {
            // Ease-out cubic again — landing into hero pose. Camera
            // "arrives" rather than coasting.
            let t = easeOutCubic((time - orbitEnd) / (pushEnd - orbitEnd))
            return lerpPose(orbitEndPose, heroPose, Float(t))
        } else {
            // Dead still. NO breathing on the final beat — research
            // synthesis: the eye locks in during a frozen final beat.
            return heroPose
        }
    }

    /// Per-frame card-yaw, independent of camera. See `CardMotion`.
    static func cardYaw(at time: Double,
                        duration: Double,
                        motion: CardMotion) -> Float {
        guard duration > 0 else { return 0 }
        let progress = max(0, min(1, time / duration))
        switch motion {
        case .`static`:
            return 0
        case .entranceSpin:
            // One full 2π rotation over the first 35% of the clip,
            // then hold. Smoothstep so the spin feels like a controlled
            // landing rather than constant velocity.
            let spinPhase = 0.35
            if progress <= spinPhase {
                let t = progress / spinPhase
                return Float(easedProgress(t)) * 2 * .pi
            }
            return 0  // 2π = 0 (snap to face camera for the rest)
        case .slowRotate:
            // v5.1: gentle ±30° sinusoidal sway. v5's linear 0→2π
            // spent half the clip showing the BACK of the card — user
            // explicitly flagged this. New behavior: card sways
            // left/right showing its 3D edges without ever turning
            // away from camera. One full oscillation per clip.
            let phase = Float(progress) * 2 * .pi
            return sin(phase) * (.pi / 6)   // ±30° amplitude
        }
    }

    /// A single key in the camera animation: camera position, look-at
    /// target, FOV. Lerped per-frame via `lerp(_:_:_:)`.
    struct CameraPose {
        var position: SIMD3<Float>
        var lookAt: SIMD3<Float>
        var fovDeg: Float
    }


    /// How the card moves during the clip, independent of camera arc.
    enum CardMotion: String, CaseIterable, Identifiable {
        /// Card is stationary; only the camera moves.
        case `static`
        /// Card spins 360° around Y during the clip's first segment,
        /// then settles for the rest. The "reveal spin" pattern.
        case entranceSpin
        /// Card rotates slowly + continuously around Y over the whole
        /// clip. Loopable on social platforms.
        case slowRotate

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .`static`:     return "Static"
            case .entranceSpin: return "Entrance Spin"
            case .slowRotate:   return "Slow Rotate"
            }
        }
    }

    struct Config {
        var card: Card
        var frontTexture: TextureResource
        var backTexture: TextureResource?
        /// The source UIImage for the front art. Used at scene-build
        /// time to (a) extract a color palette and (b) generate the
        /// env-extension backdrop + IBL environment. Required for v4.
        var frontImage: UIImage
        var includeWatermark: Bool = true
        var arc: ArcPreset = .reveal
        var cardMotion: CardMotion = .entranceSpin
        /// Default: 10s. Discrete picker values: 5 / 10 / 15 / 30.
        var duration: TimeInterval = 10.0
        var fps: Int = 60
        var size: CGSize = CGSize(width: 1080, height: 1920)
        var bitrate: Int = 12_000_000
    }

    enum RenderError: Error {
        case metalUnavailable
        case textureCreateFailed
        case pixelBufferPoolUnavailable
        case writerSetupFailed
        case cancelled
        case appendFailed
    }

    // MARK: - Public

    /// Render a SINGLE frame at the given normalized time (0…1, where
    /// 1.0 = `config.duration`). Returns a UIImage suitable for inline
    /// preview. Used by HeroShotView to show "what will frame N look
    /// like with these settings" without committing to the full render.
    /// Skips watermark composite for speed.
    func renderPreviewFrame(_ config: Config, normalizedTime: Double) async throws -> UIImage {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.metalUnavailable
        }
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        guard let textureCache else { throw RenderError.textureCreateFailed }

        // Smaller pixel buffer for preview — 540×960 is enough to read
        // the composition. ~4× faster to render than full 1080×1920.
        let previewSize = CGSize(width: 540, height: 960)
        let pool = try makePixelBufferPool(size: previewSize)
        let scene = try buildScene(config: config)

        // Apply camera + yaw for the requested time.
        let time = max(0, min(1, normalizedTime)) * config.duration
        let camPose = config.arc.cameraFrame(at: time,
                                             duration: config.duration,
                                             cardW: Self.cardW, cardH: Self.cardH, halfT: Self.halfT)
        let yaw = HeroShotRenderer.cardYaw(at: time,
                                           duration: config.duration,
                                           motion: config.cardMotion)
        HeroShotRenderer.applyCameraPose(camPose, to: scene.camera)
        scene.cardPivot.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        HeroShotRenderer.applyKeyLightPose(time: time, duration: config.duration,
                                            light: scene.keyLight)

        // Build the buffer + texture, render one frame.
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { throw RenderError.pixelBufferPoolUnavailable }
        guard let mtlTex = makeMTLTexture(from: pixelBuffer,
                                          cache: textureCache,
                                          size: previewSize) else {
            throw RenderError.textureCreateFailed
        }
        try renderFrame(scene.renderer, into: mtlTex, deltaTime: 0)

        // Convert CVPixelBuffer → CIImage → apply EV-stop reduction → UIImage.
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let exposed = Self.applyExposureEV(ci, ev: -2.0)
        let ctx = CIContext(mtlDevice: device)
        guard let cg = ctx.createCGImage(exposed, from: ci.extent) else {
            throw RenderError.textureCreateFailed
        }
        return UIImage(cgImage: cg)
    }

    /// v6.0.8.1 — apply CIExposureAdjust as an EV-stop reduction post-
    /// process. Scales all light contributions in the rendered frame
    /// by 2^ev. Lives in CoreImage land so we don't depend on a
    /// non-existent PerspectiveCameraComponent.exposureCompensation
    /// property (my v6.0.8 ship referenced it; PBR camera API doesn't
    /// actually expose it).
    static func applyExposureEV(_ image: CIImage, ev: Float) -> CIImage {
        let filter = CIFilter(name: "CIExposureAdjust")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(ev, forKey: "inputEV")
        return filter.outputImage ?? image
    }

    /// Renders the hero shot to a temporary file URL and returns it.
    /// `progress` is called on MainActor with values 0…1.
    func render(_ config: Config,
                progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> URL {

        let totalFrames = max(1, Int((config.duration * Double(config.fps)).rounded()))

        // Metal device + texture cache for the MTLTexture → CVPixelBuffer bridge.
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.metalUnavailable
        }
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        guard let textureCache else { throw RenderError.textureCreateFailed }

        // CVPixelBuffer pool — IOSurface-backed buffers for zero-copy bridging.
        let pool = try makePixelBufferPool(size: config.size)

        // AVAssetWriter setup (HEVC, portrait, 12 Mbps default).
        let outputURL = makeOutputURL()
        let writer = try makeAssetWriter(url: outputURL, size: config.size, bitrate: config.bitrate, fps: config.fps)
        let input  = writer.inputs.first!
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String:  Int(config.size.width),
                kCVPixelBufferHeightKey as String: Int(config.size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
            ]
        )

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // RealityKit scene.
        let scene = try buildScene(config: config)

        // Watermark prep (rasterize once).
        let watermarkCI: CIImage? = config.includeWatermark
            ? rasterizeWatermark(targetSize: config.size)
            : nil
        let ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])

        let cardW: Float = HeroShotRenderer.cardW
        let cardH: Float = HeroShotRenderer.cardH
        let halfT: Float = HeroShotRenderer.halfT

        for frame in 0..<totalFrames {
            try Task.checkCancellation()

            // Back-pressure: wait for the writer + yield so SwiftUI stays
            // responsive during the render.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }

            // Time the frame represents in the output video.
            let time = Double(frame) / Double(config.fps)
            let camPose = config.arc.cameraFrame(at: time,
                                                 duration: config.duration,
                                                 cardW: cardW, cardH: cardH, halfT: halfT)
            let yaw = HeroShotRenderer.cardYaw(at: time,
                                               duration: config.duration,
                                               motion: config.cardMotion)
            HeroShotRenderer.applyCameraPose(camPose, to: scene.camera)
            scene.cardPivot.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            HeroShotRenderer.applyKeyLightPose(time: time,
                                                duration: config.duration,
                                                light: scene.keyLight)

            // Build a fresh CVPixelBuffer for this frame.
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else { throw RenderError.pixelBufferPoolUnavailable }

            // Bridge the CVPixelBuffer to an MTLTexture, render into it.
            guard let mtlTex = makeMTLTexture(from: pixelBuffer,
                                              cache: textureCache,
                                              size: config.size) else {
                throw RenderError.textureCreateFailed
            }
            try renderFrame(scene.renderer,
                            into: mtlTex,
                            deltaTime: 1.0 / Double(config.fps))

            // v6.0.8.1 — EV-stop exposure reduction. Run BEFORE the
            // watermark composite so the watermark stays at full
            // brightness over the darkened scene.
            applyExposurePass(to: pixelBuffer, ev: -2.0,
                               ciContext: ciContext)

            // Optional watermark composite.
            let finalBuffer: CVPixelBuffer
            if let watermarkCI {
                finalBuffer = compositeWatermark(into: pixelBuffer,
                                                 watermark: watermarkCI,
                                                 ciContext: ciContext) ?? pixelBuffer
            } else {
                finalBuffer = pixelBuffer
            }

            let pts = CMTime(value: CMTimeValue(frame), timescale: Int32(config.fps))
            if !adaptor.append(finalBuffer, withPresentationTime: pts) {
                throw RenderError.appendFailed
            }

            // Progress reporting; yield to runloop every few frames.
            if frame % 4 == 0 {
                let p = Double(frame + 1) / Double(totalFrames)
                progress(min(1.0, p))
                await Task.yield()
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? RenderError.writerSetupFailed
        }
        progress(1.0)
        return outputURL
    }

    // MARK: - Scene

    /// Card dimensions — single source of truth in `BOBACardEntity`.
    /// Re-exposed here for the camera-animation math (it needs cardW
    /// and cardH to compute pan positions and look-at offsets).
    static var cardW: Float { BOBACardEntity.width }
    static var cardH: Float { BOBACardEntity.height }
    static var halfT: Float { BOBACardEntity.halfThickness }
    static var cornerRadiusRatio: Float { BOBACardEntity.cornerRadiusRatio }
    static var cornerRadius: Float { BOBACardEntity.cornerRadius }

    /// Bundle of references the render loop drives per-frame.
    private struct SceneBundle {
        let renderer: RealityRenderer
        let camera: PerspectiveCamera
        /// The CARD pivot — child of root, parent of front+back planes.
        /// Rotated around Y per frame during phase 1 to spin the card.
        let cardPivot: Entity
        /// Key directional light. Per-frame `look(at:from:)` updates
        /// rotate it slowly around the card so foil treatments catch
        /// the light at different angles — the "rim-pass" beat from
        /// the research synthesis (the MKBHD silhouette-rake move).
        let keyLight: DirectionalLight
    }

    private func buildScene(config: Config) throws -> SceneBundle {
        let renderer = try RealityRenderer()

        // Pure black scene clear — the backdrop plane covers the camera
        // frustum at all preset poses. Any peek-through reads as void.
        renderer.cameraSettings.colorBackground = .color(UIColor.black.cgColor)

        let root = Entity()
        renderer.entities.append(root)

        // ── Env-extension texture (Apple-Music ambient style) ────────
        // Generate ONE 2048×1024 image from the card art: gentle blur +
        // mild saturation + mirror-tile + a low-opacity treatment
        // overlay (Battlefoil stripes, etc.). Used purely as a TEXTURE
        // on the backdrop plane — no IBL, no lighting interaction.
        //
        // v4 over-applied this: saturation 1.7× + heavy IBL + PBR
        // lights all multiplied, blowing the card out. v4.1 tunes
        // saturation down and ditches the lighting that was the source
        // of the blowout.
        let palette = HeroShotEnvironment.extractPalette(from: config.frontImage)
        let envCG = HeroShotEnvironment.generateImage(
            frontArt: config.frontImage,
            treatment: config.card.treatment,
            palette: palette
        )

        // ── Stage backdrop (Unlit) ───────────────────────────────────
        // Large plane far behind, textured with the env-extension
        // image. UnlitMaterial = the texture shows EXACTLY as drawn,
        // no PBR shading can over-bright it.
        var backdropMat = UnlitMaterial()
        if let cg = envCG,
           let tex = try? TextureResource(image: cg, withName: nil,
                                          options: TextureResource.CreateOptions(
                                              semantic: .color,
                                              mipmapsMode: .allocateAndGenerateAll)) {
            backdropMat.color = .init(tint: .white, texture: .init(tex))
        } else {
            backdropMat.color = .init(tint: palette.first ?? .darkGray)
        }
        let backdrop = ModelEntity(
            mesh: MeshResource.generatePlane(width: 2.4, depth: 3.2),
            materials: [backdropMat]
        )
        backdrop.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        // v5.5: pull backdrop closer (was -0.85 since v5.1). At -0.85,
        // the camera sees only ~13% × 18% of the env image at hero
        // pose — any heavy-blur env design converged to a smooth
        // gradient (sim-confirmed). At -0.40 the visible env window
        // is ~28% × 39%, showing actual color/composition detail from
        // the deepDive zoomed art.
        backdrop.position = SIMD3<Float>(0, 0.10, -0.40)
        root.addChild(backdrop)

        // ── v5.7: NO floor, NO pedestal, NO light beams, NO accent
        // glows, NO rim halo. Research finding: "the dominant pattern
        // in product reveal cinema is no visible floor. The subject
        // floats in dark space, defined by rim lighting and a faint
        // contact shadow." Apple iPhone 17 reveal, MKBHD B-roll, Nike
        // product films — all skip the floor + staging elements.
        //
        // v5.6 stacked floor + pedestal + beams + halo + glows + env
        // overlays — 12+ alpha layers that averaged to mud. v5.7 drops
        // every one of them. The CARD carries all the chroma; the env
        // image (cleanStudio in HeroShotEnvironment) provides subtle
        // accent spill via the backdrop + IBL.
        //
        // Sim-validated against three palettes (Hex purple, Fire
        // orange, Ice blue) — all rendered clean, no muddy floor, no
        // brown stains. v5.6's same test produced "brown on brown"
        // mud for Fire (warm-palette compounding via palette-tinted
        // surfaces).

        // ── Card (PBR — sim-validated lighting setup) ────────────────
        // v4 used PBR with whatever lights happened to be in the scene
        // and blew out. v4.1-v5.3 reverted to Unlit (safe, but
        // visually flat — no dimension, no env participation).
        // v5.4 returns to PBR with sim-tuned lighting: DirectionalLight
        // at 30,000 lumen + IBL from env at intensityExponent 1.0. The
        // Phase 2 simulator's 4×8 sweep showed this combo lights the
        // card uniformly without blowout (80k blew out, dim & IBL-only
        // were near-black) AND gives ambient color shift from the env.
        let cardPivot = BOBACardEntity.build(BOBACardEntity.Config(
            frontTexture: config.frontTexture,
            backTexture: config.backTexture,
            includeEdge: true,
            pose: .upright,
            material: .physicallyBased,
            treatment: config.card.treatment,
            useHolofoil: true   // v6.0 — Metal holofoil shader on front
        ))
        cardPivot.position = .zero
        root.addChild(cardPivot)

        // ── 3-point lighting (v5.7.2) ────────────────────────────────
        // User: "card flashes black during rotation." Captured the bug
        // in the rotation sim (yaw=120° → solid black silhouette). The
        // root cause is NOT face culling — it's Lambert math. At
        // yaw=120° the back plane's normal points to (-0.866, 0, +0.5)
        // and the single upper-front-right key light's direction gives
        // dot product ≈ 0. The PBR shader correctly renders the surface
        // at near-zero brightness → black. cleanStudio env's IBL is
        // too dim to fill in.
        //
        // Fix: classic 3-point setup. Key (upper-front-right) + Fill
        // (from camera direction, ~40% intensity, ensures any visible
        // surface gets Lambert > 0) + Rim (upper-back, lights the
        // silhouette + the back face when card rotates 180°). Sim-
        // validated across yaw=0/60/120/180/240/300° — no more black.
        let keyLight = DirectionalLight()
        keyLight.light.intensity = 22_500
        keyLight.light.color = .white
        keyLight.look(at: .zero, from: SIMD3<Float>(0.3, 0.4, 0.5),
                      relativeTo: nil)
        root.addChild(keyLight)
        let fillLight = DirectionalLight()
        fillLight.light.intensity = 22_500 * 0.40
        fillLight.light.color = .white
        fillLight.look(at: .zero, from: SIMD3<Float>(0, 0.05, 0.5),
                       relativeTo: nil)
        root.addChild(fillLight)
        let rimLight = DirectionalLight()
        rimLight.light.intensity = 22_500
        rimLight.light.color = .white
        rimLight.look(at: .zero, from: SIMD3<Float>(-0.3, 0.4, -0.5),
                      relativeTo: nil)
        root.addChild(rimLight)
        if let envCG,
           let env = try? EnvironmentResource(equirectangular: envCG, withName: nil) {
            // v6.0.7: IBL exp -3.0. v6.0.6 used 0.0 thinking that was
            // "zero" but intensityExponent is base-2 → 2^0 = 1× (full
            // baseline). User reported "almost identical" — the IBL
            // contribution barely budged.
            // exp -3.0 → 2^-3 = 0.125× (1/8 of baseline). That's the
            // dramatic reduction the user can actually SEE. Card now
            // gets its illumination overwhelmingly from the 3-point
            // direct lights, not the env's ambient bath. Pigment punch
            // restored; "washed out" appearance should go away.
            let ibl = ImageBasedLightComponent(source: .single(env),
                                               intensityExponent: -3.0)
            root.components.set(ibl)
            // ImageBasedLightReceiverComponent doesn't propagate through
            // the entity hierarchy — must be set on each ModelEntity
            // that should be lit. cardPivot is an empty parent; its
            // children (card-front, card-back, card-edge) are the
            // actual ModelEntities holding the PBR materials.
            let receiver = ImageBasedLightReceiverComponent(imageBasedLight: root)
            for child in cardPivot.children where child is ModelEntity {
                child.components.set(receiver)
            }
        }

        // ── Atmospheric particles ────────────────────────────────────
        // Subtle dust drifting upward in the dominant palette color.
        // 10-30 particles, large-soft size, fully additive blend so
        // they BRIGHTEN the scene without dithering issues.
        // The emitter sits slightly in front of the card so particles
        // appear in the camera's foreground — adds the "premium
        // moving frame" feel that distinguishes a sizzle reel from
        // a still photo.
        let particles = Entity()
        particles.position = SIMD3<Float>(0, 0, 0.06)
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = SIMD3<Float>(0.30, 0.20, 0.04)
        emitter.birthDirection = .world
        emitter.birthLocation = .volume
        emitter.simulationState = .play
        // v5.1: more plentiful per user feedback. birthRate 6→18 with
        // 5s lifeSpan = ~90 in frame at any time. Size variation
        // raised so the cloud has depth — some big soft motes, some
        // tiny twinkles.
        emitter.mainEmitter.birthRate = 18
        emitter.mainEmitter.birthRateVariation = 4
        emitter.mainEmitter.lifeSpan = 5.0
        emitter.mainEmitter.lifeSpanVariation = 1.5
        emitter.mainEmitter.size = 0.018
        emitter.mainEmitter.sizeVariation = 0.012
        // Slow upward drift with very mild lateral noise.
        emitter.mainEmitter.acceleration = SIMD3<Float>(0, 0.005, 0)
        emitter.mainEmitter.dampingFactor = 0.5
        emitter.mainEmitter.noiseStrength = 0.012
        emitter.mainEmitter.noiseScale = 1.0
        emitter.mainEmitter.noiseAnimationSpeed = 0.5
        emitter.mainEmitter.spreadingAngle = .pi
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.billboardMode = .billboard
        emitter.mainEmitter.colorEvolutionPower = 1.0
        // Palette-tinted color, very low alpha — additive so even a
        // dim color contributes visible light.
        let particleColor = palette.first ?? .white
        emitter.mainEmitter.color = .constant(.single(
            particleColor.withAlphaComponent(0.6)
        ))
        particles.components.set(emitter)
        root.addChild(particles)

        // NOTE: STILL NO PBR LIGHTS / IBL on the card.
        //
        // UnlitMaterial card means the card art always renders true to
        // the source PNG — known-good visual that works everywhere.
        // The "lit" feel comes from the backdrop's center-glow layer
        // (rendered into the env image during HeroShotEnvironment
        // generation) and the additive particles overhead.

        // ── Camera ───────────────────────────────────────────────────
        let camera = PerspectiveCamera()
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        // v6.0.8.1 — PerspectiveCameraComponent doesn't expose
        // exposureCompensation (my v6.0.8 ship referenced a property
        // that doesn't exist). The EV-stop reduction now lives in
        // the per-frame render loop as a CoreImage CIExposureAdjust
        // post-process pass. Same end result: -2 EV applied to every
        // pixel of every output frame.
        let firstPose = config.arc.cameraFrame(
            at: 0,
            duration: config.duration,
            cardW: Self.cardW, cardH: Self.cardH, halfT: Self.halfT
        )
        HeroShotRenderer.applyCameraPose(firstPose, to: camera)

        return SceneBundle(renderer: renderer, camera: camera,
                           cardPivot: cardPivot, keyLight: keyLight)
    }

    // MARK: - Color helpers

    nonisolated private static func blendColor(_ a: UIColor, with b: UIColor, t: CGFloat) -> UIColor {
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

    nonisolated private static func blendUIColor(_ a: UIColor, with b: UIColor, t: CGFloat) -> UIColor {
        Self.blendColor(a, with: b, t: t)
    }

    /// Generate a radial gradient CGImage for the floor: palette-bright
    /// at center → near-black at edges. v5.5 replaces the flat solid-
    /// tinted floor with this so the stage reads as "spotlight from
    /// above" instead of "uniformly-lit brown plane." Sim-validated:
    /// the gradient is visible at every camera pose in the arc.
    nonisolated private static func makeRadialFloorTexture(palette: [UIColor]) -> CGImage? {
        let size = 1024
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let primary = palette.first ?? .darkGray
        let bright = Self.blendColor(primary, with: .white, t: 0.25)
        let mid = Self.blendColor(primary, with: .black, t: 0.30)
        let dark = Self.blendColor(primary, with: .black, t: 0.70)
        let colors = [bright.cgColor, mid.cgColor, dark.cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                 locations: [0.0, 0.40, 1.0]) else { return nil }
        let cx = CGFloat(size) / 2
        let cy = CGFloat(size) / 2
        ctx.drawRadialGradient(g,
                               startCenter: CGPoint(x: cx, y: cy),
                               startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy),
                               endRadius: CGFloat(size) * 0.65,
                               options: [])
        return ctx.makeImage()
    }

    // MARK: - 3D scene element builders (v5.6)
    //
    // Real geometry added to the world — visible to the camera as
    // actual objects, not painted into env image. Sim-validated:
    // these read prominently at pulled-back camera poses (the
    // pulled/craneUp beats of the new MKBHD-style arc), and add
    // subtle peeks-around-the-silhouette at hero pose.

    /// Glow-circle plane positioned just behind the card. The card
    /// occludes the bright center; the outer falloff reads as a
    /// backlit halo around the card silhouette. ~2.4× card size.
    @MainActor
    static func makeRimHalo(palette: [UIColor]) throws -> ModelEntity {
        let primary = palette.first ?? .darkGray
        let texSize = 512
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: texSize, height: texSize,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "HeroShot", code: 100) }
        let center = primary.withAlphaComponent(0.95).cgColor
        let mid = primary.withAlphaComponent(0.55).cgColor
        let edge = primary.withAlphaComponent(0).cgColor
        let colors = [center, mid, edge] as CFArray
        guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                 locations: [0.0, 0.40, 1.0]) else {
            throw NSError(domain: "HeroShot", code: 101)
        }
        let cx = CGFloat(texSize) / 2
        ctx.drawRadialGradient(g,
                               startCenter: CGPoint(x: cx, y: cx),
                               startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cx),
                               endRadius: cx,
                               options: [])
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "HeroShot", code: 102)
        }
        var mat = UnlitMaterial()
        let opts = TextureResource.CreateOptions(semantic: .color,
                                                  mipmapsMode: .allocateAndGenerateAll)
        let tex = try TextureResource(image: cg, withName: nil, options: opts)
        mat.color = .init(tint: .white, texture: .init(tex))
        mat.blending = .transparent(opacity: 1.0)
        let halo = ModelEntity(
            mesh: MeshResource.generatePlane(width: Self.cardW * 2.4,
                                             depth: Self.cardH * 2.4),
            materials: [mat]
        )
        halo.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        halo.position = SIMD3<Float>(0, 0, -0.015)
        return halo
    }

    /// Three thin vertical light-beam planes positioned diagonally
    /// behind the card. Read as "shafts from off-screen spotlights."
    @MainActor
    static func makeLightBeams(palette: [UIColor]) throws -> [ModelEntity] {
        let primary = palette.first ?? .darkGray
        let rim = Self.hueShifted(primary, byHue: 0.42, satScale: 0.85)

        func beam(color: UIColor, alpha: CGFloat) throws -> ModelEntity {
            let w = 64, h = 512
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw NSError(domain: "HeroShot", code: 110) }
            let colors = [
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(alpha).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray
            guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                     locations: [0.0, 0.5, 1.0]) else {
                throw NSError(domain: "HeroShot", code: 111)
            }
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: CGFloat(w), y: 0),
                                   options: [])
            guard let cg = ctx.makeImage() else {
                throw NSError(domain: "HeroShot", code: 112)
            }
            var mat = UnlitMaterial()
            let opts = TextureResource.CreateOptions(semantic: .color,
                                                      mipmapsMode: .allocateAndGenerateAll)
            let tex = try TextureResource(image: cg, withName: nil, options: opts)
            mat.color = .init(tint: .white, texture: .init(tex))
            mat.blending = .transparent(opacity: 1.0)
            let entity = ModelEntity(
                mesh: MeshResource.generatePlane(width: 0.02, depth: 0.30),
                materials: [mat]
            )
            return entity
        }

        let beamL = try beam(color: primary, alpha: 0.65)
        beamL.position = SIMD3<Float>(-0.09, 0.02, -0.08)
        beamL.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)) *
                            simd_quatf(angle: -0.18, axis: SIMD3<Float>(0, 0, 1))

        let beamR = try beam(color: rim, alpha: 0.55)
        beamR.position = SIMD3<Float>(0.09, 0.02, -0.08)
        beamR.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)) *
                            simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 0, 1))

        let beamC = try beam(color: primary, alpha: 0.45)
        beamC.position = SIMD3<Float>(0, 0.03, -0.12)
        beamC.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))

        return [beamL, beamR, beamC]
    }

    /// Six small glow spheres scattered behind/beside the card.
    /// Read as floating specular highlights or particles.
    @MainActor
    static func makeAccentGlows(palette: [UIColor]) -> [ModelEntity] {
        let primary = palette.first ?? .darkGray
        let rim = Self.hueShifted(primary, byHue: 0.42, satScale: 0.85)
        let positions: [(SIMD3<Float>, UIColor)] = [
            (SIMD3<Float>(-0.08,  0.05, -0.04), primary),
            (SIMD3<Float>( 0.08,  0.04, -0.04), rim),
            (SIMD3<Float>(-0.07, -0.04, -0.06), rim),
            (SIMD3<Float>( 0.07, -0.05, -0.06), primary),
            (SIMD3<Float>(-0.04,  0.07, -0.10), primary),
            (SIMD3<Float>( 0.04, -0.07, -0.10), rim)
        ]
        return positions.map { pos, color in
            var mat = UnlitMaterial()
            mat.color = .init(tint: color)
            let glow = ModelEntity(
                mesh: MeshResource.generateSphere(radius: 0.004),
                materials: [mat]
            )
            glow.position = pos
            return glow
        }
    }

    /// Low, wide pedestal beneath the card. The card visibly sits ON
    /// something instead of floating. Top palette-bright, front face
    /// darker (faux ambient occlusion).
    @MainActor
    static func makePedestal(palette: [UIColor]) -> [ModelEntity] {
        let primary = palette.first ?? .darkGray
        let top = Self.blendColor(primary, with: .white, t: 0.20)
        let side = Self.blendColor(primary, with: .black, t: 0.55)

        var topMat = UnlitMaterial()
        topMat.color = .init(tint: top)
        let pedTop = ModelEntity(
            mesh: MeshResource.generatePlane(width: 0.12, depth: 0.10),
            materials: [topMat]
        )
        pedTop.position = SIMD3<Float>(0, -Self.cardH * 0.5 + 0.001, 0)

        var sideMat = UnlitMaterial()
        sideMat.color = .init(tint: side)
        let pedFront = ModelEntity(
            mesh: MeshResource.generatePlane(width: 0.12, depth: 0.012),
            materials: [sideMat]
        )
        pedFront.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        pedFront.position = SIMD3<Float>(0, -Self.cardH * 0.5 - 0.005, 0.050)
        return [pedTop, pedFront]
    }

    /// Hue rotation helper for rim color (mirrors sim3d.swift recipe).
    nonisolated static func hueShifted(_ color: UIColor, byHue delta: CGFloat,
                                       satScale: CGFloat = 1.0) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 1
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        var newH = h + delta
        if newH > 1 { newH -= 1 } else if newH < 0 { newH += 1 }
        return UIColor(hue: newH, saturation: max(0, min(1, s * satScale)),
                       brightness: v, alpha: a)
    }

    // MARK: - Camera math

    /// Animate the key light through a slow rim-light sweep across
    /// the clip duration. Base position (0.3, 0.4, 0.5) → sweep around
    /// Y axis by ±45° centered on the base azimuth. This makes foil
    /// treatments (Battlefoil's diagonal stripes, Superfoil's noise,
    /// Inspired Ink's vertical bands) catch the light at different
    /// angles as the clip progresses — the "silhouette rake" beat per
    /// the research synthesis on MKBHD tech-demo camera-and-light
    /// dynamics. For non-foil cards the effect is subtle but adds the
    /// "alive frame" feel the eye reads as production value.
    static func applyKeyLightPose(time: Double, duration: Double,
                                   light: DirectionalLight) {
        let progress = duration > 0 ? max(0, min(1, time / duration)) : 0
        // Smooth oscillation: -45° → +45° → -45° across the clip via
        // sine. Avoids constant velocity (hobbyist tell) and gives the
        // settle beats moments of held rim emphasis.
        let phase = progress * .pi * 2.0
        let sweepDeg: Float = 45.0
        let azOffset = Float(sin(phase)) * sweepDeg * .pi / 180
        // Base position: (0.3, 0.4, 0.5). Distance from origin ≈ 0.71.
        // Rotate (x, z) around Y by azOffset.
        let r: Float = 0.71
        let baseAz: Float = atan2(0.3, 0.5)
        let az = baseAz + azOffset
        let pos = SIMD3<Float>(sin(az) * r, 0.4, cos(az) * r)
        light.look(at: .zero, from: pos, relativeTo: nil)
    }

    /// Smoothstep: 3t² - 2t³. Matches `easeInOut` shape.
    /// Ease-out cubic — fast start, slow finish. Reads as the camera
    /// "arriving" or "settling" into a pose, which is what premium
    /// product reveals do at every keyframe landing. Smoothstep
    /// (used elsewhere) is symmetric and reads as constant motion;
    /// this asymmetric curve is what gives weight to the arrival.
    static func easeOutCubic(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return 1.0 - pow(1.0 - c, 3.0)
    }

    /// Apply a tiny sinusoidal "breath" to a camera pose. Used during
    /// hold phases (and for stylistic effect inside long static beats)
    /// so the frame doesn't feel frozen. Amplitude is below the
    /// perceptual threshold for "motion" but above zero — the eye
    /// reads the frame as alive.
    static func breathing(_ pose: CameraPose, at time: Double) -> CameraPose {
        let dx = Float(sin(time * 0.7)) * 0.0008
        let dy = Float(cos(time * 0.5)) * 0.0006
        let dfov = Float(sin(time * 0.3)) * 0.15
        return CameraPose(
            position: pose.position + SIMD3<Float>(dx, dy, 0),
            lookAt:   pose.lookAt,
            fovDeg:   pose.fovDeg + dfov
        )
    }

    static func easedProgress(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }

    static func applyCameraPose(_ pose: CameraPose, to camera: PerspectiveCamera) {
        camera.look(at: pose.lookAt, from: pose.position,
                    upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
        camera.camera.fieldOfViewInDegrees = pose.fovDeg
    }

    static func lerpPose(_ a: CameraPose, _ b: CameraPose, _ t: Float) -> CameraPose {
        CameraPose(
            position: SIMD3<Float>(
                lerp(a.position.x, b.position.x, t),
                lerp(a.position.y, b.position.y, t),
                lerp(a.position.z, b.position.z, t)
            ),
            lookAt: SIMD3<Float>(
                lerp(a.lookAt.x, b.lookAt.x, t),
                lerp(a.lookAt.y, b.lookAt.y, t),
                lerp(a.lookAt.z, b.lookAt.z, t)
            ),
            fovDeg: lerp(a.fovDeg, b.fovDeg, t)
        )
    }

    // MARK: - Render frame

    private func renderFrame(_ renderer: RealityRenderer,
                             into texture: MTLTexture,
                             deltaTime: Double) throws {
        let desc = RealityRenderer.CameraOutput.Descriptor.singleProjection(colorTexture: texture)
        let output = try RealityRenderer.CameraOutput(desc)
        let group = DispatchGroup()
        group.enter()
        try renderer.updateAndRender(deltaTime: deltaTime, cameraOutput: output, onComplete: { _ in
            group.leave()
        })
        group.wait()
    }

    // MARK: - MTLTexture ↔ CVPixelBuffer bridge

    private func makeMTLTexture(from pixelBuffer: CVPixelBuffer,
                                cache: CVMetalTextureCache,
                                size: CGSize) -> MTLTexture? {
        var cvTex: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, Int(size.width), Int(size.height),
            0, &cvTex
        )
        guard result == kCVReturnSuccess, let cvTex,
              let tex = CVMetalTextureGetTexture(cvTex) else { return nil }
        return tex
    }

    private func makePixelBufferPool(size: CGSize) throws -> CVPixelBufferPool {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:  Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var pool: CVPixelBufferPool?
        let r = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        guard r == kCVReturnSuccess, let pool else {
            throw RenderError.pixelBufferPoolUnavailable
        }
        return pool
    }

    // MARK: - AVAssetWriter

    private func makeOutputURL() -> URL {
        let name = "hero-shot-\(UUID().uuidString).mp4"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    private func makeAssetWriter(url: URL, size: CGSize, bitrate: Int, fps: Int) throws -> AVAssetWriter {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(url: url, fileType: .mp4)

        let codec: AVVideoCodecType = .hevc
        let settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps  // 1s GOP
            ] as [String: Any]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw RenderError.writerSetupFailed }
        writer.add(input)
        return writer
    }

    // MARK: - Watermark

    /// Rasterize the BOBA wordmark once to a `CIImage` sized to the output
    /// frame. Positioned bottom-right with safe-area-like inset.
    private func rasterizeWatermark(targetSize: CGSize) -> CIImage? {
        // Render the SwiftUI wordmark at 2x for crispness, then offset into
        // the bottom-right corner of a target-sized transparent canvas.
        let scale: CGFloat = 2.0
        let renderer = ImageRenderer(content:
            HeroShotWatermarkOverlay()
                .frame(width: targetSize.width / scale,
                       height: targetSize.height / scale)
        )
        renderer.scale = scale
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }

    /// v6.0.8.1 — render the pixel buffer through CIExposureAdjust
    /// in place. Each EV stop halves brightness; -2 EV = 1/4
    /// brightness. The user's "still so so so washed out" report
    /// after individual lighting tweaks didn't move the needle
    /// suggested I needed a single dial on perceived exposure
    /// rather than balancing competing light sources.
    private func applyExposurePass(to pixelBuffer: CVPixelBuffer,
                                    ev: Float,
                                    ciContext: CIContext) {
        let base = CIImage(cvPixelBuffer: pixelBuffer)
        let exposed = Self.applyExposureEV(base, ev: ev)
        ciContext.render(exposed, to: pixelBuffer)
    }

    private func compositeWatermark(into pixelBuffer: CVPixelBuffer,
                                    watermark: CIImage,
                                    ciContext: CIContext) -> CVPixelBuffer? {
        let base = CIImage(cvPixelBuffer: pixelBuffer)
        let filter = CIFilter.sourceOverCompositing()
        filter.inputImage = watermark
        filter.backgroundImage = base
        guard let out = filter.outputImage else { return nil }
        ciContext.render(out, to: pixelBuffer)
        return pixelBuffer
    }
}

// MARK: - Helpers

@inline(__always)
private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

/// The visual overlay that becomes the watermark — anchored bottom-right.
/// Public so the preview UI and the renderer can share the same shape.
struct HeroShotWatermarkOverlay: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                BOBAWordmark()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                    .padding(.trailing, 24)
                    .padding(.bottom, 36)
            }
        }
    }
}
