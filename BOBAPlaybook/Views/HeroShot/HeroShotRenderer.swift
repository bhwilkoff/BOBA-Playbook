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

    enum ArcPreset: String, CaseIterable, Identifiable {
        case pivot   // 3/4 angle → straight-on with quarter rotation
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pivot: return "Pivot"
            }
        }

        /// Spherical-coordinate keyframes around the card's origin.
        var keyframes: (start: CameraKey, end: CameraKey) {
            switch self {
            case .pivot:
                return (
                    start: CameraKey(azimuth:  -25 * .pi / 180,
                                     elevation: 12 * .pi / 180,
                                     distance:  0.32,
                                     fovDeg:    32),
                    end:   CameraKey(azimuth:   20 * .pi / 180,
                                     elevation: -3 * .pi / 180,
                                     distance:  0.22,
                                     fovDeg:    26)
                )
            }
        }
    }

    struct CameraKey {
        var azimuth: Float
        var elevation: Float
        var distance: Float
        var fovDeg: Float
    }

    struct Config {
        var card: Card
        var frontTexture: TextureResource
        var backTexture: TextureResource?
        var includeWatermark: Bool = true
        var arc: ArcPreset = .pivot
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

        let arc = config.arc.keyframes

        for frame in 0..<totalFrames {
            try Task.checkCancellation()

            // Wait for adaptor to be ready (back-pressure). Yield to keep
            // SwiftUI responsive during the render.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }

            // Compute eased progress and camera pose for this frame.
            let raw = totalFrames == 1 ? 0.0 : Double(frame) / Double(totalFrames - 1)
            let eased = HeroShotRenderer.easedProgress(raw)
            let pose = HeroShotRenderer.interpolatePose(start: arc.start, end: arc.end, t: Float(eased))
            HeroShotRenderer.applyCameraPose(pose, to: scene.camera)
            HeroShotRenderer.updateSheen(scene.sheen, t: Float(eased))

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

    /// Bundle of references the render loop drives per-frame.
    private struct SceneBundle {
        let renderer: RealityRenderer
        let camera: PerspectiveCamera
        let sheen: ModelEntity
    }

    private func buildScene(config: Config) throws -> SceneBundle {
        let renderer = try RealityRenderer()

        // Near-black background, matching the app's surface palette.
        let bg = UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1.0).cgColor
        renderer.cameraSettings.colorBackground = .color(bg)

        // Root entity.
        let root = Entity()
        renderer.entities.append(root)

        // Card geometry — flat, ~63.5mm wide × 88.9mm tall (real card scale).
        let cardW: Float = 0.0635
        let cardH: Float = 0.0889
        let halfT: Float = 0.0015  // ~1.5mm visual thickness

        // ── Plane orientation math
        //
        // `MeshResource.generatePlane(width:depth:)` lives in the XZ plane:
        // width along X, depth along Z, normal +Y. Image V axis maps top→-Z.
        //
        // Front plane: rotate +π/2 around X. This sends:
        //   normal +Y         → world +Z (faces the default-position camera)
        //   image-top (-Z)    → world +Y (right-side up)
        // Back plane: rotate -π/2 around X. Normal +Y → -Z. (Texture would
        // appear mirrored, but the back uses a solid color in v1 so no UV
        // headache.)

        let frontMesh = MeshResource.generatePlane(width: cardW, depth: cardH)
        var frontMat = UnlitMaterial()
        frontMat.color = .init(tint: .white, texture: .init(config.frontTexture))
        let front = ModelEntity(mesh: frontMesh, materials: [frontMat])
        front.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        front.position = SIMD3<Float>(0, 0, halfT)
        root.addChild(front)

        let backMesh = MeshResource.generatePlane(width: cardW, depth: cardH)
        var backMat = UnlitMaterial()
        if let backTex = config.backTexture {
            backMat.color = .init(tint: .white, texture: .init(backTex))
        } else {
            backMat.color = .init(tint: UIColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1))
        }
        let back = ModelEntity(mesh: backMesh, materials: [backMat])
        back.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        back.position = SIMD3<Float>(0, 0, -halfT)
        root.addChild(back)

        // Foil sheen quad — parented to the FRONT face. Sized larger than
        // the card so the sheen sweeps fully off-edge at the start/end of
        // its travel. Tilted ~20° for the "stripe across the foil" look.
        let sheenWidth: Float  = cardW * 0.45
        let sheenHeight: Float = cardH * 1.6
        let sheenMesh = MeshResource.generatePlane(width: sheenWidth, depth: sheenHeight)
        var sheenMat = UnlitMaterial()
        sheenMat.color = .init(tint: .white, texture: .init(makeSheenTexture()))
        sheenMat.blending = .transparent(opacity: .init(floatLiteral: sheenOpacity(for: config.card)))
        let sheen = ModelEntity(mesh: sheenMesh, materials: [sheenMat])
        // Sheen parented to FRONT, so coordinates are FRONT-local. After
        // the front's +π/2 X rotation, front-local axes → world:
        //   local +X → world +X (card width)
        //   local +Y → world +Z (camera-facing — front normal direction)
        //   local +Z → world -Y (down the card from top to bottom)
        // Sheen quad's own +Y normal aligns with front's +Y after this
        // parenting, so the sheen faces the camera by default. Tilt the
        // stripe ~20° around its local Y (= world +Z) for the swoosh.
        sheen.orientation = simd_quatf(angle: 20 * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
        sheen.position = SIMD3<Float>(0, 0.0005, 0)   // +Y = just in front of the art
        front.addChild(sheen)

        // Camera.
        let camera = PerspectiveCamera()
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        // Initial pose — overwritten per frame.
        let arc = config.arc.keyframes
        HeroShotRenderer.applyCameraPose(arc.start, to: camera)

        // Lighting — UnlitMaterial doesn't need any, but a directional
        // light + IBL is needed if we ever swap to PBR for edges. For now
        // a single ambient probe keeps the scene neutral.
        let lighting = DirectionalLight()
        lighting.light.intensity = 800
        lighting.look(at: .zero, from: [0.2, 0.5, 0.3], relativeTo: nil)
        renderer.entities.append(lighting)

        return SceneBundle(renderer: renderer, camera: camera, sheen: sheen)
    }

    /// Per-treatment sheen intensity. Base = none, foil treatments scale up.
    private func sheenOpacity(for card: Card) -> Float {
        let t = (card.treatment ?? "").lowercased()
        if t.isEmpty || t == "base" || t == "standard" { return 0.0 }
        if t.contains("superfoil") || card.isInspiredInk { return 0.9 }
        if t.contains("blizzard")  { return 0.75 }
        if t.contains("battlefoil") || t.contains("logofoil") { return 0.6 }
        if t.contains("blast") || t.contains("paper") { return 0.35 }
        return 0.5  // other foil treatments
    }

    /// Generate the sheen texture — a soft white gradient stripe with
    /// transparent edges. Cached statically since it's identical for every
    /// hero shot.
    private static let sheenTextureCache: TextureResource? = {
        let w = 256, h = 768
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor.white.withAlphaComponent(0).cgColor,
                UIColor.white.withAlphaComponent(0.85).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: 0, y: 0),
                                  end:   CGPoint(x: CGFloat(w), y: 0),
                                  options: [])
        }
        guard let cg = img.cgImage else { return nil }
        let opts = TextureResource.CreateOptions(semantic: .color)
        return try? TextureResource(image: cg, withName: nil, options: opts)
    }()

    private func makeSheenTexture() -> TextureResource {
        // Fallback to a 1x1 transparent texture if generation failed.
        if let cached = Self.sheenTextureCache { return cached }
        let opts = TextureResource.CreateOptions(semantic: .color)
        let fallback = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        return (try? TextureResource(image: fallback.cgImage!, withName: nil, options: opts))!
    }

    // MARK: - Camera math

    /// Smoothstep: 3t² - 2t³. Matches `easeInOut` shape.
    static func easedProgress(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }

    static func interpolatePose(start: CameraKey, end: CameraKey, t: Float) -> CameraKey {
        CameraKey(
            azimuth:   lerp(start.azimuth,   end.azimuth,   t),
            elevation: lerp(start.elevation, end.elevation, t),
            distance:  lerp(start.distance,  end.distance,  t),
            fovDeg:    lerp(start.fovDeg,    end.fovDeg,    t)
        )
    }

    static func applyCameraPose(_ pose: CameraKey, to camera: PerspectiveCamera) {
        let pos = SIMD3<Float>(
            pose.distance * cos(pose.elevation) * sin(pose.azimuth),
            pose.distance * sin(pose.elevation),
            pose.distance * cos(pose.elevation) * cos(pose.azimuth)
        )
        camera.look(at: .zero, from: pos, upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
        camera.camera.fieldOfViewInDegrees = pose.fovDeg
    }

    /// Translate the sheen quad across the card face: t=0 fully off-left,
    /// t=1 fully off-right. Travel range scales with card width.
    static func updateSheen(_ sheen: ModelEntity, t: Float) {
        let cardW: Float = 0.0635
        // Map [0,1] to [-cardW * 0.9, +cardW * 0.9].
        let x = (t * 2 - 1) * cardW * 0.9
        sheen.position = SIMD3<Float>(x, 0, sheen.position.z)
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
