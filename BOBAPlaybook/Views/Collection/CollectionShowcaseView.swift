import SwiftUI
import AVFoundation
import AVKit
import Combine
import CoreMedia
import CoreVideo
import ImageIO
import Network
import UniformTypeIdentifiers

// MARK: - ShowcaseAnimation
//
// AlbumArtwork-style variants. Each cycle the orchestrator picks one
// variant and applies it across 3-6 random tiles (or, for row
// variants, across every tile in a single row with a 100ms internal
// stagger). Weights mirror the lingkuma/AlbumArtwork repo's defaults.
enum ShowcaseAnimation: String, CaseIterable, Identifiable {
    case flip
    case drop
    case rollDrop
    case pinRotation
    case dropFromCorner
    case rowDrop
    case rowRollDrop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flip:            return "Flip"
        case .drop:            return "Drop"
        case .rollDrop:        return "Roll Drop"
        case .pinRotation:     return "Spin"
        case .dropFromCorner:  return "Corner Drop"
        case .rowDrop:         return "Row Drop"
        case .rowRollDrop:     return "Row Roll Drop"
        }
    }

    /// AlbumArtwork's weights: tile variants ~15, row variants ~12.5.
    var weight: Double {
        switch self {
        case .rowDrop, .rowRollDrop: return 12.5
        default:                     return 15.0
        }
    }

    /// True for variants that operate on whole rows.
    var isRowVariant: Bool {
        switch self {
        case .rowDrop, .rowRollDrop: return true
        default:                     return false
        }
    }
}

// MARK: - ShowcaseSession
//
// Single source of truth for an active Showcase. Owns pool, tiles,
// grid geometry, paused / cycle-speed state, animation variants, and
// the cycle Task. Shared between the phone-side view (grid or control
// panel) and — when external display is active — the UIWindow hosted
// on the second screen via ExternalDisplayManager. Branching on
// `renderTarget` keeps only ONE grid mounted at a time.
@Observable
@MainActor
final class ShowcaseSession {
    enum RenderTarget {
        case phone
        case external
    }

    var cards: [Card] = []
    var pool = ShowcaseImagePool()
    var tiles: [ShowcaseTileState] = []
    var columns: Int = 0

    // Grid geometry — user-tunable.
    var rows: Int = 6

    // Playback state.
    var paused: Bool = false
    var cycleSpeed: Double = 3.0   // [3, 15]
    var cycleJitter: Double = 1.0

    // Variant filter — user can disable variants from the control panel.
    var enabledVariants: Set<ShowcaseAnimation> = Set(ShowcaseAnimation.allCases)

    // External display routing.
    var renderTarget: RenderTarget = .phone

    // Bumped on every state change that should restart the cycle Task.
    var cycleEpoch: Int = 0

    // Thermal observer state — drops cadence under pressure.
    var thermalState: ProcessInfo.ThermalState = .nominal

    func setCards(_ newCards: [Card]) {
        cards = newCards
        pool.setCandidates(newCards)
    }

    /// Variant pool the orchestrator picks from. If the user disabled
    /// everything (shouldn't happen via the control panel UI, but
    /// defensive) we fall back to flip.
    var activeVariants: [ShowcaseAnimation] {
        let active = ShowcaseAnimation.allCases.filter { enabledVariants.contains($0) }
        return active.isEmpty ? [.flip] : active
    }

    /// Initialize tile grid for the given total count. Splits into
    /// two phases for fast first paint:
    ///
    /// Phase 1 (synchronous): walk the pool and assign a card to each
    /// tile slot, applying the no-adjacent-duplicates rule. Tiles are
    /// created with bobaId but no image yet, so the grid renders
    /// instantly with placeholder backgrounds.
    ///
    /// Phase 2 (parallel): fan out image loads via withTaskGroup. Each
    /// tile fills in as its image lands. URLSession multiplexes over
    /// HTTP/2 so the loads truly run in parallel rather than serialized
    /// on a single MainActor await chain.
    ///
    /// Initial fill uses the thumb CDN tier (~10KB / 200px) for fast
    /// first paint. Animation cycles use full CDN tier (~80KB / 1200px)
    /// for the cards that flip into view — handled by ShowcaseImagePool's
    /// loadImage call which the cycle path uses.
    func initializeTiles(count: Int) async {
        if tiles.count == count { return }
        pool.setCandidates(cards)

        // Phase 1: card assignment with no-adjacent-duplicates rule.
        var assignments: [(Int, Card)] = []
        var lastRow: [String] = []
        var rowBuf: [String] = []
        let cols = max(1, columns)
        for i in 0..<count {
            let col = i % cols
            let exclude = Set(lastRow + rowBuf)
            guard let card = pool.pickCard(excluding: exclude) else { break }
            assignments.append((i, card))
            rowBuf.append(card.id)
            if col == cols - 1 {
                lastRow = rowBuf
                rowBuf = []
            }
        }

        // Create empty tiles and publish immediately so the grid
        // renders before any images have loaded.
        // `let` because we only mutate the tile instances (reference
        // types) — the array itself is never reassigned.
        let newTiles: [ShowcaseTileState] = (0..<count).map { _ in ShowcaseTileState() }
        for (i, card) in assignments where i < newTiles.count {
            newTiles[i].currentBobaId = card.id
        }
        tiles = newTiles
        cycleEpoch &+= 1

        // Phase 2: parallel image fetch + populate.
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, card) in assignments {
                group.addTask { [pool] in
                    let img = await pool.loadImage(for: card, preferThumb: true)
                    return (i, img)
                }
            }
            for await (i, img) in group {
                if i < self.tiles.count, let img = img {
                    self.tiles[i].front = img
                }
            }
        }
    }

    /// Cycle loop — schedules flip cycles forever until cancelled.
    /// Suspends when paused; sleeps adapt to thermalState.
    func runCycleLoop(reduceMotion: Bool) async {
        try? await Task.sleep(for: .milliseconds(200))
        while !Task.isCancelled {
            if paused { return }
            let cadence = baseCadence()
            let jitter = Double.random(in: 0...cycleJitter)
            try? await Task.sleep(for: .seconds(cadence + jitter))
            if Task.isCancelled || paused { return }
            await runFlipCycle(reduceMotion: reduceMotion)
        }
    }

    private func baseCadence() -> Double {
        switch thermalState {
        case .nominal, .fair: return cycleSpeed
        case .serious:        return max(cycleSpeed, 6.0)
        case .critical:       return max(cycleSpeed, 10.0)
        @unknown default:     return cycleSpeed
        }
    }

    /// Pick a variant (weighted) + set of tiles, animate each in
    /// sequence. Row variants pick a whole row; tile variants pick
    /// 3-6 random tiles.
    func runFlipCycle(reduceMotion: Bool) async {
        guard !tiles.isEmpty, columns > 0 else { return }
        let variant = pickVariant()

        let indices: [Int]
        if variant.isRowVariant {
            let r = Int.random(in: 0..<rows)
            indices = Array(0..<columns).map { r * columns + $0 }
                .filter { $0 < tiles.count }
        } else {
            let count = Int.random(in: 3...min(6, tiles.count))
            indices = Array(Array(0..<tiles.count).shuffled().prefix(count))
        }

        let stagger = variant.isRowVariant ? 100 : 200
        for (i, tileIndex) in indices.enumerated() {
            if i > 0 {
                try? await Task.sleep(for: .milliseconds(stagger))
            }
            if Task.isCancelled || paused { return }
            // Exclude both the tile's current card AND its neighbors'
            // cards — a tile must never animate to the same card it's
            // already showing (otherwise the animation plays for no
            // visible change).
            var exclude = neighborBobaIds(of: tileIndex)
            if let own = tiles[tileIndex].currentBobaId {
                exclude.insert(own)
            }
            guard let (newId, image) = await pool.nextImage(excluding: exclude) else { continue }
            tiles[tileIndex].currentBobaId = newId
            await tiles[tileIndex].animate(to: image, variant: variant, reduceMotion: reduceMotion)
        }
    }

    private func pickVariant() -> ShowcaseAnimation {
        let active = activeVariants
        let totalWeight = active.reduce(0.0) { $0 + $1.weight }
        let r = Double.random(in: 0..<totalWeight)
        var running = 0.0
        for v in active {
            running += v.weight
            if r < running { return v }
        }
        return active.first ?? .flip
    }

    private func neighborBobaIds(of index: Int) -> Set<String> {
        guard columns > 0 else { return [] }
        var ids: Set<String> = []
        let row = index / columns, col = index % columns
        let candidates: [(Int, Int)] = [
            (row, col - 1), (row, col + 1),
            (row - 1, col), (row + 1, col)
        ]
        for (r, c) in candidates where r >= 0 && r < rows && c >= 0 && c < columns {
            let n = r * columns + c
            if n < tiles.count, let id = tiles[n].currentBobaId {
                ids.insert(id)
            }
        }
        return ids
    }
}

// MARK: - ExternalDisplayManager
//
// Singleton that observes external-screen connect/disconnect (via
// ExternalDisplaySceneDelegate in AppDelegate.swift) and holds a
// weak reference to the current ShowcaseSession. The ExternalShowcase
// Root view reads `session` to decide whether to render the grid on
// the second screen.
//
// `useExternalDisplay` is the user's preference toggle (in the
// phone-side control panel). When true AND an external screen is
// available, session.renderTarget flips to .external.
@Observable
@MainActor
final class ExternalDisplayManager {
    static let shared = ExternalDisplayManager()
    private init() {}

