import Foundation
import RealityKit
import UIKit

/// Canonical 3D BoBA card entity — the one shared model used wherever
/// the app shows a card in 3D. Used by House of BoBA (interactive
/// physics scene), Hero Shot (offline-rendered sizzle reel), and any
/// future 3D-card surface.
///
/// ## Why a shared helper
///
/// Each new 3D-card surface would otherwise reinvent the same shape:
/// two textured planes, rounded-corner alpha mask, off-white edge,
/// real card dimensions. Drift between surfaces is a footgun — and
/// the wrong choices (element-tinted edges, mismatched corner radius,
/// inverted back textures) all happened to Hero Shot in v2.225–v2.228
/// before this consolidation. One helper, one set of decisions.
///
/// ## What it produces
///
/// An `Entity` named `card-pivot` with three (or two, optionally) named
/// children:
///
/// ```
/// pivot                          [Entity, "card-pivot"]
///   ├── card-front               [ModelEntity, art texture or placeholder]
///   ├── card-back                [ModelEntity, card-back texture or fallback]
///   └── card-edge                [ModelEntity, off-white card-stock edge]
///                                (optional — Config.includeEdge)
/// ```
///
/// Names are stable — callers can `findEntity(named:)` to swap textures
/// (`applyFrontTexture(_:to:)` / `applyBackTexture(_:to:)`) or to attach
/// per-card components.
///
/// ## Pose
///
/// `.upright` (default) — front normal +Z, image-top +Y, card width
/// along X, height along Y, thickness along Z. The canonical pose for
/// any scene that wants a card facing a camera at +Z.
///
/// `.flat` — front normal +Y, image-top -Z (pivot-local), thin axis
/// along Y. The "lying on a table" pose. Used by House of BoBA so its
/// existing spawn-rotation chain + physics collision shape continue to
/// work unchanged.
///
/// Both poses produce visually equivalent cards (same dimensions,
/// rounded corners, off-white edge); only the local-frame orientation
/// differs.
///
/// ## Texture prep
///
/// Source images must be clipped to a rounded silhouette via
/// `BOBACardEntity.roundedCorners(_:)` before they become
/// `TextureResource`s — `MeshResource.generatePlane(cornerRadius:)`'s
/// rounding parameter is silently ignored on iOS 17/18/26, so the
/// silhouette has to live in the texture's alpha channel.
///
/// House of BoBA pre-rotates the FRONT image 180° (`applyRotation: true`)
/// to compensate for its entity-rotation chain. Hero Shot doesn't need
/// rotation. The helper exposes both via a parameter.
/// `nonisolated` because most call sites (texture preprocessing,
/// constants) run from background `Task.detached` contexts. The
/// individual entity-mutating methods (`build`, `applyFrontTexture`,
/// `applyBackTexture`) opt back in to `@MainActor` since RealityKit
/// entity components are main-actor isolated.
nonisolated enum BOBACardEntity {

    // MARK: - Pose

    enum Pose {
        /// Canonical: front normal +Z, image-top +Y. Default for any
        /// camera at +Z (most scenes, Hero Shot, future 3D-card views).
        case upright
        /// Lying flat with front facing +Y. Pivot-local image-top at
        /// -Z. Used by House of BoBA so its spawn-rotation chain and
        /// collision shape stay unchanged.
        case flat
    }

    // MARK: - Dimensions

    /// Real BoBA card width in meters (~63.5mm).
    static let width: Float = 0.0635
    /// Real BoBA card height in meters (~88.9mm).
    static let height: Float = 0.0889
    /// Half-thickness in meters. Total visual card thickness is
    /// `2 * halfThickness` ≈ 3mm. Picked thick enough for physics
    /// solver stability AND visible edge profile at viewing angles.
    static let halfThickness: Float = 0.0015

    /// Corner-radius ratio applied via texture-alpha clipping.
    /// 0.045 of the shorter card dimension.
    static let cornerRadiusRatio: Float = 0.045

    /// Corner radius in meters.
    static var cornerRadius: Float { min(width, height) * cornerRadiusRatio }

    // MARK: - Materials

    /// Matte off-white card-stock edge. Real trading cards have
    /// cream-paper edges; element tints (FIRE orange, etc.) belong in
    /// the environment, not on the card. Use `Self.edgeColor`
    /// everywhere a card edge needs a color.
    static let edgeColor = UIColor(white: 0.92, alpha: 1)

    /// Neutral dark color shown as a placeholder front material when
    /// no texture is supplied. Matches HouseOfCardsView's pre-load
    /// placeholder so async art-loading flows can build the entity
    /// first and apply the texture when it arrives.
    static let placeholderFrontColor = UIColor(white: 0.08, alpha: 1)

    /// Fallback solid color used for the back when no card-back PNG
    /// texture is supplied. Matches HouseOfCardsView's existing
    /// fallback red palette.
    static let placeholderBackColor = UIColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1)

    // MARK: - Config

    struct Config {
        /// Optional front art texture (the card image). If nil, a
        /// dark placeholder is used; apply later via
        /// `BOBACardEntity.applyFrontTexture(_:to:)`.
        var frontTexture: TextureResource?
        /// Optional back texture (typically the bundled card-back.png).
        var backTexture: TextureResource?
        /// Include the cream off-white edge box between front and
        /// back planes. Provides visible card thickness at angles.
        /// Defaults to true; pass false for pure-art applications
        /// (raw thumbnails, etc.) that don't want the edge.
        var includeEdge: Bool
        /// Pose to build the card in. See the `Pose` enum.
        var pose: Pose

        init(frontTexture: TextureResource? = nil,
             backTexture: TextureResource? = nil,
             includeEdge: Bool = true,
             pose: Pose = .upright) {
            self.frontTexture = frontTexture
            self.backTexture = backTexture
            self.includeEdge = includeEdge
            self.pose = pose
        }
    }

    // MARK: - Build

    /// Build a card entity. Returns a pivot `Entity` with named
    /// children (`card-front`, `card-back`, optional `card-edge`).
    /// Callers add their own components on top (collision, physics
    /// body, gestures) — this helper produces VISUAL geometry only.
    @MainActor
    static func build(_ config: Config = Config()) -> Entity {
        let pivot = Entity()
        pivot.name = "card-pivot"

        let r = cornerRadius

        // ── Front plane ──
        let frontMesh = MeshResource.generatePlane(width: width, depth: height)
        var frontMat = UnlitMaterial()
        if let tex = config.frontTexture {
            frontMat.color = .init(tint: .white, texture: .init(tex))
        } else {
            frontMat.color = .init(tint: placeholderFrontColor)
        }
        let front = ModelEntity(mesh: frontMesh, materials: [frontMat])
        front.name = "card-front"

        // ── Back plane ──
        let backMesh = MeshResource.generatePlane(width: width, depth: height)
        var backMat = UnlitMaterial()
        if let tex = config.backTexture {
            backMat.color = .init(tint: .white, texture: .init(tex))
        } else {
            backMat.color = .init(tint: placeholderBackColor)
        }
        let back = ModelEntity(mesh: backMesh, materials: [backMat])
        back.name = "card-back"

        // ── Edge box ──
        // X/Y dimensions inset by 2*cornerRadius so the box's corners
        // sit inside the rounded plane silhouette (no corner stickout
        // through the transparent quarter-circles — the v2.160 failure
        // mode in HouseOfCardsView). Z thickness slightly less than
        // 2*halfThickness so the box ±Z faces hide behind the planes
        // (no z-fighting). Mesh shape is pose-specific because the
        // "thin axis" rotates with the card.
        var edge: ModelEntity? = nil
        if config.includeEdge {
            let edgeMesh: MeshResource
            switch config.pose {
            case .upright:
                // Thin axis = Z (matches plane normals +Z / -Z).
                edgeMesh = MeshResource.generateBox(
                    size: SIMD3<Float>(
                        width - 2 * r,
                        height - 2 * r,
                        halfThickness * 1.5
                    )
                )
            case .flat:
                // Thin axis = Y (matches plane normals +Y / -Y).
                edgeMesh = MeshResource.generateBox(
                    size: SIMD3<Float>(
                        width - 2 * r,
                        halfThickness * 1.5,
                        height - 2 * r
                    )
                )
            }
            var edgeMat = UnlitMaterial()
            edgeMat.color = .init(tint: edgeColor)
            let e = ModelEntity(mesh: edgeMesh, materials: [edgeMat])
            e.name = "card-edge"
            e.position = .zero
            edge = e
        }

        // ── Apply pose-specific plane orientations + positions ──
        switch config.pose {
        case .upright:
            // MeshResource.generatePlane lives in the XZ plane (width
            // X, depth Z), normal +Y, image-V mapped top → -Z.
            //
            // Front +π/2 around X: normal +Y → +Z (camera-facing),
            // image-top -Z → +Y (right-side up).
            //
            // Back -π/2 X then π Y (Swift compose order: Y applied
            // first to local axes, then X). Sends normal +Y → -Z AND
            // image-top -Z → +Y. The `* R_y(π)` term is the critical
            // bit that prevents the image-V from landing upside-down.
            front.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            front.position = SIMD3<Float>(0, 0, halfThickness)
            back.orientation =
                simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
            back.position = SIMD3<Float>(0, 0, -halfThickness)

        case .flat:
            // House of BoBA's "lying flat" native pose. Front has no
            // local rotation (normal +Y, image-top at pivot-local -Z).
            // Back has R_x(π) (normal -Y, image-top at +Z).
            //
            // Note: in this pose, source image-V lands at world -Y
            // after House of BoBA's standUp + faceCamera entity-
            // rotation chain — i.e., upside-down. HouseOfCards
            // compensates via `roundedCorners(_:applyRotation: true)`
            // on the front image only. This helper preserves that
            // behavior for backward compat.
            front.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
            front.position = SIMD3<Float>(0, halfThickness, 0)
            back.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
            back.position = SIMD3<Float>(0, -halfThickness, 0)
        }

        pivot.addChild(front)
        pivot.addChild(back)
        if let edge { pivot.addChild(edge) }

        return pivot
    }

    // MARK: - Mutating an existing card

    /// Replace the front-face texture on a built card.
    @MainActor
    static func applyFrontTexture(_ texture: TextureResource, to card: Entity) {
        guard let front = card.findEntity(named: "card-front") as? ModelEntity,
              var model = front.components[ModelComponent.self] else { return }
        var mat = UnlitMaterial()
        mat.color = .init(tint: .white, texture: .init(texture))
        model.materials = [mat]
        front.components.set(model)
    }

    /// Replace the back-face texture on a built card.
    @MainActor
    static func applyBackTexture(_ texture: TextureResource, to card: Entity) {
        guard let back = card.findEntity(named: "card-back") as? ModelEntity,
              var model = back.components[ModelComponent.self] else { return }
        var mat = UnlitMaterial()
        mat.color = .init(tint: .white, texture: .init(texture))
        model.materials = [mat]
        back.components.set(model)
    }

    // MARK: - Texture prep

    /// Clip a UIImage to rounded corners. Output's alpha channel is
    /// transparent outside the rounded rect, opaque inside.
    /// Generate a `TextureResource` from the result; the corresponding
    /// card plane will then display with the rounded silhouette.
    ///
    /// `applyRotation` 180°-pre-rotates the image. House of BoBA's
    /// front images need this (`true`) to compensate for its entity-
    /// rotation chain that lands image-V upside-down. Hero Shot and
    /// any `.upright`-pose use does NOT need it (`false`, the default).
    static func roundedCorners(_ image: UIImage, applyRotation: Bool = false) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let radius = min(size.width, size.height) * CGFloat(cornerRadiusRatio)
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            if applyRotation {
                cg.translateBy(x: size.width, y: size.height)
                cg.scaleBy(x: -1, y: -1)
            }
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            image.draw(in: rect)
        }
    }
}
