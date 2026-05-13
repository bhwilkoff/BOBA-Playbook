import SwiftUI
import RealityKit
import ARKit
import Combine
import simd

// MARK: - HouseOfCardsView
//
// Easter-egg physics game launched from the Profile sheet
// (square.stack.3d.up icon at .topBarLeading). Built on
// RealityKit per the WWDC25 "soft-deprecation" of SceneKit —
// see memory: project_house_of_cards_spec, decision recorded
// 2026-05-12.
//
// Goal: build a tower of BoBA cards at least 10 levels high.
// Score = number of stable levels reached before collapse.
// Persist high score in @AppStorage.
//
// Card pool: catalog cards with power > 135 by default. Toggle
// "Use my collection" pulls from the user's owned cards (also
// power > 135). Card front = R2 CDN art, back = bundled
// card-back.png (Resources/card-back.png).
//
// Single-file per [[feedback-xcode-synchronized-groups]] — all
// physics setup, gesture handling, and SwiftUI chrome live here.

struct HouseOfCardsView: View {

    // MARK: Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(CardStore.self) private var cardStore
    @Environment(CollectionStore.self) private var collection
    @Environment(AuthManager.self) private var auth

    // MARK: Persisted state
    @AppStorage("bp_houseOfCardsHighScore_v1") private var highScore: Int = 0
    @AppStorage("bp_houseOfCardsUseCollection_v1") private var useCollection: Bool = false

    // MARK: Scene state
    @State private var session = HouseOfCardsSession()
    @State private var showingHelp = false

    var body: some View {
        ZStack {
            // RealityKit scene — fills the whole canvas
            HouseOfCardsRealityView(session: session, cardPool: cardPool)
                .ignoresSafeArea()

            // Foreground UI overlay
            VStack {
                topBar
                Spacer()
                bottomDeckStrip
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .sheet(isPresented: $showingHelp) { helpSheet }
        .onChange(of: session.currentLevels) { _, newValue in
            if newValue > highScore { highScore = newValue }
        }
        .onAppear {
            // Refresh pool when user toggles collection source.
            session.reseedDeck(from: cardPool)
        }
        .onChange(of: useCollection) { _, _ in
            session.reseedDeck(from: cardPool)
        }
    }

    // MARK: Top bar — Close · score · help
    private var topBar: some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("HOUSE OF CARDS")
                    .font(Design.Fonts.display(14))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 14) {
                    levelPill(label: "LEVEL",  value: session.currentLevels)
                    levelPill(label: "BEST",   value: highScore, accent: true)
                }
            }

            Spacer()