    private(set) var externalScreenAvailable: Bool = false
    private(set) weak var externalWindow: UIWindow?
    var session: ShowcaseSession?

    /// User preference. Effective only when externalScreenAvailable.
    var useExternalDisplay: Bool = true {
        didSet { applyRenderTarget() }
    }

    func setSession(_ session: ShowcaseSession?) {
        self.session = session
        applyRenderTarget()
    }

    func didConnect(window: UIWindow) {
        externalWindow = window
        externalScreenAvailable = true
        applyRenderTarget()
    }

    func didDisconnect() {
        externalWindow = nil
        externalScreenAvailable = false
        applyRenderTarget()
    }

    private func applyRenderTarget() {
        guard let session else { return }
        if externalScreenAvailable && useExternalDisplay {
            session.renderTarget = .external
        } else {
            session.renderTarget = .phone
        }
    }
}

// MARK: - CollectionShowcaseView (root)
//
// Decides which UI to render on the phone based on session.renderTarget:
//   .phone    → ShowcaseGridView (the iTunes-style screensaver fullscreen)
//   .external → ShowcaseControlPanel (pause / speed / rows / variant
//               toggles; grid is rendering on the TV via ExternalShowcaseRoot)
//
// Wires lifecycle: idle timer, orientation unlock, session<->manager.
struct CollectionShowcaseView: View {
    let cards: [Card]
    var onDismiss: () -> Void

    @State private var session: ShowcaseSession
    @State private var externalManager: ExternalDisplayManager
    @State private var streamer: ShowcaseVideoStreamer

    init(cards: [Card], onDismiss: @escaping () -> Void) {
        let s = ShowcaseSession()
        s.setCards(cards)
        self.cards = cards
        self.onDismiss = onDismiss
        self._session = State(initialValue: s)
        self._externalManager = State(initialValue: ExternalDisplayManager.shared)
        self._streamer = State(initialValue: ShowcaseVideoStreamer(session: s))
    }

    /// Phone-side switches to the control panel whenever either path
    /// is showing content on a TV:
    ///   - AirPlay-Video routing (user picked Apple TV from AVRoutePickerView)
    ///   - Plain Screen Mirroring (user enabled it via Control Center)
    private var tvActive: Bool {
        streamer.isExternalPlaybackActive
        || (externalManager.externalScreenAvailable
            && externalManager.useExternalDisplay
            && session.renderTarget == .external)
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if tvActive {
                    ShowcaseControlPanel(
                        session: session,
                        streamer: streamer,
                        onDismiss: onDismiss
                    )
                } else {
                    ShowcaseGridView(
                        session: session,
                        streamer: streamer,
                        showsToolbar: true,
                        onDismiss: onDismiss
                    )
                }
            }
            // AirPlaySurface must persist across the grid ↔ control
            // panel swap, otherwise the AVPlayerLayer disappears when
            // AirPlay engages — at exactly the moment the routing
            // engine needs it. Mounted at the outermost level here.
            AirPlaySurface(player: streamer.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(-1)   // behind everything else
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationManager.shared.allowLandscape()
            ExternalDisplayManager.shared.setSession(session)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationManager.shared.lockPortrait()
            ExternalDisplayManager.shared.setSession(nil)
            streamer.stop()
        }
        // Async streamer startup so MainActor isn't blocked on the
        // NWListener "ready" wait. The grid renders immediately; the
        // encoder + HTTP server + AVPlayer come online a fraction of
        // a second later. AirPlay-Video routing engages as soon as
        // the player has a current item, which happens at the tail
        // of start().
        .task {
            await streamer.start()
        }
        // Cycle loop owned by the OUTER view so it survives the
        // grid ↔ control-panel swap when AirPlay engages. Previously
        // this lived on ShowcaseGridView's .task, which got cancelled
        // when the phone switched to ControlPanel — causing tiles to
        // freeze on the TV.
        .task(id: session.cycleEpoch) {
            await session.runCycleLoop(reduceMotion: reduceMotion)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !session.paused {
                session.cycleEpoch &+= 1
            }
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            let new = ProcessInfo.processInfo.thermalState
            if new != session.thermalState {
                session.thermalState = new
                session.cycleEpoch &+= 1
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - ShowcaseGridView
//
// The actual screensaver: 6-row (default) tile grid of card art at
// natural 3:4 aspect, tiles bleed off the screen edges. Mounted on
// either the phone (fullscreen) or the external display (via
// ExternalShowcaseRoot in AppDelegate.swift).
//
// Phone-side mount uses `showsToolbar: true` for the auto-hiding
// Photos-pattern toolbar (Dismiss / Pause / AirPlay). External-side
// mount uses `showsToolbar: false` — TV stays chromeless; controls
// live on the phone via ShowcaseControlPanel.
struct ShowcaseGridView: View {
    @Bindable var session: ShowcaseSession
    var streamer: ShowcaseVideoStreamer?
    let showsToolbar: Bool
    var onDismiss: (() -> Void)?

    @State private var rowsAtPinchStart: Int = 6
    @State private var revealedToolbar: Bool = true
    @State private var toolbarHideTask: Task<Void, Never>?

    // scenePhase + reduceMotion observers moved up to
    // CollectionShowcaseView with the cycle loop, since they need
    // to stay alive when this view unmounts during AirPlay routing.

    private let cardAspect: CGFloat = 0.75   // width / height = 3/4
    private let minRows: Int = 2
    private let maxRows: Int = 12

    /// True until ~25% of grid tiles have populated their `front`
    /// image. The initial fan-out fetch from R2 + WebP decode can
    /// take 1-3 seconds; without the overlay the user sees a near-
    /// black screen full of dark placeholders, which reads as broken.
    private var isInitialLoading: Bool {
        let total = session.tiles.count
        guard total > 0 else { return true }
        let loaded = session.tiles.reduce(into: 0) { count, tile in
            if tile.front != nil { count += 1 }
        }
        return Double(loaded) / Double(total) < 0.25
    }

    /// Top safe-area inset read directly from the foreground window
    /// scene. GeometryReader.safeAreaInsets returns .zero when its
    /// container has `.ignoresSafeArea(.all)` applied (which our
    /// outer modifier does, intentionally — the grid needs to bleed
    /// past the Dynamic Island). Falling back to the window-scene
    /// insets keeps the toolbar safely below the notch.
    private var deviceTopSafeInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)
        return scene?.windows.first?.safeAreaInsets.top ?? 47
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Defensive: SwiftUI's initial layout pass can deliver
            // size = .zero before the view is sized, which would make
            // cellW = 0 and `size.width / cellW` = NaN. Int(NaN)
            // crashes (the Showcase v2.121 launch crash). Bail to a
            // black frame until geometry is real.
            let geometryReady = size.width > 1 && size.height > 1 && session.rows > 0
            let cellH = geometryReady ? size.height / CGFloat(session.rows) : 0
            let cellW = max(1, cellH * cardAspect)
            let cols = geometryReady ? max(1, Int(ceil(size.width / cellW))) : 0
            let totalTiles = session.rows * cols

            ZStack(alignment: .top) {
                // (AirPlaySurface moved up to CollectionShowcaseView
                // so it persists when the phone-side swaps between
                // grid and control panel.)
                Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)
                    .ignoresSafeArea()

                // Tap-to-reveal layer — only active when the toolbar
                // is hidden. Keeps the reveal-on-tap gesture out of
                // the toolbar's button territory so taps on Pause /
                // AirPlay / Dismiss fire their actions instead of
                // re-triggering toolbar-show (the landscape "buttons
                // don't respond" bug).
                if showsToolbar && !revealedToolbar {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { revealToolbar() }
                }

                if geometryReady {
                    // Manual ZStack-positioned grid (not LazyVGrid) so
                    // each cell can lift its zIndex during an exit
                    // animation and render OVER neighbor cells while
                    // the card "falls down" past them (per AlbumArtwork
                    // visual semantics).
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<totalTiles, id: \.self) { index in
                            if index < session.tiles.count {
                                let row = index / cols
                                let col = index % cols
                                ShowcaseTileCell(
                                    state: session.tiles[index],
                                    width: cellW,
                                    height: cellH
                                )
                                .frame(width: cellW, height: cellH)
                                .position(
                                    x: CGFloat(col) * cellW + cellW / 2,
                                    y: CGFloat(row) * cellH + cellH / 2
                                )
                                .zIndex(session.tiles[index].exitImage != nil ? 1 : 0)
                            }
                        }
                    }
                    .frame(width: cellW * CGFloat(cols), height: cellH * CGFloat(session.rows))
                    .position(x: size.width / 2, y: size.height / 2)
                    // Grid tiles are Image views — they consume taps
                    // without handling them, blocking the
                    // tap-to-reveal-toolbar layer below them in the
                    // ZStack. Disabling hit testing lets taps fall
                    // through to the Color.clear reveal layer (when
                    // toolbar is hidden) and to toolbar buttons (when
                    // visible).
                    .allowsHitTesting(false)
                    .onAppear {
                        session.columns = cols
                        Task { await session.initializeTiles(count: totalTiles) }
                    }
                    .onChange(of: cols) { _, newCols in
                        session.columns = newCols
                        Task { await session.initializeTiles(count: session.rows * newCols) }
                    }
                    .onChange(of: session.rows) { _, _ in
                        session.columns = cols
                        Task { await session.initializeTiles(count: session.rows * cols) }
                    }
                }

