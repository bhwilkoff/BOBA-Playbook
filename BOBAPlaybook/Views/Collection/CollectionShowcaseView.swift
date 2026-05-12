import SwiftUI
import AVKit
import Combine
import ImageIO

// MARK: - CollectionShowcaseView
//
// "Personal Showcase" — iTunes Album Artwork-style screensaver
// surface for the user's owned collection. Surfaces as a Collection
// display-mode launcher (alongside Grid/List/Wall). Per DESIGN.md
// §8.4 the Collection toolbar Menu is the natural home.
//
// Aesthetic per the lingkuma/AlbumArtwork reference: 6-row tile grid,
// square cells edge-to-edge bleeding off the screen, solid near-black
// background, every ~3s a random 3-6 tiles flip on the Y axis (200ms
// stagger) to reveal a different card. Single-axis flip is the
// canonical iTunes behavior; the AlbumArtwork repo's drop / rollDrop
// / pinRotation / row-sweep variants are out of scope for v1.
//
// Card source: owned cards (every designation EXCEPT .wanted, since
// wanted = wishlist, not owned), image-bearing only, sorted by
// acquiredAt descending so new acquisitions surface first. If the
// pool is smaller than the grid, cards repeat but no two adjacent
// tiles render the same card (retry up to 8 times).
//
// AirPlay: v1 = system screen mirroring. AVRoutePickerView in the
// auto-hiding toolbar surfaces the route picker; iOS handles the
// actual mirror. Dedicated external-display mode is deferred.
struct CollectionShowcaseView: View {
    let cards: [Card]
    var onDismiss: () -> Void

    @State private var pool = ShowcaseImagePool()
    @State private var tiles: [ShowcaseTileState] = []
    @State private var columns: Int = 0
    @State private var revealedToolbar: Bool = true
    @State private var paused: Bool = false
    @State private var cycleEpoch: Int = 0
    @State private var thermalState: ProcessInfo.ThermalState = .nominal
    @State private var toolbarHideTask: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows: Int = 6