            Menu {
                Toggle("Use my collection",  isOn: $useCollection)
                    .disabled(!auth.isAuthenticated || ownedHighPowerCount == 0)
                Button("Reset Tower",  systemImage: "arrow.counterclockwise") {
                    session.resetScene()
                }
                Button("How to Play",  systemImage: "questionmark.circle") {
                    showingHelp = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    @ViewBuilder
    private func levelPill(label: String, value: Int, accent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Design.Fonts.mono(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("\(value)")
                .font(Design.Fonts.mono(14, weight: .bold))
                .foregroundStyle(accent ? Design.Colors.bobaOrange : .white)
        }
    }

    // MARK: Bottom deck strip — upcoming cards
    private var bottomDeckStrip: some View {
        VStack(spacing: 8) {
            Text("TAP A CARD · DRAG TO PLACE · RELEASE TO DROP")
                .font(Design.Fonts.mono(9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(session.deck.prefix(8).enumerated()), id: \.offset) { idx, card in
                        DeckStripCard(
                            card: card,
                            isNext: idx == 0,
                            onTap: {
                                // Pop the card from the deck and signal
                                // the coordinator to spawn it. Scene
                                // gestures handle placement from there.
                                session.pendingSpawn = card
                                if !session.deck.isEmpty {
                                    session.deck.removeFirst()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 100)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Card pool resolution
    private var cardPool: [Card] {
        if useCollection, auth.isAuthenticated, ownedHighPowerCount > 0 {
            let ownedIds = Set(collection.userCards.map { $0.cardNumber })
            return cardStore.displayCards.filter {
                ownedIds.contains($0.cardNumber)
                    && ($0.power ?? 0) > 135
                    && ($0.imageFile?.isEmpty == false)
            }
        }
        return cardStore.displayCards.filter {
            ($0.power ?? 0) > 135 && ($0.imageFile?.isEmpty == false)
        }
    }

    private var ownedHighPowerCount: Int {
        let ownedIds = Set(collection.userCards.map { $0.cardNumber })
        return cardStore.displayCards.reduce(into: 0) { acc, c in
            if ownedIds.contains(c.cardNumber)
                && (c.power ?? 0) > 135
                && (c.imageFile?.isEmpty == false) {
                acc += 1
            }
        }
    }

    // MARK: Help sheet
    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("BUILD A TOWER")
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(.white)
                    Text("Place cards onto the table or onto other cards. Lean them against each other to climb levels. The taller and more stable the tower, the higher the score.")
                        .font(Design.Fonts.mono(15))
                        .foregroundStyle(.white.opacity(0.85))
                    Divider().overlay(.white.opacity(0.15))
                    helpRow("Place",       "Tap the leftmost card in the strip — it appears in the scene. Drag with one finger to position, release to drop.")
                    helpRow("Look around", "Two-finger drag to orbit the camera. Pinch to zoom in or out.")
                    helpRow("Lean",        "Cards have friction. Two cards leaning against each other count as one level.")
                    helpRow("Score",       "Each stable layer adds to your tower height. 10+ is the dream.")
                    helpRow("Switch deck", "Toggle 'Use my collection' to build with cards you own (power > 135).")
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingHelp = false }
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func helpRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Design.Fonts.mono(12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Design.Colors.bobaCyan)
            Text(detail)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - DeckStripCard
//
// Compact card thumbnail in the bottom strip. The leftmost
// ("next") card is tappable. Tapping pulls the card off the
// deck and signals the coordinator to spawn it in the scene
// as a held kinematic entity. Drag-from-strip was abandoned
// after the v2.151–v2.154 attempts — SwiftUI→UIKit gesture
// coupling across the strip→scene boundary was too brittle.
// Tap is reliable; the scene's own gestures handle placement.
private struct DeckStripCard: View {
    let card: Card
    let isNext: Bool
    var onTap: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardImageView(card: card, size: .thumb)
                .aspectRatio(0.714, contentMode: .fit)
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isNext ? Design.Colors.bobaOrange : .white.opacity(0.2),
                                lineWidth: isNext ? 2 : 0.5)
                )
                .shadow(color: isNext ? Design.Colors.bobaOrange.opacity(0.4) : .clear,
                        radius: isNext ? 6 : 0)
                .scaleEffect(isNext ? 1.0 : 0.92)
                .opacity(isNext ? 1.0 : 0.7)
            if let power = card.power {
                Text("\(power)")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isNext else { return }
            onTap()
        }
    }
}

// MARK: - HouseOfCardsRealityView
//
// Wraps ARView (RealityKit's UIKit canvas, used here in
// .nonAR camera mode — pure virtual scene, no camera passthrough).
// RealityView is iOS 18+ native-SwiftUI; ARView is the production-
// tested path that's stable on iOS 17+ which is our floor.
// All scene construction (tabletop / lights / camera / IBL),
// card spawning, drag handling, and settle detection live in
// the Coordinator.

private struct HouseOfCardsRealityView: UIViewRepresentable {
    let session: HouseOfCardsSession
    let cardPool: [Card]

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableCameraGrain)
        view.environment.background = .color(UIColor(red: 0.05, green: 0.04, blue: 0.04, alpha: 1))
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.consumeSessionState()
    }
}

// MARK: - Coordinator
//
// Owns the RealityKit scene, the card entity registry, the
// per-frame physics tick subscription, and the drag-to-place
// state machine. The Session is the source of truth for
// inputs (pendingSpawn, dragSpawnCard, dragScreenPoint,
// resetGeneration); the Coordinator is the source of truth
// for outputs (currentLevels, settled-card cache).

@MainActor
private final class HouseOfCardsCoordinator: NSObject {
    let session: HouseOfCardsSession
    private weak var arView: ARView?
    private var anchor: AnchorEntity?
    private var camera: PerspectiveCamera?
    private var tabletop: ModelEntity?
    private var sceneSubscription: Cancellable?

    /// All dynamic card entities currently in the world.
    private var dynamicCards: [CardEntity] = []
    /// The kinematic card currently being placed by the user.
    /// Replaces the old "dragCard" — same role, different
    /// interaction model (spawned by tap, moved by scene-pan).
    private var heldCard: CardEntity?
    private var lastResetGeneration: Int = -1

    /// Card-back texture is loaded once and reused across
    /// every card; card-front texture is loaded async per
    /// card from the R2 CDN.
    private var backTexture: TextureResource?
    private var edgeMaterial: PhysicallyBasedMaterial?

    /// Box mesh template — shared across all cards (RealityKit
    /// caches the mesh resource, so this is a real perf win).
    private static let cardWidth:  Float = 0.0635
    private static let cardThick:  Float = 0.0004
    private static let cardHeight: Float = 0.0889
    private static let cornerR:    Float = 0.0025

    /// Camera framing: as the tower grows, the camera lifts
    /// to keep the top in view.
    private var targetMaxY: Float = 0.0

    /// Spherical-coordinate camera state (orbit around the table).
    /// azimuth: rotation around world Y (horizontal pan)
    /// elevation: angle above the horizontal plane (vertical pan)
    /// distance: radial distance from the cameraTarget
    private var camAzimuth:   Float = 0
    private var camElevation: Float = 0.55   // ~31° above horizon
    private var camDistance:  Float = 0.65
    private let cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0.06, 0)

    /// Gesture recognizers — retained so we can remove them
    /// cleanly if the view detaches.
    private weak var cardPanGesture:    UILongPressGestureRecognizer?
    private weak var cameraPanGesture:  UIPanGestureRecognizer?
    private weak var cameraPinchGesture: UIPinchGestureRecognizer?

    init(session: HouseOfCardsSession) {
        self.session = session
        super.init()
    }

    // MARK: Scene attach
    func attach(to view: ARView) {
        self.arView = view

        // World anchor at origin.
        let root = AnchorEntity(world: .zero)
        view.scene.addAnchor(root)
        self.anchor = root

        buildLighting(on: root)
        buildCamera(on: root, view: view)
        buildTabletop(on: root)
        loadCardBack()
        installGestures(on: view)

        // Per-frame physics + scoring tick.
        sceneSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(deltaTime: Float(event.deltaTime))
        }
    }

    // MARK: Gestures
    //
    // Three gestures live on the ARView:
    //   - cameraPan  (2-finger)  → orbit camera (azimuth + elevation)
    //   - cameraPinch            → zoom (radial distance)
    //   - cardPan    (1-finger)  → move the held kinematic card
    //
    // UILongPressGestureRecognizer with minimumPressDuration=0 is
    // used for cardPan because it fires .began on touch-down
    // (UIPanGestureRecognizer waits for a movement threshold,
    // which felt sluggish for "tap-and-drag-immediately").
    private func installGestures(on view: ARView) {
        let cameraPan = UIPanGestureRecognizer(target: self, action: #selector(handleCameraPan(_:)))
        cameraPan.minimumNumberOfTouches = 2
        cameraPan.maximumNumberOfTouches = 2
        cameraPan.delegate = self
        view.addGestureRecognizer(cameraPan)
        self.cameraPanGesture = cameraPan

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        self.cameraPinchGesture = pinch

        let cardPan = UILongPressGestureRecognizer(target: self, action: #selector(handleCardPan(_:)))
        cardPan.minimumPressDuration = 0
        cardPan.numberOfTouchesRequired = 1
        cardPan.allowableMovement = .greatestFiniteMagnitude
        cardPan.delegate = self
        view.addGestureRecognizer(cardPan)
        self.cardPanGesture = cardPan
    }

    @objc private func handleCameraPan(_ g: UIPanGestureRecognizer) {
        guard let view = g.view else { return }
        let delta = g.translation(in: view)
        // 1 pixel ≈ 0.005 rad of orbit — feels close to native
        // (Maps / Photos zoomed-out views).
        camAzimuth   -= Float(delta.x) * 0.005
        camElevation  = max(0.05, min(1.45, camElevation - Float(delta.y) * 0.005))
        g.setTranslation(.zero, in: view)
        updateCameraTransform()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard g.scale > 0 else { return }
        camDistance = max(0.25, min(2.5, camDistance / Float(g.scale)))
        g.scale = 1.0
        updateCameraTransform()
    }

    @objc private func handleCardPan(_ g: UILongPressGestureRecognizer) {
        guard let view = arView else { return }
        let point = g.location(in: view)

        switch g.state {
        case .began, .changed:
            // Only move if we have a held card. If the user
            // taps without a card held, do nothing — they need
            // to first tap a card in the strip.
            guard let held = heldCard else { return }
            let y = held.entity.position.y
            if let world = view.project(point, ontoPlaneAt: y) {
                held.entity.position = world
            }
        case .ended, .cancelled, .failed:
            // Commit the held card to dynamic so gravity engages.
            if heldCard != nil {
                commitHeldCard()
            }
        default:
            break
        }
    }

    private func updateCameraTransform() {
        guard let cam = camera else { return }
        let x = cameraTarget.x + camDistance * cos(camElevation) * sin(camAzimuth)
        let y = cameraTarget.y + camDistance * sin(camElevation)
        let z = cameraTarget.z + camDistance * cos(camElevation) * cos(camAzimuth)
        let pos = SIMD3<Float>(x, y, z)
        cam.position = pos
        cam.look(at: cameraTarget, from: pos, relativeTo: nil)
    }

    // MARK: Per-frame
    private func tick(deltaTime _: Float) {
        // Settle detection + score update. The held card's
        // movement is handled by handleCardPan via the gesture
        // recognizer — no per-frame drag follow needed.
        var maxSettledY: Float = 0
        var settledCount = 0
        for c in dynamicCards {
            guard let motion = c.entity.components[PhysicsMotionComponent.self] else { continue }
            let lv = simd_length(motion.linearVelocity)
            let av = simd_length(motion.angularVelocity)
            if lv < 0.005 && av < 0.01 {
                c.settledFrames += 1
                if c.settledFrames > 30 { c.isSettled = true }
            } else {
                c.settledFrames = 0
                c.isSettled = false
            }
            if c.isSettled {
                settledCount += 1
                maxSettledY = max(maxSettledY, c.entity.transform.translation.y)
            }
        }

        // Levels: settled top-of-pile divided by an empirical
        // lean-height per level. Cards leaning at ~30° contribute
        // about half their long axis to height.
        let perLevel: Float = 0.045
        let levels = settledCount > 0 ? Int((maxSettledY / perLevel).rounded(.down)) : 0
        if levels != session.currentLevels {
            session.currentLevels = max(0, levels)
        }

        // Track tower height (used for next-card spawn altitude).
        targetMaxY = maxSettledY
    }

    // MARK: Input handling — consumed each updateUIView
    func consumeSessionState() {
        // Reset signal — rebuild scene from scratch.
        if session.resetGeneration != lastResetGeneration {
            lastResetGeneration = session.resetGeneration
            clearAllCards()
        }

        // Tap-spawn: user tapped a card in the deck strip.
        // Spawn a kinematic card at the table center. The user
        // then drags it into position with the 1-finger long-
        // press on the ARView; release commits to dynamic.
        if let card = session.pendingSpawn {
            session.pendingSpawn = nil
            spawnHeldCard(card)
        }
    }

    // MARK: Lighting
    //
    // Brighter than v2.151 — the table was unreadable in the
    // first version. PBR materials need significant light to
    // read as more than flat dark blobs.
    private func buildLighting(on root: AnchorEntity) {
        // Key directional — warm white, with shadow. Aims down
        // from front-right of the camera at ~60° elevation.
        let key = DirectionalLight()
        key.light.intensity   = 6000
        key.light.color       = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
        key.shadow            = DirectionalLightComponent.Shadow(
            maximumDistance: 2.0,
            depthBias: 1.0
        )
        let rot1 = simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0))
        let rot2 = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0))
        key.orientation = rot1 * rot2
        key.position = SIMD3<Float>(0.4, 0.8, 0.5)
        root.addChild(key)