                if showsToolbar && revealedToolbar {
                    toolbarOverlay(topInset: deviceTopSafeInset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Brand-styled loading overlay during the initial
                // fan-out fetch of card images. Fades out once enough
                // tiles have populated to look "full." Covers the
                // sparse-dark-placeholder state that previously read
                // as a blank screen.
                if isInitialLoading {
                    ShowcaseLoadingOverlay()
                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea(.all, edges: .all)
        // Pinch-to-zoom: commit only on .onEnded to avoid stacking
        // withAnimation calls on every onChanged tick (which produced
        // the "Invalid sample AnimatablePair" console spam and made
        // the layout reflow fight every frame).
        .gesture(
            showsToolbar
            ? MagnifyGesture()
                .onEnded { value in
                    let mag = max(0.1, min(10.0, value.magnification))
                    let raw = Double(rowsAtPinchStart) / mag
                    guard raw.isFinite else { return }
                    let candidate = Int(round(raw))
                    let clamped = max(minRows, min(maxRows, candidate))
                    if clamped != session.rows {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            session.rows = clamped
                        }
                    }
                    rowsAtPinchStart = clamped
                }
            : nil
        )
        .onAppear {
            rowsAtPinchStart = session.rows
            if showsToolbar { scheduleToolbarHide() }
        }
        .onDisappear {
            toolbarHideTask?.cancel()
        }
        // (cycle loop + scenePhase + thermal observers moved to
        // CollectionShowcaseView so they survive the grid ↔ panel
        // swap when AirPlay engages.)
        .statusBar(hidden: true)
    }

    // MARK: Toolbar

    /// Toolbar overlay. `topInset` is the device's actual top safe-
    /// area (Dynamic Island in portrait, ~0 in landscape on most
    /// iPhones, ~24pt on home-indicator iPads). Reading this from
    /// GeometryReader instead of hardcoding 56pt is what makes the
    /// toolbar usable in landscape — the previous fixed inset pushed
    /// content into nowhere-tappable territory in some orientations.
    private func toolbarOverlay(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Close Showcase")

                Spacer()

                Text("PERSONAL SHOWCASE")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    session.paused.toggle()
                    if !session.paused { session.cycleEpoch &+= 1 }
                    revealToolbar()
                } label: {
                    Image(systemName: session.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(session.paused ? "Resume" : "Pause")

                // AirPlay-Video picker. Now functional: the streamer
                // owns an AVPlayer with allowsExternalPlayback=true
                // playing a local HLS stream of the Showcase grid.
                // Tap → system picker → choose Apple TV → AVPlayer
                // routes the H.264 stream to the TV (no Screen
                // Mirroring), phone-side swaps to control panel.
                if let player = streamer?.player {
                    RoutePickerView(player: player)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                        .accessibilityLabel("AirPlay")
                }
            }
            .padding(.horizontal, 20)
            // Pad past safe area + 8pt clearance. In landscape this
            // collapses to ~8-12pt total; in portrait Dynamic Island
            // it expands to ~56-64pt.
            .padding(.top, max(topInset, 8) + 8)
            .padding(.bottom, 14)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.92),
                        Color.black.opacity(0.78),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: max(topInset, 8) + 110)
                .offset(y: -10),
                alignment: .top
            )
        }
    }

    private func revealToolbar() {
        withAnimation(.easeOut(duration: 0.2)) { revealedToolbar = true }
        scheduleToolbarHide()
    }

    private func scheduleToolbarHide() {
        toolbarHideTask?.cancel()
        toolbarHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.3)) { revealedToolbar = false }
            }
        }
    }
}

// MARK: - ShowcaseControlPanel
//
// Phone-side controls when the grid is displaying on an external
// screen (TV). Brand-styled controls (BOBA Cyan accents, monospaced
// labels) over a near-black background.
//
// Sliders:
//   - Rows on TV (2-12)
//   - Cycle speed (3-15 seconds)
// Toggles:
//   - Each animation variant (Flip, Drop, Roll Drop, Spin, Corner Drop,
//     Row Drop, Row Roll Drop)
//   - "Mirror to phone" — when off, phone shows control panel only;
//     when on, phone also mirrors the grid (split attention; default off)
// Buttons:
//   - Pause / Resume
//   - Use phone display (returns Showcase to phone-only)
//   - Done (dismiss entirely)
struct ShowcaseControlPanel: View {
    @Bindable var session: ShowcaseSession
    var streamer: ShowcaseVideoStreamer?
    var onDismiss: () -> Void
    @State private var externalManager = ExternalDisplayManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    nowShowingCard
                    playbackCard
                    layoutCard
                    variantsCard
                }
                .padding(20)
            }
            .background(Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255).ignoresSafeArea())
            .navigationTitle("Personal Showcase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(.white)
                }
                // No top-right action — to stop AirPlay the user opens
                // Control Center → AirPlay picker → iPhone. The
                // previous "Use Phone" button only affected the
                // Screen Mirroring path (ExternalDisplayManager) and
                // did nothing for the AirPlay-Video routing flow,
                // which is the canonical path now.
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var nowShowingCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "tv.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(red: 0, green: 0xF5/255, blue: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPLAYING ON TV")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(session.rows) rows · \(session.cards.count) cards in pool")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("PLAYBACK")

            HStack(spacing: 12) {
                Button {
                    session.paused.toggle()
                    if !session.paused { session.cycleEpoch &+= 1 }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: session.paused ? "play.fill" : "pause.fill")
                        Text(session.paused ? "Resume" : "Pause")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(session.paused
                                  ? Color(red: 1, green: 0x4D/255, blue: 0)
                                  : Color.white.opacity(0.15))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Card Swap Interval")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("every \(Int(session.cycleSpeed))s")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Slider(value: $session.cycleSpeed, in: 3.0...15.0, step: 1.0)
                    .tint(Color(red: 0, green: 0xF5/255, blue: 1))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var layoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("LAYOUT")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Rows on TV")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(session.rows)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Slider(
                    value: Binding(
                        get: { Double(session.rows) },
                        set: { session.rows = Int($0) }
                    ),
                    in: 2.0...12.0,
                    step: 1.0
                )
                .tint(Color(red: 0, green: 0xF5/255, blue: 1))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var variantsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ANIMATIONS")
            ForEach(ShowcaseAnimation.allCases) { variant in
                Toggle(isOn: Binding(
                    get: { session.enabledVariants.contains(variant) },
                    set: { isOn in
                        if isOn {
                            session.enabledVariants.insert(variant)
                        } else if session.enabledVariants.count > 1 {
                            // Keep at least one variant enabled.
                            session.enabledVariants.remove(variant)
                        }
                    }
                )) {
                    Text(variant.displayName)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                .tint(Color(red: 0, green: 0xF5/255, blue: 1))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.6))
    }
}

// MARK: - ExternalShowcaseRoot
//
// Hosted on the external-display UIWindow via UIHostingController in
// ExternalDisplaySceneDelegate. Reads ExternalDisplayManager.shared
// for the active session. Two states:
//   - session present + renderTarget == .external → ShowcaseGridView (no toolbar)
//   - else → idle placeholder ("Open Personal Showcase in the app")
struct ExternalShowcaseRoot: View {
    @State private var externalManager = ExternalDisplayManager.shared

    var body: some View {
        ZStack {
            Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)
                .ignoresSafeArea()

            if let session = externalManager.session,
               session.renderTarget == .external {
                // External (mirror) path doesn't need a streamer
                // reference — the TV is being driven by Screen
                // Mirroring, not AirPlay-Video. Pass nil so the
                // toolbar-less grid renders without the route picker.
                ShowcaseGridView(
                    session: session,
                    streamer: nil,
                    showsToolbar: false,
                    onDismiss: nil
                )
            } else {
                idlePlaceholder
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 84))
                .foregroundStyle(.white.opacity(0.35))
            Text("BOBA PLAYBOOK")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.white)
            Text("Open Personal Showcase in the app to display here")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - ShowcaseTileCell
//
// Renders the tile via the "layered exit" pattern: the persistent
// `front` image is always at rest (never rotated, never translated)
// so the cell never displays an upside-down card. The optional `exit`
// overlay sits on top during a non-flip animation and animates away
// (translate / rotate / fade) to reveal the new `front` underneath.
//
// The 3D Y-flip variant is special — it uses the front + back face
// pattern via faceUp, which is the only animation that touches the
// tile's container rotation. The exit overlay is hidden during flips.
private struct ShowcaseTileCell: View {
    @Bindable var state: ShowcaseTileState
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            // Persistent front face (always at rest — never rotated,
            // never translated).
            face(image: state.front)
                .opacity(state.faceUp ? 1 : 0)

