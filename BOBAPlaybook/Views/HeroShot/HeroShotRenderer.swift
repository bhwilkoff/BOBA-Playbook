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

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .reveal:   return "Reveal"
            case .showcase: return "Showcase"
            case .detail:   return "Detail"
            }
        }

        var caption: String {
            switch self {
            case .reveal:
                return "Slides in, settles, pushes for the close-up"
            case .showcase:
                return "Slow arc, then a dolly-push to the hero pose"
            case .detail:
                return "Wide opener, then a macro orbit of the art"
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
    ///   0.00 → 0.25  SLIDE IN  — far+offaxis dolly to hero-wide.
    ///   0.25 → 0.65  SETTLE    — small drift; absorb the card.
    ///   0.65 → 0.95  PUSH IN   — camera + FOV both close on detail.
    ///   0.95 → 1.00  HOLD
    static func revealFrame(at time: Double, duration: Double) -> CameraPose {
        let slideEnd:  Double = duration * 0.25
        let settleEnd: Double = duration * 0.65
        let pushEnd:   Double = duration * 0.95

        let slideStart = CameraPose(
            position: SIMD3<Float>(-0.32, -0.08, 0.55),
            lookAt:   SIMD3<Float>(-0.04, -0.02, 0),
            fovDeg:   46
        )
        let heroWide = CameraPose(
            position: SIMD3<Float>(0.02, 0.03, 0.24),
            lookAt:   .zero,
            fovDeg:   34
        )
        let settleHold = CameraPose(
            position: SIMD3<Float>(-0.02, 0.025, 0.22),
            lookAt:   .zero,
            fovDeg:   32
        )
        let pushClose = CameraPose(
            position: SIMD3<Float>(0.015, 0.015, 0.10),
            lookAt:   SIMD3<Float>(0, 0.005, 0),
            fovDeg:   28
        )

        if time <= slideEnd {
            let t = Float(easedProgress(slideEnd == 0 ? 1.0 : time / slideEnd))
            return lerpPose(slideStart, heroWide, t)
        } else if time <= settleEnd {
            let t = Float(easedProgress((time - slideEnd) / (settleEnd - slideEnd)))
            return lerpPose(heroWide, settleHold, t)
        } else if time <= pushEnd {
            // Cubic ease-in for the last 30% — feels like the camera
            // is grabbed and pulled toward the card.
            let raw = (time - settleEnd) / (pushEnd - settleEnd)
            let eased = Float(raw * raw * (3 - 2 * raw))   // smoothstep
            return lerpPose(settleHold, pushClose, eased)
        } else {
            return pushClose
        }
    }

    /// "Showcase" — slow arc → dolly-push climax. Card stays static.
    ///   0.00 → 0.85  ARC       — orbit -25° → +25° at constant 0.30m.
    ///   0.85 → 0.96  PUSH IN   — dolly forward to 0.11m + tighten FOV.
    ///   0.96 → 1.00  HOLD
    static func showcaseFrame(at time: Double, duration: Double) -> CameraPose {
        let arcEnd:  Double = duration * 0.85
        let pushEnd: Double = duration * 0.96

        let arcDistance: Float = 0.30
        let arcElev:     Float = 5 * .pi / 180
        let arcAzMin:    Float = -25 * .pi / 180
        let arcAzMax:    Float =  25 * .pi / 180
        let arcR: Float = arcDistance * cos(arcElev)
        let arcY: Float = arcDistance * sin(arcElev)
        let orbital: (Float) -> SIMD3<Float> = { az in
            SIMD3<Float>(arcR * sin(az), arcY, arcR * cos(az))
        }

        if time <= arcEnd {
            let t = Float(easedProgress(arcEnd == 0 ? 1.0 : time / arcEnd))
            let az = lerp(arcAzMin, arcAzMax, t)
            return CameraPose(position: orbital(az), lookAt: .zero, fovDeg: 36)
        } else {
            // PUSH IN from arc-end position toward a closer hero pose,
            // narrowing FOV simultaneously (subtle dolly-zoom feel).
            let arcEndPose = CameraPose(
                position: orbital(arcAzMax),
                lookAt: .zero,
                fovDeg: 36
            )
            let closePose = CameraPose(
                position: SIMD3<Float>(0.05, 0.015, 0.11),
                lookAt: SIMD3<Float>(0, 0, 0),
                fovDeg: 26
            )
            if time <= pushEnd {
                let t = Float(easedProgress((time - arcEnd) / (pushEnd - arcEnd)))
                return lerpPose(arcEndPose, closePose, t)
            } else {
                return closePose
            }
        }
    }

    /// "Detail" — wide opener → macro orbit. Best for foil cards.
    ///   0.00 → 0.18  WIDE      — far establishing shot, card small.
    ///   0.18 → 0.32  DOLLY IN  — fast push into the art's center 60%.
    ///   0.32 → 0.92  MACRO ARC — small orbit at very close range.
    ///   0.92 → 1.00  HOLD
    static func detailFrame(at time: Double, duration: Double) -> CameraPose {
        let wideEnd:  Double = duration * 0.18
        let dollyEnd: Double = duration * 0.32
        let macroEnd: Double = duration * 0.92

        let wide = CameraPose(
            position: SIMD3<Float>(-0.10, 0.04, 0.50),
            lookAt:   SIMD3<Float>(0, -0.005, 0),
            fovDeg:   42
        )
        let macroDistance: Float = 0.085
        let macroElev:     Float = 4 * .pi / 180
        let macroAzMin:    Float = -10 * .pi / 180
        let macroAzMax:    Float =  10 * .pi / 180
        let macroR: Float = macroDistance * cos(macroElev)
        let macroY: Float = macroDistance * sin(macroElev)
        let macroOrbital: (Float) -> SIMD3<Float> = { az in
            SIMD3<Float>(macroR * sin(az), macroY, macroR * cos(az))
        }
        let macroStart = CameraPose(
            position: macroOrbital(macroAzMin),
            lookAt:   .zero,
            fovDeg:   26
        )

        if time <= wideEnd {
            return wide
        } else if time <= dollyEnd {
            let t = Float(easedProgress((time - wideEnd) / (dollyEnd - wideEnd)))
            return lerpPose(wide, macroStart, t)
        } else if time <= macroEnd {
            // Macro orbit at ~8.5cm — close enough to see foil texture.
            let t = Float(easedProgress((time - dollyEnd) / (macroEnd - dollyEnd)))
            let az = lerp(macroAzMin, macroAzMax, t)
            return CameraPose(position: macroOrbital(az), lookAt: .zero, fovDeg: 26)
        } else {
            return CameraPose(position: macroOrbital(macroAzMax),
                              lookAt: .zero,
                              fovDeg: 26)
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
            // One slow 360° rotation across the WHOLE clip, linear so
            // the clip is loopable (constant angular velocity).
            return Float(progress) * 2 * .pi
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

        // Convert CVPixelBuffer → UIImage.
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(mtlDevice: device)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            throw RenderError.textureCreateFailed
        }
        return UIImage(cgImage: cg)
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
    }

    private func buildScene(config: Config) throws -> SceneBundle {
        let renderer = try RealityRenderer()

        // Scene clear is irrelevant — the backdrop plane covers the
        // whole camera frustum at all preset cameras. Keep it dark so
        // any misframe at least reads as intentional.
        renderer.cameraSettings.colorBackground = .color(UIColor.black.cgColor)

        let root = Entity()
        renderer.entities.append(root)

        // ── Env-extension texture ────────────────────────────────────
        // Generate ONE 2048×1024 image from the card art: heavy blur +
        // saturation + mirror-tile + treatment overlay. Used as BOTH
        // the visible backdrop texture AND the IBL environment, so
        // the lighting tone literally comes from the card's colors.
        let palette = HeroShotEnvironment.extractPalette(from: config.frontImage)
        let envCG = HeroShotEnvironment.generateImage(
            frontArt: config.frontImage,
            treatment: config.card.treatment,
            palette: palette
        )

        // ── Stage backdrop ───────────────────────────────────────────
        // Big plane behind everything, textured with the env-extension
        // image. PBR matte so it picks up rim lighting from the back
        // light + IBL — gives the backdrop depth.
        var backdropMat = PhysicallyBasedMaterial()
        if let cg = envCG,
           let tex = try? TextureResource(image: cg, withName: nil,
                                          options: TextureResource.CreateOptions(
                                              semantic: .color,
                                              mipmapsMode: .allocateAndGenerateAll)) {
            backdropMat.baseColor = .init(tint: .white, texture: .init(tex))
        } else {
            backdropMat.baseColor = .init(tint: palette.first ?? .darkGray)
        }
        backdropMat.roughness = 0.85
        backdropMat.metallic = 0.0
        let backdrop = ModelEntity(
            mesh: MeshResource.generatePlane(width: 2.4, depth: 3.2),
            materials: [backdropMat]
        )
        backdrop.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        backdrop.position = SIMD3<Float>(0, 0.10, -0.85)
        root.addChild(backdrop)

        // ── Stage floor ──────────────────────────────────────────────
        // PBR matte floor that picks up the rim/fill lights. Tinted
        // by the primary palette color so the ground reads as part
        // of the same environment as the backdrop, just dimmer.
        var floorMat = PhysicallyBasedMaterial()
        floorMat.baseColor = .init(tint: Self.blendColor(
            palette.first ?? .darkGray, with: .black, t: 0.65))
        floorMat.roughness = 0.55
        floorMat.metallic = 0.0
        let floor = ModelEntity(
            mesh: MeshResource.generatePlane(width: 1.6, depth: 1.6),
            materials: [floorMat]
        )
        floor.position = SIMD3<Float>(0, -Self.cardH * 0.5 - 0.003, 0)
        root.addChild(floor)

        // ── Card (PBR with treatment-keyed roughness) ────────────────
        // The card now renders with PhysicallyBasedMaterial so it
        // responds to the lighting rig AND to the IBL environment.
        // Foil treatments use a localized roughness texture so the
        // foil regions reflect light differently from paper regions —
        // real specular sheen as the camera arcs around.
        let cardPivot = BOBACardEntity.build(BOBACardEntity.Config(
            frontTexture: config.frontTexture,
            backTexture: config.backTexture,
            includeEdge: true,
            pose: .upright,
            material: .physicallyBased,
            treatment: config.card.treatment
        ))
        cardPivot.position = .zero
        root.addChild(cardPivot)

        // ── Image-Based Lighting ─────────────────────────────────────
        // The IBL environment is the SAME env-extension image used on
        // the backdrop plane. The card lights itself from its own
        // colors. intensityExponent: 1.2 compensates for the source
        // being LDR (real HDRIs are brighter so they need less boost).
        if let cg = envCG,
           let env = try? EnvironmentResource(equirectangular: cg, withName: nil) {
            let iblComponent = ImageBasedLightComponent(
                source: .single(env),
                intensityExponent: 1.2
            )
            cardPivot.components.set(iblComponent)
            cardPivot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: cardPivot))
            // Backdrop + floor receive too, so their PBR materials sample
            // the same ambient color contribution.
            backdrop.components.set(ImageBasedLightReceiverComponent(imageBasedLight: cardPivot))
            floor.components.set(ImageBasedLightReceiverComponent(imageBasedLight: cardPivot))
        }

        // ── 3-point lighting rig ─────────────────────────────────────
        // Calibrated intensities per the lighting research — these
        // values produce a bright cinematic look (NOT defaults, which
        // read as dim AR-style). RealityKit caps: 1 DirectionalLight,
        // 8 total dynamic lights. We use 3 (key + fill + rim).

        // KEY — DirectionalLight, camera-right + above. Dominant source.
        let key = DirectionalLight()
        key.light.intensity = 20_000           // lumen/m² — bright but not blown
        key.light.color = .white
        key.look(at: .zero, from: SIMD3<Float>(0.4, 0.35, 0.35), relativeTo: nil)
        root.addChild(key)

        // FILL — PointLight, camera-left, softer, no shadows. Lifts
        // shadows on the camera-left side of the card.
        let fill = PointLight()
        fill.light.intensity = 3_000_000        // lumen
        fill.light.attenuationRadius = 1.5
        fill.light.color = Self.blendUIColor(palette.first ?? .white, with: .white, t: 0.55)
        fill.position = SIMD3<Float>(-0.35, 0.18, 0.30)
        root.addChild(fill)

        // RIM — SpotLight, behind + above, tight cone, aimed at card
        // top edge. Produces the "keynote glow" silhouette stripe.
        let rim = SpotLight()
        rim.light.intensity = 5_000_000         // lumen
        rim.light.innerAngleInDegrees = 20
        rim.light.outerAngleInDegrees = 35
        rim.light.attenuationRadius = 2.0
        rim.light.color = Self.blendUIColor(palette.first ?? .white, with: .white, t: 0.30)
        rim.look(at: SIMD3<Float>(0, BOBACardEntity.height * 0.4, 0),
                 from: SIMD3<Float>(0.05, 0.30, -0.20),
                 relativeTo: nil)
        root.addChild(rim)

        // ── Camera ───────────────────────────────────────────────────
        let camera = PerspectiveCamera()
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        let firstPose = config.arc.cameraFrame(
            at: 0,
            duration: config.duration,
            cardW: Self.cardW, cardH: Self.cardH, halfT: Self.halfT
        )
        HeroShotRenderer.applyCameraPose(firstPose, to: camera)

        return SceneBundle(renderer: renderer, camera: camera, cardPivot: cardPivot)
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

    // MARK: - Camera math

    /// Smoothstep: 3t² - 2t³. Matches `easeInOut` shape.
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
