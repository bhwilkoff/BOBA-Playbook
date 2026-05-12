import SwiftUI
import AVKit
import Combine
import ImageIO

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

    /// Initialize tile grid for the given total count. Repeats cards
    /// when the pool is smaller than the grid, avoiding adjacent
    /// duplicates (8 retries per cell — AlbumArtwork's behavior).
    func initializeTiles(count: Int) async {
        if tiles.count == count { return }
        pool.setCandidates(cards)

        var newTiles: [ShowcaseTileState] = []
        newTiles.reserveCapacity(count)
        var lastRow: [String] = []
        var rowBuf: [String] = []

        let cols = max(1, columns)
        for i in 0..<count {
            let col = i % cols
            let exclude = Set(lastRow + rowBuf)
            let pick = await pool.nextImage(excluding: exclude)
            let tile = ShowcaseTileState()
            if let (id, img) = pick {
                tile.currentBobaId = id
                tile.front = img
            }
            newTiles.append(tile)
            rowBuf.append(tile.currentBobaId ?? "")
            if col == cols - 1 {
                lastRow = rowBuf
                rowBuf = []
            }
        }
        tiles = newTiles
        cycleEpoch &+= 1
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
            let neighbors = neighborBobaIds(of: tileIndex)
            guard let (newId, image) = await pool.nextImage(excluding: neighbors) else { continue }
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

    init(cards: [Card], onDismiss: @escaping () -> Void) {
        let s = ShowcaseSession()
        s.setCards(cards)
        self.cards = cards
        self.onDismiss = onDismiss
        self._session = State(initialValue: s)
        self._externalManager = State(initialValue: ExternalDisplayManager.shared)
    }

    var body: some View {
        Group {
            if externalManager.externalScreenAvailable
                && externalManager.useExternalDisplay
                && session.renderTarget == .external {
                ShowcaseControlPanel(session: session, onDismiss: onDismiss)
            } else {
                ShowcaseGridView(session: session, showsToolbar: true, onDismiss: onDismiss)
            }
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
    let showsToolbar: Bool
    var onDismiss: (() -> Void)?

    @State private var rowsAtPinchStart: Int = 6
    @State private var revealedToolbar: Bool = true
    @State private var toolbarHideTask: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardAspect: CGFloat = 0.75   // width / height = 3/4
    private let minRows: Int = 2
    private let maxRows: Int = 12

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
                Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)

                if geometryReady {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(cellW), spacing: 0),
                            count: cols
                        ),
                        spacing: 0
                    ) {
                        ForEach(0..<totalTiles, id: \.self) { index in
                            if index < session.tiles.count {
                                ShowcaseTileCell(
                                    state: session.tiles[index],
                                    width: cellW,
                                    height: cellH
                                )
                            } else {
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                    .frame(width: cellW * CGFloat(cols), height: cellH * CGFloat(session.rows))
                    .position(x: size.width / 2, y: size.height / 2)
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
                    toolbarOverlay
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea(.all, edges: .all)
        .contentShape(Rectangle())
        .onTapGesture { if showsToolbar { revealToolbar() } }
        .gesture(
            showsToolbar
            ? MagnifyGesture()
                .onChanged { value in
                    // Clamp to a sensible range so magnification = 0
                    // (theoretically possible mid-gesture) doesn't
                    // produce infinity / NaN through the division.
                    let mag = max(0.1, min(10.0, value.magnification))
                    let raw = Double(rowsAtPinchStart) / mag
                    guard raw.isFinite else { return }
                    let candidate = Int(round(raw))
                    let clamped = max(minRows, min(maxRows, candidate))
                    if clamped != session.rows {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            session.rows = clamped
                        }
                    }
                }
                .onEnded { _ in
                    rowsAtPinchStart = session.rows
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
        .task(id: session.cycleEpoch) {
            await session.runCycleLoop(reduceMotion: reduceMotion)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !session.paused {
                session.cycleEpoch &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            let new = ProcessInfo.processInfo.thermalState
            if new != session.thermalState {
                session.thermalState = new
                session.cycleEpoch &+= 1
            }
        }
        .statusBar(hidden: true)
    }

    // MARK: Toolbar

    private var toolbarOverlay: some View {
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

                RoutePickerView()
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .accessibilityLabel("AirPlay")
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
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
                .frame(height: 160)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        externalManager.useExternalDisplay = false
                    } label: {
                        Label("Use Phone", systemImage: "iphone")
                            .foregroundStyle(Color(red: 0, green: 0xF5/255, blue: 1))
                    }
                }
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
                    Text("Cycle Speed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(session.cycleSpeed))s")
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
                ShowcaseGridView(session: session, showsToolbar: false, onDismiss: nil)
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

private struct ShowcaseTileCell: View {
    @Bindable var state: ShowcaseTileState
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            face(image: state.front)
                .opacity(state.faceUp ? 1 : 0)
            face(image: state.back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(state.faceUp ? 0 : 1)
        }
        .opacity(state.opacity)
        .rotationEffect(.degrees(state.rotation2D))
        .rotation3DEffect(
            .degrees(state.faceUp ? 0 : 180),
            axis: (x: 0, y: 1, z: 0)
        )
        .offset(x: state.translateX, y: state.translateY)
        .frame(width: width, height: height)
        .clipped()
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

@Observable
@MainActor
final class ShowcaseTileState: Identifiable {
    let id = UUID()
    var currentBobaId: String?
    var front: UIImage?
    var back: UIImage?
    var faceUp: Bool = true

    var translateX: CGFloat = 0
    var translateY: CGFloat = 0
    var rotation2D: Double = 0
    var opacity: Double = 1

    func animate(to next: UIImage, variant: ShowcaseAnimation, reduceMotion: Bool) async {
        if reduceMotion {
            crossfade(to: next)
            try? await Task.sleep(for: .milliseconds(400))
            return
        }
        switch variant {
        case .flip:                       await flip(to: next)
        case .drop, .rowDrop:             await drop(to: next)
        case .rollDrop, .rowRollDrop:     await rollDrop(to: next)
        case .pinRotation:                await pinRotation(to: next)
        case .dropFromCorner:             await dropFromCorner(to: next)
        }
    }

    private func flip(to next: UIImage) async {
        if faceUp {
            back = next
            withAnimation(.easeInOut(duration: 0.6)) { faceUp = false }
        } else {
            front = next
            withAnimation(.easeInOut(duration: 0.6)) { faceUp = true }
        }
        try? await Task.sleep(for: .milliseconds(600))
    }

    private func drop(to next: UIImage) async {
        withAnimation(.easeIn(duration: 0.3)) { translateY = 1500 }
        try? await Task.sleep(for: .milliseconds(310))
        translateY = -1500
        swapFace(to: next)
        withAnimation(.easeOut(duration: 0.5)) { translateY = 0 }
        try? await Task.sleep(for: .milliseconds(510))
    }

    private func rollDrop(to next: UIImage) async {
        withAnimation(.easeIn(duration: 0.3)) {
            translateY = 1500
            rotation2D = 360
        }
        try? await Task.sleep(for: .milliseconds(310))
        translateY = -1500
        rotation2D = 0
        swapFace(to: next)
        withAnimation(.easeOut(duration: 0.5)) {
            translateY = 0
            rotation2D = 360
        }
        try? await Task.sleep(for: .milliseconds(510))
        rotation2D = 0
    }

    private func pinRotation(to next: UIImage) async {
        withAnimation(.easeInOut(duration: 0.5)) {
            rotation2D += 180
            opacity = 0
        }
        try? await Task.sleep(for: .milliseconds(260))
        swapFace(to: next)
        withAnimation(.easeInOut(duration: 0.5)) { opacity = 1 }
        try? await Task.sleep(for: .milliseconds(510))
        rotation2D = rotation2D.truncatingRemainder(dividingBy: 360)
    }

    private func dropFromCorner(to next: UIImage) async {
        let xDir: CGFloat = Bool.random() ? 1 : -1
        let yDir: CGFloat = Bool.random() ? 1 : -1
        withAnimation(.easeIn(duration: 0.35)) {
            translateX = xDir * 1500
            translateY = yDir * 1500
            rotation2D = xDir * 30
        }
        try? await Task.sleep(for: .milliseconds(360))
        translateX = -xDir * 1500
        translateY = -yDir * 1500
        rotation2D = -xDir * 30
        swapFace(to: next)
        withAnimation(.easeOut(duration: 0.5)) {
            translateX = 0
            translateY = 0
            rotation2D = 0
        }
        try? await Task.sleep(for: .milliseconds(510))
    }

    private func swapFace(to next: UIImage) {
        if faceUp { front = next } else { back = next }
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

    func nextImage(excluding: Set<String> = []) async -> (String, UIImage)? {
        guard !candidates.isEmpty else { return nil }
        for _ in 0..<8 {
            let card = pick()
            if !excluding.contains(card.id) {
                if let img = await loadDecodedImage(for: card) {
                    return (card.id, img)
                }
                continue
            }
        }
        let card = pick()
        if let img = await loadDecodedImage(for: card) {
            return (card.id, img)
        }
        return nil
    }

    private func pick() -> Card {
        let card = candidates[cursor]
        cursor += 1
        if cursor >= candidates.count {
            cursor = 0
            candidates.shuffle()
        }
        return card
    }

    private func loadDecodedImage(for card: Card) async -> UIImage? {
        guard let url = CDN.fullURL(for: card) else { return nil }
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
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        v.activeTintColor = UIColor(red: 0, green: 0xF5/255, blue: 1, alpha: 1)
        v.tintColor = .white
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
