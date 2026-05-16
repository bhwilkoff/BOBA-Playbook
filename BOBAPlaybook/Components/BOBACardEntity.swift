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

    // MARK: - Material kind

    /// Material shading model for the card faces + edge. Pick `.unlit`
    /// for scenes that have NO lights or IBL (the texture's colors are
    /// rendered as-is — what HouseOfCards uses since its AR-like scene
    /// has no lights). Pick `.physicallyBased` for lit scenes (Hero
    /// Shot's stage with 3-point rig + IBL) — the card responds to
    /// lighting, treatment foils develop real specular sheen via a
    /// roughness texture map, and a clearcoat varnish layer simulates
    /// the card's protective coating.
    ///
    /// PBR REQUIRES a scene with lights and/or an IBL environment.
    /// Without those, PBR materials render dark. UnlitMaterial doesn't
    /// care about lighting at all.
    enum MaterialKind {
        case unlit
        case physicallyBased
    }

    // MARK: - Dimensions

    /// Real BoBA card width in meters (~63.5mm).
    static let width: Float = 0.0635
    /// Real BoBA card height in meters (~88.9mm).
    static let height: Float = 0.0889
    /// Half-thickness in meters. Total VISUAL card thickness is
    /// `2 * halfThickness` = 0.3mm — matches a real trading card.
    /// (House of BoBA's physics collision uses its own thicker value
    /// `Self.cardThick = 3mm` for PhysX solver stability — that's
    /// independent from the visual thickness here.)
    static let halfThickness: Float = 0.00015

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
        /// Material shading model. `.unlit` for scenes without lights
        /// (HouseOfCards); `.physicallyBased` for lit scenes with IBL
        /// (Hero Shot). See the `MaterialKind` enum.
        var material: MaterialKind
        /// The card's `treatment` string (e.g. "Red Battlefoil",
        /// "Superfoil", "Blizzard"). Used by `.physicallyBased` to
        /// generate the right localized roughness map so foil
        /// regions actually reflect light differently from paper
        /// regions. Pass nil for non-foil cards (base set, paper).
        var treatment: String?

        init(frontTexture: TextureResource? = nil,
             backTexture: TextureResource? = nil,
             includeEdge: Bool = true,
             pose: Pose = .upright,
             material: MaterialKind = .unlit,
             treatment: String? = nil) {
            self.frontTexture = frontTexture
            self.backTexture = backTexture
            self.includeEdge = includeEdge
            self.pose = pose
            self.material = material
            self.treatment = treatment
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
        let frontMaterial: any Material = makeFrontMaterial(config: config)
        let front = ModelEntity(mesh: frontMesh, materials: [frontMaterial])
        front.name = "card-front"

        // ── Back plane ──
        let backMesh = MeshResource.generatePlane(width: width, depth: height)
        let backMaterial: any Material = makeBackMaterial(config: config)
        let back = ModelEntity(mesh: backMesh, materials: [backMaterial])
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
            let edgeMaterial: any Material = makeEdgeMaterial(config: config)
            let e = ModelEntity(mesh: edgeMesh, materials: [edgeMaterial])
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

    // MARK: - Material builders

    @MainActor
    private static func makeFrontMaterial(config: Config) -> any Material {
        switch config.material {
        case .unlit:
            var mat = UnlitMaterial()
            if let tex = config.frontTexture {
                mat.color = .init(tint: .white, texture: .init(tex))
            } else {
                mat.color = .init(tint: placeholderFrontColor)
            }
            // Anti-aliased rounded corners. Was `opacityThreshold = 0.5`
            // (alpha-test, binary cutout) — that produces jagged
            // stair-step edges at the rounded corners which read as
            // "pixelated card." `.transparent` blends the alpha properly.
            // Dither risk per feedback_realitykit_alpha_dither is minimal
            // because the texture is ~99% alpha=1 with only a few-pixel
            // transition band at the corners (vs. the failed sheen quad
            // which was partial-alpha everywhere).
            mat.blending = .transparent(opacity: 1.0)
            return mat
        case .physicallyBased:
            return makeFrontPBRMaterial(config: config)
        }
    }

    @MainActor
    private static func makeBackMaterial(config: Config) -> any Material {
        switch config.material {
        case .unlit:
            var mat = UnlitMaterial()
            if let tex = config.backTexture {
                mat.color = .init(tint: .white, texture: .init(tex))
            } else {
                mat.color = .init(tint: placeholderBackColor)
            }
            mat.blending = .transparent(opacity: 1.0)
            return mat
        case .physicallyBased:
            var mat = PhysicallyBasedMaterial()
            if let tex = config.backTexture {
                mat.baseColor = .init(tint: .white, texture: .init(tex))
            } else {
                mat.baseColor = .init(tint: placeholderBackColor)
            }
            // Card back is matte paper — no foil, no metallic, slight
            // clearcoat for the protective varnish layer.
            mat.metallic = 0.0
            mat.roughness = 0.55
            mat.clearcoat = 0.20
            mat.clearcoatRoughness = 0.15
            return mat
        }
    }

    @MainActor
    private static func makeEdgeMaterial(config: Config) -> any Material {
        switch config.material {
        case .unlit:
            var mat = UnlitMaterial()
            mat.color = .init(tint: edgeColor)
            return mat
        case .physicallyBased:
            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: edgeColor)
            // Card-stock paper edges — no specular, fairly rough.
            mat.metallic = 0.0
            mat.roughness = 0.65
            return mat
        }
    }

    /// PBR front-face material. The killer feature here is the
    /// treatment-keyed roughness map: foil regions render at very low
    /// roughness (specular sheen) while paper regions are matte. As
    /// the camera moves, the foil pattern visibly catches the lights.
    @MainActor
    private static func makeFrontPBRMaterial(config: Config) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        if let tex = config.frontTexture {
            mat.baseColor = .init(tint: .white, texture: .init(tex))
        } else {
            mat.baseColor = .init(tint: placeholderFrontColor)
        }

        // Treatment determines roughness behavior.
        let kind = foilKind(for: config.treatment)
        if let roughnessTex = roughnessTexture(for: kind) {
            // Foil cards: localized low-roughness regions where the
            // foil sits, high-roughness elsewhere. Drives real
            // specular sheen as the card rotates against the lights.
            mat.roughness = .init(scale: 1.0, texture: .init(roughnessTex))
            mat.metallic = .init(floatLiteral: kind.metallicScale)
        } else {
            // Base / paper cards: uniform matte gloss.
            mat.roughness = 0.40
            mat.metallic = 0.0
        }

        // Clearcoat varnish — the protective layer printed cards have
        // that gives them their "fresh from the pack" sheen. Applied
        // uniformly above the baseColor + roughness/metallic stack.
        mat.clearcoat = 0.30
        mat.clearcoatRoughness = 0.10
        return mat
    }

    // MARK: - Treatment-keyed roughness textures

    /// Coarse-grained category for the card's treatment, used to pick
    /// the right procedural roughness pattern.
    private enum FoilKind {
        case none           // base set, paper — no foil, scalar roughness
        case battlefoil     // colored foils (Red, Blue, Silver, etc.) — diagonal stripes
        case superfoil      // rainbow / holographic — noise flakes
        case blizzard       // icy crackle — voronoi
        case inspiredInk    // serialized vertical bands
        case logofoil       // repeating logo — denser noise
        case blast          // paper-grain — mild noise

        var metallicScale: Float {
            switch self {
            case .none:        return 0.0
            case .battlefoil:  return 0.55
            case .superfoil:   return 0.65
            case .blizzard:    return 0.45
            case .inspiredInk: return 0.60
            case .logofoil:    return 0.45
            case .blast:       return 0.10
            }
        }
    }

    private static func foilKind(for treatment: String?) -> FoilKind {
        guard let t = treatment?.lowercased(), !t.isEmpty else { return .none }
        if t == "base" || t == "base set" || t == "standard" { return .none }
        if t.contains("battlefoil") || t.contains("logofoil") {
            // Logofoils get their own pattern despite the similar name —
            // they print a repeating logo over the art, not stripes.
            return t.contains("logofoil") ? .logofoil : .battlefoil
        }
        if t.contains("superfoil") { return .superfoil }
        if t.contains("blizzard")  { return .blizzard }
        if t.contains("inspired") || t.contains("ink") { return .inspiredInk }
        if t.contains("blast") || t.contains("paper") { return .blast }
        // Unknown treatment — treat as a generic foil with mild stripes
        // (better than scalar-matte for unrecognized foil names).
        return .battlefoil
    }

    /// Cache for procedural roughness textures, keyed by `FoilKind`.
    /// One pattern per kind; computed lazily on first use. Static so
    /// every card of the same treatment shares one texture.
    @MainActor
    private static var roughnessTextureCache: [String: TextureResource] = [:]

    @MainActor
    private static func roughnessTexture(for kind: FoilKind) -> TextureResource? {
        if kind == .none { return nil }
        let key = "\(kind)"
        if let cached = roughnessTextureCache[key] { return cached }
        guard let img = makeRoughnessImage(for: kind),
              let cg = img.cgImage,
              let tex = try? TextureResource(
                  image: cg,
                  withName: "boba-roughness-\(key)",
                  options: TextureResource.CreateOptions(semantic: .raw))
        else { return nil }
        roughnessTextureCache[key] = tex
        return tex
    }

    /// Generate the per-treatment roughness pattern as a UIImage. In
    /// roughness textures, BLACK (0) = mirror-smooth, WHITE (1) =
    /// fully diffuse. We paint the FOIL regions black-ish (~0.05) and
    /// the paper regions grey-ish (~0.6).
    private static func makeRoughnessImage(for kind: FoilKind) -> UIImage? {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Paper baseline — grey ~0.6 roughness.
            cg.setFillColor(UIColor(white: 0.60, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            switch kind {
            case .none:
                break  // shouldn't happen — kind == .none returns nil above

            case .battlefoil:
                // Diagonal stripes at 30°. Foil bands are nearly mirror
                // (white = 0.05 means GLOSSY in shader terms; here we
                // draw DARK to indicate low roughness).
                cg.saveGState()
                cg.translateBy(x: size.width / 2, y: size.height / 2)
                cg.rotate(by: CGFloat.pi / 6)
                cg.translateBy(x: -size.width, y: -size.height)
                cg.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
                let stripeW: CGFloat = 60
                let gap: CGFloat = 90
                var x: CGFloat = 0
                while x < size.width * 2 {
                    cg.fill(CGRect(x: x, y: 0, width: stripeW, height: size.height * 2))
                    x += stripeW + gap
                }
                cg.restoreGState()

            case .superfoil:
                // Holographic flake field — small dark spots
                // (low-roughness "flakes") scattered over the paper.
                cg.setFillColor(UIColor(white: 0.10, alpha: 1).cgColor)
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<900 {
                    let x = CGFloat.random(in: 0..<size.width, using: &rng)
                    let y = CGFloat.random(in: 0..<size.height, using: &rng)
                    let r = CGFloat.random(in: 3...8, using: &rng)
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }

            case .blizzard:
                // Voronoi-ish crackle — scatter "ice fracture" line
                // segments. Real voronoi would be more work; approximate
                // with random thin dark lines radiating from random seeds.
                cg.setStrokeColor(UIColor(white: 0.12, alpha: 1).cgColor)
                cg.setLineWidth(2.5)
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<60 {
                    let cx = CGFloat.random(in: 0..<size.width, using: &rng)
                    let cy = CGFloat.random(in: 0..<size.height, using: &rng)
                    let spokes = Int.random(in: 3...6, using: &rng)
                    for i in 0..<spokes {
                        let angle = CGFloat(i) * (2 * .pi / CGFloat(spokes))
                            + CGFloat.random(in: -0.4...0.4, using: &rng)
                        let len = CGFloat.random(in: 30...90, using: &rng)
                        cg.move(to: CGPoint(x: cx, y: cy))
                        cg.addLine(to: CGPoint(x: cx + cos(angle) * len, y: cy + sin(angle) * len))
                    }
                }
                cg.strokePath()

            case .inspiredInk:
                // Vertical iridescent bands — denser than Battlefoil,
                // narrower stripes.
                cg.setFillColor(UIColor(white: 0.10, alpha: 1).cgColor)
                let stripeW: CGFloat = 18
                let gap: CGFloat = 22
                var x: CGFloat = 0
                while x < size.width {
                    cg.fill(CGRect(x: x, y: 0, width: stripeW, height: size.height))
                    x += stripeW + gap
                }

            case .logofoil:
                // Repeating round dots — surrogate for a small repeating
                // BoBA logo pattern across the surface.
                cg.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
                let spacing: CGFloat = 70
                let r: CGFloat = 18
                var y: CGFloat = spacing / 2
                while y < size.height {
                    var x: CGFloat = spacing / 2
                    while x < size.width {
                        cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                        x += spacing
                    }
                    y += spacing
                }

            case .blast:
                // Paper-grain — fine random speckle. Slightly less
                // contrast than the other foil patterns.
                cg.setFillColor(UIColor(white: 0.40, alpha: 1).cgColor)
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<3500 {
                    let x = CGFloat.random(in: 0..<size.width, using: &rng)
                    let y = CGFloat.random(in: 0..<size.height, using: &rng)
                    cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
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