            // Flip back face (only visible during a flip animation).
            face(image: state.back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(state.faceUp ? 0 : 1)

            // Exit overlay (only present during non-flip variants).
            // Animates translate / rotation / opacity away to reveal
            // the new `front` underneath. Cleared after animation.
            if let exit = state.exitImage {
                Image(uiImage: exit)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .opacity(state.exitOpacity)
                    .rotationEffect(.degrees(state.exitRotation))
                    .offset(x: state.exitOffsetX, y: state.exitOffsetY)
                    .allowsHitTesting(false)
            }
        }
        .rotation3DEffect(
            .degrees(state.faceUp ? 0 : 180),
            axis: (x: 0, y: 1, z: 0)
        )
        .frame(width: width, height: height)
        // NO outer .clipped() — the persistent front face has its own
        // .clipped() inside face(), but we want the exit overlay to
        // render OUTSIDE the cell bounds so the card visibly falls
        // down through the grid (over neighbor cells). The parent
        // ShowcaseGridView ZStack lifts this cell's zIndex while an
        // exit animation is active so it composites above its
        // neighbors during the fall.
        .onAppear { state.setCellSize(width, height) }
        .onChange(of: width) { _, w in state.setCellSize(w, height) }
        .onChange(of: height) { _, h in state.setCellSize(width, h) }
    }

    @ViewBuilder
    private func face(image: UIImage?) -> some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        } else {
            Color(red: 0x0D/255, green: 0x0D/255, blue: 0x1A/255)
        }
    }
}

// MARK: - ShowcaseTileState
//
// Two separate animation pipelines:
//   1. Flip — Y-axis 3D rotation via `faceUp` toggling front/back faces.
//      Front stays at rest; back is the offscreen face that gets the
//      new image before rotation. Canonical iTunes behavior.
//   2. Exit-reveal — for every non-flip variant (drop, rollDrop,
//      pinRotation, dropFromCorner, row variants). The new image
//      slides into `front` instantly; the OLD image is copied into
//      `exitImage` and animates away to reveal the new one underneath.
//      Front itself never moves, so the tile never shows an inverted
//      card at any point in the animation.
@Observable
@MainActor
final class ShowcaseTileState: Identifiable {
    let id = UUID()
    var currentBobaId: String?

    // Persistent visible image (never rotated, never translated).
    var front: UIImage?

    // 3D flip state — flip variant only.
    var back: UIImage?
    var faceUp: Bool = true

    // Exit overlay — every non-flip variant uses these to animate the
    // OLD image away while `front` already holds the NEW image
    // underneath. All four reset to identity after each animation.
    var exitImage: UIImage?
    var exitOffsetX: CGFloat = 0
    var exitOffsetY: CGFloat = 0
    var exitRotation: Double = 0
    var exitOpacity: Double = 1

    func animate(to next: UIImage, variant: ShowcaseAnimation, reduceMotion: Bool) async {
        if reduceMotion {
            crossfade(to: next)
            try? await Task.sleep(for: .milliseconds(400))
            return
        }
        if variant == .flip {
            await flip(to: next)
        } else {
            await exitReveal(to: next, variant: variant)
        }
    }

    // MARK: Flip

    /// 3D Y-axis flip. The hidden face receives the new image before
    /// rotation, so the swap is invisible at mid-flip when the tile
    /// edge is camera-on.
    private func flip(to next: UIImage) async {
        if faceUp {
            back = next
            withAnimation(.easeInOut(duration: 0.75)) { faceUp = false }
        } else {
            front = next
            withAnimation(.easeInOut(duration: 0.75)) { faceUp = true }
        }
        try? await Task.sleep(for: .milliseconds(760))
    }

    // MARK: Exit-reveal (drop / rollDrop / pinRotation / dropFromCorner)

    /// Set up the exit overlay with the current image, swap `front`
    /// to the new image, then animate the overlay away per variant.
    /// Reset overlay to identity once done.
    private func exitReveal(to next: UIImage, variant: ShowcaseAnimation) async {
        // Capture currently-visible image as the exit overlay.
        let visible = faceUp ? front : back
        exitImage = visible
        exitOffsetX = 0
        exitOffsetY = 0
        exitRotation = 0
        exitOpacity = 1

        // New image instantly takes the persistent slot underneath.
        if faceUp { front = next } else { back = next }

        // One frame for state to settle (otherwise the implicit
        // animation can pick up the new exitImage assignment).
        try? await Task.sleep(for: .milliseconds(16))

        switch variant {
        case .drop, .rowDrop:
            // Fall down past 4-ish cells of neighbors, with gravity
            // accel. The parent ZStack lifts our zIndex during this
            // animation so the card composites over its neighbors.
            withAnimation(.timingCurve(0.4, 0, 0.7, 1, duration: 1.1)) {
                exitOffsetY = height * 5
                exitOpacity = 0.85
            }
            try? await Task.sleep(for: .milliseconds(1110))

        case .rollDrop, .rowRollDrop:
            // Fall down + full 360° spin (lands upright, never mid-rotation).
            withAnimation(.timingCurve(0.4, 0, 0.7, 1, duration: 1.2)) {
                exitOffsetY = height * 5
                exitRotation = 360
                exitOpacity = 0.85
            }
            try? await Task.sleep(for: .milliseconds(1210))

        case .pinRotation:
            // Full 360° rotation in place + crossfade. Always lands
            // upright (never visibly upside-down).
            withAnimation(.easeInOut(duration: 1.0)) {
                exitRotation = 360
                exitOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(1010))

        case .dropFromCorner:
            // Fly out toward a random corner past 4-5 neighbors, with
            // a slight rotation. Card stays mostly visible during
            // travel so the trajectory reads.
            let xDir: CGFloat = Bool.random() ? 1 : -1
            let yDir: CGFloat = Bool.random() ? 1 : -1
            withAnimation(.timingCurve(0.4, 0, 0.7, 1, duration: 1.2)) {
                exitOffsetX = width * 5 * xDir
                exitOffsetY = height * 5 * yDir
                exitRotation = xDir * 20
                exitOpacity = 0.8
            }
            try? await Task.sleep(for: .milliseconds(1210))

        case .flip:
            break // handled above
        }

        // Reset overlay to identity for the next cycle.
        exitImage = nil
        exitOffsetX = 0
        exitOffsetY = 0
        exitRotation = 0
        exitOpacity = 1
    }

    // Cell dimensions used inside the animation (drop distance scales
    // with cell height so the card visibly clears its own bounds).
    // The tile cell sets these when it mounts; defaults are sized for
    // a typical 6-row iPhone layout if a tile animates before the cell
    // ever reports its frame.
    private var width: CGFloat { _animationWidth ?? 200 }
    private var height: CGFloat { _animationHeight ?? 280 }
    var _animationWidth: CGFloat?
    var _animationHeight: CGFloat?

    func setCellSize(_ w: CGFloat, _ h: CGFloat) {
        _animationWidth = w
        _animationHeight = h
    }

    func crossfade(to next: UIImage) {
        if faceUp {
            withAnimation(.easeInOut(duration: 0.4)) { front = next }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { back = next }
        }
    }
}

// MARK: - ShowcaseImagePool

@Observable
@MainActor
final class ShowcaseImagePool {
    private var candidates: [Card] = []
    private var cursor: Int = 0
    private let decodedCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()

    func setCandidates(_ cards: [Card]) {
        if candidates.map(\.id) == cards.map(\.id) { return }
        candidates = cards
        cursor = 0
    }

    /// Synchronous card selection with no-adjacent-duplicates retry.
    /// Returns nil only when the candidate pool is empty.
    func pickCard(excluding: Set<String> = []) -> Card? {
        guard !candidates.isEmpty else { return nil }
        for _ in 0..<8 {
            let card = advance()
            if !excluding.contains(card.id) { return card }
        }
        return advance() // fallback: accept a potential duplicate
    }

    /// Async card+image picker for the cycle path. Picks a card (with
    /// retries on adjacency), loads its full-res image, returns both.
    /// Cycle animations want the higher-quality full URL; initial tile
    /// fill calls `loadImage(for:preferThumb:true)` separately.
    func nextImage(excluding: Set<String> = []) async -> (String, UIImage)? {
        guard let card = pickCard(excluding: excluding) else { return nil }
        if let img = await loadImage(for: card, preferThumb: false) {
            return (card.id, img)
        }
        return nil
    }

    private func advance() -> Card {
        let card = candidates[cursor]
        cursor += 1
        if cursor >= candidates.count {
            cursor = 0
            candidates.shuffle()
        }
        return card
    }

    /// Load + decode a card's image. `preferThumb: true` uses the
    /// 200px thumbnail tier (~10KB, fast initial paint); false uses
    /// the ≤1200px full tier (~80KB, sharper for animation cycles).
    func loadImage(for card: Card, preferThumb: Bool) async -> UIImage? {
        let url: URL?
        if preferThumb {
            url = CDN.thumbURL(for: card)
        } else {
            url = CDN.fullURL(for: card)
        }
        guard let url else { return nil }
        let key = url.absoluteString as NSString
        if let cached = decodedCache.object(forKey: key) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = await Self.decode(data) else { return nil }
            decodedCache.setObject(
                decoded,
                forKey: key,
                cost: Int(decoded.size.width * decoded.size.height * 4)
            )
            return decoded
        } catch {
            return nil
        }
    }

    private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, [
                      kCGImageSourceShouldCache: true,
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary)
            else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }
}