    var body: some View {
        ZStack {
            Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)
                .ignoresSafeArea()

            GeometryReader { geo in
                let size = geo.size
                let cellSide = size.height / CGFloat(rows)
                let cols = max(1, Int(ceil(size.width / cellSide)))
                let total = rows * cols

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cellSide), spacing: 0), count: cols),
                    spacing: 0
                ) {
                    ForEach(0..<total, id: \.self) { index in
                        if index < tiles.count {
                            ShowcaseTileCell(
                                state: tiles[index],
                                side: cellSide
                            )
                        } else {
                            Color.clear.frame(width: cellSide, height: cellSide)
                        }
                    }
                }
                .frame(width: cellSide * CGFloat(cols), height: cellSide * CGFloat(rows))
                .position(x: size.width / 2, y: size.height / 2)
                .onAppear {
                    columns = cols
                    Task { await initializeTiles(count: total) }
                }
                .onChange(of: cols) { _, newCols in
                    columns = newCols
                    Task { await initializeTiles(count: rows * newCols) }
                }
            }

            // Auto-hiding toolbar overlay (Photos pattern). Tap anywhere
            // reveals; auto-hides after 3s of no interaction.
            if revealedToolbar {
                toolbarOverlay
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { revealToolbar() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleToolbarHide()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            toolbarHideTask?.cancel()
        }
        // Cycle driver. Restarts whenever cycleEpoch changes (pause /
        // resume / thermal-state change). Suspends when paused or in
        // background.
        .task(id: cycleEpoch) {
            await runCycleLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            // Pause cycle when the app is backgrounded or inactive
            // (e.g., AirPlay disconnect, incoming call, app switcher).
            // The .task(id:) bump on resume restarts the loop.
            if phase == .active && !paused {
                cycleEpoch &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            let new = ProcessInfo.processInfo.thermalState
            if new != thermalState {
                thermalState = new
                cycleEpoch &+= 1 // restart with new cadence
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar

    private var toolbarOverlay: some View {
        VStack {
            HStack(spacing: 16) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Close Showcase")

                Spacer()

                Text("PERSONAL SHOWCASE")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    paused.toggle()
                    if !paused { cycleEpoch &+= 1 }
                    revealToolbar()
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(paused ? "Resume" : "Pause")

                RoutePickerView()
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .accessibilityLabel("AirPlay")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
        }
    }

    private func revealToolbar() {
        withAnimation(.easeOut(duration: 0.2)) { revealedToolbar = true }
        scheduleToolbarHide()
    }

    private func scheduleToolbarHide() {
        toolbarHideTask?.cancel()
        toolbarHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) { revealedToolbar = false }
                }
            }
        }
    }

    // MARK: - Cycle loop

    private func runCycleLoop() async {
        // Build the pool's candidate list on first entry (cards is
        // already filtered + sorted by the caller per DESIGN.md §8.4).
        pool.setCandidates(cards)

        // Wait for the first frame to render so tiles exist before
        // we try to flip them.
        try? await Task.sleep(for: .milliseconds(200))

        while !Task.isCancelled {
            if paused { return }

            let cadence = baseCadence()
            let jitter = Double.random(in: 0...1.0)
            try? await Task.sleep(for: .seconds(cadence + jitter))
            if Task.isCancelled || paused { return }

            await runFlipCycle()
        }
    }

    /// Base seconds between flip cycles. Drops to a slower pace under
    /// thermal pressure to avoid throttling.
    private func baseCadence() -> Double {
        switch thermalState {
        case .nominal, .fair: return 3.0
        case .serious:        return 6.0
        case .critical:       return 10.0
        @unknown default:     return 3.0
        }
    }

    /// Pick 3-6 random tiles and flip each on a 200ms stagger. Each
    /// tile gets a freshly-decoded image whose bobaId isn't already
    /// shown on either of its left/right neighbors (8-try retry).
    private func runFlipCycle() async {
        guard !tiles.isEmpty else { return }
        let count = Int.random(in: 3...min(6, tiles.count))
        let indices = Array(0..<tiles.count).shuffled().prefix(count)

        for (i, tileIndex) in indices.enumerated() {
            // 200ms stagger between tiles in the same cycle.
            if i > 0 {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if Task.isCancelled || paused { return }

            let neighbors = neighborBobaIds(of: tileIndex)
            guard let (newId, image) = await pool.nextImage(excluding: neighbors) else { continue }

            await MainActor.run {
                tiles[tileIndex].currentBobaId = newId
                if reduceMotion {
                    tiles[tileIndex].crossfade(to: image)
                } else {
                    tiles[tileIndex].flip(to: image)
                }
            }
        }
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

    // MARK: - Tile initialization

    private func initializeTiles(count: Int) async {
        // Preserve existing tiles when grid count is unchanged.
        if tiles.count == count { return }
        pool.setCandidates(cards)

        var newTiles: [ShowcaseTileState] = []
        newTiles.reserveCapacity(count)
        var lastRow: [String] = []
        var rowBuf: [String] = []

        let cols = max(1, columns)
        for i in 0..<count {
            let col = i % cols
            // For the very first fill, avoid duplicates in the current
            // row + the row above (cheap O(1) adjacency check).
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
        await MainActor.run {
            self.tiles = newTiles
            self.cycleEpoch &+= 1
        }
    }
}

// MARK: - ShowcaseTileCell
//
// Each tile owns its own @State to prevent the parent's body from
// re-rendering the whole grid on every flip (per memory
// `feedback_swiftui_gesture_perf.md` — extract animated subviews
// with their own state).
private struct ShowcaseTileCell: View {
    @Bindable var state: ShowcaseTileState
    let side: CGFloat

    var body: some View {
        ZStack {
            face(image: state.front)
                .opacity(state.faceUp ? 1 : 0)
            face(image: state.back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(state.faceUp ? 0 : 1)
        }
        .rotation3DEffect(
            .degrees(state.faceUp ? 0 : 180),
            axis: (x: 0, y: 1, z: 0)
        )
        .frame(width: side, height: side)
        .clipped()
    }

    private func face(image: UIImage?) -> some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            } else {
                Color(red: 0x0D/255, green: 0x0D/255, blue: 0x1A/255)
            }
        }
    }
}

