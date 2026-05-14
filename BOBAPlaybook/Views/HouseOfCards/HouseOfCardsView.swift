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
            HouseOfCardsRealityView(
                session: session,
                cardPool: cardPool,
                catalog: catalogByBobaId
            )
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
                Text("HOUSE OF BOBA")
                    .font(Design.Fonts.display(14))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 14) {
                    levelPill(label: "LEVEL",  value: session.currentLevels)
                    levelPill(label: "BEST",   value: highScore, accent: true)
                }
            }

            Spacer()

            // Reset Field — prominent, immediate (no confirm per
            // user choice). Clears the tower so they can start over.
            Button {
                session.resetScene()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Reset Field")

            Menu {
                // Undo — restores the previous scene state. Only
                // enabled when the coordinator's undo stack has
                // something to pop (a snap fired, a spawn, a
                // physics fall, etc.).
                Button {
                    session.undoRequested = true
                } label: {
                    Label("Undo last action", systemImage: "arrow.uturn.backward")
                }
                .disabled(!session.canUndo)

                // Snap toggle — when off, gestures release cards
                // exactly where placed. Pure physics-sandbox mode.
                Button {
                    session.snapsEnabled.toggle()
                } label: {
                    Label(
                        session.snapsEnabled ? "Smart snap  ✓" : "Smart snap",
                        systemImage: session.snapsEnabled ? "wand.and.stars" : "wand.and.stars.inverse"
                    )
                }

                Divider()

                // Toggle in Menu can be flaky across iOS versions —
                // use a manual Button with state-mirroring label.
                Button {
                    // v2.177: just flip the flag. The
                    // .onChange(of: useCollection) handler on the
                    // root body fires reseedDeck once — no need
                    // to also call it here.
                    useCollection.toggle()
                } label: {
                    Label(
                        useCollection ? "Use my collection  ✓" : "Use my collection",
                        systemImage: useCollection ? "checkmark.circle.fill" : "person.crop.circle"
                    )
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

    // MARK: Bottom deck strip — upcoming cards + Place button
    private var bottomDeckStrip: some View {
        VStack(spacing: 8) {
            // Status + LOCK + PLAY/PAUSE row.
            HStack(spacing: 10) {
                Text(stripStatusText)
                    .font(Design.Fonts.mono(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                playPauseButton
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(session.deck.prefix(12).enumerated()), id: \.offset) { _, card in
                        DeckStripCard(
                            card: card,
                            selectionIndex: session.selectionIndex(of: card),
                            onTap: {
                                session.toggleSelection(card)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)   // room for the order-badge to extend above
            }
            .frame(height: 108)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var playPauseButton: some View {
        Button {
            session.togglePause()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(session.isPaused ? "PLAY" : "PAUSE")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    session.hasAnyCards
                        ? Design.Colors.bobaOrange
                        : Color.white.opacity(0.18)
                )
            )
        }
        .disabled(!session.hasAnyCards)
    }

    private var stripStatusText: String {
        if !session.isPaused {
            return "PHYSICS RUNNING"
        }
        if !session.selectedCards.isEmpty {
            return "\(session.selectedCards.count)/4 · TAP TABLE TO PLACE"
        }
        if session.hasAnyCards {
            return "PAUSED · TAP A CARD TO ADJUST"
        }
        return "PICK CARDS FROM DRAWER"
    }

    /// v2.196: stable lookup from a card's bobaId to its full Card
    /// data. Used by the coordinator when restoring a saved scene
    /// — persisted card states reference bobaId because it's the
    /// only guaranteed-unique identifier across treatments
    /// (CLAUDE.md "One ID per Card"). cardPool isn't enough on its
    /// own; it's pre-filtered by power/ownership and a persisted
    /// card might fall outside the current pool.
    private var catalogByBobaId: [String: Card] {
        Dictionary(uniqueKeysWithValues: cardStore.displayCards.map { ($0.bobaId, $0) })
    }

    // MARK: Card pool resolution
    //
    // v2.177: "Use my collection" now drops the power-135 filter
    // entirely for owned cards. The user already curated their
    // collection — the catalog default's high-power filter was
    // over-trimming small collections (and producing a silent
    // fallback to catalog when nothing passed). Fallback to
    // catalog only when (a) toggle is off, (b) not signed in, or
    // (c) no owned cards have images at all. The fallback is
    // logged so console output makes it obvious why the strip
    // didn't change.
    private var cardPool: [Card] {
        guard useCollection else {
            return catalogPool
        }
        guard auth.isAuthenticated else {
            print("[HoB] cardPool: collection mode requested but not signed in → catalog")
            return catalogPool
        }
        let pool = ownedPool
        if pool.isEmpty {
            print("[HoB] cardPool: collection mode but \(collection.userCards.count) owned cards have no images → catalog")
            return catalogPool
        }
        print("[HoB] cardPool: collection mode, \(pool.count) owned cards (total owned=\(collection.userCards.count))")
        return pool
    }

    /// Catalog default: high-power cards with images.
    private var catalogPool: [Card] {
        cardStore.displayCards.filter {
            ($0.power ?? 0) > 135 && ($0.imageFile?.isEmpty == false)
        }
    }

    /// User's owned cards (no power filter — they curated it
    /// themselves). Must have an image.
    private var ownedPool: [Card] {
        let ownedNumbers = Set(collection.userCards.map { $0.cardNumber })
        return cardStore.displayCards.filter {
            ownedNumbers.contains($0.cardNumber) && ($0.imageFile?.isEmpty == false)
        }
    }

    // MARK: Help sheet
    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("HOUSE OF BOBA")
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(.white)
                    Text("Build first, then play. Set up your tower in a frozen physics playground, then hit PLAY to see if it stands.")
                        .font(Design.Fonts.mono(15))
                        .foregroundStyle(.white.opacity(0.85))
                    Divider().overlay(.white.opacity(0.15))
                    helpRow("1. Select from strip", "Tap up to 4 cards in the bottom strip — orange numbered badge shows placement order.")
                    helpRow("2. Tap to place",      "Tap the table to spawn the selected cards there, standing vertical — or tap the FLAT TOP of an existing card to spawn the next layer on top of your tower. Add more anytime by selecting more strip cards and tapping again.")
                    helpRow("3. Tap a card",        "Tap a placed card to SELECT it — an orange halo appears around it. While selected, ALL gestures manipulate that card (camera is paused).")
                    helpRow("Translate",            "One-finger drag STARTING ON the selected card → slide it across the table (X/Z). The bottom always rides whatever surface is below — table or top of another card.")
                    helpRow("Tilt (angle)",         "Two-finger HORIZONTAL drag → tilt the selected card forward/back, up to flat (90°). The bottom keeps riding the surface below as it leans.")
                    helpRow("Lift / lower",         "Two-finger VERTICAL drag → raise or lower the selected card freely. Lift a card high to position it as a roof piece on top of an A-frame apex.")
                    helpRow("Rotate (yaw)",         "TWIST with two fingers → spin the selected card around its vertical axis. (Standard iOS rotation gesture, same as Photos / Maps.)")
                    helpRow("Smart snap",           "When you release a drag, lift, or tilt near another card, the closest valid stacking pose snaps automatically. Five cases: (1) Both tilted in OPPOSITE directions, your TOPS close → A-frame apex. (2) Both tilted in OPPOSITE directions, your BOTTOMS close → share a foot (start the NEXT A-frame in a row). (3) Your FLAT card dragged between TWO apex points (cardHeight apart) → roof tile spans both, one apex under each end. (4) Your card is ABOVE a support → bottom rests on the support's top. (5) Two FLAT cards' bottoms close together → roof tiles side-by-side. Build pyramids, rows, and roofs without measuring.")
                    helpRow("Deselect",             "Tap empty space (or tap the selected card again) to deselect.")
                    helpRow("Look around",          "When NOTHING is selected: one-finger drag orbits, two-finger drag pans the view, pinch zooms.")
                    helpRow("Play / Pause",        "Tap PLAY to engage physics. Tap PAUSE anytime to freeze mid-fall, repair, and play again.")
                    helpRow("Reset",                "The ↺ button in the top bar clears the field immediately.")
                    helpRow("Score",                "Each stable layer adds to your tower height. 10+ is the dream.")
                    helpRow("Switch deck",          "Toggle 'Use my collection' to build with cards you own (power > 135).")
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
// Compact card thumbnail in the bottom strip. Tap to toggle
// selection (up to 4 cards selectable). Selected cards show
// orange border + the order-of-selection index in the corner.
// v2.167 multi-select model — the user explicitly picks which
// cards to place rather than the leftmost-pair auto-pop.
private struct DeckStripCard: View {
    let card: Card
    let selectionIndex: Int?   // nil = not selected; otherwise 0..3
    var onTap: () -> Void = {}

    private var isSelected: Bool { selectionIndex != nil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CardImageView(card: card, size: .thumb)
                .aspectRatio(0.714, contentMode: .fit)
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Design.Colors.bobaOrange : .white.opacity(0.2),
                                lineWidth: isSelected ? 3 : 0.5)
                )
                .shadow(color: isSelected ? Design.Colors.bobaOrange.opacity(0.7) : .clear,
                        radius: isSelected ? 10 : 0)
            // (No scaleEffect — v2.168 scaled by 6% on select which
            // clipped the top/bottom of the card AND the order
            // badge against the strip frame. Glow + thicker border
            // is enough visual feedback.)

            if let idx = selectionIndex {
                Text("\(idx + 1)")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Design.Colors.bobaOrange, in: Circle())
                    .offset(x: 4, y: -4)
            }

            if let power = card.power {
                VStack {
                    Spacer()
                    HStack {
                        Text("\(power)")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.6), in: Capsule())
                        Spacer()
                    }
                }
                .padding(3)
            }
        }
        .frame(width: 60, height: 84)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
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
    /// v2.196: full catalog (bobaId → Card) so the coordinator
    /// can resolve persisted cards back to their data on restore.
    /// cardPool alone isn't enough — it's the filtered set
    /// (power>135 or owned-only), and persisted cards might be
    /// outside that filter if the user switched modes between
    /// sessions.
    let catalog: [String: Card]

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableCameraGrain)
        view.environment.background = .color(UIColor(red: 0.05, green: 0.04, blue: 0.04, alpha: 1))
        context.coordinator.attach(to: view, catalog: catalog)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // v2.196: retry restore until catalog is populated. attach
        // is only called once and the catalog might still be
        // loading at that point.
        context.coordinator.restoreSavedSceneIfAvailable(catalog: catalog)
        // v2.205: undo trigger lives here so it has access to the
        // catalog (needed to rebuild card entities from bobaIds).
        context.coordinator.performUndoIfRequested(catalog: catalog)
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
    /// Kinematic cards. In pause mode this is every card on
    /// the table. In play mode it's empty unless a card is
    /// being actively grabbed.
    private var heldCards: [CardEntity] = []
    /// The card currently SELECTED for individual manipulation
    /// in pause mode. Has a visual outline halo. While set, all
    /// gestures route to it (camera gestures are suppressed).
    /// Always nil in play mode.
    private var selectedCardEntity: CardEntity?
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
    private static let outlineMargin: Float = 0.005
    /// Minimum clearance from the table for the BOTTOM of the
    /// outline (= bottom of card + outlineMargin) plus a 1mm air
    /// gap. centerY must be ≥ halfH + minClearance.
    private static let minClearance: Float = outlineMargin + 0.001

    /// Camera framing: as the tower grows, the camera lifts
    /// to keep the top in view.
    private var targetMaxY: Float = 0.0

    // Cached selection-outline mesh + material — built lazily
    // on first use, reused for every selection.
    private lazy var outlineMesh: MeshResource = {
        return MeshResource.generatePlane(
            width: Self.cardWidth + 2 * Self.outlineMargin,
            depth: Self.cardHeight + 2 * Self.outlineMargin,
            cornerRadius: Self.cornerR + Self.outlineMargin
        )
    }()
    private lazy var outlineMaterial: UnlitMaterial = {
        var m = UnlitMaterial()
        m.color = .init(tint: UIColor(red: 1.0, green: 0.5, blue: 0.05, alpha: 1.0))
        return m
    }()


    /// Spherical-coordinate camera state (orbit around the
    /// `cameraTarget` point). 2-finger drag in empty space pans
    /// the target across the table so user can look anywhere.
    private var camAzimuth:   Float = .pi / 6
    private var camElevation: Float = 0.45   // ~26° above horizon
    private var camDistance:  Float = 0.50
    private var cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0.035, 0)
    /// Pinch zoom range. v2.157's [0.25, 2.5] let the user
    /// zoom out so far the cards "got lost" in empty space.
    /// Tighter range keeps the tabletop always meaningful.
    private static let camDistanceMin: Float = 0.30
    private static let camDistanceMax: Float = 1.10

    /// Gesture recognizers — retained so we can remove them
    /// cleanly if the view detaches.
    private weak var primaryPanGesture:   UIPanGestureRecognizer?
    private weak var twoFingerPanGesture: UIPanGestureRecognizer?
    private weak var pinchGesture:        UIPinchGestureRecognizer?

    /// v2.173: Apple's `ARView.installGestures([.translation,
    /// .rotation], for:)` recognizers attached to the currently
    /// selected card. Installed in setSelectedCard, removed on
    /// deselect. Apple's translation handles XZ-plane drag and
    /// Apple's rotation handles 2-finger-twist yaw — both
    /// canonical iOS RealityKit APIs (verified against Apple
    /// docs for iOS 26).
    private var entityGestures: [EntityGestureRecognizer] = []

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
    func attach(to view: ARView, catalog: [String: Card] = [:]) {
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

        // v2.196: restore previously-saved scene if available.
        // Spawn cards at their saved positions/orientations,
        // restore camera, restore pause state. Each user-driven
        // change (gesture .ended, spawn, reset, play/pause) writes
        // back to UserDefaults so the next visit picks up where
        // the last one left off.
        restoreSavedSceneIfAvailable(catalog: catalog)

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
        // 1-finger pan: orbit camera OR drag a held card.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePrimaryPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
        self.primaryPanGesture = pan

        // 2-finger pan: rotate a held card (yaw + pitch) OR pan
        // the camera target across the table.
        let twoPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoPan.minimumNumberOfTouches = 2
        twoPan.maximumNumberOfTouches = 2
        twoPan.delegate = self
        view.addGestureRecognizer(twoPan)
        self.twoFingerPanGesture = twoPan

        // Pinch: zoom camera always (v2.172 — dropped pinch-for-yaw,
        // which was non-standard. v2.173: yaw is now handled by
        // Apple's EntityRotationGestureRecognizer attached per-
        // selected-card via installGestures.)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        self.pinchGesture = pinch

        // Tap: spawn-at-location (when cards selected) OR grab a
        // settled card. Requires pan to fail first so dragging
        // doesn't trigger an accidental spawn.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
    }

    // v2.173: install Apple's native entity gestures on a card
    // when it becomes the selection. Returns Apple-managed
    // recognizers that update the entity transform directly each
    // frame. We attach a target callback so we can re-apply
    // surface-snap + A-frame-snap after each gesture update —
    // Apple's translation is XZ-only (Y untouched), so our snap
    // and Apple's drag are orthogonal and compose cleanly.
    //
    // Per Apple staff (forum 771441), ARView is the canonical
    // iOS RealityKit container; installGestures(_:for:) is the
    // canonical entity-manipulation API on iOS through iOS 26.
    // ManipulationComponent / GestureComponent on visionOS only.
    private func installEntityGestures(on card: CardEntity) {
        guard let view = arView else { return }
        let recognizers = view.installGestures([.translation, .rotation], for: card.entity)
        for r in recognizers {
            r.addTarget(self, action: #selector(handleEntityGestureUpdate(_:)))
            r.delegate = self
            // v2.175: restrict Apple's translation to exactly 1 finger.
            // EntityTranslationGestureRecognizer is a UIPanGesture
            // subclass; by default it accepts multi-finger pans, so
            // it fires DURING our 2-finger pitch/lift gestures and
            // drags the card sideways while the user tries to tilt
            // (visible in v2.174 diagnostics).
            if let pan = r as? UIPanGestureRecognizer,
               !(r is UIRotationGestureRecognizer) {
                pan.minimumNumberOfTouches = 1
                pan.maximumNumberOfTouches = 1
            }
        }
        entityGestures = recognizers
    }

    private func removeEntityGestures() {
        guard let view = arView else { return }
        for r in entityGestures {
            view.removeGestureRecognizer(r)
        }
        entityGestures.removeAll()
    }

    @objc private func handleEntityGestureUpdate(_ g: UIGestureRecognizer) {
        guard let selected = selectedCardEntity else { return }

        // v2.182: skip surface-snap during ROTATION (yaw). Apple's
        // rotation preserves Y for every point on the entity, but
        // a yaw of an upright/tilted card sweeps the bottom-mid
        // in XZ around the center. When the bottom-mid sweeps
        // even slightly off a supporting card, the raycast finds
        // the table below instead of the support — and surface-
        // snap drops the card to table-level mid-yaw. We want
        // yaw to be a pure orientation change that keeps the
        // card at its current level. (Translation and pitch
        // still need per-frame snap to ride supports.)
        let isRotation = g is EntityRotationGestureRecognizer

        // Surface snap on every .changed frame for translation
        // (XZ drag): translation is XZ-only, our snap modifies Y
        // — orthogonal, card visibly rides the surface as it drags.
        if g.state == .changed, !isRotation {
            applySurfaceSnap(to: selected)
        }
        // Smart snap on .ended (all gesture types). For non-
        // rotation, also re-fire surface-snap defensively. For
        // rotation, skip surface-snap so the card doesn't drop
        // to whatever the raycast finds at the new XZ.
        if g.state == .ended {
            if !isRotation {
                applySurfaceSnap(to: selected)
            }
            applySmartSnap(to: selected)
            saveScene()  // v2.196: persist after Apple gesture release
        }
    }

    /// What the 2-finger gesture is currently driving.
    private enum TwoFingerMode {
        case idle
        case rotatingCard(CardEntity)
        case panningCamera
    }
    private var twoFingerMode: TwoFingerMode = .idle

    /// v2.172: When 2-finger pan is rotating a card, lock to the
    /// FIRST significant axis (H = pitch, V = lift). Eliminates the
    /// diagonal-drag-does-both-at-once bug.
    private enum CardManipAxis {
        case undetermined
        case pitch   // horizontal drag dominant → tilt
        case lift    // vertical drag dominant → Y translate
    }
    private var cardManipAxis: CardManipAxis = .undetermined
    private var cardManipAccum: CGPoint = .zero
    private static let cardManipAxisThreshold: CGFloat = 8.0

    /// v2.174: true if Apple's entity gestures are currently
    /// claiming the touches (translation in .began/.changed OR
    /// rotation in .began/.changed). When true, our custom
    /// 2-finger pan should bail to avoid pitch/lift firing
    /// simultaneously with Apple's translate/yaw.
    private var entityGestureActive: Bool {
        for g in entityGestures where g.state == .began || g.state == .changed {
            return true
        }
        return false
    }

    @objc private func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
        guard let view = arView else { return }
        let delta = g.translation(in: view)

        switch g.state {
        case .began:
            // Selected card takes priority. Otherwise pan camera.
            if let selected = selectedCardEntity {
                twoFingerMode = .rotatingCard(selected)
                cardManipAxis = .undetermined
                cardManipAccum = .zero
            } else {
                twoFingerMode = .panningCamera
            }
            g.setTranslation(.zero, in: view)

        case .changed:
            switch twoFingerMode {
            case .rotatingCard(let card):
                // v2.174 gesture-exclusivity: if Apple's
                // EntityRotationGesture is currently firing (the
                // user is twisting yaw), skip pitch/lift this
                // frame. Stops the "diagonal-twist fires pitch
                // and yaw simultaneously" conflict the user
                // reported in v2.173. Apple's translate uses
                // 1-finger only so doesn't compete here, but the
                // check covers it defensively.
                if entityGestureActive {
                    g.setTranslation(.zero, in: view)
                    return
                }
                // v2.172 axis lock: accumulate delta until the user
                // has moved >8pt in either axis, then lock to the
                // dominant one for the rest of the gesture. Stops
                // diagonal drags from firing pitch + lift at once.
                if cardManipAxis == .undetermined {
                    cardManipAccum.x += delta.x
                    cardManipAccum.y += delta.y
                    let absX = abs(cardManipAccum.x)
                    let absY = abs(cardManipAccum.y)
                    if max(absX, absY) > Self.cardManipAxisThreshold {
                        cardManipAxis = (absX > absY) ? .pitch : .lift
                    }
                }

                switch cardManipAxis {
                case .pitch:
                    // v2.175: pitch now rotates AROUND THE BOTTOM-
                    // EDGE MIDPOINT, not the card center. Three-step:
                    // 1. Capture pivot (bottom-mid in world)
                    // 2. Apply rotation to orientation
                    // 3. Translate so the new bottom-mid lands at
                    //    the pre-rotation pivot.
                    // Bottom stays anchored — only the top moves.
                    //
                    // Also clamps total tilt to ±70° via the
                    // pitchAngle() decomposition. Past 70° the card
                    // is nearly horizontal and further tilt isn't
                    // useful for stacking — it just flips upside-
                    // down.
                    let bottomLocal = SIMD3<Float>(0, 0, -Self.cardHeight / 2)
                    let pivotBefore = card.entity.convert(position: bottomLocal, to: nil as Entity?)
                    let inputAngle = Float(delta.x) * 0.012
                    let currentTilt = pitchAngle(of: card.entity)
                    // v2.179: max tilt 70° → 90°. Users need a flat
                    // (horizontal) card to make roof pieces that
                    // sit-on-top of A-frame apexes — the v2.175
                    // 70° cap was preventing that core part of
                    // tower construction. Past 90° the card is
                    // upside-down which isn't useful, so the cap
                    // stays at exactly π/2.
                    let maxTilt: Float = .pi / 2
                    let proposed = currentTilt + inputAngle
                    let clamped = max(-maxTilt, min(maxTilt, proposed))
                    let actualAngle = clamped - currentTilt
                    if abs(actualAngle) > 1e-5 {
                        let pitchQ = simd_quatf(angle: actualAngle, axis: pitchAxis(of: card.entity))
                        card.entity.orientation = pitchQ * card.entity.orientation
                        let pivotAfter = card.entity.convert(position: bottomLocal, to: nil as Entity?)
                        card.entity.position += (pivotBefore - pivotAfter)
                    }
                    // Defensive surface re-snap (corrects any small
                    // drift, and re-evaluates whether the bottom is
                    // now over a different supporting card).
                    applySurfaceSnap(to: card)
                    // No A-frame snap during pitch — XZ stays where
                    // the user placed the card. Snap engages on
                    // Apple's translation .ended.

                case .lift:
                    // v2.181: lock button removed. 2-finger vertical
                    // drag always allows free Y translation.
                    // Surface-snap deliberately NOT called here —
                    // it would fight the lift. Smart snap on .ended
                    // pulls the card to whichever surface is below
                    // its new XZ (table, another card's top, etc.).
                    let yDelta: Float = -Float(delta.y) * 0.0005
                    let newY = card.entity.position.y + yDelta
                    card.entity.position.y = max(minCardY(for: card), newY)

                case .undetermined:
                    // Haven't committed to an axis yet — apply nothing.
                    break
                }
                g.setTranslation(.zero, in: view)

            case .panningCamera:
                // v2.187: drag-the-object direction. Matches Apple
                // Maps, Photos pan, AR Quick Look, and every
                // native iOS 3D viewer Ben has used: drag finger
                // right → table moves right (camera target moves
                // LEFT in world; world appears to shift right
                // under the finger).
                //
                // Derived from camera geometry (camAzimuth = CCW
                // angle from +Z to camera offset; camera sits at
                // target + (sin(az), _, cos(az)) * distance,
                // looking AT target):
                //   screen-right in world = ( cos(az), 0, -sin(az))
                //   screen-up    in world = (-sin(az), 0, -cos(az))
                //                           [XZ projection of cam fwd]
                //
                // For UIPan delta (dx right-positive, dy down-
                // positive), drag-the-world world delta is the
                // NEGATION of screen-right and screen-down:
                //   ΔX = -dx*cos(az) - dy*sin(az)
                //   ΔZ =  dx*sin(az) - dy*cos(az)
                //
                // Pinch (zoom) and Apple's entity rotation (yaw)
                // stay simultaneous with this pan — the canonical
                // Photos/Maps combined gesture. See v2.187
                // delegate change.
                let factor: Float = camDistance * 0.0018
                let dx = Float(delta.x) * factor
                let dy = Float(delta.y) * factor
                let cosA = cos(camAzimuth)
                let sinA = sin(camAzimuth)
                cameraTarget.x += -dx * cosA - dy * sinA
                cameraTarget.z +=  dx * sinA - dy * cosA
                g.setTranslation(.zero, in: view)
                updateCameraTransform()

            case .idle:
                break
            }

        case .ended, .cancelled, .failed:
            // v2.176: after a pitch/lift gesture releases, evaluate
            // smart snap. The user has just settled the card's
            // orientation/height; this is the moment to pull it
            // into a stable configuration if a partner is nearby.
            if case .rotatingCard(let card) = twoFingerMode, g.state == .ended {
                applySurfaceSnap(to: card)
                applySmartSnap(to: card)
                saveScene()  // v2.196: persist after pitch/lift release
            }
            twoFingerMode = .idle
            cardManipAxis = .undetermined
            cardManipAccum = .zero

        default:
            break
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let view = arView else { return }
        guard g.state == .ended else { return }
        let point = g.location(in: view)

        // Hit-test for a card under the tap.
        let tappedCard = hitTestCardEntity(at: point)

        // v2.199: tower-builder spawn. Strip selection means
        // "spawn here" — and "here" now includes the top of an
        // existing flat-card platform, not just the table. Tap a
        // horizontal-facing card top with strip cards held → next
        // layer spawns ON TOP of that platform. Scales to any
        // tower height without the user manually lifting cards
        // out of the snap zone of ground-level neighbors.
        //
        // Falls back to the Y=0 plane projection for taps on the
        // table or on non-platform surfaces (tilted cards), so
        // the muscle-memory "tap anywhere on the table to spawn"
        // path is preserved.
        if !session.selectedCards.isEmpty {
            if let world = spawnLocationFromTap(at: point) {
                session.pendingSpawnLocation = world
                return
            }
        }

        // Tap on a card: select/deselect.
        if let card = tappedCard {
            if let current = selectedCardEntity, current === card {
                setSelectedCard(nil)        // tap selected card again → deselect
            } else {
                setSelectedCard(card)       // switch / new selection
            }
            return
        }

        // Tap on empty space with no strip selection: deselect
        // any placed-card selection.
        if selectedCardEntity != nil {
            setSelectedCard(nil)
        }
    }

    /// Walk the hit-test results to find the nearest card-root
    /// ancestor entity.
    private func hitTestCardEntity(at point: CGPoint) -> CardEntity? {
        guard let view = arView else { return nil }
        let hits = view.hitTest(point, query: .nearest, mask: .all)
        for hit in hits {
            var entity: Entity? = hit.entity
            while let e = entity {
                if e.name == "card-root" {
                    if let card = heldCards.first(where: { $0.entity === e })
                        ?? dynamicCards.first(where: { $0.entity === e }) {
                        return card
                    }
                }
                entity = e.parent
            }
        }
        return nil
    }

    @objc private func handlePrimaryPan(_ g: UIPanGestureRecognizer) {
        guard let view = arView else { return }
        let point = g.location(in: view)

        switch g.state {
        case .began:
            // v2.173: when a card is SELECTED, our shouldReceive
            // delegate filters out touches landing on it — those
            // go to Apple's EntityTranslationGestureRecognizer
            // installed via installGestures. Anything that reaches
            // this handler with a selection active is therefore on
            // empty space → orbit camera (preserves selection).
            let hitCard = hitTestCardEntity(at: point)
            if selectedCardEntity != nil {
                panMode = .orbiting
                g.setTranslation(.zero, in: view)
                return
            }

            // No selection: pan a card if one was touched, else orbit.
            // Play-mode grab path: switch a dynamic card to
            // kinematic for the duration of the drag.
            if let card = hitCard {
                if !session.isPaused, dynamicCards.contains(where: { $0 === card }) {
                    switchToKinematic(card)
                    dynamicCards.removeAll(where: { $0 === card })
                    heldCards.append(card)
                }
                panMode = .draggingCards([card])
            } else {
                panMode = .orbiting
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
                let dx = world.x - first.entity.position.x
                let dz = world.z - first.entity.position.z
                for c in cards {
                    c.entity.position.x += dx
                    c.entity.position.z += dz
                    // Clamp Y to keep card and outline above the
                    // table at all times (user explicit rule #10).
                    let minY = minCardY(for: c)
                    if c.entity.position.y < minY {
                        c.entity.position.y = minY
                    }
                    // v2.172: after every XZ move, re-evaluate the
                    // surface below the card and snap the bottom
                    // edge to it (when locked). Lets the user slide
                    // a card off the table onto the top of another
                    // card without any vertical fiddling — bottom
                    // rides whatever's underneath.
                    applySurfaceSnap(to: c)
                }
            case .idle:
                break
            }

        case .ended, .cancelled, .failed:
            // In PAUSE mode: leave the dragged card kinematic
            // where it is — playground mode, no commit yet.
            // In PLAY mode: if a single card was transiently
            // grabbed from dynamic, transition it back to dynamic.
            if case .draggingCards(let cards) = panMode,
               !session.isPaused,
               cards.count == 1,
               let card = cards.first,
               heldCards.contains(where: { $0 === card }) {
                // Re-engage physics on the single card.
                if var body = card.entity.components[PhysicsBodyComponent.self] {
                    body.mode = .dynamic
                    body.isContinuousCollisionDetectionEnabled = true
                    card.entity.components.set(body)
                }
                heldCards.removeAll(where: { $0 === card })
                dynamicCards.append(card)
            }
            panMode = .idle

        default:
            break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard g.scale > 0 else { return }
        // Pinch ALWAYS zooms camera. v2.172 dropped pinch-for-yaw
        // (which was non-standard). v2.173 routes yaw through
        // Apple's EntityRotationGestureRecognizer attached per-
        // selected-card via installGestures.
        camDistance = max(Self.camDistanceMin,
                          min(Self.camDistanceMax, camDistance / Float(g.scale)))
        g.scale = 1.0
        updateCameraTransform()
    }

    /// World-Y of the card's LOWEST corner (across all 8 box
    /// corners). v2.198: this is what should anchor to a support
    /// surface, not the bottom-edge midpoint. For a tilted card,
    /// the bottom-face corners offset along local Y direction sit
    /// up to cardThick/2 * sin(tilt) BELOW the bottom-edge
    /// midpoint in world Y. If surface-snap targets the bottom-
    /// edge midpoint, a tilted card's actual lowest point ends up
    /// below the clearance plane — visually "the new card snaps
    /// to slightly above the bottom" of a leaning neighbor (the
    /// user's report). Anchoring on lowest corner unifies the Y
    /// position of every card's actual lowest point.
    private func lowestWorldY(of entity: Entity) -> Float {
        let hw = Self.cardWidth  / 2
        let ht = Self.cardThick  / 2
        let hh = Self.cardHeight / 2
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>( hw,  ht,  hh), SIMD3<Float>( hw,  ht, -hh),
            SIMD3<Float>( hw, -ht,  hh), SIMD3<Float>( hw, -ht, -hh),
            SIMD3<Float>(-hw,  ht,  hh), SIMD3<Float>(-hw,  ht, -hh),
            SIMD3<Float>(-hw, -ht,  hh), SIMD3<Float>(-hw, -ht, -hh),
        ]
        var minY = Float.greatestFiniteMagnitude
        for c in corners {
            let world = entity.convert(position: c, to: nil as Entity?)
            if world.y < minY { minY = world.y }
        }
        return minY
    }

    /// Minimum world-Y for the card's CENTER given clearance for
    /// the outline halo. Hard floor — bottoms out at table level.
    /// v2.198: orientation-aware AND corner-aware. Returns the
    /// center.y at which the card's LOWEST corner sits exactly
    /// at clearance above the table.
    private func minCardY(for card: CardEntity) -> Float {
        let lowest = lowestWorldY(of: card.entity)
        // How far below the center is the lowest corner?
        let belowCenter = card.entity.position.y - lowest
        return belowCenter + Self.minClearance
    }

    /// Fallback when no card is available (called from 2-finger
    /// pan .lift before a selection is established). Uses a
    /// conservative vertical-card extent.
    private func minCardYConservative() -> Float {
        return Self.cardHeight * 0.5 + Self.minClearance
    }

    // MARK: Surface snap (v2.172)
    //
    // Cast a ray straight down from the card's bottom-edge
    // midpoint and find the top of the nearest collision (the
    // tabletop OR the top of another card under this one).
    // Returns nil only if nothing is in range — defensive, the
    // table is always present.
    /// Result of casting a ray straight down from a card's bottom-
    /// edge midpoint: the Y where the ray hit something, plus
    /// whether that surface is the table (true) or another card
    /// (false). The distinction lets applySurfaceSnap use the
    /// halo-safe clearance only on the table — card-on-card
    /// contacts get a tiny air-gap so stacked cards actually touch.
    private struct SurfaceHit {
        let y: Float
        let isTable: Bool
    }

    private func surfaceYBelow(card: CardEntity) -> SurfaceHit? {
        guard let arView = self.arView else { return nil }
        // v2.193: reverted v2.192's multi-point probe. Multi-point
        // caused regressions: corner probes near the edge of a
        // supporting card sometimes hit a TALLER nearby card,
        // jacking up the placed card to that taller support
        // instead of resting it on its intended support. Back to
        // a single ray from the downward face center, which is
        // the most "intended support" point for the card.
        let lowestFace = downwardFaceCenter(of: card.entity)
        let origin = SIMD3<Float>(lowestFace.x, lowestFace.y + 0.01, lowestFace.z)
        let hits = arView.scene.raycast(
            origin: origin,
            direction: SIMD3<Float>(0, -1, 0),
            length: 2.0,
            query: .all,
            mask: .default,
            relativeTo: nil
        )
        for hit in hits {
            var e: Entity? = hit.entity
            var isSelf = false
            var isCard = false
            while let cur = e {
                if cur.name == "card-root" {
                    if cur === card.entity { isSelf = true } else { isCard = true }
                    break
                }
                e = cur.parent
            }
            if !isSelf {
                return SurfaceHit(y: hit.position.y, isTable: !isCard)
            }
        }
        return nil
    }

    /// Probe points for surfaceYBelow's multi-point raycast: the
    /// orientation-aware downward face's center plus its 4 corners.
    /// For a vertical card the "downward face" is the bottom edge
    /// strip (cardWidth × cardThick); for a horizontal card it's
    /// the broad bottom face (cardWidth × cardHeight). Either way
    /// we probe the full extent so any corner over a supporting
    /// card pulls the whole card to that support's level.
    private func downwardFaceProbePoints(of entity: Entity) -> [SIMD3<Float>] {
        // Identify which of the 6 local-frame face centers has the
        // lowest world Y. That's the downward face.
        let faceLocalCenters: [SIMD3<Float>] = [
            SIMD3<Float>( Self.cardWidth  / 2, 0, 0),
            SIMD3<Float>(-Self.cardWidth  / 2, 0, 0),
            SIMD3<Float>(0,  Self.cardThick / 2, 0),
            SIMD3<Float>(0, -Self.cardThick / 2, 0),
            SIMD3<Float>(0, 0,  Self.cardHeight / 2),
            SIMD3<Float>(0, 0, -Self.cardHeight / 2),
        ]
        var bestIdx = 0
        var bestY = Float.greatestFiniteMagnitude
        for (i, faceCenter) in faceLocalCenters.enumerated() {
            let world = entity.convert(position: faceCenter, to: nil as Entity?)
            if world.y < bestY {
                bestY = world.y
                bestIdx = i
            }
        }
        let bestFaceCenter = faceLocalCenters[bestIdx]
        // The downward face is perpendicular to whichever axis has
        // bestFaceCenter's nonzero coordinate. The corners vary the
        // other two axes by ±extent.
        let halfExtents = SIMD3<Float>(
            Self.cardWidth  / 2,
            Self.cardThick  / 2,
            Self.cardHeight / 2
        )
        var perpAxis = 0
        if abs(bestFaceCenter.y) > 0 { perpAxis = 1 }
        if abs(bestFaceCenter.z) > 0 { perpAxis = 2 }
        let otherAxes = [0, 1, 2].filter { $0 != perpAxis }
        var probes: [SIMD3<Float>] = [entity.convert(position: bestFaceCenter, to: nil as Entity?)]
        for sa: Float in [-1, 1] {
            for sb: Float in [-1, 1] {
                var corner = bestFaceCenter
                let ax0 = otherAxes[0], ax1 = otherAxes[1]
                if ax0 == 0 { corner.x = sa * halfExtents.x }
                else if ax0 == 1 { corner.y = sa * halfExtents.y }
                else { corner.z = sa * halfExtents.z }
                if ax1 == 0 { corner.x = sb * halfExtents.x }
                else if ax1 == 1 { corner.y = sb * halfExtents.y }
                else { corner.z = sb * halfExtents.z }
                probes.append(entity.convert(position: corner, to: nil as Entity?))
            }
        }
        return probes
    }

    // v2.183: orientation-aware face centers. For sit-on-top
    // snapping, we want the face that's currently facing UP on
    // the supporting card (and DOWN on our card), not the
    // local-frame +Z/-Z edge. Examples:
    //   - Vertical card: upward face is the top edge (+Z face).
    //   - Tilted card: upward face is still the top edge (+Z
    //     face has highest Y when card is mostly upright).
    //   - Horizontal card (lying flat with broad face up): upward
    //     face is the broad face (+Y face), NOT the back edge.
    // Picks among all six box faces; returns the world center of
    // whichever has the most-extreme world-Y in the requested
    // direction (+1 = upward, -1 = downward).
    private func extremeFaceCenter(of entity: Entity, towardWorldY sign: Float) -> SIMD3<Float> {
        let faces: [SIMD3<Float>] = [
            SIMD3<Float>( Self.cardWidth  / 2, 0, 0),
            SIMD3<Float>(-Self.cardWidth  / 2, 0, 0),
            SIMD3<Float>(0,  Self.cardThick / 2, 0),
            SIMD3<Float>(0, -Self.cardThick / 2, 0),
            SIMD3<Float>(0, 0,  Self.cardHeight / 2),
            SIMD3<Float>(0, 0, -Self.cardHeight / 2),
        ]
        var best: (point: SIMD3<Float>, score: Float)? = nil
        for face in faces {
            let world = entity.convert(position: face, to: nil as Entity?)
            let score = world.y * sign
            if best == nil || score > best!.score {
                best = (world, score)
            }
        }
        return best!.point
    }
    private func upwardFaceCenter(of entity: Entity) -> SIMD3<Float> {
        extremeFaceCenter(of: entity, towardWorldY:  1)
    }
    private func downwardFaceCenter(of entity: Entity) -> SIMD3<Float> {
        extremeFaceCenter(of: entity, towardWorldY: -1)
    }

    /// World-space normal of the face whose normal points MOST in
    /// the +Y direction. Used to decide whether a placed card can
    /// serve as a platform for the next spawn layer — a card whose
    /// top normal has y > 0.85 is "horizontal enough" (within ~32°
    /// of perfectly flat) that spawning cards above it produces a
    /// stable next layer; tilted cards (leaning A-frame partners,
    /// vertical singles) return small y and don't qualify.
    private func upwardFaceWorldNormal(of entity: Entity) -> SIMD3<Float> {
        let normals: [SIMD3<Float>] = [
            SIMD3<Float>( 1, 0, 0), SIMD3<Float>(-1, 0, 0),
            SIMD3<Float>( 0, 1, 0), SIMD3<Float>( 0,-1, 0),
            SIMD3<Float>( 0, 0, 1), SIMD3<Float>( 0, 0,-1),
        ]
        var best: (world: SIMD3<Float>, y: Float)? = nil
        for n in normals {
            let world = entity.convert(direction: n, to: nil as Entity?)
            if best == nil || world.y > best!.y {
                best = (world, world.y)
            }
        }
        return best!.world
    }

    /// A rectangular face of a card, expressed in world space.
    /// Used by sit-on-top to land the card at the NEAREST point on
    /// the support's top face (clamped to its rectangle bounds)
    /// instead of the face center — which the user perceived as
    /// snapping to "the middle" of flat supports.
    private struct CardFaceRect {
        let center: SIMD3<Float>   // world center of the face
        let normal: SIMD3<Float>   // world normal (outward)
        let axisU: SIMD3<Float>    // unit vector along one in-face axis
        let axisV: SIMD3<Float>    // unit vector along the other in-face axis
        let halfU: Float           // half-extent along U
        let halfV: Float           // half-extent along V
    }

    /// Returns the face whose outward normal points MOST in +Y —
    /// the card's "up face" — as a rectangle with center, normal,
    /// and two in-face axes plus half-extents. Lets sit-on-top
    /// snap to the nearest point on the rectangle rather than the
    /// face center.
    private func upwardFaceRect(of entity: Entity) -> CardFaceRect {
        let hw = Self.cardWidth  / 2
        let ht = Self.cardThick  / 2
        let hh = Self.cardHeight / 2
        // (localCenter, localNormal, localU, localV, halfU, halfV)
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Float, Float)] = [
            (SIMD3<Float>( hw, 0, 0), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1), ht, hh),
            (SIMD3<Float>(-hw, 0, 0), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1), ht, hh),
            (SIMD3<Float>(0,  ht, 0), SIMD3<Float>(0,  1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), hw, hh),
            (SIMD3<Float>(0, -ht, 0), SIMD3<Float>(0, -1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), hw, hh),
            (SIMD3<Float>(0, 0,  hh), SIMD3<Float>(0, 0,  1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), hw, ht),
            (SIMD3<Float>(0, 0, -hh), SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), hw, ht),
        ]
        var bestY: Float = -.greatestFiniteMagnitude
        var bestRect: CardFaceRect = CardFaceRect(
            center: .zero, normal: .zero, axisU: .zero, axisV: .zero, halfU: 0, halfV: 0
        )
        for f in faces {
            let worldNormal = entity.convert(direction: f.1, to: nil as Entity?)
            if worldNormal.y > bestY {
                bestY = worldNormal.y
                bestRect = CardFaceRect(
                    center: entity.convert(position: f.0, to: nil as Entity?),
                    normal: worldNormal,
                    axisU: entity.convert(direction: f.2, to: nil as Entity?),
                    axisV: entity.convert(direction: f.3, to: nil as Entity?),
                    halfU: f.4,
                    halfV: f.5
                )
            }
        }
        return bestRect
    }

    /// Closest point on a face rectangle to a query point in world
    /// space. Projects the query onto the face plane, then clamps
    /// to the rectangle's in-face bounds. Returns a point on the
    /// face (including its boundary) — never inside or outside the
    /// rectangle's edges.
    private func nearestPointOnFace(_ face: CardFaceRect, to q: SIMD3<Float>) -> SIMD3<Float> {
        let toQ = q - face.center
        let u = simd_dot(toQ, face.axisU)
        let v = simd_dot(toQ, face.axisV)
        let uClamped = max(-face.halfU, min(face.halfU, u))
        let vClamped = max(-face.halfV, min(face.halfV, v))
        return face.center + face.axisU * uClamped + face.axisV * vClamped
    }

    /// Resolve a screen-space tap to a spawn location in world.
    ///
    /// Why this matters: tower building beyond the first layer
    /// kept failing because cards spawned at table-level Y=0 had
    /// to be manually lifted ~18-25cm up into the next layer's
    /// snap zone before A-frame/sit-on-top could engage. Users
    /// don't know about 2-finger vertical lift, and even when
    /// they do, the constant fight against side-by-side snaps
    /// with ground-level neighbors is friction. Solution: hand
    /// the spawn-location decision back to the user — they point
    /// at the surface they want the next layer on top of.
    ///
    /// Three lookups, in order:
    ///   1. Direct hit-test (v2.199): tap lands ON a horizontal
    ///      platform → spawn ON it. Tap on a tilted card returns
    ///      nil so tap-to-select still works.
    ///   2. Footprint sweep (v2.201): tap projection onto the
    ///      table plane at Y=0 lands INSIDE an existing platform's
    ///      XZ footprint → spawn on that platform. Recognizes
    ///      taps that the user intended for the platform but
    ///      landed slightly off (parallax, small target, occlusion
    ///      by user's finger).
    ///   3. Plane projection (legacy): no platform found → spawn
    ///      at the table-plane projection.
    ///
    /// Returns nil only when a TILTED card was hit directly —
    /// keeps the tap-tilted-card-to-select affordance intact.
    private func spawnLocationFromTap(at point: CGPoint) -> SIMD3<Float>? {
        guard let view = arView else { return nil }

        // 1. Direct screen-space hit.
        let hits = view.hitTest(point, query: .nearest, mask: .all)
        for hit in hits {
            var entity: Entity? = hit.entity
            while let e = entity {
                if e.name == "card-root" {
                    let topNormal = upwardFaceWorldNormal(of: e)
                    if topNormal.y > 0.85 {
                        let topY = upwardFaceCenter(of: e).y
                        return SIMD3<Float>(hit.position.x, topY, hit.position.z)
                    }
                    // Tilted card — let caller handle tap-to-select.
                    return nil
                }
                entity = e.parent
            }
        }

        // 2 + 3. Project to the table plane to find an XZ point,
        // then look for an existing platform that covers it.
        guard let world = view.project(point, ontoPlaneAt: 0) else { return nil }

        // Footprint sweep: raycast straight down from far above
        // through the tap XZ. The first card-root hit with a
        // horizontal upward face is the topmost platform covering
        // that XZ. If found, spawn there.
        let probeOrigin = SIMD3<Float>(world.x, 5.0, world.z)
        let downHits = view.scene.raycast(
            origin: probeOrigin,
            direction: SIMD3<Float>(0, -1, 0),
            length: 10.0,
            query: .all,
            mask: .default,
            relativeTo: nil
        )
        for h in downHits {
            var entity: Entity? = h.entity
            while let e = entity {
                if e.name == "card-root" {
                    let topNormal = upwardFaceWorldNormal(of: e)
                    if topNormal.y > 0.85 {
                        let topY = upwardFaceCenter(of: e).y
                        return SIMD3<Float>(world.x, topY, world.z)
                    }
                    // Topmost card at this XZ is tilted (e.g., an
                    // A-frame leaning card under an unfinished
                    // structure) — fall back to table-level spawn.
                    return world
                }
                entity = e.parent
            }
        }
        return world
    }

    /// Set card.position.y so the card's bottom-edge midpoint
    /// rests on the surface below (table OR top of supporting
    /// card) with a small air gap so the halo doesn't intersect
    /// the surface. v2.181: always on — lock button removed.
    /// During 2-finger vertical drag (.lift), this isn't called
    /// so the user can lift cards freely.
    /// Tiny air-gap above a supporting CARD surface. Halo doesn't
    /// need to clear another card (the card occludes any halo
    /// poking through it), so the only requirement is preventing
    /// collider intersection. 0.5mm is plenty.
    private static let cardStackClearance: Float = 0.0005

    private func applySurfaceSnap(to card: CardEntity) {
        guard let hit = surfaceYBelow(card: card) else { return }
        // v2.198: anchor the LOWEST corner (across all 8 OBB
        // corners) to the support surface, not the bottom-edge
        // midpoint. A tilted card's lowest corner sits up to
        // cardThick/2 * sin(tilt) BELOW its bottom-edge midpoint
        // (~0.5mm at 20° tilt). When surface-snap targeted the
        // midpoint, vertical cards landed at clearance while
        // tilted cards' lowest corners dipped slightly below —
        // visually "the new card snaps to slightly above the
        // bottom" of a leaning neighbor, per the user report.
        // Using lowest-corner unifies the actual lowest point of
        // every card to the same Y across orientations.
        let currentLowestY = lowestWorldY(of: card.entity)
        // v2.188: full minClearance (halo clearance) only when the
        // surface is the table. Card-on-card stacking uses tiny
        // cardStackClearance so cards actually touch their supports
        // — previously the 6mm gap meant stacked cards would drop
        // immediately when physics engaged.
        let clearance = hit.isTable ? Self.minClearance : Self.cardStackClearance
        let targetLowestY = hit.y + clearance
        let dy = targetLowestY - currentLowestY
        card.entity.position.y += dy
        // Safety floor: keep card's lowest corner above the table.
        // Computed AFTER the dy adjustment so it reflects the new
        // orientation/position.
        let minCenter = minCardY(for: card)
        if card.entity.position.y < minCenter {
            card.entity.position.y = minCenter
        }
    }

    // MARK: A-frame partner snap (v2.172)
    //
    // When the selected card is tilted >5° AND there's another
    // placed card within ~4cm whose tilt is roughly the MIRROR of
    // ours (opposite sign, within 10°), snap our X/Z position so
    // the top-edge midpoints meet — forming a stable A-frame.
    //
    // Snap is XZ-only; surface-snap handles the Y. Together they
    // produce the canonical "two cards leaning on each other"
    // pose without manual fiddling.
    // v2.176: generalized snap. Two snap kinds:
    //
    //   A-frame (top ↔ top): both cards tilted in opposite
    //     directions; their tops meet at the apex. Snaps our top-
    //     midpoint to the partner's top-midpoint. XZ-only — Y is
    //     left to surface-snap.
    //
    //   Sit-on-top (our bottom ↔ their top): our card's bottom-
    //     midpoint is at or above the candidate's top. Snaps our
    //     bottom-midpoint onto their top-midpoint, including Y so
    //     the card lands on the supporting surface (e.g., vertical
    //     card resting on a flat roof card, flat roof card resting
    //     on an A-frame apex, next-layer A-frame whose base sits
    //     on a roof). After the XYZ snap, applySurfaceSnap fires
    //     defensively to anchor the bottom exactly at the
    //     supporting card's top + clearance.
    //
    // For each candidate card, both snap kinds are evaluated.
    // Across all candidates and all kinds, the closest valid pair
    // (smallest horizontal distance) wins. The user's "snap to the
    // closest card" intent emerges naturally from picking the
    // minimum-distance valid pairing — favors local geometry.
    private static let snapDistance: Float = 0.12   // 12cm — generic far range (sitOnTop tilted/vertical, spanRoof)
    private static let snapTiltMin: Float = 0.07     // ~4°
    private static let snapMirrorTolerance: Float = 0.35 // ~20°
    /// Two cards whose tops are within this distance are considered
    /// already partnered in an A-frame. A new card cannot A-frame-
    /// snap to a partnered card (its apex is already occupied —
    /// snapping would pull the new card on top of the partner).
    private static let partneredApexDistance: Float = 0.02  // 2cm
    /// Side-by-side snap is tighter than A-frame's general
    /// 12cm range — it's a precise base-adjacency relationship,
    /// not a long-range magnet. User has to drag close to the
    /// cardWidth-radius ring around the candidate for snap to
    /// engage; max pull is 4cm.
    private static let sideBySideTolerance: Float = 0.04 // 4cm
    /// v2.205: aFrame range restored to snapDistance (12cm).
    /// v2.204's 8cm tightening broke the standard "two A-frame
    /// partners close together" snap at the common drag radius
    /// the user actually uses — most A-frame partner placements
    /// approach from 8-12cm out. shareFoot stays tight at 6cm:
    /// it's a structural-contact relationship (bottoms touching
    /// AT a specific shared point) that benefits from requiring
    /// deliberate drag precision.
    private static let aFrameSnapRange: Float = 0.12
    private static let shareFootSnapRange: Float = 0.06
    /// v2.204: a snap target is "occupied" if any OTHER card's
    /// bottom face is within this radius of the proposed target.
    /// Prevents the snap from pulling a new card onto a position
    /// already taken by an existing card in the structure.
    ///
    /// `nonisolated` because this is referenced as a default
    /// parameter value in `slotOccupied(...)`. Default param
    /// values evaluate outside the method's isolation context, so
    /// a MainActor-isolated static (the implicit isolation under
    /// SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor) wouldn't be
    /// reachable. Float is Sendable and immutable; no concurrency
    /// hazard. Same pattern as the existing `nonisolated` Card
    /// struct override (see Models/Card.swift).
    private nonisolated static let occupancyRadius: Float = 0.03  // 3cm

    private enum SmartSnapKind: String {
        case aFrame      // mirror-tilted, TOPS meet at apex (build a new A-frame)
        case shareFoot   // mirror-tilted, BOTTOMS meet at shared foot (extend a row of A-frames)
        case spanRoof    // flat card spans TWO apex supports (each apex under one END of the card)
        case sitOnTop    // our bottom rests on a single candidate's top face
        case sideBySide  // two flat roof tiles, edges touching (cardWidth apart)
    }

    /// XZ distance between two points (Y ignored).
    private func xzDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx * dx + dz * dz)
    }

    /// v2.204: is the proposed snap target already physically
    /// occupied? Walks every OTHER card in the scene and checks if
    /// its bottom-face center is within `radius` of `target`. A
    /// "yes" means snapping there would place our card inside (or
    /// on top of) an existing card — the bad behavior the user
    /// reported when building taller towers. Snaps that fail this
    /// check are silently skipped; the user's manual placement is
    /// honored instead.
    ///
    /// Excludes `self` (the card being snapped) and `ignoring`
    /// (the snap's intentional partner, e.g., the support whose
    /// top we're sitting on — sit-on-top to apex card X is fine
    /// even though X's bottom is somewhere else nearby).
    private func slotOccupied(
        at target: SIMD3<Float>,
        excluding ourCard: CardEntity,
        ignoring: Entity? = nil,
        in others: [CardEntity],
        radius: Float = HouseOfCardsCoordinator.occupancyRadius
    ) -> Bool {
        for o in others {
            if o === ourCard { continue }
            if let ignored = ignoring, o.entity === ignored { continue }
            let oBottom = downwardFaceCenter(of: o.entity)
            let dx = target.x - oBottom.x
            let dy = target.y - oBottom.y
            let dz = target.z - oBottom.z
            if sqrt(dx * dx + dy * dy + dz * dz) < radius {
                return true
            }
        }
        return false
    }

    /// True if `c` is already in an A-frame with some other card
    /// in `candidates` — meaning their top midpoints are coincident
    /// (within partneredApexDistance) and their tilts are mirror.
    private func isAlreadyPartnered(_ c: CardEntity, in candidates: [CardEntity]) -> Bool {
        let topLocal = SIMD3<Float>(0, 0, Self.cardHeight / 2)
        let cTop = c.entity.convert(position: topLocal, to: nil as Entity?)
        let cTilt = pitchAngle(of: c.entity)
        guard abs(cTilt) > Self.snapTiltMin else { return false }
        for other in candidates {
            if other === c { continue }
            let oTilt = pitchAngle(of: other.entity)
            guard abs(oTilt) > Self.snapTiltMin else { continue }
            guard cTilt * oTilt < 0 else { continue }
            let oTop = other.entity.convert(position: topLocal, to: nil as Entity?)
            if simd_length(oTop - cTop) < Self.partneredApexDistance {
                return true
            }
        }
        return false
    }

    private func applySmartSnap(to card: CardEntity) {
        // v2.205: user-controllable snap. When the session's
        // master snap switch is OFF, every gesture release leaves
        // the card exactly where the user placed it. Restores the
        // physics-sandbox feel for creative play.
        guard session.snapsEnabled else { return }

        let bottomLocal = SIMD3<Float>(0, 0, -Self.cardHeight / 2)
        let topLocal    = SIMD3<Float>(0, 0,  Self.cardHeight / 2)

        let ourBottom = card.entity.convert(position: bottomLocal, to: nil as Entity?)
        let ourTop    = card.entity.convert(position: topLocal,    to: nil as Entity?)
        let ourTilt   = pitchAngle(of: card.entity)
        // v2.183: orientation-aware face centers for sit-on-top.
        // For a horizontal card lying flat, the bottom-edge
        // midpoint is one EDGE of the broad face, not the broad
        // face center — that produced the "halfway up" snap target
        // the user reported. Now sit-on-top uses the face that's
        // actually facing UP (or DOWN) for the given orientation.
        let ourBottomFace = downwardFaceCenter(of: card.entity)

        let candidates = (heldCards + dynamicCards).filter { $0 !== card }
        struct Best {
            let kind: SmartSnapKind
            let target: SIMD3<Float>
            let ourFeature: SIMD3<Float>
            let dist: Float
            let partner: Entity
            /// Used by spanRoof only: the SECOND apex point of the
            /// pair the flat card is spanning. Lets the apply
            /// branch yaw-align the card so its long axis points
            /// along the apex line. Nil for all other snap kinds.
            let auxPoint: SIMD3<Float>?

            init(kind: SmartSnapKind, target: SIMD3<Float>, ourFeature: SIMD3<Float>, dist: Float, partner: Entity, auxPoint: SIMD3<Float>? = nil) {
                self.kind = kind
                self.target = target
                self.ourFeature = ourFeature
                self.dist = dist
                self.partner = partner
                self.auxPoint = auxPoint
            }
        }
        // v2.193 diagnostics: track the closest sit-on-top
        // candidate that was REJECTED (out of range or Y check
        // failed). On a "no candidate" failure, the print includes
        // this info so we can see why nothing engaged.
        var nearestSitDist: Float = .greatestFiniteMagnitude
        var nearestSitReason: String = "no candidates"
        var best: Best? = nil

        for c in candidates {
            let theirTop  = c.entity.convert(position: topLocal,    to: nil as Entity?)
            let theirTilt = pitchAngle(of: c.entity)

            // 1) A-frame top-to-top. Both tilted, mirror sign,
            //    similar magnitude. SKIP if the candidate is already
            //    partnered in an A-frame (its apex is occupied —
            //    snapping would pull our card onto its partner,
            //    producing a stack instead of a new pyramid).
            //    Sit-on-top below is still allowed against
            //    partnered candidates (that's how you place a roof
            //    card on an A-frame apex).
            // Helpers shared between A-frame and share-foot below.
            let theirBottomForMirror = c.entity.convert(position: bottomLocal, to: nil as Entity?)
            let dTopXZ: Float = {
                let dx = theirTop.x - ourTop.x
                let dz = theirTop.z - ourTop.z
                return sqrt(dx * dx + dz * dz)
            }()
            let dBottomXZ: Float = {
                let dx = theirBottomForMirror.x - ourBottom.x
                let dz = theirBottomForMirror.z - ourBottom.z
                return sqrt(dx * dx + dz * dz)
            }()

            // 1a) A-frame TOP-to-TOP. Both tilted, mirror sign,
            //     similar magnitude. The user is closer to the
            //     partner's TOP than their BOTTOM — that signals
            //     "we're forming an apex." SKIP if the partner
            //     already has an A-frame mate (their apex is
            //     occupied; snapping us there would put us on top
            //     of the mate's stack, not a new pyramid).
            //
            //     v2.205 LAYER-AWARE: also require the partner's
            //     bottom to be at OUR layer (Y within ±2cm of
            //     ours). A layer-0 partner with bottom at table
            //     level shouldn't aFrame-snap with a layer-2 card
            //     even if their tops happen to be close — they're
            //     on different tower layers.
            let layerAlignedTops = abs(theirBottomForMirror.y - ourBottom.y) < 0.02
            if abs(ourTilt) > Self.snapTiltMin,
               abs(theirTilt) > Self.snapTiltMin,
               ourTilt * theirTilt < 0,
               abs(abs(theirTilt) - abs(ourTilt)) < Self.snapMirrorTolerance,
               layerAlignedTops,
               dTopXZ <= dBottomXZ,
               !isAlreadyPartnered(c, in: candidates),
               !slotOccupied(at: theirTop, excluding: card, ignoring: c.entity, in: candidates) {
                if dTopXZ < Self.aFrameSnapRange, best == nil || dTopXZ < best!.dist {
                    best = Best(kind: .aFrame, target: theirTop, ourFeature: ourTop, dist: dTopXZ, partner: c.entity)
                }
            }

            // 1b) Share-foot: BOTTOM-to-BOTTOM for mirror-tilted
            //     cards. This is the snap that builds a ROW of
            //     adjacent A-frames — the inner cards of two
            //     neighboring A-frames share a foot point on the
            //     table (or on a flat roof at layer 1+). Two
            //     mirror-tilted cards whose tops point AWAY from
            //     each other and whose bottoms coincide.
            //
            //     Gate: user is closer to the partner's BOTTOM than
            //     their TOP — that signals "we're building outward
            //     from this card's foot," not "forming an apex
            //     above it." Unlike A-frame, share-foot is ALLOWED
            //     for already-partnered candidates (extending the
            //     row is the whole point).
            //
            //     Target: our bottom snaps to their bottom XZ.
            //     The Y is preserved (surface-snap handles altitude
            //     so the new card lands on whatever surface is
            //     below the snapped XZ — table at layer 0, flat
            //     roof at layer 1+).
            //     v2.204: range tightened to 6cm (was 12cm). The
            //     foot-to-foot relationship is a precise structural
            //     contact; loose magnetism here is what was
            //     producing the "snap to 12cm away from the
            //     partner" complaint. Occupancy check: skip if
            //     some OTHER card's bottom is already at this
            //     foot point.
            //     v2.205 LAYER-AWARE: also require the partner's
            //     bottom Y to match ours (within ±2cm). Two
            //     cards sharing a foot must be at the same
            //     elevation.
            if abs(ourTilt) > Self.snapTiltMin,
               abs(theirTilt) > Self.snapTiltMin,
               ourTilt * theirTilt < 0,
               abs(abs(theirTilt) - abs(ourTilt)) < Self.snapMirrorTolerance,
               layerAlignedTops,
               dBottomXZ < dTopXZ {
                let target = SIMD3<Float>(theirBottomForMirror.x, ourBottom.y, theirBottomForMirror.z)
                if dBottomXZ < Self.shareFootSnapRange,
                   !slotOccupied(at: target, excluding: card, ignoring: c.entity, in: candidates),
                   best == nil || dBottomXZ < best!.dist {
                    best = Best(kind: .shareFoot, target: target, ourFeature: ourBottom, dist: dBottomXZ, partner: c.entity)
                }
            }

            // 2) Sit-on-top: our downward face center meets the
            //    NEAREST POINT on the candidate's upward face
            //    rectangle (v2.200) — not the face center. Lets
            //    the user place a card AT THE EDGE of a flat
            //    support to start the next A-frame, not always at
            //    the geometric middle.
            //
            //    Y-gate (v2.201): restored. The card must be at or
            //    above the candidate's top (within 1cm tolerance)
            //    to fire sit-on-top. Horizontal cards bypass the
            //    Y-gate (they're laying flat onto a support and
            //    range 25cm reaches across the structure). The
            //    v2.200 lift-escape priority was reverted — it
            //    caused every ground-level spawn to fly up onto
            //    the nearest tall structure, which is the opposite
            //    of the user's intent in most cases. Tower
            //    building flows through platform-tap spawn
            //    (spawnLocationFromTap, v2.199 + v2.201) and
            //    explicit 2-finger vertical lift, both of which
            //    place the card AT the destination layer so the
            //    standard Y-gate clears.
            let theirTopRect = upwardFaceRect(of: c.entity)
            let theirTopNearest = nearestPointOnFace(theirTopRect, to: ourBottomFace)
            let isHorizontalish = abs(abs(ourTilt) - .pi / 2) < 0.3
            let canSit: Bool = isHorizontalish
                || (ourBottomFace.y >= theirTopRect.center.y - 0.01)
            // XZ distance to the nearest point on the support
            // face. v2.200 change preserved: snap target is the
            // edge-aware nearest point, not the face center.
            let dxS = theirTopNearest.x - ourBottomFace.x
            let dzS = theirTopNearest.z - ourBottomFace.z
            let dS = sqrt(dxS * dxS + dzS * dzS)
            let range: Float = isHorizontalish ? 0.25 : Self.snapDistance
            // Track nearest for diagnostics (whether we used it or not).
            if dS < nearestSitDist {
                nearestSitDist = dS
                if !canSit {
                    nearestSitReason = "Y-check (bottom \(String(format: "%.3f", ourBottomFace.y)) below top \(String(format: "%.3f", theirTopRect.center.y)))"
                } else if dS >= range {
                    nearestSitReason = "out of range (\(String(format: "%.3f", dS))m > \(String(format: "%.2f", range))m)"
                } else {
                    nearestSitReason = "fired"
                }
            }
            if canSit, dS < range,
               !slotOccupied(at: theirTopNearest, excluding: card, ignoring: c.entity, in: candidates),
               best == nil || dS < best!.dist {
                best = Best(kind: .sitOnTop, target: theirTopNearest, ourFeature: ourBottomFace, dist: dS, partner: c.entity)
            }

            // 3) Side-by-side: TWO FLAT ROOF TILES, edges touching.
            //
            //    v2.202: restricted to horizontal cards only. The
            //    prior "any tilts within 20° of each other"
            //    semantic was the source of the user's "snaps the
            //    card cardWidth away when I want it touching"
            //    complaint — vertical + slightly-tilted cards
            //    qualified, and the cardWidth offset is wrong for
            //    every shape EXCEPT laying flat roof tiles next
            //    to each other. Adjacent A-frames now use
            //    share-foot (snap kind 1b above) instead.
            //
            //    The cardWidth offset is correct here: two flat
            //    cards (broad face up) placed edge-to-edge along
            //    their short axis are exactly cardWidth apart
            //    center-to-center.
            //
            //    Gates: both cards horizontal (|tilt| within ~17°
            //    of π/2), bottoms at similar heights (within 2cm).
            //    Tolerance stays 4cm — precise relationship, not
            //    a long-range magnet.
            let theirBottom = c.entity.convert(position: bottomLocal, to: nil as Entity?)
            let yAligned = abs(ourBottom.y - theirBottom.y) < 0.02
            let ourFlat   = abs(abs(ourTilt)   - .pi / 2) < 0.3
            let theirFlat = abs(abs(theirTilt) - .pi / 2) < 0.3
            if yAligned, ourFlat, theirFlat {
                let dirToOurs = SIMD3<Float>(
                    ourBottom.x - theirBottom.x, 0, ourBottom.z - theirBottom.z
                )
                let len = simd_length(dirToOurs)
                if len > 1e-3 {
                    let dirUnit = dirToOurs / len
                    let target = theirBottom + Self.cardWidth * dirUnit
                    let d = simd_length(target - ourBottom)
                    if d < Self.sideBySideTolerance,
                       !slotOccupied(at: target, excluding: card, ignoring: c.entity, in: candidates),
                       best == nil || d < best!.dist {
                        best = Best(kind: .sideBySide, target: target, ourFeature: ourBottom, dist: d, partner: c.entity)
                    }
                }
            }
        }

        // 4) Span-roof: a HORIZONTAL card resting on TWO support
        //    points, with each point under one END of the card
        //    (point-to-point ≈ cardHeight, the card's long axis).
        //    A single-support sit-on-top would place the support
        //    at the card's CENTER, leaving both ends in mid-air —
        //    the "physically impossible" result the user flagged
        //    in v2.202. Span-roof targets the MIDPOINT between
        //    two support points and yaw-aligns the card so its
        //    long axis points along the pair line.
        //
        //    v2.206: support points are richer than just
        //    "upwardFaceCenter of each candidate." A horizontal
        //    flat card (already on the table at layer N) provides
        //    TWO support points — one at each long-axis END —
        //    because a NEW flat card can rest on one end of an
        //    existing flat card and bridge to a separate support.
        //    This is the canonical "stack the second roof tile
        //    partially on the first, partially on the next apex"
        //    pattern the user described: layer 1 has flat-card-1
        //    spanning A1+A2, and the user wants flat-card-2 to
        //    span A2+A3 by resting its left end on flat-card-1's
        //    right end (the A2-side end) and its right end on
        //    A3's bare apex. Without flat-card-end support points
        //    that pair never matched the pair-distance check.
        //
        //    Tilted/vertical candidates still contribute a single
        //    support point (their top edge midpoint) — they don't
        //    have a "long axis end" in the same sense.
        //
        //    Only fires for horizontal "us" cards. Runs as a
        //    post-pass because it needs PAIRS of candidates.
        let isHorizontalishUs = abs(abs(ourTilt) - .pi / 2) < 0.3
        if isHorizontalishUs {
            var apexPoints: [(point: SIMD3<Float>, partner: Entity)] = []
            for c in candidates {
                let topNormal = upwardFaceWorldNormal(of: c.entity)
                let topRect = upwardFaceRect(of: c.entity)
                if topNormal.y > 0.85 {
                    // Horizontal candidate — contributes TWO
                    // support points at its long-axis ends.
                    // Long axis in local space is +Z (the card's
                    // "top edge" before stand-up rotation; after
                    // stand-up + horizontal-pitch it lies in the
                    // horizontal plane).
                    let worldLong = c.entity.convert(direction: SIMD3<Float>(0, 0, 1), to: nil as Entity?)
                    let worldLongXZ = SIMD3<Float>(worldLong.x, 0, worldLong.z)
                    let lenXZ = simd_length(worldLongXZ)
                    if lenXZ > 1e-4 {
                        let unit = worldLongXZ / lenXZ
                        let half = Self.cardHeight / 2
                        let end1 = SIMD3<Float>(
                            topRect.center.x + unit.x * half,
                            topRect.center.y,
                            topRect.center.z + unit.z * half
                        )
                        let end2 = SIMD3<Float>(
                            topRect.center.x - unit.x * half,
                            topRect.center.y,
                            topRect.center.z - unit.z * half
                        )
                        apexPoints.append((end1, c.entity))
                        apexPoints.append((end2, c.entity))
                    } else {
                        apexPoints.append((topRect.center, c.entity))
                    }
                } else {
                    // Tilted / vertical candidate — single top
                    // edge midpoint as before.
                    apexPoints.append((topRect.center, c.entity))
                }
            }
            // Tolerances:
            //   pair distance ≈ cardHeight ± 1.5cm (the natural
            //     apex spacing of two adjacent A-frames at the
            //     canonical 30° lean is exactly cardHeight)
            //   our XZ-to-midpoint distance < 12cm (snapDistance)
            // v2.205: tolerance widened from 1.5cm to 3cm.
            // Real-world A-frame builds rarely produce apices
            // EXACTLY cardHeight apart — varying lean angles
            // (28-32° rather than perfect 30°) easily produce
            // spacings 7-10cm. The tighter tolerance was
            // preventing spanRoof from firing on the user's
            // actual towers.
            let spanLengthTolerance: Float = 0.03
            let spanRangeXZ: Float = Self.snapDistance
            for i in 0..<apexPoints.count {
                for j in (i + 1)..<apexPoints.count {
                    // v2.206: skip pairs whose two points are
                    // contributed by the SAME partner card. A
                    // horizontal candidate emits its two long-axis
                    // ends — and those are exactly cardHeight
                    // apart by construction (that's just the
                    // card's length), which would match the
                    // pair-distance gate and propose a degenerate
                    // "span the card by itself" snap.
                    if apexPoints[i].partner === apexPoints[j].partner { continue }
                    let p1 = apexPoints[i].point
                    let p2 = apexPoints[j].point
                    let pairDist = xzDistance(p1, p2)
                    if abs(pairDist - Self.cardHeight) > spanLengthTolerance { continue }
                    let midpoint = SIMD3<Float>(
                        (p1.x + p2.x) * 0.5,
                        (p1.y + p2.y) * 0.5,
                        (p1.z + p2.z) * 0.5
                    )
                    // Skip pairs we'd snap DOWN onto (no-drop
                    // rule — our flat card sits at Y ≈ 0.006 at
                    // table level; a pair at Y < -0.05 from us
                    // would mean snapping down through the table,
                    // which never happens in this geometry but
                    // keep the symmetry with sit-on-top).
                    let dY = midpoint.y - ourBottomFace.y
                    if dY < -0.05 { continue }
                    let dToMid = xzDistance(ourBottomFace, midpoint)
                    if dToMid >= spanRangeXZ { continue }
                    // Span-roof wins over single sit-on-top
                    // whenever it's a closer XZ match than the
                    // currently-best snap. Standard "lowest dist
                    // wins" — no priority tier.
                    // v2.204: occupancy check — skip if another
                    // card already spans this midpoint (resting on
                    // both apices already). Ignore both apex
                    // partners; they're the supports, not occupants
                    // of the roof slot.
                    let p1Partner = apexPoints[i].partner
                    let p2Partner = apexPoints[j].partner
                    let occupiedByOther = candidates.contains { o in
                        if o === card { return false }
                        if o.entity === p1Partner || o.entity === p2Partner { return false }
                        let oBottom = downwardFaceCenter(of: o.entity)
                        return simd_length(midpoint - oBottom) < Self.occupancyRadius
                    }
                    if occupiedByOther { continue }
                    if best == nil || dToMid < best!.dist {
                        best = Best(kind: .spanRoof, target: midpoint, ourFeature: ourBottomFace, dist: dToMid, partner: apexPoints[i].partner, auxPoint: p2)
                    }
                }
            }
        }

        guard let snap = best else {
            let horiz = abs(abs(ourTilt) - .pi / 2) < 0.3 ? "(horizontal)" : ""
            print("[HoB] Smart snap MISS: tilt=\(String(format: "%.2f", ourTilt))rad\(horiz) ourBottomY=\(String(format: "%.3f", ourBottomFace.y)) nearestSit=\(String(format: "%.3f", nearestSitDist))m reason=\(nearestSitReason)")
            return
        }

        // Apply the snap.
        switch snap.kind {
        case .aFrame:
            // v2.188: yaw-align FIRST so both cards' broad faces
            // share the same world-Y rotation. Without this, even
            // a small yaw mismatch between partners separates the
            // apex corners by a few mm (cardWidth/2 * sin(yawDiff))
            // — physics then fails to find a stable apex contact
            // and the cards fall.
            let partnerYaw = yawAngle(of: snap.partner)
            let ourCurrentYaw = yawAngle(of: card.entity)
            let yawDelta = wrapAngle(partnerYaw - ourCurrentYaw)
            // v2.191: only align SMALL yaw drifts (< 30°). A real
            // card-house A-frame has its two partners yawed 180°
            // apart so their bodies extend in opposite Z directions
            // (no apex body-overlap, both fronts face outward).
            // The user explicitly chose a 180° yaw to get that
            // configuration; v2.188's unconditional yaw-align was
            // flipping it back to 0° and breaking the orientation.
            // Small accidental twist (< 30°) still gets aligned.
            if abs(yawDelta) > 0.005, abs(yawDelta) < .pi / 6 {
                let pivotBefore = card.entity.convert(position: bottomLocal, to: nil as Entity?)
                let yawQ = simd_quatf(angle: yawDelta, axis: SIMD3<Float>(0, 1, 0))
                card.entity.orientation = yawQ * card.entity.orientation
                let pivotAfter = card.entity.convert(position: bottomLocal, to: nil as Entity?)
                card.entity.position += (pivotBefore - pivotAfter)
            }
            // v2.183 pitch tilt-snap: align our pitch to mirror the
            // partner's. Rotation around the bottom-edge pivot
            // keeps our base anchored while the top rotates into
            // mirror position. After the orientation change, our
            // top edge is somewhere new — re-snap XZ so the new
            // top edge meets the partner's apex.
            let partnerTilt = pitchAngle(of: snap.partner)
            let ourCurrentTilt = pitchAngle(of: card.entity)
            let tiltDelta = -partnerTilt - ourCurrentTilt
            if abs(tiltDelta) > 0.005 {
                let pivotBefore = card.entity.convert(position: bottomLocal, to: nil as Entity?)
                let pitchQ = simd_quatf(angle: tiltDelta, axis: pitchAxis(of: card.entity))
                card.entity.orientation = pitchQ * card.entity.orientation
                let pivotAfter = card.entity.convert(position: bottomLocal, to: nil as Entity?)
                card.entity.position += (pivotBefore - pivotAfter)
            }
            let ourTopAfter = card.entity.convert(position: topLocal, to: nil as Entity?)
            let xz = snap.target - ourTopAfter
            card.entity.position.x += xz.x
            card.entity.position.z += xz.z

        case .sitOnTop:
            // Full XYZ — our (downward) face center lands on
            // their (upward) face center.
            let offset = snap.target - snap.ourFeature
            card.entity.position += offset

        case .shareFoot:
            // XZ only — our bottom-edge midpoint lands at the
            // partner's bottom-edge midpoint XZ. Tilt is preserved
            // (the user chose it). Y is delegated to surface-snap,
            // so a layer-0 share-foot lands on the table and a
            // layer-1+ share-foot lands on whatever flat support is
            // below the snapped XZ. This is the "extend a row of
            // A-frames" gesture — two mirror-tilted cards sharing
            // a foot point, the canonical adjacent-A-frame seed.
            let offset = snap.target - snap.ourFeature
            card.entity.position.x += offset.x
            card.entity.position.z += offset.z

        case .spanRoof:
            // YAW-ALIGN, then position. The card's long axis
            // (local +Z, which is "up" before standUp and a
            // horizontal axis after stand-up + horizontal pitch)
            // is aligned to point from one apex to the other so
            // the card's two cardHeight/2 ends land ON the apex
            // points. Then we set the entity position so our
            // bottom face center (the broad face facing down)
            // ends up at the apex-midpoint.
            if let p2 = snap.auxPoint {
                let midpoint = snap.target
                // Direction we want our long axis to point.
                let pairDir = SIMD2<Float>(p2.x - midpoint.x, p2.z - midpoint.z)
                let pairLen = simd_length(pairDir)
                if pairLen > 1e-4 {
                    let targetAngle = atan2(pairDir.x, pairDir.y)
                    // Card's current local +Z direction in world.
                    let currentLong = card.entity.convert(direction: SIMD3<Float>(0, 0, 1), to: nil as Entity?)
                    let currentAngle = atan2(currentLong.x, currentLong.z)
                    let rawDelta = wrapAngle(targetAngle - currentAngle)
                    // The long axis has 180° symmetry — flipping
                    // the card end-for-end produces the same span.
                    // Take whichever rotation is smaller.
                    let yawDelta: Float
                    if rawDelta > .pi / 2 {
                        yawDelta = rawDelta - .pi
                    } else if rawDelta < -.pi / 2 {
                        yawDelta = rawDelta + .pi
                    } else {
                        yawDelta = rawDelta
                    }
                    if abs(yawDelta) > 0.005 {
                        let pivotBefore = ourBottomFace
                        let yawQ = simd_quatf(angle: yawDelta, axis: SIMD3<Float>(0, 1, 0))
                        card.entity.orientation = yawQ * card.entity.orientation
                        let pivotAfter = downwardFaceCenter(of: card.entity)
                        card.entity.position += (pivotBefore - pivotAfter)
                    }
                }
                // Now move our (re-computed) bottom face center to
                // the midpoint. Full XYZ — the midpoint's Y is the
                // apex-pair's average Y, which is where the card
                // should sit (resting on both apices).
                let bottomNow = downwardFaceCenter(of: card.entity)
                let offset = midpoint - bottomNow
                card.entity.position += offset
            } else {
                // Defensive: auxPoint missing — fall back to
                // single-target sit-on-top semantics.
                let offset = snap.target - snap.ourFeature
                card.entity.position += offset
            }

        case .sideBySide:
            // XZ only — Y delegated to surface-snap.
            let offset = snap.target - snap.ourFeature
            card.entity.position.x += offset.x
            card.entity.position.z += offset.z
        }
        applySurfaceSnap(to: card)
        // v2.190: final collision-safety pass. The point-to-point
        // snap math is now correct, but a snapped position can
        // still place our body intersecting an unrelated card
        // (e.g., a roof sit-on-top'd on apex 1 whose broad face
        // extends into pyramid 2's column). SAT-based resolve
        // pushes us out of any overlap exceeding cardThick (which
        // is the natural body overlap at an A-frame apex from
        // card thickness — we keep that contact intact).
        resolveCollisions(for: card)
        // Re-floor in case collision-resolve pushed us below the
        // table-clearance level.
        let minCenter = minCardY(for: card)
        if card.entity.position.y < minCenter {
            card.entity.position.y = minCenter
        }
        print("[HoB] Smart snap: \(snap.kind.rawValue), \(String(format: "%.2f", snap.dist))m")
    }

    /// Decompose an entity's orientation to extract its tilt
    /// (signed angle around world X). Approximation valid when
    /// the card's "up" axis (local +Z post-standUp) lies in the
    /// world YZ plane — true for cards manipulated only by pitch
    /// + yaw, which is the only case the playground produces.
    private func pitchAngle(of entity: Entity) -> Float {
        // v2.197: reference forward is now YAW-EXTRACTED, not the
        // current cardForward direction. Past ±π/2 the current
        // cardForward FLIPS in world XZ (it was pointing toward
        // camera, now it's tipped past horizontal and points away),
        // which inverted upForward's sign. That made the gesture
        // clamp see a wrong-sign tilt and apply massive corrective
        // rotations — the "card flashes around" the user reported.
        //
        // Using the yaw-extracted preForward (always pointing in
        // the card's current yaw direction projected onto XZ,
        // regardless of pitch) gives a sign-stable reference. Then
        // saturate to [-π/2, π/2] so past-horizontal cards report
        // a stable boundary value the clamp can converge from.
        let worldUp = entity.convert(direction: SIMD3<Float>(0, 0, 1), to: nil as Entity?)
        let yaw = yawAngle(of: entity)
        let preForwardX = sin(yaw)
        let preForwardZ = cos(yaw)
        let upForward = worldUp.x * preForwardX + worldUp.z * preForwardZ
        let raw = atan2(upForward, worldUp.y)
        // Saturate. Past ±π/2 the card is upside-down — not a
        // valid playable state. The clamp in handleTwoFingerPan
        // .pitch can then steer the orientation back into range
        // by sending a corrective rotation each drag.
        return max(-.pi / 2, min(.pi / 2, raw))
    }

    /// Pitch rotation axis for a card: the card's local +X
    /// direction projected to the horizontal plane and negated.
    /// Negation makes positive-input pitch tilt the top toward
    /// the card's facing direction (matching user intent at any
    /// yaw). The card's local +X direction IS the bottom-edge
    /// line of the card, so rotating around this axis keeps the
    /// entire bottom edge fixed in world — no corner dips into
    /// the table regardless of yaw.
    private func pitchAxis(of entity: Entity) -> SIMD3<Float> {
        let localX = entity.convert(direction: SIMD3<Float>(1, 0, 0), to: nil as Entity?)
        let xz = SIMD3<Float>(localX.x, 0, localX.z)
        let len = simd_length(xz)
        if len > 1e-3 {
            return -(xz / len)
        }
        return SIMD3<Float>(1, 0, 0)
    }

    /// Yaw (signed angle around world Y) of an entity's
    /// orientation, returned in [-π, π]. v2.190: redefined so that
    /// a card with NO additional yaw (just base standUp +
    /// faceCamera) returns 0 — the previous version returned ±π
    /// at the default orientation, which broke yaw-delta math
    /// across the wraparound.
    ///
    /// Derivation: post-standUp+faceCamera, local +X direction in
    /// world is `(-1, 0, 0)`. We want yaw = 0 in that case, so
    /// invert the X component: `atan2(worldLateral.z, -worldLateral.x)`.
    /// CCW yaw +30° → returns +30°; CW -30° → returns -30°.
    private func yawAngle(of entity: Entity) -> Float {
        let worldLateral = entity.convert(direction: SIMD3<Float>(1, 0, 0), to: nil as Entity?)
        return atan2(worldLateral.z, -worldLateral.x)
    }

    /// Wrap an angle delta into [-π, π] so e.g. a card at +179° vs
    /// a partner at -179° resolves as a 2° turn, not 358°.
    private func wrapAngle(_ a: Float) -> Float {
        var v = a
        while v >  .pi { v -= 2 * .pi }
        while v < -.pi { v += 2 * .pi }
        return v
    }

    // MARK: OBB collision resolution (v2.190)
    //
    // After every smart snap, check the snapped card against every
    // other placed card via Separating Axis Theorem (SAT). If our
    // body overlaps another by more than the allowed-overlap
    // threshold (= cardThick, the natural overlap at an A-frame
    // apex from card thickness), push us out along the
    // minimum-translation-vector. Iterates until no offending
    // overlap remains, so resolving against card A doesn't leave
    // us overlapping card B.
    //
    // This is the only mechanism that prevents cards from
    // intersecting in pause mode. Snap math places cards by
    // point-to-point constraints (face center → face center);
    // it has no awareness of full-body overlap. SAT closes that
    // gap and makes the smart-snap output collision-safe.

    private struct OBB {
        let center: SIMD3<Float>
        let halfExtents: SIMD3<Float>
        let axisX: SIMD3<Float>
        let axisY: SIMD3<Float>
        let axisZ: SIMD3<Float>
    }

    private func obb(of entity: Entity) -> OBB {
        return OBB(
            center: entity.position,
            halfExtents: SIMD3<Float>(
                Self.cardWidth  / 2,
                Self.cardThick  / 2,
                Self.cardHeight / 2
            ),
            axisX: entity.convert(direction: SIMD3<Float>(1, 0, 0), to: nil as Entity?),
            axisY: entity.convert(direction: SIMD3<Float>(0, 1, 0), to: nil as Entity?),
            axisZ: entity.convert(direction: SIMD3<Float>(0, 0, 1), to: nil as Entity?)
        )
    }

    /// Separating Axis Theorem test for two OBBs. Returns the
    /// minimum-translation-vector that, when added to `a.center`,
    /// separates the boxes — or nil if they don't overlap.
    private func obbOverlap(_ a: OBB, _ b: OBB) -> SIMD3<Float>? {
        let axes: [SIMD3<Float>] = [
            a.axisX, a.axisY, a.axisZ,
            b.axisX, b.axisY, b.axisZ,
            simd_cross(a.axisX, b.axisX),
            simd_cross(a.axisX, b.axisY),
            simd_cross(a.axisX, b.axisZ),
            simd_cross(a.axisY, b.axisX),
            simd_cross(a.axisY, b.axisY),
            simd_cross(a.axisY, b.axisZ),
            simd_cross(a.axisZ, b.axisX),
            simd_cross(a.axisZ, b.axisY),
            simd_cross(a.axisZ, b.axisZ),
        ]
        let centerDiff = a.center - b.center
        var minOverlap: Float = .infinity
        var minAxis = SIMD3<Float>(0, 0, 0)
        for axis in axes {
            let len = simd_length(axis)
            if len < 1e-6 { continue }  // skip degenerate cross products
            let unit = axis / len
            let projA = abs(simd_dot(a.axisX, unit)) * a.halfExtents.x +
                        abs(simd_dot(a.axisY, unit)) * a.halfExtents.y +
                        abs(simd_dot(a.axisZ, unit)) * a.halfExtents.z
            let projB = abs(simd_dot(b.axisX, unit)) * b.halfExtents.x +
                        abs(simd_dot(b.axisY, unit)) * b.halfExtents.y +
                        abs(simd_dot(b.axisZ, unit)) * b.halfExtents.z
            let centerProj = abs(simd_dot(centerDiff, unit))
            let overlap = projA + projB - centerProj
            if overlap <= 0 { return nil }  // separating axis found
            if overlap < minOverlap {
                minOverlap = overlap
                // Orient axis so adding mtv to a separates it from b.
                let signedDot = simd_dot(centerDiff, unit)
                minAxis = signedDot >= 0 ? unit : -unit
            }
        }
        return minAxis * minOverlap
    }

    /// Push the given card out of overlap with every other placed
    /// card EXCEPT its A-frame partner. Allowed overlap drops to
    /// 0.5mm — basically any visible body overlap gets resolved.
    /// A-frame partners are explicitly skipped because their
    /// natural top-edge contact has ~cardThick body overlap from
    /// thickness + mirror tilt, and resolving that would create
    /// the apex gap the user is trying NOT to have.
    private func resolveCollisions(for card: CardEntity) {
        let allowedOverlap: Float = 0.0005  // 0.5mm — any visible overlap resolved
        let margin: Float = 0.0002
        let allOthers = (heldCards + dynamicCards).filter { $0 !== card }
        // Filter out A-frame partners — see isAFramePartner doc.
        let resolveAgainst = allOthers.filter { !isAFramePartner(card, $0) }
        if resolveAgainst.isEmpty { return }
        let maxIterations = 8
        for _ in 0..<maxIterations {
            let ourBox = obb(of: card.entity)
            var didResolve = false
            for other in resolveAgainst {
                let otherBox = obb(of: other.entity)
                guard let mtv = obbOverlap(ourBox, otherBox) else { continue }
                let mtvLen = simd_length(mtv)
                if mtvLen <= allowedOverlap { continue }
                let unit = mtv / mtvLen
                let pushDist = (mtvLen - allowedOverlap) + margin
                card.entity.position += unit * pushDist
                didResolve = true
                break  // restart with the new position
            }
            if !didResolve { return }
        }
    }

    /// True if `a` and `b` are A-frame partners — their top-edge
    /// midpoints are coincident (within partneredApexDistance) AND
    /// their pitches have opposite sign. These cards SHOULD touch
    /// at the apex (that's the whole point); SAT must not push
    /// them apart.
    private func isAFramePartner(_ a: CardEntity, _ b: CardEntity) -> Bool {
        let topLocal = SIMD3<Float>(0, 0, Self.cardHeight / 2)
        let aTop = a.entity.convert(position: topLocal, to: nil as Entity?)
        let bTop = b.entity.convert(position: topLocal, to: nil as Entity?)
        guard simd_length(aTop - bTop) < Self.partneredApexDistance else { return false }
        let aTilt = pitchAngle(of: a.entity)
        let bTilt = pitchAngle(of: b.entity)
        return abs(aTilt) > Self.snapTiltMin &&
               abs(bTilt) > Self.snapTiltMin &&
               aTilt * bTilt < 0
    }

    // MARK: Selection (pause-mode-only manipulation)
    //
    // Tap a card to select it: an orange halo appears and all
    // subsequent gestures route to that card (camera control
    // is suppressed). Tap empty space or the same card to
    // deselect.
    private func setSelectedCard(_ card: CardEntity?) {
        // If the same card is being passed in, nothing to do.
        if let prev = selectedCardEntity, let next = card, prev === next { return }
        // Remove outline + entity gestures from previously-selected
        // card; let it return to physics if play mode.
        if let prev = selectedCardEntity {
            removeEntityGestures()
            removeSelectionOutline(from: prev)
            if !session.isPaused {
                // Card was kinematic-during-selection; restore it
                // to dynamic for play.
                if var body = prev.entity.components[PhysicsBodyComponent.self] {
                    body.mode = .dynamic
                    body.isContinuousCollisionDetectionEnabled = true
                    prev.entity.components.set(body)
                }
                heldCards.removeAll(where: { $0 === prev })
                if !dynamicCards.contains(where: { $0 === prev }) {
                    dynamicCards.append(prev)
                }
            }
        }
        selectedCardEntity = card
        // Ensure new selection is kinematic + outline visible.
        // Install Apple's native translate + yaw gestures so the
        // user gets canonical iOS gesture handling on the card.
        if let card = card {
            switchToKinematic(card)
            if let idx = dynamicCards.firstIndex(where: { $0 === card }) {
                dynamicCards.remove(at: idx)
            }
            if !heldCards.contains(where: { $0 === card }) {
                heldCards.append(card)
            }
            addSelectionOutline(to: card)
            installEntityGestures(on: card)
        }
    }

    private func addSelectionOutline(to card: CardEntity) {
        // Add halo planes BEHIND both the front and the back so
        // the halo is visible regardless of which face the camera
        // is looking at.
        if card.entity.findEntity(named: "selection-outline-front") != nil { return }
        let halfT = Self.cardThick * 0.5

        // Front-side halo: at local +Y, slightly behind front plane.
        let frontHalo = ModelEntity(mesh: outlineMesh, materials: [outlineMaterial])
        frontHalo.name = "selection-outline-front"
        frontHalo.position = SIMD3<Float>(0, halfT + 0.00006, 0)
        card.entity.addChild(frontHalo)

        // Back-side halo: at local -Y, slightly behind back plane.
        // The back plane has a π-around-X local rotation; matching
        // that on the halo makes its visible side face the same
        // direction (camera-from-behind).
        let backHalo = ModelEntity(mesh: outlineMesh, materials: [outlineMaterial])
        backHalo.name = "selection-outline-back"
        backHalo.position = SIMD3<Float>(0, -halfT - 0.00006, 0)
        backHalo.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        card.entity.addChild(backHalo)
    }

    private func removeSelectionOutline(from card: CardEntity) {
        for name in ["selection-outline-front", "selection-outline-back"] {
            if let outline = card.entity.findEntity(named: name) {
                outline.removeFromParent()
            }
        }
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
            // v2.205: reset is an explicit "start over" — drop
            // the undo history. We don't want a user to reset,
            // then accidentally undo back into their last build.
            undoStack.removeAll()
            session.canUndo = false
            saveScene()  // v2.196: persist the empty state so a fresh visit doesn't re-restore old cards
        }

        // Spawn-at-location: user tapped a location on the table
        // with cards selected. Always auto-pauses so the new
        // cards spawn into a frozen scene (can't spawn into a
        // physics-running world without chaos).
        if let location = session.pendingSpawnLocation {
            session.pendingSpawnLocation = nil
            if !session.isPaused {
                session.isPaused = true
                applyPauseState()
            }
            let toSpawn = session.selectedCards
            session.selectedCards.removeAll()
            for card in toSpawn {
                if let idx = session.deck.firstIndex(where: { $0.id == card.id }) {
                    session.deck.remove(at: idx)
                }
            }
            spawnHeldCards(toSpawn, at: location)
            session.hasAnyCards = !heldCards.isEmpty || !dynamicCards.isEmpty
            saveScene()  // v2.196: persist after spawn
        }

        // Pause/Play toggle. Auto-deselect any selected card so
        // the new physics state applies cleanly.
        if session.togglePauseRequested {
            session.togglePauseRequested = false
            if selectedCardEntity != nil {
                setSelectedCard(nil)
            }
            session.isPaused.toggle()
            applyPauseState()
            saveScene()  // v2.196: persist after play/pause flip
        }
    }

    /// Switch every card's physics body to match session.isPaused.
    /// PAUSED → all bodies become kinematic, cards lock in place.
    /// PLAYING → all bodies become dynamic, gravity engages.
    private func applyPauseState() {
        if session.isPaused {
            // Move all dynamic cards back to held (kinematic).
            for card in dynamicCards {
                if var body = card.entity.components[PhysicsBodyComponent.self] {
                    body.isContinuousCollisionDetectionEnabled = false
                    body.mode = .kinematic
                    card.entity.components.set(body)
                }
                // Zero velocity so they don't drift in pause.
                if var motion = card.entity.components[PhysicsMotionComponent.self] {
                    motion.linearVelocity = .zero
                    motion.angularVelocity = .zero
                    card.entity.components.set(motion)
                }
                card.settledFrames = 0
                card.isSettled = false
                heldCards.append(card)
            }
            dynamicCards.removeAll()
            print("[HoC] PAUSED \(heldCards.count) cards")
        } else {
            // Move all held cards to dynamic.
            for card in heldCards {
                if var body = card.entity.components[PhysicsBodyComponent.self] {
                    body.isContinuousCollisionDetectionEnabled = true
                    body.mode = .dynamic
                    card.entity.components.set(body)
                }
                // Tiny downward seed velocity so the solver doesn't
                // treat the body as at-rest equilibrium.
                if var motion = card.entity.components[PhysicsMotionComponent.self] {
                    motion.linearVelocity = SIMD3<Float>(0, -0.01, 0)
                    card.entity.components.set(motion)
                }
                dynamicCards.append(card)
            }
            heldCards.removeAll()
            print("[HoC] PLAYING with \(dynamicCards.count) cards")
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
                // v2.181: bumped 0.70 → 0.9 to match card-material
                // friction. Base of every A-frame grips the table
                // firmly so pyramids don't slide apart when the
                // physics engages.
                material: .generate(friction: 0.9, restitution: 0.0),
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
        // Clip card-back to rounded corners. applyRotation: false
        // because the back plane's π-around-X local rotation
        // already flips the texture V axis — double-flipping
        // would make the back appear upside-down.
        let rounded = Self.roundedCorners(image, applyRotation: false) ?? image
        guard let cg = rounded.cgImage,
              let tex = makeColorTexture(from: cg)
        else { return }
        backTexture = tex
    }

    // MARK: Card spawning
    //
    // v2.169 spawn: vertical row at tap location.
    //
    // 1-4 cards spawn standing vertical, facing the camera,
    // spread horizontally in a row at the tap location. NO
    // auto-arrangement into A-frames / pinwheels — user
    // rotates and positions individually via gestures.
    //
    // Previous radial pattern produced visually-impossible
    // geometry (3-card faces intersecting, 2-card V instead of
    // tent) because real physical cards can't all converge at
    // a single apex without passing through each other.
    private func spawnHeldCards(_ cards: [Card], at location: SIMD3<Float>) {
        guard let root = anchor, !cards.isEmpty else { return }

        let halfH = Self.cardHeight * 0.5

        // Card stands vertical. centerY must clear both the card
        // bottom (halfH) AND the selection-outline border that
        // extends `outlineMargin` past the card edges, otherwise
        // the halo intersects the table.
        let centerY = halfH + Self.minClearance

        // Spread cards along world X so they don't overlap.
        // Spacing = card width + small gap.
        let spacing = Self.cardWidth + 0.015   // ~7.85cm apart
        let count = min(cards.count, 4)
        let firstX = -Float(count - 1) * 0.5 * spacing

        // Base rotation: stand vertical, front facing the user's
        // current camera direction. v2.195: now safe to add the
        // camera yaw because pitch was rewritten to rotate around
        // the card's local X axis (pitchAxis helper), not world X.
        // No corner dips into the table at any yaw.
        let standUp = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let faceCamera = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        let faceCurrentCamera = simd_quatf(angle: camAzimuth, axis: SIMD3<Float>(0, 1, 0))
        let rotation = faceCurrentCamera * faceCamera * standUp
        // Spread along camera-right direction (not world X) so
        // cards appear "in a row, next to one another" from the
        // user's view regardless of camera azimuth.
        let cameraRight = SIMD3<Float>(cos(camAzimuth), 0, -sin(camAzimuth))

        var newHeld: [CardEntity] = []
        for i in 0..<count {
            let lateralOffset = (firstX + Float(i) * spacing) * cameraRight
            let entityX = location.x + lateralOffset.x
            let entityY = location.y + centerY
            let entityZ = location.z + lateralOffset.z

            let entity = buildCardEntity(
                for: cards[i],
                position: SIMD3<Float>(entityX, entityY, entityZ),
                rotation: rotation
            )
            if var body = entity.components[PhysicsBodyComponent.self] {
                body.isContinuousCollisionDetectionEnabled = false
                body.mode = .kinematic
                entity.components.set(body)
            }
            root.addChild(entity)
            newHeld.append(CardEntity(entity: entity, card: cards[i]))
        }
        heldCards.append(contentsOf: newHeld)

        for c in newHeld {
            let entity = c.entity
            loadFrontArt(for: c.card) { [weak self, weak entity] tex in
                self?.applyArt(to: entity, texture: tex)
            }
        }
        print("[HoC] Spawned \(newHeld.count) vertical cards at \(location); held=\(heldCards.count)")
    }

    // Legacy stub — kept to avoid breaking call sites mid-refactor.
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
        selectedCardEntity = nil   // outline gets removed with entity
        for c in dynamicCards { c.entity.removeFromParent() }
        dynamicCards.removeAll()
        for c in heldCards { c.entity.removeFromParent() }
        heldCards.removeAll()
        targetMaxY = 0
        session.hasAnyCards = false
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
        // Neutral dark placeholder until CDN art loads. Previously
        // used the back-texture which made the front face briefly
        // look like a flipped card back — user reported the
        // half-second of "back" appearance on spawn.
        var placeholder = UnlitMaterial()
        placeholder.color = .init(tint: UIColor(white: 0.08, alpha: 1))
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
        // v2.181: pushed cards into "more forgiving than real" range
        // because the user wants structurally-sound tower configs to
        // survive PLAY. Friction μ_s=1.0 / μ_d=0.9 is at the top of
        // real matte paper. Angular damping doubled (0.25 → 0.5)
        // kills micro-wobble that propagates into apex-contact
        // slips. Linear damping doubled (0.05 → 0.10) prevents tiny
        // velocity drifts from accumulating. Density 107 → 200
        // doesn't change toppling rate (mass-equivalence) but
        // improves PhysX solver numerical stability — solver
        // impulses translate to smaller velocity changes per frame.
        let pmat = PhysicsMaterialResource.generate(
            staticFriction:  1.0,
            dynamicFriction: 0.9,
            restitution:     0.0
        )
        var body = PhysicsBodyComponent(
            shapes:   [shape],
            density:  200,
            material: pmat,
            mode:     .dynamic
        )
        body.isContinuousCollisionDetectionEnabled = true
        body.linearDamping  = 0.10
        body.angularDamping = 0.50
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
    static func roundedCorners(_ image: UIImage,
                               radiusRatio: CGFloat = 0.045,
                               applyRotation: Bool = true) -> UIImage? {
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
            if applyRotation {
                // 180° rotation for the FRONT-plane texture only.
                // The front plane has no local rotation, so we
                // compensate for the plane's UV mapping (image top
                // → plane -Z) by rotating the image. The BACK plane
                // already has a π-around-X local rotation which
                // does this flip implicitly — applying the same
                // image rotation to the back-card texture would
                // double-flip and show upside-down.
                cg.translateBy(x: size.width, y: size.height)
                cg.scaleBy(x: -1, y: -1)
            }
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

    // MARK: Persistence (v2.196)
    //
    // Every user action that changes the scene writes the full
    // scene state to UserDefaults. On the next attach, we restore.
    // This means leaving House of BoBA and coming back picks up
    // exactly where you left off — same cards, same poses, same
    // camera angle, same pause state.

    private static let persistKey = "bp_houseOfBoba_persistedScene_v1"

    /// Becomes true after the first restore-attempt with a
    /// non-empty catalog. saveScene is gated on this so a user
    /// who opens House of BoBA before cardStore.displayCards has
    /// loaded doesn't overwrite their old saved state with an
    /// empty scene. The flag flips even if no saved state was
    /// found (in that case the user is starting fresh and saves
    /// are fine).
    private var restoreCompleted = false

    private struct PersistedCard: Codable {
        let bobaId: String
        let posX, posY, posZ: Float
        let quatX, quatY, quatZ, quatW: Float
        let isDynamic: Bool
    }

    private struct PersistedScene: Codable {
        let version: Int
        let cards: [PersistedCard]
        let isPaused: Bool
        let camAzimuth: Float
        let camElevation: Float
        let camDistance: Float
        let targetX, targetY, targetZ: Float
    }

    /// v2.205: in-memory stack of scene states for Undo. Each
    /// saveScene() call pushes the PREVIOUS scene state (the one
    /// already on disk) onto this stack BEFORE overwriting, so
    /// undo restores the state just before the last action. Cap
    /// at undoStackLimit; older states drop off the bottom when
    /// the cap is reached. Cleared on reset (the user explicitly
    /// asked to start over) and bounded to runtime — not
    /// persisted across app launches.
    private var undoStack: [Data] = []
    private static let undoStackLimit = 25

    /// Build a PersistedScene from the current scene state. Used
    /// by both saveScene (to write to disk) and undo (to capture
    /// the PRESENT state before restoring an older one — so undo
    /// is itself reversible via a redo, though we don't yet
    /// expose redo in the UI).
    private func makePersistedScene() -> PersistedScene {
        let snapshot: [(CardEntity, Bool)] =
            heldCards.map { ($0, false) } + dynamicCards.map { ($0, true) }
        let persistedCards: [PersistedCard] = snapshot.map { (c, isDynamic) in
            let p = c.entity.position
            let q = c.entity.orientation
            return PersistedCard(
                bobaId: c.card.bobaId,
                posX: p.x, posY: p.y, posZ: p.z,
                quatX: q.imag.x, quatY: q.imag.y, quatZ: q.imag.z, quatW: q.real,
                isDynamic: isDynamic
            )
        }
        return PersistedScene(
            version: 1,
            cards: persistedCards,
            isPaused: session.isPaused,
            camAzimuth: camAzimuth,
            camElevation: camElevation,
            camDistance: camDistance,
            targetX: cameraTarget.x, targetY: cameraTarget.y, targetZ: cameraTarget.z
        )
    }

    /// Serialize the current scene to UserDefaults AND push the
    /// previous on-disk state onto the undo stack. Called from
    /// every code path that changes card state, camera state, or
    /// pause state (gesture handlers' .ended branches, spawn,
    /// reset, play/pause).
    func saveScene() {
        guard restoreCompleted else { return }
        // Push the EXISTING on-disk state (which is the
        // pre-action snapshot) onto the undo stack BEFORE we
        // overwrite it. This is what makes "undo last action"
        // mean "go back one step."
        if let prior = UserDefaults.standard.data(forKey: Self.persistKey) {
            undoStack.append(prior)
            if undoStack.count > Self.undoStackLimit {
                undoStack.removeFirst(undoStack.count - Self.undoStackLimit)
            }
            session.canUndo = true
        }
        let state = makePersistedScene()
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.persistKey)
        }
    }

    /// Pop the most recent state off the undo stack and rebuild
    /// the scene from it. Reads `session.undoRequested` from the
    /// update loop. Always restores in PAUSED state, regardless
    /// of the saved isPaused, so the user can inspect / adjust
    /// the recovered tower before re-engaging physics. Persists
    /// the restored state as the new on-disk scene so a re-attach
    /// picks up the undone state.
    func performUndoIfRequested(catalog: [String: Card]) {
        guard session.undoRequested else { return }
        session.undoRequested = false
        guard let prior = undoStack.popLast() else {
            session.canUndo = false
            return
        }
        session.canUndo = !undoStack.isEmpty
        guard let raw = try? JSONDecoder().decode(PersistedScene.self, from: prior) else { return }
        // Force-paused undo: the user undoes BECAUSE something
        // unwanted happened (bad snap, tower fell, etc.). They
        // need a moment to look at the recovered state, so we
        // always restore as paused — even if the captured state
        // was mid-physics. Re-engaging physics on the user's
        // command is one tap away.
        let state = PersistedScene(
            version: raw.version,
            cards: raw.cards,
            isPaused: true,
            camAzimuth: raw.camAzimuth,
            camElevation: raw.camElevation,
            camDistance: raw.camDistance,
            targetX: raw.targetX, targetY: raw.targetY, targetZ: raw.targetZ
        )
        clearAllCards()
        rebuildScene(from: state, catalog: catalog)
        // Persist the restored state as the new on-disk scene,
        // WITHOUT pushing yet another item onto the undo stack
        // (we don't want undo itself to be undoable in a way
        // that walks the stack backwards). Write directly.
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.persistKey)
        }
    }

    /// Attempts to restore from saved state. No-op if already
    /// completed OR if the catalog is still empty (cardStore is
    /// loading async). Safe to call from both attach() and
    /// updateUIView so the restore happens as soon as the catalog
    /// is ready, even if it wasn't ready at attach time.
    func restoreSavedSceneIfAvailable(catalog: [String: Card]) {
        guard !restoreCompleted, !catalog.isEmpty else { return }
        restoreCompleted = true
        // Sync lastResetGeneration so the first consumeSessionState
        // call after attach doesn't trigger a clearAllCards that
        // would wipe whatever we're about to restore (or already
        // restored). Default was -1 vs session's initial 0 →
        // first consume always cleared the scene as a no-op for
        // empty scenes, which would wipe restored cards.
        lastResetGeneration = session.resetGeneration
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistKey),
            let state = try? JSONDecoder().decode(PersistedScene.self, from: data)
        else { return }
        rebuildScene(from: state, catalog: catalog)
        print("[HoB] Restored \(state.cards.count) cards from saved scene")
    }

    /// Shared rebuild logic used by both initial restore and the
    /// undo path (v2.205). Assumes the caller has already cleared
    /// any existing in-scene cards (initial restore runs against
    /// an empty scene; undo runs `clearAllCards` before calling).
    private func rebuildScene(from state: PersistedScene, catalog: [String: Card]) {
        // Restore camera state first so the view shows the saved
        // angle even before art finishes loading.
        camAzimuth   = state.camAzimuth
        camElevation = state.camElevation
        camDistance  = state.camDistance
        cameraTarget = SIMD3<Float>(state.targetX, state.targetY, state.targetZ)
        updateCameraTransform()

        guard let root = anchor else { return }
        for ps in state.cards {
            guard let card = catalog[ps.bobaId] else { continue }
            let position = SIMD3<Float>(ps.posX, ps.posY, ps.posZ)
            let orientation = simd_quatf(
                ix: ps.quatX, iy: ps.quatY, iz: ps.quatZ, r: ps.quatW
            )
            let entity = buildCardEntity(for: card, position: position, rotation: orientation)
            if var body = entity.components[PhysicsBodyComponent.self] {
                // Restored cards always start kinematic — physics
                // only re-engages when the user presses PLAY (which
                // applyPauseState then flips them back to dynamic
                // if !isPaused).
                body.mode = .kinematic
                body.isContinuousCollisionDetectionEnabled = false
                entity.components.set(body)
            }
            root.addChild(entity)
            let ce = CardEntity(entity: entity, card: card)
            if ps.isDynamic {
                dynamicCards.append(ce)
            } else {
                heldCards.append(ce)
            }
            loadFrontArt(for: card) { [weak self, weak entity] tex in
                self?.applyArt(to: entity, texture: tex)
            }
        }

        session.hasAnyCards = !state.cards.isEmpty
        session.isPaused = state.isPaused
        if !state.isPaused {
            applyPauseState()
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
        // Long-press is always exclusive (different touch counts).
        if gestureRecognizer is UILongPressGestureRecognizer ||
           other is UILongPressGestureRecognizer {
            return false
        }
        // v2.187: all other gesture pairs recognize simultaneously.
        // The 2-finger pan, pinch, and Apple's rotation all fire
        // together on the same 2-finger gesture — same as Photos
        // and AR Quick Look. v2.186 made pan+pinch exclusive to
        // try to fix unpredictable motion; that was the wrong fix.
        // The right fix was the drag-the-object direction (v2.187
        // .panningCamera math) which made the combined gesture
        // feel natural again.
        return true
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // v2.173: Our 1-finger pan must NOT receive touches that
        // land on the currently-selected card. Those go to
        // Apple's EntityTranslationGestureRecognizer (installed
        // per-selection via installGestures). This is the
        // delegate primitive Apple recommends for resolving the
        // 1-finger-pan-vs-entity-translate ambiguity on iOS.
        return MainActor.assumeIsolated {
            guard let pan = primaryPanGesture, gestureRecognizer === pan else {
                return true
            }
            guard let view = arView, let selected = selectedCardEntity else {
                return true
            }
            let point = touch.location(in: view)
            if let hit = hitTestCardEntity(at: point), hit === selected {
                return false
            }
            return true
        }
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

    /// Cards selected from the strip, up to 4. Cards in this
    /// array show selection state in the strip UI. Tapping
    /// "Place" then the table spawns these cards into the scene.
    var selectedCards: [Card] = []

    /// World position where the next spawn should happen.
    /// Set by tap-on-table after the user has tapped Place.
    /// Coordinator reads + clears it on the next update cycle.
    var pendingSpawnLocation: SIMD3<Float>? = nil

    /// Master pause/play state. When true, the entire physics
    /// simulation is frozen: every card is kinematic, gravity
    /// has no effect, the user can manipulate any card freely.
    /// When false, all cards are dynamic and physics runs.
    /// Default is paused — the user explicitly opts into physics
    /// by tapping PLAY.
    var isPaused: Bool = true

    /// Signal flag: user tapped the PLAY/PAUSE button. The
    /// coordinator reads + clears it and toggles isPaused.
    var togglePauseRequested: Bool = false

    /// v2.205: master switch for smart-snap. When OFF, the
    /// coordinator's applySmartSnap is a no-op — every gesture
    /// release leaves the card exactly where the user placed it.
    /// Default ON for first-time discovery; user toggles via the
    /// ⋯ menu. The intent is that snap is a HELPER, not a
    /// constraint — when it's fighting the user's creative
    /// placement, they can switch it off and the playground works
    /// like a real-world physics sandbox.
    var snapsEnabled: Bool = true

    /// Signal flag: user tapped the Undo menu item. Coordinator
    /// reads + clears, pops the previous Codable scene off its
    /// in-memory stack, and rebuilds the scene from that state.
    var undoRequested: Bool = false

    /// Mirrors the coordinator's undo-stack non-empty state for
    /// the menu's "Undo" item enable check. Coordinator updates
    /// it after every push / pop.
    var canUndo: Bool = false

    /// True if at least one card is on the table (kinematic
    /// or dynamic). Drives play-button enabled state.
    var hasAnyCards: Bool = false

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

    /// Toggle a card's selection. Max 4 selected at once.
    func toggleSelection(_ card: Card) {
        if let idx = selectedCards.firstIndex(where: { $0.id == card.id }) {
            selectedCards.remove(at: idx)
        } else if selectedCards.count < 4 {
            selectedCards.append(card)
        }
    }

    func isSelected(_ card: Card) -> Bool {
        selectedCards.contains(where: { $0.id == card.id })
    }

    func selectionIndex(of card: Card) -> Int? {
        selectedCards.firstIndex(where: { $0.id == card.id })
    }

    func clearSelection() {
        selectedCards.removeAll()
    }

    func togglePause() {
        togglePauseRequested = true
    }

    func resetScene() {
        currentLevels = 0
        resetGeneration &+= 1
        selectedCards.removeAll()
        pendingSpawnLocation = nil
        hasAnyCards = false
        isPaused = true
    }
}