// MARK: - RoutePickerView

private struct RoutePickerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        v.activeTintColor = UIColor(red: 0, green: 0xF5/255, blue: 1, alpha: 1)
        v.tintColor = .white
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // AVRoutePickerView routes the system AVRouteDetector pick; no
        // explicit player binding API. AVPlayer.allowsExternalPlayback
        // gates whether the player participates in AirPlay-Video.
    }
}

// MARK: - AirPlaySurface
//
// **This view is the load-bearing missing piece for AirPlay-Video.**
//
// Per Apple's AVPlayer.allowsExternalPlayback docs:
// "External playback can only be enabled if the player is playing
// the asset using an instance of AVPlayerLayer or one of its
// derivatives. If the player is using a different type of layer,
// AirPlay video can't be enabled."
//
// In v2.131-v2.134 our AVPlayer was playing the local HLS stream
// "headless" — no AVPlayerLayer in the view hierarchy. The system
// route picker still surfaced AirPlay destinations (the picker is
// system-level), but picking one silently failed to engage
// AirPlay-Video because iOS couldn't find a valid video surface to
// route from. The v2.134 trace confirmed: every other signal
// (player.status=readyToPlay, rate=1.0, segments fetching) was fine
// EXCEPT isExternalPlaybackActive never flipped to true.
//
// Pattern: a UIView whose backing layer IS an AVPlayerLayer (via
// `layerClass` override). Mounted in the view hierarchy at near-zero
// opacity. The system now has a valid AVPlayerLayer to route. This
// is the iOS 8 → iOS 26 canonical pattern; Apple has not deprecated
// or replaced it.
private struct AirPlaySurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AVPlayerContainerView {
        let view = AVPlayerContainerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: AVPlayerContainerView, context: Context) {
        uiView.player = player
    }
}

private final class AVPlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}

// =============================================================================
// MARK: - SHOWCASE VIDEO PIPELINE
//
// Inlined here (instead of its own file) per memory
// `feedback_xcode_synchronized_groups.md` — Xcode's
// PBXFileSystemSynchronizedRootGroup intermittently fails to pick up
// new Swift files. Keeping this in CollectionShowcaseView.swift
// guarantees Xcode finds the new types on a clean build.
// =============================================================================

// MARK: - Showcase diagnostics
//
// Plain `print()` per memory feedback_diagnostic_console.md — use
// the Xcode console, not os.Logger which needs Console.app + device
// sidebar setup. Filter by tag `[Showcase]` when watching.
@inline(__always)
nonisolated func showcaseLog(_ message: @autoclosure () -> String) {
    print("[Showcase] \(message())")
}

// MARK: - LAN IP helper
//
// Returns the iPhone's Wi-Fi (en0) IPv4 address so AVPlayer can hand
// Apple TV a URL the TV can actually fetch. The Apple TV cannot
// reach the iPhone's `127.0.0.1` — that's its own loopback. The
// research report flagged this as "inferred — verify on-device,"
// and on-device verification confirms: tapping AirPlay + picking
// Apple TV did nothing because the TV got a localhost URL it
// couldn't dial. With the LAN IP, Apple TV fetches the HLS playlist
// directly (we already bind NWListener to .any so the server
// answers both interfaces).
nonisolated func showcaseLocalIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee
        let family = interface.ifa_addr.pointee.sa_family
        guard family == UInt8(AF_INET) else { continue }
        let name = String(cString: interface.ifa_name)
        // en0 = Wi-Fi on iPhone. pdp_ip* = cellular (no AirPlay), skip.
        guard name == "en0" else { continue }
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
            interface.ifa_addr,
            socklen_t(interface.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        let addr = String(cString: hostname)
        // Skip self-assigned / link-local 169.254.x.x.
        if !addr.hasPrefix("169.254") {
            address = addr
            break
        }
    }
    return address
}

// MARK: - ShowcaseVideoConstants
//
// `nonisolated` overrides the project's default-MainActor isolation
// (per memory feedback_project_default_mainactor_isolation.md). These
// are compile-time constants that need to be readable from the
// AVAssetWriterDelegate callback (which fires on a nonisolated
// background queue) without crossing an actor boundary.
nonisolated enum ShowcaseVideoConstants {
    /// TV output dimensions. 1920×1080 = standard 16:9 HD.
    static let renderWidth: Int = 1920
    static let renderHeight: Int = 1080

    /// Source capture cadence — how often we re-snapshot the SwiftUI
    /// grid view. Apple TV's pipeline judders at unusual frame rates,
    /// so each source frame is repeated 3× during encode to land on a
    /// clean 30 fps stream (per WWDC HLS-on-tvOS guidance).
    static let captureFPS: Int = 10
    static let encodeFPS: Int32 = 30

    /// Segment duration. 2s gives a fast first-segment time so the
    /// AVPlayer has playable content within ~2s of Showcase opening,
    /// which is what enables AirPlay-Video routing to work when the
    /// user taps the in-app picker. Apple's HLS Authoring Spec
    /// permits 2s as the lower bound (full LL-HLS spec goes lower,
    /// but for our purposes 2s is the responsiveness/overhead sweet
    /// spot).
    static let segmentDurationSeconds: Double = 2.0

    /// Sliding-window: keep N most-recent segments in the playlist.
    /// Older segment files are deleted to bound temp storage.
    static let segmentWindowSize: Int = 8

    /// Video bitrate. 4 Mbps is Apple's middle-of-the-road for 1080p
    /// in the HLS Authoring Specification.
    static let bitrate: Int = 4_000_000

    /// Card aspect ratio (width / height) for the TV-side render.
    static let cardAspect: CGFloat = 0.75
}

// MARK: - ShowcaseVideoStreamer
//
// Renders the Showcase grid at 1920×1080 via ImageRenderer at 10 fps,
// encodes through AVAssetWriter in HLS-fMP4 profile, serves the
// resulting fragments via a localhost HTTP listener, and consumes them
// in a single AVPlayer with AirPlay-Video routing enabled.
//
// Implementation follows the WWDC20 10011 + WWDC19 501 guidance: one
// AVAssetWriter for the whole session emitting segments via the
// delegate; CVPixelBuffer from the adaptor's pool; H.264 30 fps with
// each source frame appended 3× so Apple TV's video pipeline doesn't
// judder; CADisplayLink + autoreleasepool for frame production; KVO
// on isExternalPlaybackActive to drive the phone-side UI swap.
@MainActor
@Observable
final class ShowcaseVideoStreamer: NSObject {

    // MARK: Public observable state

    /// True when AVPlayer routing reports external playback active —
    /// i.e., AirPlay-Video has taken over and the phone-side view can
    /// swap to the control-panel layout.
    private(set) var isExternalPlaybackActive: Bool = false

    /// True between `start()` and `stop()`.
    private(set) var isRunning: Bool = false

    /// The route picker view should bind to this AVPlayer.
    private(set) var player: AVPlayer = AVPlayer()

    // MARK: Dependencies

    private weak var session: ShowcaseSession?

    // MARK: Encoder

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var displayLink: CADisplayLink?
    private var sourceFrameIndex: Int64 = 0

    // Silent audio track — required for AirPlay-Video. Research-
    // confirmed: AirPlay-Video routing is rooted in the audio session
    // mechanism, and video-only HLS streams fail to route. Silent AAC
    // gives the routing engine something to bind to.
    private var audioInput: AVAssetWriterInput?
    private var audioFormatDescription: CMAudioFormatDescription?

    // MARK: Playlist + server

    private var segmentDir: URL?
    private var playlist = HLSPlaylistBuilder()
    private var server: LocalHLSServer?
    /// Sendable bridge between MainActor (where playlist + segment
    /// metadata live) and the background NWListener queue (where the
    /// HTTP request handler reads). MainActor pushes into the cache
    /// whenever the playlist or segment files change; the server's
    /// provider closure reads without any actor hop (no semaphore
    /// deadlock risk).
    private let serverCache = ShowcaseHLSServerCache()

    // MARK: KVO / Combine

    /// Combine subscription on AVPlayer.isExternalPlaybackActive.
    /// We use Combine + .sink (not @Sendable) instead of
    /// NSKeyValueObservation + Task { @MainActor }, because Swift 6
    /// flags the nested Task self-capture as "Reference to captured
    /// var 'self' in concurrently-executing code." Combine's sink
    /// closure runs on the queue we specify (.main here), no concurrent
    /// closure boundary to cross.
    private var externalPlaybackCancellable: AnyCancellable?
    /// KVO subscriptions for diagnostics — surface player + item
    /// failures in the console so we stop guessing what's wrong.
    private var playerStatusCancellable: AnyCancellable?
    private var playerRateCancellable: AnyCancellable?
    private var playerTimeControlCancellable: AnyCancellable?
    private var playerWaitingReasonCancellable: AnyCancellable?
    private var itemStatusCancellable: AnyCancellable?
    private var itemErrorLogObserver: NSObjectProtocol?
    private var audioRouteObserver: NSObjectProtocol?

    // MARK: Init

