import SwiftUI

// MARK: - CollectionView
// Main Collection tab. Shows cards grouped by designation with a value summary.
// One row per unique card_number — multiple physical copies are shown on the detail page.

struct CollectionView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore

    @State private var selectedDesignation: UserCard.Designation = .personal
    @State private var selectedCard: BobaIdWrapper?
    @State private var showingSignIn    = false
    @State private var showTradeRoom    = false
    @State private var discord          = DiscordService()
    /// Top-level view mode. Rainbow is a collecting-progress lens across
    /// all owned heroes — a different axis than the designation tabs,
    /// which partition cards by intent (Personal / For Sale / Wanted).
    /// Keeping these on separate toggles so coaches don't confuse "how I'm
    /// using this card" with "how close am I to completing this hero."
    @State private var viewMode: CollectionViewMode = .myCards
    @State private var isRecalculating = false
    @State private var recalcProgress: (current: Int, total: Int)? = nil

    @State private var showingFilters      = false
    @State private var exportShareURL: URL?    = nil
    /// Collection-only sort axis. Persisted across app launches because
    /// it's a personal preference (a coach who likes "Recently Added"
    /// doesn't want it reset every time they open the app).
    @AppStorage("bp_collectionSortOrder_v1") private var collectionSortRaw: String = CollectionSortOrder.dateAddedDesc.rawValue

    enum CollectionViewMode: String, CaseIterable, Identifiable {
        case myCards = "My Cards"
        case rainbow = "Rainbow"
        case shows   = "My Shows"
        var id: String { rawValue }
    }

    /// Modes visible to the current user. Streamers see all three;
    /// everyone else sees My Cards + Rainbow. Keeps the picker clean
    /// for non-streamers without gating elsewhere in the body.
    private var availableModes: [CollectionViewMode] {
        auth.isStreamer ? CollectionViewMode.allCases : [.myCards, .rainbow]
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isAuthenticated {
                    unauthenticatedView
                } else {
                    authenticatedView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if auth.isAuthenticated {
                    ToolbarItem(placement: .topBarLeading) {
                        collectionMenu
                    }
                }
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
                if auth.isAuthenticated && viewMode == .myCards {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterButton
                    }
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showingFilters) {
            // Bind the @AppStorage-backed raw string through a custom
            // Binding so the sort picker reads/writes the typed enum
            // while the persistence layer keeps a plain String.
            FilterSheetView(
                store: cardStore,
                collectionSort: Binding(
                    get: { CollectionSortOrder(rawValue: collectionSortRaw) ?? .dateAddedDesc },
                    set: { collectionSortRaw = $0.rawValue }
                )
            )
        }
        .sheet(item: $selectedCard) { wrapper in
            CollectionCardDetailView(bobaId: wrapper.id)
        }
        .task {
            if auth.isAuthenticated {
                await collection.loadCollection()
            }
        }
        .onAppear {
            // Reset shared CardStore filter state whenever Collection
            // becomes visible again — coaches shouldn't inherit a
            // forgotten "Fire only" dial from their last visit to
            // Find. Sheets (card detail, add-to-deck, etc.) don't
            // re-trigger onAppear, so in-tab interactions keep the
            // filters the user set this session.
            cardStore.clearAllFilters()
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task { await collection.loadCollection() }
            } else {
                collection.clearCollection()
            }
        }
    }

    // MARK: - Unauthenticated state

    private var unauthenticatedView: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Design.Colors.textMuted)
            Text("My Collection")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Sign in to track owned cards,\nwishlist, and portfolio value.")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
            Button {
                showingSignIn = true
            } label: {
                Text("Sign In")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .frame(maxWidth: 200)
                    .frame(height: 50)
                    .background(Design.Colors.bobaOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Authenticated state

    private var authenticatedView: some View {
        // .refreshable intentionally does NOT go on this VStack — it would
        // attach to the first ancestor scroll view (the horizontal
        // designation pill row), bringing its vertical bounce back and
        // firing the refresh on the wrong surface. Each inner ScrollView
        // (cardList / rainbowList) attaches its own .refreshable so the
        // pull-to-refresh gesture lives where the refresh actually shows.
        //
        // The recalc progress banner renders as a TOP overlay on the
        // ZStack (NOT as the first child of the VStack) — inserting it
        // into the layout flow used to push every sibling down when
        // isRecalculating flipped true, which re-mounted the cardList
        // ScrollView and cancelled its .refreshable Task. Cancellation
        // makes URLSession.data fail-fast and Task.sleep return
        // immediately, so the loop "speedran" through every owned
        // card in <1s without doing real work. Overlay keeps the
        // ScrollView identity stable so the .refreshable Task runs
        // to completion.
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)

                switch viewMode {
                case .myCards:
                    valueSummary
                    designationPicker
                    cardList
                case .rainbow:
                    rainbowIntro
                    rainbowList
                case .shows:
                    ShowsListView()
                }
            }
            .background(Design.Colors.nearBlack)

            // tradeRoomFAB — hidden until Discord bot is added to server
        }
        .overlay(alignment: .top) {
            if isRecalculating, let p = recalcProgress {
                recalcProgressBanner(current: p.current, total: p.total)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRecalculating)
        .sheet(isPresented: $showTradeRoom) {
            TradeRoomSheet(discord: discord)
        }
    }

    // MARK: - Top-level view mode picker

    private var modePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(availableModes) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        // Snap back to My Cards if the user loses streamer role while
        // parked on the Shows tab — avoids a view displaying with no
        // selected segment.
        .onChange(of: auth.isStreamer) { _, newValue in
            if !newValue && viewMode == .shows { viewMode = .myCards }
        }
    }

    // MARK: - Collection menu (toolbar)

    private var collectionMenu: some View {
        Menu {
            Button {
                Task { await recalculateAll() }
            } label: {
                Label(isRecalculating ? "Refreshing prices…" : "Refresh market values",
                      systemImage: "arrow.clockwise")
            }
            .disabled(isRecalculating)

            // (Find a Store moved to the Purchase tab.)

            // Last item — matches user spec. Writes CSV to a tmp file
            // named with today's date, then presents the share sheet
            // via the exportShareURL sheet modifier on the body.
            Button {
                exportCollectionCSV()
            } label: {
                Label("Export Collection", systemImage: "square.and.arrow.up")
            }
            .disabled(collection.userCards.isEmpty)
        } label: {
            if isRecalculating {
                ProgressView().tint(Design.Colors.bobaOrange)
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
        }
    }

    // MARK: - Filters button (trailing)
    // Shares filter state with the Find tab via CardStore. Changing a
    // filter here will also apply when the user switches to Find —
    // treated as a feature, not a bug: filters follow intent.
    private var filterButton: some View {
        Button {
            showingFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)
                if cardStore.activeFilterCount > 0 {
                    Circle()
                        .fill(Design.Colors.bobaOrange)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    private func recalcProgressBanner(current: Int, total: Int) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            ProgressView().tint(Design.Colors.bobaOrange).scaleEffect(0.85)
            Text(total == 0
                 ? "Refreshing market values…"
                 : "Updating \(current) of \(total) cards…")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
        .background(Design.Colors.surface)
    }

    private func recalculateAll() async {
        isRecalculating = true
        recalcProgress = (0, 0)
        await collection.recalculateAllValues(cardStore: cardStore) { current, total in
            recalcProgress = (current, total)
        }
        isRecalculating = false
        recalcProgress = nil
    }

    // MARK: - Value summary

    private var valueSummary: some View {
        let estimated = collection.totalEstimatedValue
        let purchased = collection.totalPurchaseValue
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(estimated > 0 ? "EST. MARKET VALUE" : "COST BASIS")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                let displayValue = estimated > 0 ? estimated : purchased
                Text(displayValue == 0 ? "—" : formatCurrency(displayValue))
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(displayValue == 0 ? Design.Colors.textMuted : Design.Colors.bobaOrange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("CARDS OWNED")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text("\(collection.userCards.filter { $0.designation.isOwned }.count)")
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .background(Design.Colors.surface)
    }

    // MARK: - Designation picker

    private var designationPicker: some View {
        // Fixed-height row (34pt pill + 12pt × 2 vertical padding = 58).
        // Without this, the horizontal ScrollView inherits flexible
        // height from its parent VStack and the pull-to-refresh bounce
        // from the enclosing `.refreshable` scroll can tug the pill row
        // up and down, making it feel like the pills scroll vertically.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.sm) {
                ForEach(UserCard.Designation.allCases) { d in
                    let count = collection.uniqueBobaIds(for: d).count
                    Button {
                        selectedDesignation = d
                    } label: {
                        HStack(spacing: Design.Spacing.xs) {
                            Image(systemName: d.icon)
                                .font(.system(size: 11))
                            Text(d.displayName)
                                .font(Design.Fonts.mono(12, weight: selectedDesignation == d ? .bold : .regular))
                            if count > 0 {
                                Text("\(count)")
                                    .font(Design.Fonts.mono(10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(selectedDesignation == d ? Color.black.opacity(0.35) : Design.Colors.glass))
                            }
                        }
                        .foregroundStyle(selectedDesignation == d ? .white : Design.Colors.textSecondary)
                        .padding(.horizontal, Design.Spacing.md)
                        .frame(height: 34)
                        .background(selectedDesignation == d ? Design.Colors.bobaOrange : Design.Colors.glass)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(height: 58)
        .background(Design.Colors.surface)
    }

    // MARK: - Rainbow intro
    // Short explainer shown at the top of the Rainbow view so coaches who
    // haven't heard the term know what they're looking at and why. "Rainbow"
    // is a community collecting goal, not a game mechanic — worth spelling
    // out when someone first encounters the tab.
    private var rainbowIntro: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "rainbow").font(.system(size: 16))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Text("What is a Rainbow?")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            Text("Community collecting goal — owning every treatment (Base + every foil + every autograph) of a single hero. If you own at least one card of a hero, that hero shows up here with progress toward a complete set.")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sorted by percent complete. Tap a row to jump to the card.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.Colors.glassBorder).frame(height: 1) }
    }

    // MARK: - Card list

    private var cardList: some View {
        let identifiers = collectionIdentifiers(for: selectedDesignation)

        // Always wrap in a vertical ScrollView so .refreshable has a
        // valid attachment point, whether or not there are cards. Empty
        // state still pulls to refresh so users can retry from a blank
        // list without having to background-foreground the app.
        return Group {
            if collection.isLoading {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if identifiers.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        LazyVStack(spacing: Design.Spacing.sm) {
                            ForEach(identifiers, id: \.self) { identifier in
                                collectionRow(identifier: identifier)
                                    .onTapGesture { selectedCard = BobaIdWrapper(id: identifier) }
                            }
                        }
                        .padding(Design.Spacing.lg)
                    }
                }
                .refreshable {
                    // Pull-to-refresh = recalculate market values
                    // for every owned card (same work the toolbar's
                    // "Refresh market values" button kicks off).
                    //
                    // CRITICAL: wrap the call in `Task { ... }.value`
                    // to detach from .refreshable's cancellation. The
                    // recalc loop's progress callback flips @State
                    // (recalcProgress, isRecalculating) which causes
                    // SwiftUI to re-render the host view tree —
                    // SwiftUI then cancels the .refreshable Task as
                    // a side effect, which makes URLSession.data and
                    // Task.sleep fail-fast for every remaining card.
                    // Result: 20-card recalc "speedran" in <1s with
                    // no real fetches. Task.init creates an
                    // unstructured task that doesn't inherit the
                    // refreshable Task's cancellation, so the work
                    // runs to completion. The outer await keeps the
                    // pull spinner attached until it's done.
                    //
                    // We deliberately do NOT call loadCollection()
                    // here either — it flips collection.isLoading
                    // which would unmount this whole ScrollView.
                    await Task { await recalculateAll() }.value
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer()
            Image(systemName: selectedDesignation.icon)
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No \(selectedDesignation.displayName) cards")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Add cards from any card detail view.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rainbow list
    //
    // For every hero the user owns at least one card of, show rainbow
    // progress: owned treatments vs. every treatment that exists for
    // that hero across all variations. Tap a row → open the card-number
    // detail view for the first owned card of that hero (entry point
    // into seeing variants). Missing-treatment jumps into Find are a
    // P2 follow-up — the list itself already shows the gap.

    private struct RainbowProgress: Identifiable {
        let hero: String
        let owned: Int
        let total: Int
        let coverCard: Card
        var id: String { hero }
        var percent: Double { total == 0 ? 0 : Double(owned) / Double(total) }
    }

    private var rainbowRows: [RainbowProgress] {
        // Owned (any designation that counts as owned, e.g. .personal / .for_sale / .for_trade).
        let ownedBobaIds: Set<String> = Set(
            collection.userCards
                .filter { $0.designation.isOwned }
                .compactMap { $0.bobaId }
        )
        // Group every hero-card in the catalog by hero.
        var byHero: [String: [Card]] = [:]
        for c in cardStore.displayCards where c.isHero && !c.hero.isEmpty {
            byHero[c.hero, default: []].append(c)
        }
        // Keep only heroes the user owns at least one printing of.
        var rows: [RainbowProgress] = []
        for (hero, cards) in byHero {
            let owned = cards.filter { ownedBobaIds.contains($0.id) }
            if owned.isEmpty { continue }
            // Prefer an owned card with an image as the cover; fall back to
            // the first card in the hero group.
            let cover = owned.first { $0.imageFile?.isEmpty == false } ?? owned.first ?? cards.first!
            rows.append(.init(
                hero: hero,
                owned: owned.count,
                total: cards.count,
                coverCard: cover
            ))
        }
        // Almost-complete rainbows are the collector's primary signal —
        // surface those first, then alphabetical.
        return rows.sorted { lhs, rhs in
            if lhs.percent != rhs.percent { return lhs.percent > rhs.percent }
            return lhs.hero.localizedCompare(rhs.hero) == .orderedAscending
        }
    }

    private var rainbowList: some View {
        let rows = rainbowRows
        // Same pattern as cardList — always in a ScrollView so pull-to-
        // refresh has a real scroll view to attach to.
        return ScrollView {
            if rows.isEmpty {
                VStack(spacing: Design.Spacing.md) {
                    Image(systemName: "rainbow")
                        .font(.system(size: 36))
                        .foregroundStyle(Design.Colors.bobaCyan.opacity(0.6))
                    Text("No rainbows in progress yet")
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textMuted)
                    Text("Add any hero card to your collection — we'll show rainbow progress here.")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.Spacing.xl)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.top, Design.Spacing.xl)
            } else {
                LazyVStack(spacing: Design.Spacing.sm) {
                    ForEach(rows) { row in
                        rainbowRow(row)
                            .onTapGesture {
                                selectedCard = BobaIdWrapper(id: row.coverCard.id)
                            }
                    }
                }
                .padding(Design.Spacing.lg)
            }
        }
        .refreshable {
            await collection.loadCollection()
        }
    }

    private func rainbowRow(_ row: RainbowProgress) -> some View {
        HStack(spacing: Design.Spacing.md) {
            CardImageView(card: row.coverCard, size: .thumb)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.hero)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                // Progress bar — segmented when there are few treatments
                // (one cell per treatment, easy to count at a glance), and
                // a continuous fill when the hero has dozens of treatments
                // (e.g. Maverick at 150). The segmented variant blew out
                // the row width past the screen edge once we crossed ~60
                // segments because the per-cell spacing alone exceeded
                // available width.
                rainbowProgressBar(row: row)
                    .frame(height: 4)
                Text("\(row.owned) of \(row.total) treatments")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            Spacer()
            Text("\(Int((row.percent * 100).rounded()))%")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(row.percent == 1.0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface))
        .contentShape(Rectangle())
    }

    /// 60 is the largest count where 1pt-spaced 2pt-wide segments still
    /// fit comfortably on an iPhone Mini's row width. Above that we drop
    /// to a continuous fill — the per-treatment cell loses meaning at
    /// that density anyway, and a single bar restores the row to the
    /// expected geometry.
    @ViewBuilder
    private func rainbowProgressBar(row: RainbowProgress) -> some View {
        if row.total <= 60 {
            GeometryReader { proxy in
                let spacing: CGFloat = 1
                let totalSpacing = spacing * CGFloat(max(0, row.total - 1))
                let segWidth = max(2, (proxy.size.width - totalSpacing) / CGFloat(max(1, row.total)))
                HStack(spacing: spacing) {
                    ForEach(0..<row.total, id: \.self) { i in
                        Rectangle()
                            .fill(i < row.owned ? Design.Colors.bobaCyan : Design.Colors.glass)
                            .frame(width: segWidth)
                    }
                }
                .clipShape(Capsule())
            }
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Colors.glass)
                    Capsule()
                        .fill(Design.Colors.bobaCyan)
                        .frame(width: proxy.size.width * row.percent)
                }
            }
        }
    }

    private func collectionRow(identifier: String) -> some View {
        // identifier is a bobaId (e.g. "BOJ-123-BoJax-Base") for new entries,
        // or a plain cardNumber for legacy entries without a bobaId stored.
        let catalog = cardStore.displayCards.first { $0.id == identifier }
                   ?? cardStore.displayCards.first { $0.cardNumber == identifier }
        let copies = collection.entries(forBobaId: identifier).filter { $0.designation == selectedDesignation }
        // Total copies of this card across EVERY designation. The
        // quantity badge reflects the entire collection so a coach
        // browsing the For Sale tab can still see they own 3 total
        // (one for sale, two personal). Without this, the per-tab
        // count looks like "I only have one" when there are actually
        // copies sitting in other tabs.
        let totalCopiesAllDesignations = collection.entries(forBobaId: identifier).count
        // Market value — sum of estimatedValue across all copies in this
        // designation. Each physical copy has an independently refreshed
        // estimate; summing reflects what the row is worth in aggregate.
        let estimatedTotal = copies.compactMap { $0.estimatedValue }.reduce(Decimal(0), +)
        let totalPaid = copies.compactMap { $0.purchasePrice }.reduce(Decimal(0), +)
        // Earliest acquired date wins — that's the "first added" anchor
        // most coaches think of when they say "when did I get this card".
        let earliestAdded = copies.map { $0.acquiredAt }.min()

        return HStack(spacing: Design.Spacing.md) {
            // Thumbnail
            if let card = catalog {
                CardImageView(card: card, size: .thumb)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
            } else {
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.surface2)
                    .frame(width: 44, height: 62)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Title + qty pill on the same row so the count stays
                // visible on long names (lineLimit(1) was clipping it).
                // Pill shows total across ALL designations; if some of
                // those copies live elsewhere, append "(N here)" so the
                // current-tab share is still readable at a glance.
                HStack(spacing: Design.Spacing.xs) {
                    Text(catalog?.name ?? catalog?.cardNumber ?? identifier)
                        .font(Design.Fonts.display(15))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                    if totalCopiesAllDesignations > 1 {
                        let label = totalCopiesAllDesignations == copies.count
                            ? "×\(totalCopiesAllDesignations)"
                            : "×\(totalCopiesAllDesignations) (\(copies.count) here)"
                        Text(label)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.15)))
                    }
                }
                // Stat strip: weapon · power · card #
                HStack(spacing: Design.Spacing.xs) {
                    if let element = catalog?.element, !element.isEmpty {
                        Text(element)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.element(element))
                    }
                    if let power = catalog?.power, power > 0 {
                        Text("⚡\(power)")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    Text(catalog?.cardNumber ?? identifier)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                // Treatment — separate line so long treatments wrap
                // gracefully without crowding the stat strip.
                if let treatment = catalog?.treatment, !treatment.isEmpty {
                    Text(treatment)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                        .lineLimit(1)
                }
                // Date added — small relative-date hint so coaches know
                // how recently they acquired the card.
                if let added = earliestAdded {
                    Text("Added \(formatAddedDate(added))")
                        .font(Design.Fonts.mono(9))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // "PAID" only makes sense for owned designations. Wanted
                // / Grails rows get a neutral "WANTED" tag instead so
                // coaches don't read any purchase-price field on a
                // wishlist entry as money actually spent.
                if selectedDesignation.isOwned {
                    if estimatedTotal > 0 {
                        Text(formatCurrency(estimatedTotal))
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                        Text("VALUE")
                            .font(Design.Fonts.mono(8))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    } else if totalPaid > 0 {
                        Text(formatCurrency(totalPaid))
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("PAID")
                            .font(Design.Fonts.mono(8))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    } else {
                        Text("$—")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    if estimatedTotal > 0 && totalPaid > 0 {
                        Text("paid \(formatCurrency(totalPaid))")
                            .font(Design.Fonts.mono(8))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                } else {
                    Text(selectedDesignation.displayName.uppercased())
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .tracking(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
    }

    /// Short, glanceable acquired-on label. Today/Yesterday for
    /// fresh adds, "3d ago" for the same week, "Mar 14" for the same
    /// year, and "Mar 14, 2025" for older entries.
    private func formatAddedDate(_ date: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "today" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let f = DateFormatter()
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            f.dateFormat = "MMM d"
        } else {
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: date)
    }

    // MARK: - Trade Room FAB

    private var tradeRoomFAB: some View {
        Button {
            showTradeRoom = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: "5865F2"))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                // Unread badge
                if discord.unreadCount > 0 {
                    Text(discord.unreadCount > 99 ? "99+" : "\(discord.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color(hex: "F23F43"))
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    // MARK: - CSV export
    //
    // Writes collection to a timestamped CSV file in the temp directory
    // and hands it to UIActivityViewController so users can share, save
    // to Files, AirDrop, etc. Named after the date so multiple exports
    // don't collide. The file sticks around in tmp until iOS evicts it.
    private func exportCollectionCSV() {
        // When the user has Collection filters active, scope the export
        // to only the rows that pass the filter — matches the visible
        // grid and prevents the "I exported 'just my Fire cards' but got
        // everything" surprise. Filter is applied via cardStore's
        // shared filter state; an empty/no-filter state exports the
        // full collection (preserves the prior default).
        let restriction: Set<String>? = cardStore.activeFilterCount > 0
            ? Set(cardStore.filteredCards.map(\.id))
            : nil
        let csv = collection.exportCSV(cardStore: cardStore, restrictTo: restriction)
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let suffix = restriction == nil ? "" : "_filtered"
        let filename = "BOBA_collection_\(stamp)\(suffix).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        presentShareSheet(for: url)
    }

    private func presentShareSheet(for url: URL) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        guard let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }),
              var top = keyWindow.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad popover anchor — trailing area near the 3-dots menu.
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(
            x: 40, y: 40, width: 0, height: 0)
        top.present(vc, animated: true)
    }

    // MARK: - Collection filter integration
    //
    // When Find-tab filters are active, intersect the collection rows
    // with the catalog cards that pass the filter. Reuses the same
    // predicate set as SearchView (element, set, treatment, power,
    // has-image, card-type, showcase) so coaches get consistent
    // filtering semantics across tabs.
    //
    // Search text is intentionally ignored here — filtering the catalog
    // by "fire" makes sense on Find; applying that same text-filter to a
    // user's owned cards surfaces rows they can only glimpse through the
    // search bar. Filters are the dial for Collection; searchbar stays
    // on Find.
    private func collectionIdentifiers(for designation: UserCard.Designation) -> [String] {
        var owned = collection.uniqueBobaIds(for: designation)
        if cardStore.activeFilterCount > 0 {
            let allowed = Set(cardStore.filteredCards.map(\.id))
            owned = owned.filter { allowed.contains($0) }
        }
        return sortIdentifiers(owned, designation: designation)
    }

    /// Apply the active CollectionSortOrder. Sort keys are derived from
    /// either the catalog (name) or the user's own copies (date added,
    /// price, paid). Tiebreakers fall back to bobaId so the order is
    /// stable across renders.
    private func sortIdentifiers(_ ids: [String], designation: UserCard.Designation) -> [String] {
        let order = CollectionSortOrder(rawValue: collectionSortRaw) ?? .dateAddedDesc
        // Pre-resolve metadata once per id so the sort comparator is O(1).
        struct Sortable {
            let id: String
            let name: String
            let added: Date
            let value: Decimal
            let paid: Decimal
        }
        let metas: [Sortable] = ids.map { id in
            let catalog = cardStore.displayCards.first { $0.id == id }
                       ?? cardStore.displayCards.first { $0.cardNumber == id }
            let copies = collection.entries(forBobaId: id).filter { $0.designation == designation }
            let added = copies.map { $0.acquiredAt }.min() ?? .distantPast
            let value = copies.compactMap { $0.estimatedValue }.reduce(Decimal(0), +)
            let paid  = copies.compactMap { $0.purchasePrice }.reduce(Decimal(0), +)
            return Sortable(
                id: id,
                name: catalog?.name ?? catalog?.cardNumber ?? id,
                added: added,
                value: value,
                paid: paid
            )
        }
        let sorted: [Sortable] = {
            switch order {
            case .nameAsc:
                return metas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .nameDesc:
                return metas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
            case .dateAddedDesc:
                return metas.sorted { lhs, rhs in
                    if lhs.added != rhs.added { return lhs.added > rhs.added }
                    return lhs.id < rhs.id
                }
            case .dateAddedAsc:
                return metas.sorted { lhs, rhs in
                    if lhs.added != rhs.added { return lhs.added < rhs.added }
                    return lhs.id < rhs.id
                }
            case .priceDesc:
                return metas.sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            case .priceAsc:
                return metas.sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value < rhs.value }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            case .paidDesc:
                return metas.sorted { lhs, rhs in
                    if lhs.paid != rhs.paid { return lhs.paid > rhs.paid }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            case .paidAsc:
                return metas.sorted { lhs, rhs in
                    if lhs.paid != rhs.paid { return lhs.paid < rhs.paid }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }()
        return sorted.map(\.id)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - BobaIdWrapper
// Identifiable wrapper so we can use sheet(item:) with a bobaId or legacy cardNumber string.
private struct BobaIdWrapper: Identifiable {
    let id: String
}

