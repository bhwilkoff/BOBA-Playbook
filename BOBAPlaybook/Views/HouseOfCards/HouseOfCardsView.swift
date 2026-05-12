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
            Text("DRAG A CARD ONTO THE TABLE")
                .font(Design.Fonts.mono(10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(session.deck.prefix(8).enumerated()), id: \.offset) { idx, card in
                        DeckStripCard(
                            card: card,
                            isNext: idx == 0,
                            // Note: we do NOT mutate the deck until
                            // onDragEnd. Mutating it mid-drag shifts
                            // the strip while the user's finger is
                            // mid-gesture and SwiftUI's view recycler
                            // breaks the gesture stream. The active
                            // dragged card lives on the coordinator
                            // (dragCard); the strip stays stable.
                            onDragStart: { card, point in
                                guard idx == 0 else { return }
                                session.dragSpawnCard = card
                                session.dragScreenPoint = point
                            },
                            onDragChange: { point in
                                session.dragScreenPoint = point
                            },
                            onDragEnd: {
                                session.dragScreenPoint = nil
                                // The coordinator commits the card to
                                // dynamic on the next updateUIView.
                                // Pop the consumed card from the deck
                                // now that the drop has completed.
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
                    Text("Drag cards onto the table or onto other cards. Lean them against each other to climb levels. The taller and more stable the tower, the higher the score.")
                        .font(Design.Fonts.mono(15))
                        .foregroundStyle(.white.opacity(0.85))
                    Divider().overlay(.white.opacity(0.15))
                    helpRow("Drag",        "Pick a card from the deck strip and place it in the scene.")
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
// card ("next") is highlighted. Drag from a card into the
// scene to spawn it as a kinematic entity that follows the
// finger; release in scene to commit to dynamic physics.
private struct DeckStripCard: View {
    let card: Card
    let isNext: Bool
    /// Drag callbacks routed up to the parent so the parent
    /// can mutate the @State session. Coordinates are in the
    /// global window space (so the RealityView coordinator can
    /// project them into world space).
    var onDragStart:  (Card, CGPoint) -> Void = { _, _ in }
    var onDragChange: (CGPoint) -> Void = { _ in }
    var onDragEnd:    () -> Void = {}

    @State private var hasFiredStart: Bool = false

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
        // Drag from the strip into the scene. Only the leftmost
        // card is draggable so the user can't fork attention
        // across multiple cards at once.
        .gesture(
            isNext
                ? DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        if !hasFiredStart {
                            hasFiredStart = true
                            onDragStart(card, value.location)
                        } else {
                            onDragChange(value.location)
                        }
                    }
                    .onEnded { _ in
                        hasFiredStart = false
                        onDragEnd()
                    }
                : nil
        )
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
    /// The card currently being dragged (kinematic).
    private var dragCard: CardEntity?
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

        // Per-frame physics + scoring tick.
        sceneSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(deltaTime: Float(event.deltaTime))
        }
    }

    // MARK: Per-frame
    private func tick(deltaTime _: Float) {
        // Drag follow: if a card is being dragged, project the
        // current screen point into world space at the current
        // hover height and snap the kinematic body there.
        if let card = dragCard, let screenPoint = session.dragScreenPoint, let view = arView {
            let hoverY = max(0.04, targetMaxY + 0.03)
            if let world = view.project(screenPoint, ontoPlaneAt: hoverY) {
                card.entity.transform.translation = world
            }
        }

        // Settle detection + score update.
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

        // Camera lift as tower grows.
        let desiredMaxY = maxSettledY
        if abs(desiredMaxY - targetMaxY) > 0.01 {
            targetMaxY = desiredMaxY
            animateCameraForTowerHeight()
        }
    }

    // MARK: Input handling — consumed each updateUIView
    func consumeSessionState() {
        // Reset signal — rebuild scene from scratch.
        if session.resetGeneration != lastResetGeneration {
            lastResetGeneration = session.resetGeneration
            clearAllCards()
        }

        // Drag-spawn: user started dragging a card from the
        // deck strip. Spawn a kinematic card; subsequent
        // dragScreenPoint updates move it.
        if let card = session.dragSpawnCard {
            session.dragSpawnCard = nil
            spawnDragCard(card)
        }

        // Drop-on-release: user lifted finger. Commit the
        // kinematic card to dynamic so gravity takes over.
        if session.dragScreenPoint == nil, dragCard != nil {
            commitDragRelease()
        }
    }

    // MARK: Lighting
    private func buildLighting(on root: AnchorEntity) {
        // Key directional light — soft yellow-white, with shadow.
        let key = DirectionalLight()
        key.light.intensity   = 2200
        key.light.color       = UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        key.light.isRealWorldProxy = false
        key.shadow            = DirectionalLightComponent.Shadow(
            maximumDistance: 1.5,
            depthBias: 1.0
        )
        // Aim down and slightly forward (z-positive in our setup
        // is toward the camera). Rotation is from light-forward
        // axis (-Z) toward the desired direction.
        let rot1 = simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0))   // tilt down
        let rot2 = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0))   // tilt sideways
        key.orientation = rot1 * rot2
        key.position = SIMD3<Float>(0.4, 0.8, 0.5)
        root.addChild(key)

        // Fill — opposite side, no shadow.
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.light.color     = UIColor(red: 0.9, green: 0.93, blue: 1.0, alpha: 1)
        fill.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(-1, 0.3, 0))
        fill.position = SIMD3<Float>(-0.3, 0.6, -0.2)
        root.addChild(fill)

        // Bottom rim — keeps shadow-side card backs readable.
        let rim = DirectionalLight()
        rim.light.intensity = 150
        rim.light.color     = UIColor(red: 1, green: 0.85, blue: 0.7, alpha: 1)
        rim.orientation     = simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(1, 0, 0))
        root.addChild(rim)
    }

    // MARK: Camera
    private func buildCamera(on root: AnchorEntity, view: ARView) {
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 48
        cam.camera.near = 0.01
        cam.camera.far  = 10.0
        cam.position = SIMD3<Float>(0, 0.32, 0.46)
        cam.look(at: SIMD3<Float>(0, 0.06, 0),
                 from: cam.position,
                 relativeTo: nil)
        root.addChild(cam)
        self.camera = cam
    }

    private func animateCameraForTowerHeight() {
        guard let cam = camera else { return }
        let h = targetMaxY
        let camY: Float = 0.32 + h * 0.55
        let camZ: Float = 0.46 + h * 0.4
        let lookY: Float = 0.06 + h * 0.5

        var t = cam.transform
        t.translation = SIMD3<Float>(0, camY, camZ)
        cam.move(to: t, relativeTo: cam.parent, duration: 0.7, timingFunction: .easeInOut)
        // Re-aim is rebuilt next frame via the look() in tick.
        cam.look(at: SIMD3<Float>(0, lookY, 0), from: SIMD3<Float>(0, camY, camZ), relativeTo: nil)
    }

    // MARK: Tabletop
    private func buildTabletop(on root: AnchorEntity) {
        let plane = MeshResource.generatePlane(width: 1.6, depth: 1.6)
        var mat = PhysicallyBasedMaterial()
        mat.baseColor    = .init(tint: UIColor(red: 0.12, green: 0.09, blue: 0.08, alpha: 1))
        mat.roughness    = .init(floatLiteral: 0.85)
        mat.metallic     = .init(floatLiteral: 0.0)
        let table = ModelEntity(mesh: plane, materials: [mat])
        table.position = SIMD3<Float>(0, 0, 0)
        table.components.set(
            CollisionComponent(shapes: [.generateBox(width: 1.6, height: 0.01, depth: 1.6)])
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

        // BOBA logo decal — slightly above the table to avoid
        // z-fighting, with an unlit material so it reads as a
        // crisp emblem, not a painted-on surface.
        if let logo = UIImage(named: "boba_playbook_icon_512") ?? UIImage(named: "AppIcon"),
           let cg = logo.cgImage,
           let tex = makeColorTexture(from: cg) {
            let logoPlane = MeshResource.generatePlane(width: 0.22, depth: 0.22)
            var logoMat = UnlitMaterial()
            logoMat.color = .init(tint: UIColor.white.withAlphaComponent(0.18), texture: .init(tex))
            logoMat.blending = .transparent(opacity: .init(floatLiteral: 0.18))
            let logoEntity = ModelEntity(mesh: logoPlane, materials: [logoMat])
            logoEntity.position = SIMD3<Float>(0, 0.0008, 0)
            root.addChild(logoEntity)
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
    private func spawnDragCard(_ card: Card) {
        guard let view = arView, let root = anchor else { return }
        // One drag at a time — ignore further spawn requests until
        // the current dragCard is committed or cleared.
        guard dragCard == nil else { return }

        // Build the entity at the current drag screen point,
        // projected onto a hover plane just above the tower.
        let hoverY = max(0.10, targetMaxY + 0.10)
        let startPos: SIMD3<Float> = {
            if let screen = session.dragScreenPoint,
               let world = view.project(screen, ontoPlaneAt: hoverY) {
                return world
            }
            return SIMD3<Float>(0, hoverY, 0)
        }()

        let entity = buildCardEntity(for: card, position: startPos)
        // Kinematic during drag — no gravity, follows finger.
        // CCD must be OFF for kinematic bodies; PhysX spams the
        // console otherwise ("kinematic bodies with CCD enabled
        // are not supported"). We re-enable on dynamic commit.
        if var body = entity.components[PhysicsBodyComponent.self] {
            body.isContinuousCollisionDetectionEnabled = false
            body.mode = .kinematic
            entity.components.set(body)
        }
        root.addChild(entity)
        let cardEntity = CardEntity(entity: entity, card: card)
        dragCard = cardEntity

        // Load front art async; until it lands, the top face
        // shows the back texture (so the user sees the right
        // proportions immediately). Once art is loaded, the
        // top face material is swapped in place.
        loadFrontArt(for: card) { [weak self, weak entity] tex in
            guard let entity, let model = entity.components[ModelComponent.self] else { return }
            var mats = model.materials
            if mats.count >= 3 {
                var art = PhysicallyBasedMaterial()
                art.baseColor = .init(tint: .white, texture: .init(tex))
                art.roughness = .init(floatLiteral: 0.55)
                art.metallic  = .init(floatLiteral: 0.0)
                mats[2] = art   // index 2 = +Y face (top, art side)
            }
            // Update the entity's materials.
            var updated = model
            updated.materials = mats
            entity.components.set(updated)
            _ = self
        }
    }

    private func commitDragRelease() {
        guard let card = dragCard else { return }
        // Swap kinematic → dynamic. Re-enable CCD now that the
        // body is dynamic again (thin geometry needs it to avoid
        // tunneling during fast falls).
        if var body = card.entity.components[PhysicsBodyComponent.self] {
            body.mode = .dynamic
            body.isContinuousCollisionDetectionEnabled = true
            card.entity.components.set(body)
        }
        // Apply a tiny downward velocity so the card "drops"
        // instead of hovering before gravity engages.
        if var motion = card.entity.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = SIMD3<Float>(0, -0.2, 0)
            card.entity.components.set(motion)
        } else {
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = SIMD3<Float>(0, -0.2, 0)
            card.entity.components.set(motion)
        }
        dynamicCards.append(card)
        dragCard = nil
    }

    private func clearAllCards() {
        for c in dynamicCards { c.entity.removeFromParent() }
        dynamicCards.removeAll()
        dragCard?.entity.removeFromParent()
        dragCard = nil
        targetMaxY = 0
        animateCameraForTowerHeight()
    }

    // MARK: Card entity construction
    private func buildCardEntity(for card: Card, position: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateBox(
            width: Self.cardWidth,
            height: Self.cardThick,
            depth: Self.cardHeight,
            cornerRadius: Self.cornerR,
            splitFaces: true
        )

        // Face order on a splitFaces box per WWDC + community
        // testing: [+X, -X, +Y, -Y, +Z, -Z]. With card lying
        // flat: +Y is top (art), -Y is bottom (back).
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

    /// One-shot flag set by tapping the next card or dragging
    /// from the deck strip into the scene. The RealityView
    /// reads + clears it on the next render cycle.
    var pendingSpawn: Card? = nil

    /// Drag state: when non-nil, the coordinator should hold
    /// the most-recently-spawned card as kinematic at this
    /// screen point. On .onEnded, set to nil and the coordinator
    /// commits the card to dynamic.
    var dragScreenPoint: CGPoint? = nil

    /// Set by DeckStripCard on drag-start. Coordinator on next
    /// update spawns the card AND begins drag tracking.
    var dragSpawnCard: Card? = nil

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

    /// Called by the coordinator after a spawn completes —
    /// clears the pending flag so we don't double-spawn.
    func clearPendingSpawn() {
        pendingSpawn = nil
    }

    func resetScene() {
        currentLevels = 0
        resetGeneration &+= 1
    }
}