    init(session: ShowcaseSession) {
        self.session = session
        super.init()

        // Configure player for AirPlay-Video routing per WWDC19 501.
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.isMuted = true   // no audio track in our stream

        externalPlaybackCancellable = player.publisher(for: \.isExternalPlaybackActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                showcaseLog("AVPlayer.isExternalPlaybackActive → \(value)")
                self?.isExternalPlaybackActive = value
            }
        playerStatusCancellable = player.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                let label = Self.describe(playerStatus: status)
                showcaseLog("AVPlayer.status → \(label)")
                if status == .failed, let player = self?.player {
                    showcaseLog("AVPlayer.error → \(player.error?.localizedDescription ?? "nil")")
                }
            }
        playerRateCancellable = player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { rate in
                showcaseLog("AVPlayer.rate → \(rate)")
            }
        playerTimeControlCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { status in
                let label: String
                switch status {
                case .paused: label = "paused"
                case .waitingToPlayAtSpecifiedRate: label = "waitingToPlayAtSpecifiedRate"
                case .playing: label = "playing"
                @unknown default: label = "@unknown"
                }
                showcaseLog("AVPlayer.timeControlStatus → \(label)")
            }
        playerWaitingReasonCancellable = player.publisher(for: \.reasonForWaitingToPlay)
            .receive(on: DispatchQueue.main)
            .sink { reason in
                if let raw = reason?.rawValue {
                    showcaseLog("AVPlayer.reasonForWaitingToPlay → \(raw)")
                }
            }
    }

    // No deinit — Swift 6's deinit is nonisolated and can't access
    // MainActor-isolated stored properties. We clean up in stop()
    // instead, which is always called from onDisappear before the
    // streamer goes out of scope.

    // MARK: Lifecycle

    /// Async startup so we don't block MainActor on the NWListener's
    /// "ready" state. The view calls this from `.task { await
    /// streamer.start() }`, which suspends the task during the server
    /// startup and lets the grid render immediately.
    ///
    /// IMPORTANT: we do NOT call attachPlayerToPlaylist() here.
    /// AVPlayer fails to play an empty HLS playlist and never engages
    /// AirPlay-Video, which is the root cause of "tapping AirPlay
    /// does nothing." Instead, the AVAssetWriterDelegate kicks the
    /// player off after the first .separable segment lands (~2s with
    /// our segmentDurationSeconds). By then the playlist has real
    /// content, AVPlayer loads cleanly, and the in-app
    /// AVRoutePickerView routes via AirPlay-Video as expected.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        showcaseLog("start() begin")
        // Ensure the session has enough tiles for the TV-sized grid.
        // The phone-side view initializes for its own (smaller) cell
        // count; if AirPlay engages without the streamer kicking off
        // a TV-sized init, the TV ends up rendering only the phone's
        // subset of tiles, with the rest as black background.
        if let session {
            let tvRows = max(2, session.rows)
            let tvCellH = CGFloat(ShowcaseVideoConstants.renderHeight) / CGFloat(tvRows)
            let tvCellW = tvCellH * ShowcaseVideoConstants.cardAspect
            let tvCols = max(1, Int(ceil(CGFloat(ShowcaseVideoConstants.renderWidth) / tvCellW)))
            let tvTotal = tvRows * tvCols
            if session.tiles.count < tvTotal {
                session.columns = max(session.columns, tvCols)
                Task { await session.initializeTiles(count: tvTotal) }
            }
        }
        // AVAudioSession MUST be configured before AVPlayer routing
        // engages. Without .playback + .moviePlayback + .longFormVideo
        // policy, AVRoutePickerView surfaces destinations but picking
        // one routes via AirPlay-AUDIO (or nothing at all) — never
        // AirPlay-Video. The diagnostic trace showed isExternalPlayback
        // Active stayed false because AVPlayer's AirPlay engine treats
        // the default .soloAmbient session as "not a video player."
        configureAudioSession()
        setupAudioRouteObserver()
        do {
            try prepareSegmentDir()
            showcaseLog("segmentDir ready: \(segmentDir?.path ?? "nil")")
            try await startServer()
            showcaseLog("server ready on port \(server?.port ?? 0); LAN IP \(showcaseLocalIPAddress() ?? "nil")")
            try startWriter()
            showcaseLog("writer started, status=\(writer?.status.rawValue ?? -1)")
            startCapture()
            showcaseLog("capture loop running at \(ShowcaseVideoConstants.captureFPS) fps")
            // Player attachment is deferred — see handleSegment.
        } catch {
            showcaseLog("start() FAILED: \(error.localizedDescription)")
            stop()
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .longFormVideo,
                options: []
            )
            try session.setActive(true)
            let route = session.currentRoute
            let outputs = route.outputs
                .map { "\($0.portName)/\($0.portType.rawValue)" }
                .joined(separator: ", ")
            showcaseLog("AudioSession set: category=playback mode=moviePlayback policy=longFormVideo")
            showcaseLog("AudioSession.currentRoute outputs=[\(outputs)]")
        } catch {
            showcaseLog("AudioSession setup FAILED: \(error.localizedDescription)")
        }
    }

    private func setupAudioRouteObserver() {
        if let old = audioRouteObserver {
            NotificationCenter.default.removeObserver(old)
        }
        audioRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            let reasonRaw = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 999
            let reason: String = {
                switch reasonRaw {
                case 0: return "unknown"
                case 1: return "newDeviceAvailable"
                case 2: return "oldDeviceUnavailable"
                case 3: return "categoryChange"
                case 4: return "override"
                case 6: return "wakeFromSleep"
                case 7: return "noSuitableRouteForCategory"
                case 8: return "routeConfigurationChange"
                default: return "raw=\(reasonRaw)"
                }
            }()
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
                .map { "\($0.portName)/\($0.portType.rawValue)" }
                .joined(separator: ", ")
            showcaseLog("AudioSession.routeChange reason=\(reason) outputs=[\(outputs)]")
        }
    }

    /// True once the first .separable HLS segment has been written
    /// and the AVPlayer has been pointed at the playlist URL.
    private var playerAttached: Bool = false

    func stop() {
        guard isRunning else { return }
        showcaseLog("stop()")
        isRunning = false
        stopCapture()
        finalizeWriter()
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerAttached = false
        server?.stop()
        server = nil
        cleanupSegmentDir()
        externalPlaybackCancellable?.cancel()
        externalPlaybackCancellable = nil
        playerStatusCancellable?.cancel()
        playerStatusCancellable = nil
        playerRateCancellable?.cancel()
        playerRateCancellable = nil
        playerTimeControlCancellable?.cancel()
        playerTimeControlCancellable = nil
        playerWaitingReasonCancellable?.cancel()
        playerWaitingReasonCancellable = nil
        itemStatusCancellable?.cancel()
        itemStatusCancellable = nil
        if let observer = itemErrorLogObserver {
            NotificationCenter.default.removeObserver(observer)
            itemErrorLogObserver = nil
        }
        if let observer = audioRouteObserver {
            NotificationCenter.default.removeObserver(observer)
            audioRouteObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Segment dir

    private func prepareSegmentDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("showcase-hls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        segmentDir = dir
        playlist = HLSPlaylistBuilder()
    }

    private func cleanupSegmentDir() {
        guard let dir = segmentDir else { return }
        try? FileManager.default.removeItem(at: dir)
        segmentDir = nil
    }

    // MARK: - Server

    private func startServer() async throws {
        let server = LocalHLSServer()
        let cache = serverCache
        try await server.start { path in
            cache.lookup(path)
        }
        self.server = server
    }

    // MARK: - Writer

    private func startWriter() throws {
        guard segmentDir != nil else { return }
        let writer = AVAssetWriter(
            contentType: UTType(AVFileType.mp4.rawValue)!
        )
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(
            seconds: ShowcaseVideoConstants.segmentDurationSeconds,
            preferredTimescale: 1
        )
        writer.initialSegmentStartTime = .zero
        writer.shouldOptimizeForNetworkUse = true
        writer.delegate = self

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: ShowcaseVideoConstants.bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(ShowcaseVideoConstants.encodeFPS),
            AVVideoMaxKeyFrameIntervalKey: Int(ShowcaseVideoConstants.encodeFPS),
            AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: false
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ShowcaseVideoConstants.renderWidth,
            AVVideoHeightKey: ShowcaseVideoConstants.renderHeight,
            AVVideoCompressionPropertiesKey: compression
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        input.mediaTimeScale = ShowcaseVideoConstants.encodeFPS

        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ShowcaseVideoConstants.renderWidth,
            kCVPixelBufferHeightKey as String: ShowcaseVideoConstants.renderHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttrs
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "ShowcaseVideoStreamer", code: 1)
        }
        writer.add(input)

        // Silent AAC audio track. The HLS Authoring Spec recommends
        // an audio rendition for every video, AirPlay-Video's routing
        // engine binds via the audio-session mechanism, and there are
        // widely-reported failures for video-only HLS streams. Silent
        // mono AAC at 64 kbps is the minimum-viable answer.
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(audioInput) else {
            throw NSError(domain: "ShowcaseVideoStreamer", code: 4)
        }
        writer.add(audioInput)

        // Source format description for silent 16-bit signed-int PCM
        // input. The AAC encoder swallows this and emits AAC packets
        // into the fragmented MP4 segments.
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var fmt: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &fmt
        )
        self.audioFormatDescription = fmt

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "ShowcaseVideoStreamer", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.audioInput = audioInput
        self.sourceFrameIndex = 0
    }

    /// Append a silent PCM sample buffer for one source-frame's worth
    /// of audio (1/captureFPS seconds). Matches the video timeline so
    /// AVAssetWriter can multiplex into HLS segments correctly.
    private func appendSilentAudio(sourceIndex: Int64) {
        guard let audioInput, audioInput.isReadyForMoreMediaData,
              let formatDesc = audioFormatDescription else { return }

        let audioSampleRate: Double = 44_100
        let sourceFPS: Double = Double(ShowcaseVideoConstants.captureFPS)
        let framesPerAppend = Int(audioSampleRate / sourceFPS)   // 4410 frames per 0.1s
        let bytesPerSample = 2
        let totalBytes = framesPerAppend * bytesPerSample

        var blockBuffer: CMBlockBuffer?
        let bbStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: totalBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard bbStatus == kCMBlockBufferNoErr, let blockBuffer else { return }
        CMBlockBufferFillDataBytes(
            with: 0,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: totalBytes
        )

        let pts = CMTime(
            value: sourceIndex * Int64(framesPerAppend),
            timescale: Int32(audioSampleRate)
        )
        let duration = CMTime(
            value: Int64(framesPerAppend),
            timescale: Int32(audioSampleRate)
        )
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sizePerSample: Int = bytesPerSample

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(framesPerAppend),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sizePerSample,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }
        audioInput.append(sampleBuffer)
    }

    private func finalizeWriter() {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer?.finishWriting { }
        writer = nil
        videoInput = nil
        adaptor = nil
        audioInput = nil
        audioFormatDescription = nil
    }

    // MARK: - Capture

    private func startCapture() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 8,
            maximum: 12,
            preferred: Float(ShowcaseVideoConstants.captureFPS)
        )
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func stopCapture() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        autoreleasepool {
            captureAndAppendFrame()
        }
    }

    private func captureAndAppendFrame() {
        guard let session, let adaptor, let input = videoInput else { return }
        guard input.isReadyForMoreMediaData else { return }
        guard let pool = adaptor.pixelBufferPool else { return }

        let renderer = ImageRenderer(content:
            ShowcaseTVRenderView(session: session)
                .frame(
                    width: CGFloat(ShowcaseVideoConstants.renderWidth),
                    height: CGFloat(ShowcaseVideoConstants.renderHeight)
                )
                .background(Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255))
        )
        renderer.scale = 1.0
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return }
        guard let pixelBuffer = ShowcaseVideoStreamer.makePixelBuffer(from: cgImage, pool: pool) else { return }

        for offset in 0..<3 {
            guard input.isReadyForMoreMediaData else { return }
            let pts = CMTime(
                value: sourceFrameIndex * 3 + Int64(offset),
                timescale: ShowcaseVideoConstants.encodeFPS
            )
            adaptor.append(pixelBuffer, withPresentationTime: pts)
        }
        // Audio runs on its own sample-rate timeline; we append one
        // PCM buffer per source frame, covering 1/captureFPS seconds.
        appendSilentAudio(sourceIndex: sourceFrameIndex)
        sourceFrameIndex += 1
    }

    // MARK: - Pixel buffer

    /// CGImage → CVPixelBuffer via the adaptor's pool. BGRA +
    /// noneSkipFirst + byteOrder32Little matches the
    /// kCVPixelFormatType_32BGRA layout CGContext can write to without
    /// channel swaps (verified pattern from CoreMLHelpers).
    nonisolated static func makePixelBuffer(from cgImage: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    // MARK: - Player

    private func attachPlayerToPlaylist() {
        guard let server else {
            showcaseLog("attachPlayerToPlaylist FAILED — no server")
            return
        }
        // Apple TV cannot reach the iPhone's 127.0.0.1, so we hand it
        // the iPhone's Wi-Fi LAN IP. The NWListener binds to .any, so
        // our server already answers on both 127.0.0.1 and the LAN IP.
        let host = showcaseLocalIPAddress() ?? "127.0.0.1"
        guard let url = URL(string: "http://\(host):\(server.port)/index.m3u8") else {
            showcaseLog("attachPlayerToPlaylist FAILED — bad URL host=\(host) port=\(server.port)")
            return
        }
        showcaseLog("attaching player → \(url.absoluteString)")
        let item = AVPlayerItem(url: url)

        // KVO on the player item so we can surface load failures.
        itemStatusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                showcaseLog("AVPlayerItem.status → \(Self.describe(itemStatus: status))")
                if status == .failed {
                    showcaseLog("AVPlayerItem.error → \(item.error?.localizedDescription ?? "nil")")
                    if let underlying = item.error as NSError?,
                       let inner = underlying.userInfo[NSUnderlyingErrorKey] as? NSError {
                        showcaseLog("AVPlayerItem.underlying → \(inner.localizedDescription) (\(inner.domain) \(inner.code))")
                    }
                }
            }

        // HLS-specific error log — fires whenever the player encounters
        // a problem fetching/parsing segments. This catches the "player
        // gave up mid-stream" failure mode that AVPlayerItem.error
        // doesn't always surface.
        if let old = itemErrorLogObserver {
            NotificationCenter.default.removeObserver(old)
        }
        itemErrorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: .main
        ) { [weak item] _ in
            guard let entry = item?.errorLog()?.events.last else { return }
            showcaseLog(
                "AVPlayerItem ERROR_LOG status=\(entry.errorStatusCode) "
                + "comment=\(entry.errorComment ?? "nil") "
                + "domain=\(entry.errorDomain) "
                + "URI=\(entry.uri ?? "nil")"
            )
        }

        player.replaceCurrentItem(with: item)
    }

    private static func describe(itemStatus: AVPlayerItem.Status) -> String {
        switch itemStatus {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "@unknown"
        }
    }

    private static func describe(playerStatus: AVPlayer.Status) -> String {
        switch playerStatus {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "@unknown"
        }
    }
}