        // Fill — opposite side, cool tint, no shadow.
        let fill = DirectionalLight()
        fill.light.intensity = 2000
        fill.light.color     = UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1)
        fill.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(-1, 0.3, 0))
        fill.position = SIMD3<Float>(-0.3, 0.6, -0.2)
        root.addChild(fill)

        // Top down ambient via a fourth directional. Approximates
        // image-based lighting without bundling an HDR — just
        // enough to keep cards readable when shadowed.
        let ambient = DirectionalLight()
        ambient.light.intensity = 1500
        ambient.light.color     = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1)
        ambient.orientation     = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        root.addChild(ambient)

        // Warm rim from behind — silhouettes card edges when the
        // tower grows.
        let rim = DirectionalLight()
        rim.light.intensity = 800
        rim.light.color     = UIColor(red: 1, green: 0.85, blue: 0.7, alpha: 1)
        rim.orientation     = simd_quatf(angle: -.pi / 5, axis: SIMD3<Float>(1, 0, 0))
        root.addChild(rim)
    }

    // MARK: Camera
    //
    // The camera lives on spherical coordinates around the
    // tabletop center. User gestures (handleCameraPan,
    // handlePinch) mutate the spherical state; updateCameraTransform
    // converts (azimuth, elevation, distance) → world position and
    // re-aims the camera at the target.
    private func buildCamera(on root: AnchorEntity, view: ARView) {
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 48
        cam.camera.near = 0.01
        cam.camera.far  = 10.0
        root.addChild(cam)
        self.camera = cam
        // Initial transform from default orbit state.
        updateCameraTransform()
    }

    // MARK: Tabletop
    //
    // v2.155: visibly textured warm wood-tone surface with a
    // darker outer rim. v2.151 used a near-black material that
    // disappeared into the background gradient and the user
    // couldn't see the table at all.
    private func buildTabletop(on root: AnchorEntity) {
        // Use a thick box (not an infinite plane) so the edge is
        // visible as a 3D surface.
        let tableW: Float = 0.6
        let tableD: Float = 0.6
        let tableH: Float = 0.02
        let box = MeshResource.generateBox(
            width: tableW, height: tableH, depth: tableD,
            cornerRadius: 0.01,
            splitFaces: false
        )
        var mat = PhysicallyBasedMaterial()
        // Warm walnut-ish wood tone.
        mat.baseColor = .init(tint: UIColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1))
        mat.roughness = .init(floatLiteral: 0.55)
        mat.metallic  = .init(floatLiteral: 0.0)
        let table = ModelEntity(mesh: box, materials: [mat])
        // Top surface sits at y=0; the box extends downward so
        // physics still uses y=0 as the contact plane.
        table.position = SIMD3<Float>(0, -tableH * 0.5, 0)
        table.components.set(
            CollisionComponent(shapes: [.generateBox(
                width: tableW, height: tableH, depth: tableD
            )])
        )
        table.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .generate(staticFriction: 0.85, dynamicFriction: 0.75, restitution: 0.05),
                mode: .static
            )
        )
        root.addChild(table)
        self.tabletop = table

        // Subtle felt-pad inset — lighter color so the logo reads.
        let inset = MeshResource.generatePlane(width: tableW * 0.85, depth: tableD * 0.85, cornerRadius: 0.02)
        var feltMat = PhysicallyBasedMaterial()
        feltMat.baseColor = .init(tint: UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1))
        feltMat.roughness = .init(floatLiteral: 0.95)
        feltMat.metallic  = .init(floatLiteral: 0.0)
        let felt = ModelEntity(mesh: inset, materials: [feltMat])
        felt.position = SIMD3<Float>(0, 0.0006, 0)
        root.addChild(felt)

        // BOBA logo decal — slightly above the felt to avoid
        // z-fighting, unlit so it reads as a crisp emblem.
        if let logo = UIImage(named: "boba_playbook_icon_512") ?? UIImage(named: "AppIcon"),
           let cg = logo.cgImage,
           let tex = makeColorTexture(from: cg) {
            let logoPlane = MeshResource.generatePlane(width: 0.22, depth: 0.22)
            var logoMat = UnlitMaterial()
            logoMat.color = .init(tint: UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 0.32),
                                  texture: .init(tex))
            logoMat.blending = .transparent(opacity: .init(floatLiteral: 0.32))
            let logoEntity = ModelEntity(mesh: logoPlane, materials: [logoMat])
            logoEntity.position = SIMD3<Float>(0, 0.0012, 0)
            root.addChild(logoEntity)
            print("[HoC] Tabletop logo loaded (\(cg.width)×\(cg.height))")
        } else {
            print("[HoC] WARN: tabletop logo image not found")
        }
    }

    // MARK: Card back loading
    private func loadCardBack() {
        // Card back is bundled. Loaded once and reused per
        // card via the same TextureResource handle.
        guard let path = Bundle.main.url(forResource: "card-back", withExtension: "png"),
              let image = UIImage(contentsOfFile: path.path),
              let cg = image.cgImage,
              let tex = makeColorTexture(from: cg)
        else {
            return
        }
        backTexture = tex
    }

    // MARK: Card spawning
    //
    // Spawn pattern: tap-from-strip → kinematic card appears at
    // table center, STANDING VERTICALLY (rotated 90° around X
    // axis so its long dimension is up). The user then drags it
    // with the 1-finger gesture; release commits to dynamic.
    private func spawnHeldCard(_ card: Card) {
        guard let root = anchor else { return }
        // One card-in-hand at a time. If there's already a held
        // card waiting to be placed, the new tap commits the
        // previous one and replaces it. (Alternative: ignore the
        // new request — but committing feels more responsive.)
        if heldCard != nil { commitHeldCard() }

        // Stand the card vertically: 90° around world X axis
        // makes the box's long axis (originally Z / depth) point
        // up. Add a small random Y tilt for visual variety.
        let standUp = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let tilt    = simd_quatf(angle: Float.random(in: -0.25...0.25),
                                 axis: SIMD3<Float>(0, 1, 0))
        let rotation = standUp * tilt

        // Spawn position: just above the table, centered. The
        // user drags it into place.
        let halfHeight = Self.cardHeight * 0.5
        let startY = halfHeight + max(0.005, targetMaxY)
        let startPos = SIMD3<Float>(0, startY, 0)

        let entity = buildCardEntity(for: card, position: startPos, rotation: rotation)

        // Kinematic during placement — no gravity, follows finger
        // via handleCardPan. CCD off (PhysX rejects CCD+kinematic).
        if var body = entity.components[PhysicsBodyComponent.self] {
            body.isContinuousCollisionDetectionEnabled = false
            body.mode = .kinematic
            entity.components.set(body)
        }
        root.addChild(entity)
        let cardEntity = CardEntity(entity: entity, card: card)
        heldCard = cardEntity

        print("[HoC] Spawned held card '\(card.cardNumber)' at \(startPos) — kinematic")

        // Load front art async; until it lands the front face
        // shows the back texture as placeholder so the card
        // still reads correctly.
        loadFrontArt(for: card) { [weak entity] tex in
            guard let entity, let model = entity.components[ModelComponent.self] else {
                print("[HoC] art load completed but entity gone")
                return
            }
            var mats = model.materials
            // Face order on a splitFaces box is [+X,-X,+Y,-Y,+Z,-Z].
            // Card stands vertically (rotated 90° around X), so its
            // geometric +Y face (index 2) is the one facing the
            // camera after rotation — that's where art goes.
            if mats.count >= 3 {
                var art = PhysicallyBasedMaterial()
                art.baseColor = .init(tint: .white, texture: .init(tex))
                art.roughness = .init(floatLiteral: 0.55)
                art.metallic  = .init(floatLiteral: 0.0)
                mats[2] = art
            }
            var updated = model
            updated.materials = mats
            entity.components.set(updated)
            print("[HoC] Art applied to face 2 (was \(model.materials.count) materials)")
        }
    }

    private func commitHeldCard() {
        guard let card = heldCard else { return }
        // Swap kinematic → dynamic. Re-enable CCD now that the
        // body is dynamic (thin geometry needs it to prevent
        // tunneling during fast falls).
        if var body = card.entity.components[PhysicsBodyComponent.self] {
            body.mode = .dynamic
            body.isContinuousCollisionDetectionEnabled = true
            card.entity.components.set(body)
        }
        // Small downward velocity so the card "drops" rather
        // than hovering before gravity engages.
        if var motion = card.entity.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = SIMD3<Float>(0, -0.1, 0)
            card.entity.components.set(motion)
        } else {
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = SIMD3<Float>(0, -0.1, 0)
            card.entity.components.set(motion)
        }
        dynamicCards.append(card)
        heldCard = nil
        print("[HoC] Committed held card to dynamic. \(dynamicCards.count) cards in tower.")
    }

    private func clearAllCards() {
        for c in dynamicCards { c.entity.removeFromParent() }
        dynamicCards.removeAll()
        heldCard?.entity.removeFromParent()
        heldCard = nil
        targetMaxY = 0
    }

    // MARK: Card entity construction
    private func buildCardEntity(for card: Card,
                                 position: SIMD3<Float>,
                                 rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(1,0,0))) -> ModelEntity {
        let mesh = MeshResource.generateBox(
            width: Self.cardWidth,
            height: Self.cardThick,
            depth: Self.cardHeight,
            cornerRadius: Self.cornerR,
            splitFaces: true
        )

        // Face order on a splitFaces box per WWDC + community
        // testing: [+X, -X, +Y, -Y, +Z, -Z]. With card lying
        // flat: +Y is top (art), -Y is bottom (back). When the
        // card is rotated 90° around X to stand vertically, the
        // geometric +Y face faces the camera — still index 2.
        let edgeMat = makeEdgeMaterial()
        let backMat: PhysicallyBasedMaterial = {
            var m = PhysicallyBasedMaterial()
            m.roughness = .init(floatLiteral: 0.55)
            m.metallic  = .init(floatLiteral: 0.0)
            if let tex = backTexture {
                m.baseColor = .init(tint: .white, texture: .init(tex))
            } else {
                m.baseColor = .init(tint: UIColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1))
            }
            return m
        }()
        // Front (art) material starts as a copy of back so the
        // card has a recognizable look even before art loads.
        let frontPlaceholder = backMat

        let entity = ModelEntity(mesh: mesh,
                                 materials: [edgeMat, edgeMat, frontPlaceholder, backMat, edgeMat, edgeMat])
        entity.position = position
        entity.orientation = rotation

        // Collision shape — convex box, same dimensions.
        let shape = ShapeResource.generateBox(
            width:  Self.cardWidth,
            height: Self.cardThick,
            depth:  Self.cardHeight
        )
        entity.components.set(CollisionComponent(shapes: [shape]))

        // Physics body — high friction so leans hold.
        let pmat = PhysicsMaterialResource.generate(
            staticFriction:  0.85,
            dynamicFriction: 0.75,
            restitution:     0.05
        )
        var body = PhysicsBodyComponent(
            massProperties: .init(mass: 0.0018),
            material: pmat,
            mode: .dynamic
        )
        body.isContinuousCollisionDetectionEnabled = true
        body.linearDamping  = 0.4
        body.angularDamping = 0.6
        entity.components.set(body)

        // Pre-attach motion component so velocity reads work
        // immediately.
        entity.components.set(PhysicsMotionComponent())

        return entity
    }

    // iOS 18 deprecated TextureResource.generate(from:options:) in
    // favor of TextureResource(image:withName:options:). Both APIs
    // are MainActor-isolated under Swift 6 strict concurrency, so
    // callers must already be on MainActor. This helper hides the
    // version split.
    private func makeColorTexture(from cg: CGImage) -> TextureResource? {
        let opts = TextureResource.CreateOptions(semantic: .color)
        if #available(iOS 18.0, *) {
            return try? TextureResource(image: cg, withName: nil, options: opts)
        } else {
            return try? TextureResource.generate(from: cg, options: opts)
        }
    }

    private func makeEdgeMaterial() -> PhysicallyBasedMaterial {
        if let m = edgeMaterial { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.92, alpha: 1))
        m.roughness = .init(floatLiteral: 0.6)
        m.metallic  = .init(floatLiteral: 0.0)
        edgeMaterial = m
        return m
    }

    // MARK: Async art loading
    //
    // Network fetch + UIImage/CGImage decode happen off-main on a
    // detached task. TextureResource construction is MainActor-
    // isolated (Swift 6), so we hop to MainActor for it + completion.
    // The detached task captures no `self` — Swift 6 strict
    // concurrency flags `[weak self]` reads across the MainActor.run
    // boundary, and we don't need instance state in here anyway.
    private func loadFrontArt(for card: Card, completion: @escaping @MainActor (TextureResource) -> Void) {
        guard let url = CDN.fullURL(for: card) ?? CDN.thumbURL(for: card) else { return }
        Task.detached(priority: .userInitiated) {
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data),
                let cg = image.cgImage
            else { return }
            await MainActor.run {
                let opts = TextureResource.CreateOptions(semantic: .color)
                let tex: TextureResource?
                if #available(iOS 18.0, *) {
                    tex = try? TextureResource(image: cg, withName: nil, options: opts)
                } else {
                    tex = try? TextureResource.generate(from: cg, options: opts)
                }
                if let tex { completion(tex) }
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
//
// Allow the 2-finger camera pan and the pinch to fire
// simultaneously (so the user can orbit + zoom in one motion).
// The 1-finger long-press for card placement is mutually
// exclusive with both — different touch counts route correctly.
extension HouseOfCardsCoordinator: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Pan + pinch coexist. Long-press stays exclusive.
        if gestureRecognizer is UILongPressGestureRecognizer ||
           other is UILongPressGestureRecognizer {
            return false
        }
        return true
    }
}

