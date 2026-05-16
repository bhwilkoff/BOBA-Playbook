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

    /// The hero-shot arc. Adds at most one case per ship — keep this
    /// list intentional. v2 ships `.heroReveal` only.
    enum ArcPreset: String, CaseIterable, Identifiable {
        /// 360° card spin (front → edge → back → edge → front) →
        /// brief settle → tight straight-on pan from the card's
        /// top-left to bottom-right. Designed to show the FULL 3D
        /// card first, then linger on the art.
        case heroReveal

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .heroReveal: return "Hero Reveal"
            }
        }

        /// Per-frame animation state. Phase boundaries scale with
        /// `duration` so longer clips stretch proportionally and look
        /// the same shape at any length.
        ///
        /// Four phases of `.heroReveal` (fractions of `duration`):
        ///
        ///   0     → 0.20   APPROACH  — wide cinematic dolly from a far
        ///                              low-left establishing shot to the
        ///                              spin viewpoint (left of center,
        ///                              slight high angle). FOV 48° → 38°.
        ///   0.20  → 0.50   SPIN      — camera fixed; cardPivot yaw 0→2π.
        ///                              Front → edge → BOBA card-back →
        ///                              edge → front. Edge box visible at
        ///                              the edge-on moments.
        ///   0.50  → 0.92   HERO PAN  — true orbital arc at constant
        ///                              distance (~36cm) from the left
        ///                              spin viewpoint across to the
        ///                              right. Card stays at yaw=0 so the
        ///                              camera sees the art the whole
        ///                              time, but from changing angles.
        ///                              This is the centerpiece move.
        ///   0.92  → 1.00   HOLD      — locked on the right-side hero pose.
        func frame(at time: Double,
                   duration: Double,
                   cardW: Float, cardH: Float, halfT: Float) -> AnimationFrame {
            switch self {
            case .heroReveal:
                return HeroShotRenderer.heroRevealFrame(
                    at: time, duration: duration,
                    cardW: cardW, cardH: cardH, halfT: halfT
                )
            }
        }
    }

    /// Camera arc for `.heroReveal`. Pure function of time — same input
    /// always returns the same frame state (deterministic offline render).
    static func heroRevealFrame(at time: Double,
                                duration: Double,
                                cardW: Float, cardH: Float, halfT: Float) -> AnimationFrame {
        // Phase boundaries in absolute time.
        let approachEnd: Double = duration * 0.20   //  2.0s @ 10s
        let spinEnd:     Double = duration * 0.50   //  5.0s @ 10s
        let panEnd:      Double = duration * 0.92   //  9.2s @ 10s

        // Orbital pan parameters. The pan stays at constant distance from
        // the card center (orbits a sphere) with a slight upward tilt.
        // "From a good distance" = 36cm in front of the card, which at
        // FOV 36° frames the card with comfortable headroom and lets the
        // stage environment show around it.
        let panDistance:  Float = 0.36
        let panElevation: Float = 7 * .pi / 180     // ~7° above horizon
        let panAzMin:     Float = -22 * .pi / 180   // left side
        let panAzMax:     Float =  22 * .pi / 180   // right side
        let panR: Float = panDistance * cos(panElevation)
        let panY: Float = panDistance * sin(panElevation)
        let orbitalPos: (Float) -> SIMD3<Float> = { az in
            SIMD3<Float>(panR * sin(az), panY, panR * cos(az))
        }

        // Approach + spin viewpoint = orbital position at the LEFT edge
        // of the hero pan. Ending the approach exactly at the pan's
        // start point means there's no awkward camera jump between
        // spin and pan — the pan continues seamlessly from where the
        // spin ended.
        let spinViewpoint = orbitalPos(panAzMin)
        let spinPose = CameraPose(
            position: spinViewpoint,
            lookAt:   .zero,
            fovDeg:   38
        )

        let approachStart = CameraPose(
            position: SIMD3<Float>(-0.28, -0.06, 0.55),
            lookAt:   SIMD3<Float>(0, -0.02, 0),
            fovDeg:   48
        )

        let panEndPose = CameraPose(
            position: orbitalPos(panAzMax),
            lookAt:   .zero,
            fovDeg:   36
        )

        if time <= approachEnd {
            // APPROACH — wide dolly from far-low-left to the spin
            // viewpoint. FOV narrows from 48° (wide establishing) to
            // 38° (3/4 over-the-shoulder).
            let raw = approachEnd == 0 ? 1.0 : time / approachEnd
            let eased = easedProgress(raw)
            return AnimationFrame(
                cameraPose: lerpPose(approachStart, spinPose, Float(eased)),
                cardYaw: 0
            )
        } else if time <= spinEnd {
            // SPIN — camera holds at spin viewpoint; card rotates.
            // Smoothstep easing makes the spin start + end feel like
            // landings; the front- and back-facing moments read as
            // intentional poses, not midpoints of constant motion.
            let raw = (time - approachEnd) / (spinEnd - approachEnd)
            let eased = easedProgress(raw)
            return AnimationFrame(
                cameraPose: spinPose,
                cardYaw: Float(eased) * 2 * .pi
            )
        } else if time <= panEnd {
            // HERO PAN — orbital arc from -22° to +22° azimuth at
            // constant 36cm distance. The camera traces a true circular
            // path (not a linear lerp between two endpoints) so the
            // pan feels like a real "around" move with constant
            // framing distance. FOV narrows slightly through the move
            // (38° → 36°) to add a subtle push-in feel.
            let raw = (time - spinEnd) / (panEnd - spinEnd)
            let eased = Float(easedProgress(raw))
            let az = lerp(panAzMin, panAzMax, eased)
            let pose = CameraPose(
                position: orbitalPos(az),
                lookAt:   .zero,
                fovDeg:   lerp(38, 36, eased)
            )
            return AnimationFrame(cameraPose: pose, cardYaw: 0)
        } else {
            // HOLD — frozen on the right-side hero pose.
            return AnimationFrame(cameraPose: panEndPose, cardYaw: 0)
        }
    }

    /// A single key in the camera animation: camera position, look-at
    /// target, FOV. Lerped per-frame via `lerp(_:_:_:)`.
    struct CameraPose {
        var position: SIMD3<Float>
        var lookAt: SIMD3<Float>
        var fovDeg: Float
    }

    /// Per-frame animation state. The camera pose drives where we look
    /// from / at, `cardYaw` rotates the card around its vertical axis
    /// for the phase-1 spin.
    struct AnimationFrame {
        var cameraPose: CameraPose
        var cardYaw: Float
    }

    struct Config {
        var card: Card
        var frontTexture: TextureResource
        var backTexture: TextureResource?
        var includeWatermark: Bool = true
        var arc: ArcPreset = .heroReveal
        /// Default: 10s. Long enough for an approach + spin + cinematic
        /// hero pan + hold without any phase feeling rushed.
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
            let anim = config.arc.frame(at: time,
                                        duration: config.duration,
                                        cardW: cardW, cardH: cardH, halfT: halfT)
            HeroShotRenderer.applyCameraPose(anim.cameraPose, to: scene.camera)
            scene.cardPivot.orientation = simd_quatf(angle: anim.cardYaw, axis: SIMD3<Float>(0, 1, 0))

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

        // Deep-space scene clear. Everything inside the camera frustum
        // is covered by the backdrop or floor planes; the clear color
        // only shows in case of misframe.
        let bg = UIColor(red: 0.015, green: 0.015, blue: 0.035, alpha: 1.0).cgColor
        renderer.cameraSettings.colorBackground = .color(bg)

        let root = Entity()
        renderer.entities.append(root)

        let elem = Self.elementColor(for: config.card)

        // ── Stage backdrop ────────────────────────────────────────────
        // Large element-tinted vertical plane far behind the card.
        // Radial gradient with element color blooming from the
        // horizon line, fading to deep-space at the edges. Larger
        // dimensions + further pushed back than v2 so wide camera
        // shots in phase 1 still frame inside it.
        let backdrop = ModelEntity(
            mesh: MeshResource.generatePlane(width: 2.4, depth: 3.2),
            materials: [Self.backdropMaterial(elementColor: elem)]
        )
        backdrop.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        backdrop.position = SIMD3<Float>(0, 0.10, -0.85)
        root.addChild(backdrop)

        // ── Stage floor ───────────────────────────────────────────────
        // Horizontal plane under the card. Gradient texture: small
        // brighter element-tinted spot directly beneath the card,
        // fading to deep-space at the edges. Grounds the card visually
        // and gives a "stage" feel during the wide approach.
        let floor = ModelEntity(
            mesh: MeshResource.generatePlane(width: 1.6, depth: 1.6),
            materials: [Self.floorMaterial(elementColor: elem)]
        )
        // Plane is XZ with normal +Y by default. Place just below the
        // card's bottom edge so the card "stands on" the floor.
        floor.position = SIMD3<Float>(0, -Self.cardH * 0.5 - 0.003, 0)
        root.addChild(floor)

        // ── Card ────────────────────────────────────────────────────
        // Front + back planes + off-white card-stock edge, all from
        // the shared BOBACardEntity helper. Canonical `.upright` pose:
        // front normal +Z (toward the default camera), image-top +Y.
        // Cinematic Hero Shot env tints come from the backdrop/floor;
        // the card itself uses cream off-white edge stock for realism.
        let cardPivot = BOBACardEntity.build(BOBACardEntity.Config(
            frontTexture: config.frontTexture,
            backTexture: config.backTexture,
            includeEdge: true,
            pose: .upright
        ))
        cardPivot.position = .zero
        root.addChild(cardPivot)

        // ── Camera ──────────────────────────────────────────────────
        let camera = PerspectiveCamera()
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        let firstFrame = config.arc.frame(
            at: 0,
            duration: config.duration,
            cardW: Self.cardW, cardH: Self.cardH, halfT: Self.halfT
        )
        HeroShotRenderer.applyCameraPose(firstFrame.cameraPose, to: camera)

        return SceneBundle(renderer: renderer, camera: camera, cardPivot: cardPivot)
    }

    /// Backdrop material — element bloom fading to deep space.
    private static func backdropMaterial(elementColor elem: UIColor) -> UnlitMaterial {
        let w = 1024, h = 1024
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // First fill with deep-space.
            cg.setFillColor(UIColor(red: 0.015, green: 0.015, blue: 0.035, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // Then bloom element color from slightly below center
            // (sits at the horizon line behind the floor).
            let center = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) * 0.62)
            let radius = CGFloat(max(w, h)) * 0.70
            let colors = [
                elem.withAlphaComponent(0.85).cgColor,
                elem.withAlphaComponent(0.30).cgColor,
                UIColor(red: 0.015, green: 0.015, blue: 0.035, alpha: 0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.35, 1.0]
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!
            cg.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter:   center, endRadius:   radius,
                options: []
            )
        }
        var mat = UnlitMaterial()
        if let cg = img.cgImage,
           let tex = try? TextureResource(image: cg, withName: nil,
                                          options: TextureResource.CreateOptions(
                                              semantic: .color,
                                              mipmapsMode: .allocateAndGenerateAll)) {
            mat.color = .init(tint: .white, texture: .init(tex))
        } else {
            mat.color = .init(tint: UIColor(red: 0.015, green: 0.015, blue: 0.035, alpha: 1))
        }
        return mat
    }

    /// Floor material — small bright spot under the card fading to dark.
    private static func floorMaterial(elementColor elem: UIColor) -> UnlitMaterial {
        let w = 1024, h = 1024
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.020, green: 0.020, blue: 0.045, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // Spotlight under the card — element-tinted radial bloom.
            let center = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
            let radius = CGFloat(min(w, h)) * 0.40
            let colors = [
                elem.withAlphaComponent(0.55).cgColor,
                elem.withAlphaComponent(0.18).cgColor,
                UIColor(red: 0.020, green: 0.020, blue: 0.045, alpha: 0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!
            cg.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter:   center, endRadius:   radius,
                options: []
            )
        }
        var mat = UnlitMaterial()
        if let cg = img.cgImage,
           let tex = try? TextureResource(image: cg, withName: nil,
                                          options: TextureResource.CreateOptions(
                                              semantic: .color,
                                              mipmapsMode: .allocateAndGenerateAll)) {
            mat.color = .init(tint: .white, texture: .init(tex))
        } else {
            mat.color = .init(tint: UIColor(red: 0.020, green: 0.020, blue: 0.045, alpha: 1))
        }
        return mat
    }

    /// Map the catalog `element` field to the canonical UI color, mirroring
    /// `Design.Colors.element(_:)`. Inlined here so this file has no
    /// SwiftUI dependency on the design tokens.
    private static func elementColor(for card: Card) -> UIColor {
        switch card.element.uppercased() {
        case "FIRE":  return UIColor(red: 1.00, green: 0.30, blue: 0.00, alpha: 1)
        case "ICE":   return UIColor(red: 0.00, green: 0.75, blue: 1.00, alpha: 1)
        case "HEX":   return UIColor(red: 0.55, green: 0.00, blue: 1.00, alpha: 1)
        case "STEEL": return UIColor(red: 0.54, green: 0.61, blue: 0.69, alpha: 1)
        case "BRAWL": return UIColor(red: 0.75, green: 0.23, blue: 0.18, alpha: 1)
        case "GLOW":  return UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
        case "GUM":   return UIColor(red: 1.00, green: 0.41, blue: 0.71, alpha: 1)
        case "SUPER": return UIColor(red: 1.00, green: 0.00, blue: 1.00, alpha: 1)
        default:      return UIColor(red: 0.40, green: 0.40, blue: 0.50, alpha: 1)
        }
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