// MARK: - AVAssetWriterDelegate

extension ShowcaseVideoStreamer: AVAssetWriterDelegate {
    nonisolated func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        let duration: Double = {
            if let report = segmentReport,
               let track = report.trackReports.first(where: { $0.mediaType == .video }) {
                return CMTimeGetSeconds(track.duration)
            }
            return ShowcaseVideoConstants.segmentDurationSeconds
        }()
        let dataCopy = segmentData
        let type = segmentType
        Task { @MainActor [weak self] in
            self?.handleSegment(data: dataCopy, type: type, duration: duration)
        }
    }

    private func handleSegment(data: Data, type: AVAssetSegmentType, duration: Double) {
        guard let dir = segmentDir else { return }
        switch type {
        case .initialization:
            let file = dir.appendingPathComponent("init.mp4")
            try? data.write(to: file, options: .atomic)
            playlist.setInitSegment("init.mp4")
            serverCache.setSegmentFile("init.mp4", url: file)
            showcaseLog("segment INIT written, \(data.count) bytes → init.mp4")
        case .separable:
            let name = "seg\(playlist.nextSegmentIndex).m4s"
            let file = dir.appendingPathComponent(name)
            try? data.write(to: file, options: .atomic)
            playlist.appendSegment(name: name, duration: duration)
            serverCache.setSegmentFile(name, url: file)
            showcaseLog("segment SEPARABLE \(name), \(data.count) bytes, dur=\(String(format: "%.2f", duration))s")
            for old in playlist.evictedFiles {
                let url = dir.appendingPathComponent(old)
                try? FileManager.default.removeItem(at: url)
                serverCache.removeSegmentFile(old)
            }
            playlist.clearEvicted()
        @unknown default:
            break
        }
        // Refresh the playlist bytes the HTTP server will hand out.
        serverCache.setPlaylist(Data(playlist.serialize().utf8))

        // Deferred player attachment — only point AVPlayer at the
        // playlist after we have actual playable content. Loading an
        // empty m3u8 makes AVPlayer fail silently and never engage
        // AirPlay-Video, which was the "AirPlay does nothing" bug.
        if !playerAttached, case .separable = type {
            playerAttached = true
            attachPlayerToPlaylist()
            player.play()
        }
    }
}

// MARK: - HLSPlaylistBuilder

@MainActor
final class HLSPlaylistBuilder {
    private var initSegmentName: String?
    private var entries: [Entry] = []
    private(set) var nextSegmentIndex: Int = 0
    private(set) var mediaSequence: Int = 0
    private(set) var evictedFiles: [String] = []

    struct Entry {
        let name: String
        let duration: Double
    }

    func setInitSegment(_ name: String) {
        initSegmentName = name
    }

    func appendSegment(name: String, duration: Double) {
        entries.append(Entry(name: name, duration: duration))
        nextSegmentIndex += 1
        let window = ShowcaseVideoConstants.segmentWindowSize
        while entries.count > window {
            let removed = entries.removeFirst()
            evictedFiles.append(removed.name)
            mediaSequence += 1
        }
    }

    func clearEvicted() {
        evictedFiles.removeAll()
    }

