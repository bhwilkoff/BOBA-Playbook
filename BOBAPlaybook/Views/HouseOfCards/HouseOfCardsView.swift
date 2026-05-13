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
            Text("TAP TO SPAWN A PAIR · DRAG TO PLACE · RELEASE")
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
                                // Signal the coordinator to spawn a
                                // pair from the deck. The coordinator
                                // pops 2 cards via inout — we don't
                                // mutate the deck here. The `card`
                                // value passed in pendingSpawn is a
                                // signal flag; the coordinator ignores
                                // its identity and pops from the deck
                                // head.
                                session.pendingSpawn = card
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
                    helpRow("Place",       "Tap the leftmost card — TWO cards spawn together as an A-frame. Drag with one finger to position the pair, release to drop.")
                    helpRow("Look around", "Drag on empty space to orbit the camera. Pinch to zoom in or out.")
                    helpRow("Re-grab",     "Touch a placed card and drag to reposition it. Release to drop again.")
                    helpRow("Lean",        "An A-frame is two cards meeting at the top — the classic house-of-cards base. Build a row, then bridge them with a horizontal card to start a second story.")
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

    /// All dynamic (settled or in-flight) card entities in the
    /// world. Re-grabbed cards move from here to heldCards.
    private var dynamicCards: [CardEntity] = []
    /// Kinematic cards currently being placed by the user.
    /// A pair-spawn from the strip puts 2 cards here forming an
    /// A-frame; the pan gesture moves them together; release
    /// commits both back to dynamic.
    private var heldCards: [CardEntity] = []
    private var lastResetGeneration: Int = -1

    /// Card-back texture is loaded once and reused across
    /// every card; card-front texture is loaded async per
    /// card from the R2 CDN.
    private var backTexture: TextureResource?
    private var edgeMaterial: PhysicallyBasedMaterial?

    /// Box mesh template — shared across all cards.
    /// `cardThick` 0.4mm → 3mm: per Apple physics docs, paper-thin
    /// rigid bodies cause PhysX to treat the base as a flat-face
    /// contact patch with omnidirectional friction (μ ≈ ∞ pin at
    /// the bottom), preventing rotation around the bottom edge.
    /// A 3mm collider gives the solver a real wedge to compute
    /// edge contact against. Real trading cards are 0.33mm; 3mm
    /// looks slightly thick but is what the physics needs.
    private static let cardWidth:  Float = 0.0635
    private static let cardThick:  Float = 0.003
    private static let cardHeight: Float = 0.0889
    private static let cornerR:    Float = 0.0025

    /// Camera framing: as the tower grows, the camera lifts
    /// to keep the top in view.
    private var targetMaxY: Float = 0.0


    /// Spherical-coordinate camera state (orbit around the table).
    /// azimuth: rotation around world Y (horizontal pan)
    /// elevation: angle above the horizontal plane (vertical pan)
    /// distance: radial distance from the cameraTarget
    ///
    /// Default azimuth π/6 (30° toward +X) gives a 3/4 view of
    /// the Z-axis tent: user sees the Λ silhouette clearly with
    /// one card's front partially visible. Orbiting reveals the
    /// other side.
    private var camAzimuth:   Float = .pi / 6
    private var camElevation: Float = 0.45   // ~26° above horizon
    private var camDistance:  Float = 0.50
    private let cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0.035, 0)
    /// Pinch zoom range. v2.157's [0.25, 2.5] let the user
    /// zoom out so far the cards "got lost" in empty space.
    /// Tighter range keeps the tabletop always meaningful.
    private static let camDistanceMin: Float = 0.30
    private static let camDistanceMax: Float = 1.10

    /// Gesture recognizers — retained so we can remove them
    /// cleanly if the view detaches.
    private weak var primaryPanGesture: UIPanGestureRecognizer?
    private weak var pinchGesture:      UIPinchGestureRecognizer?

    /// Current gesture mode set on .began of primaryPanGesture
    /// and cleared on .ended. Drives whether deltas orbit the
    /// camera or move a held/grabbed card.
    private enum PanMode {
        case idle
        case orbiting
        case draggingCards([CardEntity])
    }
    private var panMode: PanMode = .idle
    /// During an orbit drag, accumulate the screen delta into
    /// the spherical-coordinate state. setTranslation resets
    /// each .changed so we apply deltas, not absolute values.
    /// During a card drag, we project the current touch point
    /// onto the card's hover plane.

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

        // v2.165: bump physics solver iterations 4/4 → 25/25.
        // Apple's RealityKit physics-joints sample explicitly does
        // this for "stacking-sensitive" scenes. With 4 iterations,
        // the constraint solver doesn't converge on stacked thin
        // contacts — explains both cards-don't-fall-when-grabbed
        // AND apex-doesn't-establish-contact in prior versions.
        var simComponent = PhysicsSimulationComponent()
        simComponent.solverIterations.positionIterations = 25
        simComponent.solverIterations.velocityIterations = 25
        root.components.set(simComponent)

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
    // Two gestures live on the ARView:
    //   - primaryPan (1-finger)  → context-sensitive:
    //                              · If touch hits a card    → drag that card
    //                              · If there's a held card  → drag held cards
    //                              · Otherwise              → orbit camera
    //   - pinch                  → zoom (radial distance)
    //
    // Single 1-finger pan replaces the v2.156 two-recognizer
    // setup (2-finger pan + 1-finger long-press). The long-press
    // greedily claimed touches and shadowed the pinch
    // recognizer — pinch never fired. With only a 1-finger pan
    // here, the 2-finger pinch is free to recognize on 2-touch
    // gestures without conflict.
    private func installGestures(on view: ARView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePrimaryPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
        self.primaryPanGesture = pan

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        self.pinchGesture = pinch
    }

    @objc private func handlePrimaryPan(_ g: UIPanGestureRecognizer) {
        guard let view = arView else { return }
        let point = g.location(in: view)

        switch g.state {
        case .began:
            // Hit-test: did the touch land on a card?
            let hits = view.hitTest(point, query: .nearest, mask: .all)
            let hitCard = hits.compactMap { hit -> CardEntity? in
                var entity: Entity? = hit.entity
                while let e = entity {
                    if e.name == "card-root" {
                        // Find the CardEntity bookkeeping wrapper.
                        if let held = heldCards.first(where: { $0.entity === e }) {
                            return held
                        }
                        if let dyn = dynamicCards.first(where: { $0.entity === e }) {
                            return dyn
                        }
                    }
                    entity = e.parent
                }
                return nil
            }.first

            if !heldCards.isEmpty {
                // Cards already held (just spawned from strip). Drag
                // the whole group as one, regardless of where finger
                // started — natural for placing a fresh pair.
                panMode = .draggingCards(heldCards)
                print("[HoC] pan: drag held group of \(heldCards.count)")
            } else if let card = hitCard {
                // Re-grab a settled card: switch it to kinematic,
                // disable CCD, track it.
                switchToKinematic(card)
                heldCards = [card]
                dynamicCards.removeAll(where: { $0 === card })
                panMode = .draggingCards([card])
                print("[HoC] pan: re-grabbed settled card '\(card.card.cardNumber)'")
            } else {
                panMode = .orbiting
                print("[HoC] pan: orbiting camera")
            }
            g.setTranslation(.zero, in: view)

        case .changed:
            switch panMode {
            case .orbiting:
                let delta = g.translation(in: view)
                // Native iOS feel: drag direction matches scene
                // motion. Drag RIGHT → world rotates right (camera
                // moves left around the target, decreasing azimuth).
                // Drag DOWN → camera tilts DOWN (lower elevation,
                // looking more level toward the table).
                camAzimuth   -= Float(delta.x) * 0.006
                camElevation  = max(0.05, min(1.45, camElevation + Float(delta.y) * 0.006))
                g.setTranslation(.zero, in: view)
                updateCameraTransform()
            case .draggingCards(let cards):
                guard let first = cards.first else { return }
                let y = first.entity.position.y
                guard let world = view.project(point, ontoPlaneAt: y) else { return }
                // Move all cards in the group by the same delta so
                // an A-frame stays intact while being placed.
                let dx = world.x - first.entity.position.x
                let dz = world.z - first.entity.position.z
                for c in cards {
                    c.entity.position.x += dx
                    c.entity.position.z += dz
                }
            case .idle:
                break
            }

        case .ended, .cancelled, .failed:
            switch panMode {
            case .draggingCards:
                if !heldCards.isEmpty { commitHeldCards() }
            case .orbiting, .idle:
                break
            }
            panMode = .idle

        default:
            break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard g.scale > 0 else { return }
        if g.state == .began {
            print("[HoC] pinch began scale=\(g.scale)")
        }
        camDistance = max(Self.camDistanceMin,
                          min(Self.camDistanceMax, camDistance / Float(g.scale)))
        g.scale = 1.0
        updateCameraTransform()
    }

    private func switchToKinematic(_ card: CardEntity) {
        if var body = card.entity.components[PhysicsBodyComponent.self] {
            body.isContinuousCollisionDetectionEnabled = false
            body.mode = .kinematic
            card.entity.components.set(body)
        }
        card.settledFrames = 0
        card.isSettled = false
        // Wake any dynamic neighbors via mode-cycling. Per Apple
        // dev forum thread 668563: RealityKit has no public
        // wakeUp()/setAwake() API. The documented workaround is
        // to set body.mode = .kinematic then on the next frame
        // back to .dynamic — this forces PhysX to re-activate the
        // body. Plus a tiny impulse as belt-and-braces.
        let cardsToWake = dynamicCards
        for other in cardsToWake {
            if var body = other.entity.components[PhysicsBodyComponent.self] {
                body.mode = .kinematic
                other.entity.components.set(body)
            }
            other.settledFrames = 0
            other.isSettled = false
        }
        // Next frame: switch them back to dynamic so PhysX
        // re-evaluates the forces. Use Task to defer one frame.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame
            guard let self else { return }
            for other in cardsToWake where self.dynamicCards.contains(where: { $0 === other }) {
                if var body = other.entity.components[PhysicsBodyComponent.self] {
                    body.mode = .dynamic
                    body.isContinuousCollisionDetectionEnabled = true
                    other.entity.components.set(body)
                }
                // Tiny impulse to guarantee solver re-evaluates.
                other.entity.applyLinearImpulse(SIMD3<Float>(0, -0.00001, 0),
                                                relativeTo: nil)
            }
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
        // Spawn TWO kinematic cards as an A-frame at the table
        // center. The user drags the pair into position with the
        // primary pan; release commits both to dynamic.
        if session.pendingSpawn != nil {
            session.pendingSpawn = nil
            spawnHeldPair(takingFrom: &session.deck)
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
    // v2.158: procedural wood-grain texture replaces v2.155's
    // flat brown. Generated programmatically with vertical
    // bands of varying brown tones + subtle noise → reads as
    // walnut-grain at any viewing distance, no bundled image
    // asset required.
    private func buildTabletop(on root: AnchorEntity) {
        // Use a thick box (not an infinite plane) so the edge is
        // visible as a 3D surface.
        let tableW: Float = 0.6
        let tableD: Float = 0.6
        let tableH: Float = 0.02
        let box = MeshResource.generateBox(
            width: tableW, height: tableH, depth: tableD,
            cornerRadius: 0.012,
            splitFaces: false
        )
        var mat = PhysicallyBasedMaterial()
        // Procedural walnut-grain texture; fall back to flat
        // tint if the generator fails.
        if let woodImage = Self.makeWoodGrainImage(size: 1024),
           let cg = woodImage.cgImage,
           let tex = makeColorTexture(from: cg) {
            mat.baseColor = .init(tint: .white, texture: .init(tex))
            print("[HoC] Wood-grain texture generated (\(cg.width)×\(cg.height))")
        } else {
            mat.baseColor = .init(tint: UIColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1))
        }
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
        // Table μ reduced to 0.45 (was 0.55). Still higher than
        // card-card μ (0.30) so the base of an A-frame grips the
        // table better than the apex contact slips, but lower
        // overall so cards actually move when nudged.
        table.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .generate(friction: 0.45, restitution: 0.05),
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

        // BOBA logo decal — clipped to rounded corners + unlit
        // so it reads as a crisp emblem. Z-offset slightly above
        // the felt to avoid depth-fighting.
        if let raw = UIImage(named: "boba_playbook_icon_512") ?? UIImage(named: "AppIcon") {
            // Larger corner radius for the logo (~10% of side) to
            // soften the silhouette on the dark felt.
            let rounded = Self.roundedCorners(raw, radiusRatio: 0.10) ?? raw
            if let cg = rounded.cgImage, let tex = makeColorTexture(from: cg) {
                let logoPlane = MeshResource.generatePlane(width: 0.22, depth: 0.22)
                var logoMat = UnlitMaterial()
                logoMat.color = .init(tint: UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 0.34),
                                      texture: .init(tex))
                logoMat.blending = .transparent(opacity: .init(floatLiteral: 0.34))
                let logoEntity = ModelEntity(mesh: logoPlane, materials: [logoMat])
                logoEntity.position = SIMD3<Float>(0, 0.0012, 0)
                root.addChild(logoEntity)
                print("[HoC] Tabletop logo loaded rounded (\(cg.width)×\(cg.height))")
            }
        } else {
            print("[HoC] WARN: tabletop logo image not found")
        }
    }

    // MARK: Wood-grain procedural texture
    //
    // Programmatically generated walnut wood grain. Uses
    // CoreGraphics to paint vertical bands of subtly varying
    // brown tones, then a faint grain noise pass on top.
    // Good enough that it reads as wood at iPhone viewing
    // distance without needing a bundled PNG asset.
    static func makeWoodGrainImage(size: Int) -> UIImage? {
        let pxSize = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pxSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Base warm walnut.
            cg.setFillColor(UIColor(red: 0.31, green: 0.20, blue: 0.13, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: pxSize))

            // Vertical grain bands. Random widths + slight color
            // jitter around the base walnut tone.
            var x: CGFloat = 0
            while x < pxSize.width {
                let bandW = CGFloat.random(in: 6...32)
                let jitter = CGFloat.random(in: -0.06...0.06)
                let r = max(0, min(1, 0.31 + jitter))
                let g = max(0, min(1, 0.20 + jitter * 0.7))
                let b = max(0, min(1, 0.13 + jitter * 0.5))
                let alpha = CGFloat.random(in: 0.22...0.48)
                cg.setFillColor(UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor)
                cg.fill(CGRect(x: x, y: 0, width: bandW, height: pxSize.height))
                x += bandW
            }

            // Fine grain noise — short horizontal strokes in a
            // darker tone to suggest cellular wood texture.
            cg.setStrokeColor(UIColor(red: 0.16, green: 0.10, blue: 0.06, alpha: 0.18).cgColor)
            cg.setLineWidth(0.6)
            for _ in 0..<3500 {
                let x0 = CGFloat.random(in: 0...pxSize.width)
                let y0 = CGFloat.random(in: 0...pxSize.height)
                let len = CGFloat.random(in: 4...18)
                cg.move(to: CGPoint(x: x0, y: y0))
                cg.addLine(to: CGPoint(x: x0 + len, y: y0))
                cg.strokePath()
            }

            // A handful of darker "knot" spots for character.
            for _ in 0..<6 {
                let cx = CGFloat.random(in: 50...(pxSize.width - 50))
                let cy = CGFloat.random(in: 50...(pxSize.height - 50))
                let radius = CGFloat.random(in: 8...22)
                let knot = CGRect(x: cx - radius, y: cy - radius,
                                  width: radius * 2, height: radius * 2)
                cg.setFillColor(UIColor(red: 0.18, green: 0.10, blue: 0.05, alpha: 0.35).cgColor)
                cg.fillEllipse(in: knot)
            }
        }
    }

    // MARK: Card back loading
    private func loadCardBack() {
        // Card back is bundled. Loaded once and reused per
        // card via the same TextureResource handle.
        guard let path = Bundle.main.url(forResource: "card-back", withExtension: "png"),
              let image = UIImage(contentsOfFile: path.path)
        else {
            return
        }
        // Clip card-back to rounded corners so the back-facing
        // plane shows the same silhouette as the art-facing plane.
        let rounded = Self.roundedCorners(image) ?? image
        guard let cg = rounded.cgImage,
              let tex = makeColorTexture(from: cg)
        else { return }
        backTexture = tex
    }

    // MARK: Card spawning
    //
    // Pair-spawn: tap-from-strip consumes TWO cards from the
    // deck and spawns them as a TENT at the table center.
    //
    // Tent geometry (v3 — proper house-of-cards "tent"):
    //   - Main axis along world Z (depth). User views from +Z+X+Y
    //     corner (default 3/4 camera).
    //   - Card 1 at (0, centerY, -baseHalfZ) tilted by -π/4 around
    //     world X axis. Its top swings toward +Z (apex at z=0); its
    //     front face ends up pointing -Z direction (OUTWARD).
    //   - Card 2 at (0, centerY, +baseHalfZ) = (180° around Y) ∘
    //     card-1 rotation. Top toward -Z, front toward +Z (outward).
    //   - Lean axis is world X, which is parallel to both cards'
    //     bottom edges (along world X). The whole bottom edge
    //     rests on the table — not just a corner.
    //   - Front faces OUTWARD (away from apex), backs face INWARD
    //     (toward each other inside the tent) — what a real tent
    //     does, what the user asked for.
    //   - 45° lean; bottom-edge spacing ~63mm (sin(45)*H + apex
    //     gap); apex height ~31mm.
    private func spawnHeldPair(takingFrom deck: inout [Card]) {
        guard let root = anchor else { return }
        guard deck.count >= 1 else { return }
        let card1 = deck.removeFirst()
        let card2 = deck.count > 0 ? deck.removeFirst() : card1

        if !heldCards.isEmpty { commitHeldCards() }

        // 30° lean per user feedback — 45° was "too wide to
        // actually keep the cards upright." leanAngle here is
        // the angle FROM VERTICAL: 0 = upright, π/2 = lying flat.
        let leanAngle: Float = .pi / 6   // 30° from vertical
        let halfH = Self.cardHeight * 0.5

        // ROTATION FORMULA (v2.162 correction):
        // To stand the card and tilt it θ from vertical, rotate
        // by (θ - π/2) around the world X axis. At θ=0 this is
        // -π/2 (pure standUp). At θ=π/2 this is 0 (lying flat).
        //
        // v2.161 used `-leanAngle` which only worked at exactly
        // 45° because cos(π/4)=sin(π/4). At 30° lean, that bug
        // produced 60° lean instead of 30° — what the user
        // described as "even more extreme (wide)."
        //
        // After the correct rotation, for card 1:
        //   local +Z (height) → world (0, cos(θ), +sin(θ))
        //     i.e. mostly up, slightly toward +Z (apex)
        //   local +Y (front normal) → world (0, sin(θ), -cos(θ))
        //     i.e. mostly outward toward -Z, slightly up
        //
        // Card 2 mirrors across the YZ plane: 180° around Y.
        let lean1 = simd_quatf(angle: leanAngle - .pi / 2,
                               axis: SIMD3<Float>(1, 0, 0))
        let flipY = simd_quatf(angle: .pi,
                               axis: SIMD3<Float>(0, 1, 0))
        let lean2 = flipY * lean1

        // v2.164: positions account for the now-3mm collider.
        // With non-trivial thickness, the LOWEST world-Y point of
        // a leaned card is not just at the center of the bottom
        // edge — it's at the inner-bottom corner. Similarly the
        // apex contact is at the inner-top corner, not the center
        // of the top edge.
        let halfT = Self.cardThick * 0.5

        // centerY: the lowest point (inner-bottom corner of the
        // collider) has world Y offset = -(halfT*sin(θ) +
        // halfH*cos(θ)) from the entity center. To put that
        // point on the table (Y=0):
        //   centerY = halfT*sin(θ) + halfH*cos(θ)
        let centerY = halfT * sin(leanAngle)
                    + halfH * cos(leanAngle)
                    + max(0.001, targetMaxY)
                    + 0.001  // 1mm air gap so cards drop into place

        // baseHalfZ: the apex contact point is the INNER-TOP corner
        // of each card's collider. For card 1 at entity z =
        // -baseHalfZ, this corner is at world Z = -baseHalfZ +
        // (halfT*cos(θ) + halfH*sin(θ)). For colliders to meet at
        // world Z = 0:
        //   baseHalfZ = halfT*cos(θ) + halfH*sin(θ)
        // Per the research, spawn cards with a small interpene-
        // tration (~0.5mm overlap each side) so PhysX MUST resolve
        // the contact — establishes real apex normal force.
        let apexOverlap: Float = 0.0005
        let baseHalfZ = halfT * cos(leanAngle)
                      + halfH * sin(leanAngle)
                      - apexOverlap

        let leftEntity  = buildCardEntity(for: card1,
                                          position: SIMD3<Float>(0, centerY, -baseHalfZ),
                                          rotation: lean1)
        let rightEntity = buildCardEntity(for: card2,
                                          position: SIMD3<Float>(0, centerY,  baseHalfZ),
                                          rotation: lean2)

        for entity in [leftEntity, rightEntity] {
            if var body = entity.components[PhysicsBodyComponent.self] {
                body.isContinuousCollisionDetectionEnabled = false
                body.mode = .kinematic
                entity.components.set(body)
            }
            root.addChild(entity)
        }

        heldCards = [
            CardEntity(entity: leftEntity,  card: card1),
            CardEntity(entity: rightEntity, card: card2)
        ]

        print("[HoC] Spawned A-frame pair '\(card1.cardNumber)' + '\(card2.cardNumber)' at center")

        // Async art load for both cards. Each callback finds the
        // named child plane on its own entity. Explicit self
        // capture is required by Swift's escaping-closure rules.
        loadFrontArt(for: card1) { [weak self, weak leftEntity] tex in
            self?.applyArt(to: leftEntity, texture: tex)
        }
        loadFrontArt(for: card2) { [weak self, weak rightEntity] tex in
            self?.applyArt(to: rightEntity, texture: tex)
        }
    }

    @MainActor
    private func applyArt(to entity: ModelEntity?, texture: TextureResource) {
        guard let entity else { return }
        guard let front = entity.findEntity(named: "card-front") as? ModelEntity,
              var model = front.components[ModelComponent.self] else {
            print("[HoC] couldn't find card-front child")
            return
        }
        var art = UnlitMaterial()
        art.color = .init(tint: .white, texture: .init(texture))
        model.materials = [art]
        front.components.set(model)
        print("[HoC] Art applied (tex \(texture.width)×\(texture.height))")
    }

    private func commitHeldCards() {
        guard !heldCards.isEmpty else { return }
        for card in heldCards {
            if var body = card.entity.components[PhysicsBodyComponent.self] {
                body.mode = .dynamic
                body.isContinuousCollisionDetectionEnabled = true
                card.entity.components.set(body)
            }
            // Small downward seed velocity so the body isn't at
            // perfect rest on commit (avoids solver-equilibrium
            // lock-in). With the v2.164 3mm collider this is much
            // less critical — the thicker collider gives PhysX
            // proper edge contact to compute around — but a small
            // kick is cheap insurance.
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = SIMD3<Float>(0, -0.02, 0)
            card.entity.components.set(motion)
            dynamicCards.append(card)
        }
        print("[HoC] Committed \(heldCards.count) cards. Tower: \(dynamicCards.count) total.")
        heldCards.removeAll()
    }

    private func clearAllCards() {
        for c in dynamicCards { c.entity.removeFromParent() }
        dynamicCards.removeAll()
        for c in heldCards { c.entity.removeFromParent() }
        heldCards.removeAll()
        targetMaxY = 0
    }

    // MARK: Card entity construction
    //
    // v2.156: use child plane entities for the visible front
    // (art) and back. v2.155's splitFaces box approach had
    // unverified face-index mapping; the user reported art never
    // visible despite "applied to face 2" prints. Child planes
    // eliminate the guessing — front-plane is +Y in local space,
    // texture maps directly, no UV ambiguity.
    private func buildCardEntity(for card: Card,
                                 position: SIMD3<Float>,
                                 rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(1,0,0))) -> ModelEntity {
        let halfT = Self.cardThick * 0.5

        // ── Root entity: physics body + collision live here.
        //    Invisible (no mesh on the root).
        let entity = ModelEntity()
        entity.position = position
        entity.orientation = rotation
        entity.name = "card-root"

        // ── No card-body box: v2.160 used a thin off-white box
        //    for visible thickness, but its full-rectangle top/
        //    bottom faces poked past the rounded-texture planes'
        //    transparent corners — the white box showed THROUGH
        //    the rounded mask, making the cards look like rounded
        //    images inside sharp white rectangles. The card now
        //    visually is just two planes (front + back) with
        //    near-zero gap. Physics still works because the
        //    CollisionComponent on the root entity uses a box
        //    shape with the same dimensions.

        // ── Plane orientation math (v3 / v2.160):
        //
        //    Entity rotation for card 1 (left/at-Z): -π/4 around X.
        //    That maps local axes to world directions as:
        //       local +X → world +X (width, parallel to table edge)
        //       local +Y → world (0, +sin45, -cos45) = up + -Z
        //         (the "outward" tent slope for card 1)
        //       local +Z → world (0, +cos45, +sin45) = up + +Z
        //         (toward apex)
        //
        //    For the FRONT face (art) to be on the OUTWARD slope
        //    of the tent — i.e., facing away from the apex — its
        //    normal direction in world space should match local +Y's
        //    world direction. So put the front plane at entity-local
        //    +Y position with default (+Y normal) orientation.
        //
        //    The back plane goes at entity-local -Y, with its normal
        //    flipped (rotated π around X) so it points inward toward
        //    the apex (the inside of the tent).
        let frontMesh = MeshResource.generatePlane(width: Self.cardWidth,
                                                   depth: Self.cardHeight,
                                                   cornerRadius: Self.cornerR)
        var placeholder = UnlitMaterial()
        if let tex = backTexture {
            placeholder.color = .init(tint: .white, texture: .init(tex))
        } else {
            placeholder.color = .init(tint: UIColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1))
        }
        let frontEntity = ModelEntity(mesh: frontMesh, materials: [placeholder])
        // Front plane: at entity-local +Y; default normal +Y maps
        // to the outward-facing direction after entity rotation.
        frontEntity.position = SIMD3<Float>(0, halfT + 0.00012, 0)
        frontEntity.name = "card-front"
        entity.addChild(frontEntity)

        // ── Back plane: at entity-local -Y, flipped π around X so
        //    its normal points inward (toward the apex / inside
        //    the tent).
        let backMesh = MeshResource.generatePlane(width: Self.cardWidth,
                                                  depth: Self.cardHeight,
                                                  cornerRadius: Self.cornerR)
        var backMatUnlit = UnlitMaterial()
        if let tex = backTexture {
            backMatUnlit.color = .init(tint: .white, texture: .init(tex))
        } else {
            backMatUnlit.color = .init(tint: UIColor(red: 0.65, green: 0.20, blue: 0.18, alpha: 1))
        }
        let backEntity = ModelEntity(mesh: backMesh, materials: [backMatUnlit])
        backEntity.position = SIMD3<Float>(0, -halfT - 0.00012, 0)
        backEntity.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        backEntity.name = "card-back"
        entity.addChild(backEntity)

        // ── Collision + physics on the root (so the planes
        //    move with the box rigid body).
        let shape = ShapeResource.generateBox(
            width:  Self.cardWidth,
            height: Self.cardThick,
            depth:  Self.cardHeight
        )
        entity.components.set(CollisionComponent(shapes: [shape]))

        // v2.165: physics-body inertia fix.
        //
        // CRITICAL: v2.164 used PhysicsMassProperties(mass: 0.0018)
        // which sets ONLY mass, leaving inertia at default [1,1,1]
        // kg·m². For a 1.8g card whose real inertia values are
        // ~1e-6 kg·m², that default inertia was ~1 MILLION times
        // too high — the cards literally couldn't rotate.
        //
        // Per Apple's PhysicsBodies sample (Entity+Sphere.swift),
        // the right pattern is `shapes:density:` which derives
        // BOTH mass AND inertia from the shape's volume integral.
        //
        // Density chosen so volume × density = real 1.8g card
        // mass given the 3mm collider thickness (~10× real card
        // thickness for physics stability):
        //   V = 0.0635 × 0.003 × 0.0889 = 1.69e-5 m³
        //   ρ = 0.0018 / 1.69e-5 ≈ 107 kg/m³
        let pmat = PhysicsMaterialResource.generate(
            staticFriction:  0.55,
            dynamicFriction: 0.40,
            restitution:     0.02
        )
        var body = PhysicsBodyComponent(
            shapes:   [shape],
            density:  107,
            material: pmat,
            mode:     .dynamic
        )
        body.isContinuousCollisionDetectionEnabled = true
        body.linearDamping  = 0.05
        body.angularDamping = 0.05
        entity.components.set(body)
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

    // MARK: Texture helpers — rounded-corner clipping + vertical flip
    //
    // Two image preprocessing steps before texture upload:
    //
    // 1. Rounded corners: MeshResource.generatePlane(cornerRadius:)
    //    doesn't actually round the visible plane mesh — the
    //    parameter is silently ignored on iOS 17/18. So we clip
    //    the underlying image to a rounded rect and let the alpha
    //    channel cut the corners.
    //
    // 2. Vertical flip: MeshResource.generatePlane maps the image's
    //    top edge to the plane's -Z direction. With the v2.160
    //    entity rotation, plane-local -Z ends up at world -Y
    //    (downward). The card visually appears upside-down. Pre-
    //    flipping the image vertically inverts the V mapping so
    //    the card's top (where the hero name is) ends up at the
    //    highest point in world space.
    static func roundedCorners(_ image: UIImage, radiusRatio: CGFloat = 0.045) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let radius = min(size.width, size.height) * radiusRatio
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Vertical flip: translate down + scale Y by -1 so the
            // image draws with its top edge at the bottom of the
            // canvas. Net effect on the resulting UIImage: vertical
            // mirror.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            // Clip to rounded rect; note the rect is in the
            // ORIGINAL coordinate system, which after the flip
            // still corresponds to the full image.
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            path.addClip()
            image.draw(in: rect)
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
                let image = UIImage(data: data)
            else { return }
            await MainActor.run {
                // Clip to rounded corners BEFORE generating the
                // texture — the alpha channel gives us visible
                // rounded corners (since generatePlane's
                // cornerRadius param is silently ignored on iOS 17/18).
                let rounded = HouseOfCardsCoordinator.roundedCorners(image) ?? image
                guard let cg = rounded.cgImage else { return }
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