// MARK: - ShowcaseTileState
//
// Per-tile observable state. Holds front + back images plus a
// faceUp flag — the flip pattern preloads the offscreen face with
// the next image before animating, so the swap is invisible at
// mid-flip when the tile edge is camera-on.
@Observable
@MainActor
final class ShowcaseTileState: Identifiable {
    let id = UUID()
    var currentBobaId: String?
    var front: UIImage?
    var back: UIImage?
    var faceUp: Bool = true

    /// Flip to a new image. Whichever face is currently hidden
    /// receives the new image before the rotation animation starts.
    func flip(to next: UIImage) {
        if faceUp {
            back = next
            withAnimation(.easeInOut(duration: 0.6)) { faceUp = false }
        } else {
            front = next
            withAnimation(.easeInOut(duration: 0.6)) { faceUp = true }
        }
    }

    /// Reduce-Motion fallback: crossfade the visible face without
    /// rotation. The hidden face stays untouched.
    func crossfade(to next: UIImage) {
        if faceUp {
            withAnimation(.easeInOut(duration: 0.4)) { front = next }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { back = next }
        }
    }
}

// MARK: - ShowcaseImagePool
//
// Two-layer cache + lookahead pool. URLCache (configured at app
// launch, 100MB/500MB per CLAUDE.md) handles compressed-byte
// caching; NSCache here holds decoded UIImages so we never decode
// a 200px WebP inside the animation closure.
//
// Candidates: owned + has-image cards, sorted recently-added-first
// by the caller. Cycles through the list; when exhausted, reshuffles.
@Observable
@MainActor
final class ShowcaseImagePool {
    private var candidates: [Card] = []
    private var cursor: Int = 0
    private let decodedCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 64 * 1024 * 1024 // 64 MB decoded
        return c
    }()

    func setCandidates(_ cards: [Card]) {
        // Caller is responsible for filtering + sorting; we only
        // reshuffle when the pool starts a new full cycle (so the
        // recently-added bias holds for the first pass).
        if candidates.map(\.id) == cards.map(\.id) { return }
        candidates = cards
        cursor = 0
    }

    /// Hand back the next (bobaId, decoded UIImage) pair, skipping
    /// any bobaIds in `excluding`. Returns nil only if the pool is
    /// empty.
    func nextImage(excluding: Set<String> = []) async -> (String, UIImage)? {
        guard !candidates.isEmpty else { return nil }

        // Up to 8 tries to find a card whose bobaId isn't an
        // immediate neighbor's. After 8, give up and accept a
        // potential duplicate (the AlbumArtwork retry limit).
        for _ in 0..<8 {
            let card = pick()
            if !excluding.contains(card.id) {
                if let img = await loadDecodedImage(for: card) {
                    return (card.id, img)
                }
                // Image failed to load — try another.
                continue
            }
        }
        // Fall back: just take whatever's next, even if it duplicates.
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
            // Reshuffle on each full pass so users don't see the
            // exact same sequence twice in a long Showcase session.
            // The recently-added bias is sacrificed after the first
            // cycle, which is the right trade — by then the user
            // has seen the newest cards already.
            candidates.shuffle()
        }
        return card
    }

    private func loadDecodedImage(for card: Card) async -> UIImage? {
        guard let url = CDN.thumbURL(for: card) else { return nil }
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

    /// Force-decode bytes to a UIImage off the main actor using ImageIO.
    /// `kCGImageSourceShouldCacheImmediately: true` evaluates the decode
    /// on THIS thread (background) rather than lazily on first render,
    /// which is exactly what we want — animation hitches come from
    /// decode-on-first-frame, not from network latency.
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
//
// Native AVRoutePickerView wrapped for SwiftUI. `prioritizesVideoDevices = true`
// surfaces TVs / AirPlay-2 receivers at the top of the picker (instead
// of HomePods / speakers). System handles screen mirroring once a
// device is selected.
private struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        v.activeTintColor = UIColor(red: 0, green: 0xF5/255, blue: 1, alpha: 1) // BOBA cyan
        v.tintColor = .white
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