    func serialize() -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        // Apple HLS Authoring Spec: required for fMP4 segment
        // playlists. Without it, AVPlayer parses the playlist but
        // won't fetch segments — which matches the v2.132 trace
        // (3 m3u8 polls, no init/segment requests after).
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        let maxDuration = entries.map(\.duration).max() ?? ShowcaseVideoConstants.segmentDurationSeconds
        lines.append("#EXT-X-TARGETDURATION:\(Int(ceil(maxDuration)))")
        lines.append("#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)")
        if let initName = initSegmentName {
            lines.append("#EXT-X-MAP:URI=\"\(initName)\"")
        }
        for entry in entries {
            lines.append(String(format: "#EXTINF:%.3f,", entry.duration))
            lines.append(entry.name)
        }
        // No #EXT-X-ENDLIST — this is a live playlist. \r\n line
        // endings per HLS spec canonical form.
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - ShowcaseHLSServerCache
//
// Sendable bridge between MainActor (where the playlist + segment
// metadata live) and the background NWListener queue (where the
// server's request handler reads). MainActor pushes into this cache
// whenever segments are written or the playlist is updated; the
// server's provider closure reads without crossing actor boundaries.
//
// Lock-protected for safe concurrent reads. `@unchecked Sendable`
// because the lock provides the synchronization Swift's checker
// can't see automatically. `nonisolated` so the project's
// SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor setting doesn't trap
// every property to MainActor (per memory
// feedback_project_default_mainactor_isolation.md — framework-
// callback classes need explicit nonisolated at the class level).
nonisolated final class ShowcaseHLSServerCache: @unchecked Sendable {
    private let lock = NSLock()
    private var playlist: Data = Data()
    private var segments: [String: URL] = [:]

    func setPlaylist(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        playlist = data
    }

    func setSegmentFile(_ name: String, url: URL) {
        lock.lock(); defer { lock.unlock() }
        segments[name] = url
    }

    func removeSegmentFile(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        segments.removeValue(forKey: name)
    }

    /// Sendable lookup safe for the LocalHLSServer's background queue.
    /// Returns (data, content-type) for index.m3u8 / init.mp4 / segN.m4s,
    /// or nil for a 404.
    func lookup(_ path: String) -> (Data, String)? {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if trimmed == "index.m3u8" {
            lock.lock(); defer { lock.unlock() }
            return (playlist, "application/vnd.apple.mpegurl")
        }
        let url: URL? = {
            lock.lock(); defer { lock.unlock() }
            return segments[trimmed]
        }()
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let mime = (trimmed.hasSuffix(".m4s") || trimmed.hasSuffix(".mp4"))
            ? "video/mp4"
            : "application/octet-stream"
        return (data, mime)
    }
}

// MARK: - LocalHLSServer
//
// Minimal HTTP/1.1 server on 127.0.0.1 via Network.framework's
// NWListener. The stateUpdateHandler intentionally does NOT capture
// self — it reads the listener's port via the listener reference
// captured in the closure (NWListener is safe to query for `.port`
// from any thread). `@unchecked Sendable` because we synchronize the
// mutable state internally with NSLock. `nonisolated` overrides the
// project's SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor so the @Sendable
// closures the NWListener calls back into can mutate `_port` /
// `_listener` (per memory
// feedback_project_default_mainactor_isolation.md).
/// Thread-safe one-shot flag for the NWListener stateUpdateHandler
/// continuation. `state` can fire multiple times (.ready, .cancelled,
/// etc) and we must resume the continuation exactly once.
private nonisolated final class ResumedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false
    func takeResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if consumed { return false }
        consumed = true
        return true
    }
}

nonisolated final class LocalHLSServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _port: UInt16 = 0
    private var _listener: NWListener?
    private let queue = DispatchQueue(label: "playbook.showcase.hls.server")
    private var provider: (@Sendable (String) -> (Data, String)?)?

    var port: UInt16 {
        lock.lock(); defer { lock.unlock() }
        return _port
    }

    /// Continuation-based async startup — replaces an earlier
    /// DispatchSemaphore wait that blocked MainActor for up to 2 sec.
    /// The state-update handler resumes the continuation when the
    /// listener becomes ready (or fails); no main-thread blocking.
    func start(handler: @escaping @Sendable (String) -> (Data, String)?) async throws {
        self.provider = handler
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Atomic-resume guard — stateUpdateHandler can fire multiple
            // times; we resume exactly once.
            let resumedBox = ResumedBox()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumedBox.takeResume() {
                        cont.resume()
                    }
                case .failed(let err):
                    if resumedBox.takeResume() {
                        cont.resume(throwing: err)
                    }
                case .cancelled:
                    if resumedBox.takeResume() {
                        cont.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        // Extract lock/unlock to a sync helper — Swift 6 forbids
        // NSLock.lock()/.unlock() directly from async contexts
        // ("unavailable from asynchronous contexts; Use async-safe
        // scoped locking instead").
        storeReady(port: listener.port?.rawValue ?? 0, listener: listener)
    }

    private func storeReady(port: UInt16, listener: NWListener) {
        lock.lock()
        _port = port
        _listener = listener
        lock.unlock()
    }

    func stop() {
        lock.lock()
        _listener?.cancel()
        _listener = nil
        lock.unlock()
    }

    private func handle(connection: NWConnection) {
        // Surface peer endpoint so we can tell phone-local (loopback)
        // requests apart from Apple-TV-as-AirPlay-Video requests.
        let peer = String(describing: connection.endpoint)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }
            let method = String(parts[0])
            let path = String(parts[1])
            if let (body, mime) = self.provider?(path) {
                showcaseLog("HTTP \(method) 200 \(path) \(body.count)B \(mime) from \(peer)")
                LocalHLSServer.send(connection: connection, body: body, mime: mime)
            } else {
                showcaseLog("HTTP \(method) 404 \(path) from \(peer)")
                LocalHLSServer.sendNotFound(connection: connection)
            }
        }
    }

    private static func send(connection: NWConnection, body: Data, mime: String) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(mime)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func sendNotFound(connection: NWConnection) {
        let header = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - ShowcaseTVRenderView
//
// 1920×1080 16:9 layout for the AirPlay-Video stream. Reads from the
// same ShowcaseSession as the phone view, but lays out for the TV's
// aspect ratio and without phone-side chrome (toolbar / pinch).
//
// Note: ImageRenderer captures CURRENT values of @State / @Observable
// properties — not SwiftUI-interpolated mid-animation values. The TV
// stream shows tile swaps but not the flip/drop interpolation. Phone
// retains full animation. Manual TimelineView interpolation is the
// fix and is deferred.
struct ShowcaseTVRenderView: View {
    let session: ShowcaseSession

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rows = max(2, session.rows)
            let cellH = size.height / CGFloat(rows)
            let cellW = cellH * ShowcaseVideoConstants.cardAspect
            let cols = max(1, Int(ceil(size.width / cellW)))
            let totalTiles = rows * cols

            ZStack {
                Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)

                // Inner grid sized exactly to cols × rows, centered in
                // the 1920×1080 canvas so the bleed is symmetric (left
                // and right edges both have partial tiles) instead of
                // left-aligned with only-right-bleed. This matches the
                // phone-side ShowcaseGridView's layout.
                ZStack(alignment: .topLeading) {
                    ForEach(0..<totalTiles, id: \.self) { index in
                        if index < session.tiles.count {
                            let row = index / cols
                            let col = index % cols
                            TVCardTile(
                                state: session.tiles[index],
                                width: cellW,
                                height: cellH
                            )
                            .position(
                                x: CGFloat(col) * cellW + cellW / 2,
                                y: CGFloat(row) * cellH + cellH / 2
                            )
                        }
                    }
                }
                .frame(width: cellW * CGFloat(cols), height: cellH * CGFloat(rows))
                .position(x: size.width / 2, y: size.height / 2)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

private struct TVCardTile: View {
    let state: ShowcaseTileState
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let img = state.faceUp ? state.front : state.back {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Color(red: 0x0D/255, green: 0x0D/255, blue: 0x1A/255)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - ShowcaseLoadingOverlay
//
// Covers the grid while card images are still loading. TimelineView
// drives a 3-dot pulse so the animation is GPU-cheap and bounded —
// no Task loops, no @State writes, no risk of leaking. Brand styling
// (BOBA orange dot color, monospaced wordmark) so it reads as a
// first-class Showcase splash rather than a generic spinner.
private struct ShowcaseLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Text("PERSONAL SHOWCASE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.7))

                // TimelineView(.animation) ticks at the display refresh
                // rate (60-120 Hz). Each dot's phase is a sine wave
                // offset by 1.5 rad — produces a smooth left-to-right
                // pulse across the 3 dots. The previous .periodic +
                // .animation(value:) combo didn't actually interpolate
                // (TimelineView re-evaluates the body on each tick,
                // which can defeat SwiftUI's animation tracking).
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { i in
                            // Wave: amplitude 0.6 around midpoint 1.0
                            // for scale, 0.25 → 1.0 for opacity.
                            let phase = (sin(t * 3.0 - Double(i) * 1.5) + 1) / 2
                            Circle()
                                .fill(Color(red: 1, green: 0x4D/255, blue: 0))
                                .frame(width: 14, height: 14)
                                .scaleEffect(0.6 + 0.6 * phase)
                                .opacity(0.25 + 0.75 * phase)
                        }
                    }
                }
                .frame(height: 28)

                Text("Loading your collection")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1.5)
            }
        }
    }
}
