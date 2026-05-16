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
        ///   0     → 0.30   APPROACH  — cinematic wide → tighter dolly.
        ///                              Card holds at yaw=0 (front-facing).
        ///                              FOV 44° → 36°. Camera arcs from a
        ///                              low-left wide establishing shot to
        ///                              a slight 3/4 over-the-shoulder.
        ///   0.30  → 0.66   SPIN      — Camera fixed at end-of-approach.
        ///                              cardPivot yaw 0 → 2π. Front → edge
        ///                              → BOBA card-back → edge → front.
        ///                              Edge box visible at the yaw=π/2 /
        ///                              3π/2 thin-strip moments.
        ///   0.66  → 0.92   GLIDE     — Slight horizontal arc to settle on
        ///                              a final 3/4 hero pose. Card holds
        ///                              at yaw=0.
        ///   0.92  → 1.00   HOLD      — Locked on the hero pose.
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
        let approachEnd: Double = duration * 0.30   // 1.50s @ 5s
        let spinEnd:     Double = duration * 0.66   // 3.30s @ 5s
        let glideEnd:    Double = duration * 0.92   // 4.60s @ 5s

        // Camera keyframes. All look-at points sit at the card center
        // (origin) so the card stays composed in frame regardless of
        // camera angle. Cartesian positions in meters.
        let approachStart = CameraPose(
            position: SIMD3<Float>(-0.08, -0.04, 0.42),  // low, left, far
            lookAt:   SIMD3<Float>(0, -0.01, 0),
            fovDeg:   44
        )
        let approachStop = CameraPose(
            position: SIMD3<Float>(0.02, 0.04, 0.26),    // slight 3/4 high
            lookAt:   SIMD3<Float>(0, 0, 0),
            fovDeg:   36
        )
        let glideStop = CameraPose(
            position: SIMD3<Float>(0.10, 0.025, 0.22),   // hero pose, more right
            lookAt:   SIMD3<Float>(0, 0, 0),
            fovDeg:   32
        )

        if time <= approachEnd {
            // APPROACH — wide cinematic dolly. Camera moves +
            // FOV narrows from 44° (establishing) to 36° (over-shoulder).
            let raw = approachEnd == 0 ? 1.0 : time / approachEnd
            let eased = easedProgress(raw)
            return AnimationFrame(
                cameraPose: lerpPose(approachStart, approachStop, Float(eased)),
                cardYaw: 0
            )
        } else if time <= spinEnd {
            // SPIN — camera holds at end-of-approach; card rotates.
            // Easing gives the spin slight start-pause and end-pause
            // so the front-facing moments feel like landings.
            let raw = (time - approachEnd) / (spinEnd - approachEnd)
            let eased = easedProgress(raw)
            return AnimationFrame(
                cameraPose: approachStop,
                cardYaw: Float(eased) * 2 * .pi
            )
        } else if time <= glideEnd {
            // GLIDE — slight rightward arc into the hero pose.
            let raw = (time - spinEnd) / (glideEnd - spinEnd)
            let eased = easedProgress(raw)
            return AnimationFrame(
                cameraPose: lerpPose(approachStop, glideStop, Float(eased)),
                cardYaw: 0
            )
        } else {
            // HOLD — frozen on the hero pose.
            return AnimationFrame(cameraPose: glideStop, cardYaw: 0)
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
        var duration: TimeInterval = 5.0
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

    /// Standard BoBA card dimensions in meters (~63.5mm × 88.9mm — real
    /// physical card size). The 1.5mm `halfT` is purely visual offset
    /// between the front and back planes; the card has no rigid body
    /// here (Hero Shot is a pure render).
    static let cardW: Float = 0.0635
    static let cardH: Float = 0.0889
    static let halfT: Float = 0.0015

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

        // ── Card pivot ────────────────────────────────────────────────
        // Front + back planes + edge box are children of this pivot.
        // Spinning the pivot around its Y rotates the whole card as a
        // single unit. Pivot at world origin = card center.
        let cardPivot = Entity()
        cardPivot.position = .zero
        root.addChild(cardPivot)

        // ── Front plane ──────────────────────────────────────────────
        // `MeshResource.generatePlane(width:depth:)` lives in XZ (width
        // X, depth Z), normal +Y, image-V mapped top → -Z. Rotate
        // +π/2 around X to get:
        //    normal +Y    → +Z  (faces the front-of-card direction)
        //    image-top -Z → +Y  (right-side up)
        let frontMesh = MeshResource.generatePlane(width: Self.cardW, depth: Self.cardH)
        var frontMat = UnlitMaterial()
        frontMat.color = .init(tint: .white, texture: .init(config.frontTexture))
        let front = ModelEntity(mesh: frontMesh, materials: [frontMat])
        front.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        front.position = SIMD3<Float>(0, 0, Self.halfT)
        cardPivot.addChild(front)

        // ── Back plane ──────────────────────────────────────────────
        // We need:
        //   normal at -Z (faces the back direction)
        //   image-top at +Y (so the bundled card-back PNG isn't
        //                    upside-down when the spin shows the back)
        //
        // R_x(-π/2) alone gives normal at -Z but image-top at -Y
        // (upside-down). Compose with R_y(π) first (applied to the
        // local axes before the X tilt) to flip image-V:
        //
        //   R_back = R_x(-π/2) * R_y(π)
        //
        // Swift quaternion compose: q1 * q2 applies q2 first. So this
        // means R_y(π) acts on the local axes first, then R_x(-π/2)
        // tilts. Result: normal → -Z, image-top → +Y. Verified.
        let backMesh = MeshResource.generatePlane(width: Self.cardW, depth: Self.cardH)
        var backMat = UnlitMaterial()
        if let backTex = config.backTexture {
            backMat.color = .init(tint: .white, texture: .init(backTex))
        } else {
            backMat.color = .init(tint: UIColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1))
        }
        let back = ModelEntity(mesh: backMesh, materials: [backMat])
        back.orientation =
            simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        back.position = SIMD3<Float>(0, 0, -Self.halfT)
        cardPivot.addChild(back)

        // ── Card edge ───────────────────────────────────────────────
        // Thin element-tinted box that sits BETWEEN the front and back
        // planes. When the camera sees the card at an angle (and during
        // the spin's edge-on moments), the box's side faces show a
        // visible element-colored stripe — the card reads as a physical
        // object with real thickness rather than two coplanar planes
        // with nothing between them.
        //
        // Dimensions slightly smaller than the planes so the box's
        // own +Z/-Z faces are HIDDEN behind the planes (no z-fighting).
        // The box's X and Y faces (the side edges) remain visible.
        let edgeInset: Float = 0.0008
        let edgeMesh = MeshResource.generateBox(
            size: SIMD3<Float>(
                Self.cardW - edgeInset * 2,
                Self.cardH - edgeInset * 2,
                Self.halfT * 1.5    // slightly less than 2*halfT so it sits inside
            )
        )
        var edgeMat = UnlitMaterial()
        // Lighten the element color so the edge reads against the dark
        // backdrop without overpowering the art.
        edgeMat.color = .init(tint: Self.blendColor(elem, with: .white, t: 0.35))
        let edge = ModelEntity(mesh: edgeMesh, materials: [edgeMat])
        edge.position = .zero
        cardPivot.addChild(edge)

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

    /// Blend two UIColors in sRGB.
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