// MARK: - CardEntity
//
// Bookkeeping wrapper around a ModelEntity. Tracks settled
// state, frames-at-rest counter, and the source Card so we
// can show metadata later.
@MainActor
private final class CardEntity {
    let entity: ModelEntity
    let card: Card
    var settledFrames: Int = 0
    var isSettled: Bool = false

    init(entity: ModelEntity, card: Card) {
        self.entity = entity
        self.card = card
    }
}

// MARK: - ARView screen-point → world-plane projection
//
// Apple's ARView non-AR mode doesn't expose a one-liner for
// "project screen point onto plane y = h." Compute it from
// the camera's projection ray.
private extension ARView {
    func project(_ screenPoint: CGPoint, ontoPlaneAt planeY: Float) -> SIMD3<Float>? {
        // unproject screen point at z=0 and z=1 in NDC to get
        // a world-space ray; intersect with the y = planeY plane.
        guard let near = self.unproject(screenPoint, ontoPlane: float4x4.planeAtY(planeY)) else {
            return nil
        }
        return near
    }
}

private extension float4x4 {
    /// Build the homogeneous plane "y = h" in the form
    /// expected by ARView.unproject(_:ofPlane:).
    static func planeAtY(_ h: Float) -> float4x4 {
        // unproject(_:ofPlane:) expects a transform whose
        // y=0 plane in transform-space is the target plane.
        var m = matrix_identity_float4x4
        m.columns.3.y = h
        return m
    }
}

// Re-export name expected by the SwiftUI body (replaces the
// stub HouseOfCardsRealityView that was here before the
// physics pipeline landed).
private typealias Coordinator = HouseOfCardsCoordinator

// MARK: - HouseOfCardsSession
//
// Observable state for the game. Owns the deck (upcoming
// cards), the current settled tower level count, and a
// pending-spawn flag that the RealityView reads to drop the
// next card into the scene. Physics-state and entity tracking
// stay inside the RealityView's coordinator — the session is
// the high-level orchestrator.

@Observable
@MainActor
final class HouseOfCardsSession {
    /// Upcoming cards in play order. Reseeded from the pool
    /// whenever the user toggles between catalog / collection
    /// or resets the tower.
    var deck: [Card] = []

    /// Number of stable levels currently in the tower. Updated
    /// by the RealityView coordinator's settle detector.
    var currentLevels: Int = 0

    /// One-shot flag set by tapping a card in the deck strip.
    /// The RealityView coordinator reads + clears it on the
    /// next render cycle, spawning a kinematic "held" card at
    /// the table center. Scene gestures handle placement from
    /// there (1-finger long-press to drag, release to drop).
    var pendingSpawn: Card? = nil

    /// Cleared & rebuilt by resetScene; the coordinator
    /// observes it via an Int identity tag and rebuilds the
    /// physics scene from scratch.
    private(set) var resetGeneration: Int = 0

    func reseedDeck(from pool: [Card]) {
        guard !pool.isEmpty else { deck = []; return }
        // Shuffle and take enough to support a long session.
        // We refill from the pool as cards spawn.
        deck = pool.shuffled()
    }

    func requestSpawnNextCard() {
        guard let next = deck.first else { return }
        pendingSpawn = next
        deck.removeFirst()
    }

    func resetScene() {
        currentLevels = 0
        resetGeneration &+= 1
    }
}

