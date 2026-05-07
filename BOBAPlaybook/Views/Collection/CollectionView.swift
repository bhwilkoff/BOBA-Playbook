import SwiftUI

// MARK: - CollectionView
// Main Collection tab. Shows cards grouped by designation with a value summary.
// One row per unique card_number — multiple physical copies are shown on the detail page.

struct CollectionView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore
    @Environment(ScanStore.self) private var scanStore
    @Environment(ScanCoordinator.self) private var scanCoordinator

    @State private var selectedDesignation: UserCard.Designation = .personal
    @State private var selectedCard: BobaIdWrapper?
    @State private var showingSignIn    = false
    @State private var showTradeRoom    = false
    @State private var discord          = DiscordService()
    /// NavigationStack path. Push to .rainbow or .shows from the
    /// toolbar Menu — the My Cards surface is the root and shows by
    /// default. Replaces the v2.043 viewMode segmented picker per
    /// user feedback (the picker forced 5 stacked rows of chrome
    /// before users saw a single card).
    @State private var navigationPath  = NavigationPath()

    /// Music-pattern zoom transition namespace. Each grid cell carries
    /// .matchedTransitionSource(id: bobaId, in: cardZoomNamespace) and
    /// the navigationDestination for String renders
    /// CollectionCardDetailView with .navigationTransition(.zoom(...)).
    @Namespace private var cardZoomNamespace
    @State private var isRecalculating = false
    @State private var recalcProgress: (current: Int, total: Int)? = nil

    @State private var showingFilters      = false
    /// Native search field — `.searchable` with `.navigationBarDrawer(displayMode: .always)`
    /// pins it permanently below the nav bar (Settings-app pattern). Filters
    /// `collectionIdentifiers` by hero name and card number.
    @State private var searchText: String  = ""
    @State private var exportShareURL: URL?    = nil
    @State private var walkthrough: BOBAWalkthrough.Script? = nil
    @State private var showingProfile      = false
    @State private var showingWall         = false
    @State private var showingShareSheet   = false
    @State private var shareItems: [Any]   = []
    @AppStorage("selectedIconName") private var selectedIconName: String = "default"
    /// Per user feedback: collectors care most about per-card value
    /// information — the dense LIST renderer surfaces value/paid/qty
    /// inline; GRID hides it behind individual card detail. Default
    /// is now .list with the toolbar Menu picker available to switch.
    @AppStorage("bp_collectionDisplayMode_v2") private var displayModeRaw: String = CollectionDisplayMode.list.rawValue
    /// User-selectable grid density — only applies in .grid display
    /// mode. Persisted per tab. Sentinel `0` = unset → resolves to
    /// size-class default (compact: 3, regular: 5) per DESIGN.md §6.6.
    @AppStorage("bp_collectionGridColumns_v1") private var gridColumnsStorage: Int = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var gridColumns: Int {
        Design.GridDensity.resolved(stored: gridColumnsStorage, sizeClass: horizontalSizeClass, compactDefault: 3)
    }

    private var gridColumnsBinding: Binding<Int> {
        Binding(get: { gridColumns }, set: { gridColumnsStorage = $0 })
    }
    private var displayMode: CollectionDisplayMode {
        get { CollectionDisplayMode(rawValue: displayModeRaw) ?? .grid }
    }
    /// Collection-only sort axis. Persisted across app launches because
    /// it's a personal preference (a coach who likes "Recently Added"
    /// doesn't want it reset every time they open the app).
    @AppStorage("bp_collectionSortOrder_v1") private var collectionSortRaw: String = CollectionSortOrder.dateAddedDesc.rawValue

    /// Toolbar-Menu destinations that push onto the Collection
    /// NavigationStack. My Cards is the root surface (always shown
    /// without a push). Rainbow and Shows live behind toolbar Menu
    /// entries that use NavigationLink-via-path.
    enum CollectionRoute: Hashable {
        case rainbow
        case shows
    }

    /// iPad regular uses a NavigationSplitView sidebar for lens
    /// switching; compact keeps the existing path-based push from the
    /// overflow Menu. Selecting a lens in the sidebar swaps the detail
    /// column's content — My Cards (with its designation Picker),
    /// Rainbow Progress, or My Shows (streamer-only).
    enum CollectionLens: Hashable {
        case myCards
        case rainbow
        case shows
    }
    @State private var selectedLens: CollectionLens = .myCards

    /// `List(selection:)` on iOS only accepts Binding<T?>? — not the
    /// non-optional state above. This wrapper lets the iPad sidebar
    /// drive selection while keeping the rest of the body using the
    /// non-optional value (which is conceptually correct here — there
    /// is always a lens selected). Setting nil is ignored.
    private var selectedLensBinding: Binding<CollectionLens?> {
        Binding(
            get: { selectedLens },
            set: { if let v = $0 { selectedLens = v } }
        )
    }

    /// Per DESIGN.md §8.4 — three ways to render the same data set:
    ///   - grid: visual scan, card art is the focal point (default)
    ///   - list: compact rows for triage (the legacy renderer)
    ///   - wall: tile-able image for sharing (lifted from streamer-only
    ///           per DECISIONS.md #036)
    enum CollectionDisplayMode: String, CaseIterable, Identifiable {
        // Wall is intentionally NOT a display mode — it's a sharing
        // affordance (renders cards as a single image) invoked from
        // the toolbar's "Generate Wall image…" button. Including it
        // here implied users could "switch to" Wall, which it isn't.
        case grid, list
        var id: String { rawValue }
        var label: String {
            switch self {
            case .grid: return "Grid"
            case .list: return "List"
            }
        }
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular && auth.isAuthenticated {
                iPadBody
            } else {
                compactBody
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: $showingWall) {
            // Wall presents on top of the existing Collection view; on
            // dismiss we land back on the same designation + display
            // mode the user left.
            let identifiers = collectionIdentifiers(for: selectedDesignation)
            let cards: [Card] = identifiers.compactMap { id in
                cardStore.displayCards.first { $0.id == id }
                    ?? cardStore.displayCards.first { $0.cardNumber == id }
            }
            let prices = collection.estimatedValuesByBobaId(forDesignation: selectedDesignation)
            CollectionWallSheet(
                designation: selectedDesignation,
                cards: cards,
                prices: prices,
                onDismiss: { showingWall = false }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(items: shareItems)
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
            // iPad: popover anchored on the toolbar Filters button.
            .presentationCompactAdaptation(.popover)
        }
        // Card-detail is now a NavigationLink push (matchedTransitionSource
        // + .navigationTransition(.zoom(...)) on the destination above).
        // The legacy .sheet(item: $selectedCard) is removed.
        .walkthroughOverlay($walkthrough)
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
            // First-visit walkthrough per DESIGN.md §6.10.1
            // collectionTab catalog. Fires for both signed-in and
            // signed-out users; signed-out simply sees the cells
            // anchored on the empty/sign-in surface (the walkthrough
            // copy still teaches the concept).
            if WalkthroughsManager.shared.shouldShow(.collectionTab) {
                // Defer so designation Picker + first card cell lay
                // out before the walkthrough captures their anchors.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    walkthrough = .collectionTab
                }
            }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task { await collection.loadCollection() }
            } else {
                collection.clearCollection()
            }
        }
    }

    // MARK: - Body components

    /// iPhone (and signed-out iPad) — single-column NavigationStack
    /// with the existing path-based push for Rainbow / Shows /
    /// CardDetail. Unchanged from the pre-iPad-pass shape.
    @ViewBuilder
    private var compactBody: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !auth.isAuthenticated {
                    unauthenticatedView
                } else {
                    authenticatedView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { collectionToolbar }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search your collection"
            )
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: CollectionRoute.self) { route in
                switch route {
                case .rainbow: rainbowDestination
                case .shows:   ShowsListView()
                }
            }
            .navigationDestination(for: String.self) { bobaId in
                CollectionCardDetailView(bobaId: bobaId, wrapInNavStack: false)
                    .compactZoomDestination(id: bobaId, in: cardZoomNamespace)
            }
            // CollectionCardDetailView's "Other Versions" pushes
            // un-owned variants via value-based NavigationLink — the
            // destination Card → CardDetailView (catalog detail, not
            // collection detail) is the right surface there since the
            // user doesn't own that copy. wrapInNavStack: false because
            // we're inside this NavigationStack already.
            .navigationDestination(for: Card.self) { card in
                CardDetailView(card: card, wrapInNavStack: false)
            }
        }
    }

    /// iPad regular per DESIGN.md §6.6 / §8.4 — sidebar lens picker
    /// (My Cards / Rainbow / Shows) feeding a detail column. The
    /// designation segmented Picker stays inside the My Cards detail
    /// (familiar UX); Rainbow + Shows now have permanent sidebar
    /// entries instead of being buried in the overflow Menu.
    @ViewBuilder
    private var iPadBody: some View {
        NavigationSplitView {
            iPadSidebar
        } detail: {
            NavigationStack(path: $navigationPath) {
                iPadDetail
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { collectionToolbar }
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search your collection"
                    )
                    .toolbarBackground(.regularMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .navigationDestination(for: String.self) { bobaId in
                        CollectionCardDetailView(bobaId: bobaId, wrapInNavStack: false)
                            .compactZoomDestination(id: bobaId, in: cardZoomNamespace)
                    }
                    // Mirrors compactBody — un-owned "Other Versions"
                    // variants from CollectionCardDetailView push as
                    // catalog detail.
                    .navigationDestination(for: Card.self) { card in
                        CardDetailView(card: card, wrapInNavStack: false)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var iPadSidebar: some View {
        List(selection: selectedLensBinding) {
            Section("My Cards") {
                Label("All", systemImage: "square.grid.2x2.fill")
                    .tag(CollectionLens.myCards)
            }
            Section("Other") {
                Label("Rainbow Progress", systemImage: "sparkles")
                    .tag(CollectionLens.rainbow)
                if auth.isStreamer {
                    Label("My Shows", systemImage: "tv.fill")
                        .tag(CollectionLens.shows)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Collection")
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var iPadDetail: some View {
        switch selectedLens {
        case .myCards: authenticatedView
        case .rainbow: rainbowDestination
        case .shows:   ShowsListView()
        }
    }

    /// Toolbar shared between compact and regular paths. The Rainbow /
    /// Shows menu items are conditionally hidden on iPad regular —
    /// the sidebar handles those lens switches.
    @ToolbarContentBuilder
    private var collectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            BOBAWordmark()
        }
        if auth.isAuthenticated {
            ToolbarItem(placement: .topBarTrailing) {
                filterButton
            }
            // iPad regular surfaces Scan as a standalone toolbar
            // button per DESIGN.md §6.6 (matches Find + Decks). My
            // Cards lens only — Rainbow / Shows don't take scans.
            if horizontalSizeClass == .regular && selectedLens == .myCards {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentScanner()
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    .accessibilityLabel("Scan into \(selectedDesignation.displayName)")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                collectionMenu
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
                valueSummary
                designationPicker
                cardList
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

    // MARK: - Pushed destinations (Rainbow / My Shows)

    /// Rainbow Progress as its own pushed destination (per Option B
    /// Music-style restructure). Owns its own nav title; reuses the
    /// existing rainbowIntro + rainbowList helpers from this struct
    /// since the closure captures self.
    private var rainbowDestination: some View {
        VStack(spacing: 0) {
            rainbowIntro
            rainbowList
        }
        .background(Design.Colors.nearBlack)
        .navigationTitle("Rainbow Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Collection menu (toolbar)

    private var collectionMenu: some View {
        Menu {
            // Other collection lenses — compact only. iPad regular
            // surfaces these as permanent sidebar entries (per
            // DESIGN.md §6.6); duplicating them here would be redundant.
            // Compact pushes to their own full-screen surfaces instead
            // of cramming into a top-of-view segmented picker.
            if horizontalSizeClass == .compact {
                Section {
                    Button {
                        navigationPath.append(CollectionRoute.rainbow)
                    } label: {
                        Label("Rainbow Progress", systemImage: "sparkles")
                    }
                    if auth.isStreamer {
                        Button {
                            navigationPath.append(CollectionRoute.shows)
                        } label: {
                            Label("My Shows", systemImage: "tv.fill")
                        }
                    }
                }
            }

            // Grid density (only meaningful in .grid display mode but
            // always shown so the user can switch density and mode in
            // one menu visit).
            if displayMode == .grid {
                Section("Columns") {
                    Picker("Columns", selection: gridColumnsBinding) {
                        ForEach(Design.GridDensity.columnOptions(for: horizontalSizeClass), id: \.self) { n in
                            Text("\(n) across").tag(n)
                        }
                    }
                }
            }

            // Display mode is Grid OR List — Wall is NOT a display
            // mode, it's a sharing affordance (lives in the actions
            // section below as "Generate Wall image…").
            Section("Display") {
                Picker("Display mode", selection: Binding(
                    get: { displayMode },
                    set: { displayModeRaw = $0.rawValue }
                )) {
                    ForEach(CollectionDisplayMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            }

            Section {
                // Wall as a one-shot share action, not a persistent
                // view. Generates an image of the current designation
                // scope and presents Save / Share controls inline.
                Button {
                    showingWall = true
                } label: {
                    Label("Generate Wall image…", systemImage: "rectangle.on.rectangle.angled")
                }
                .disabled(collection.userCards.isEmpty)

                // Scan is iPad-inline (when on My Cards lens); only
                // show in Menu on compact width.
                if horizontalSizeClass == .compact {
                    Button {
                        presentScanner()
                    } label: {
                        Label("Scan into \(selectedDesignation.displayName)", systemImage: "camera.viewfinder")
                    }
                }

                Button {
                    Task { await recalculateAll() }
                } label: {
                    Label(isRecalculating ? "Refreshing prices…" : "Refresh market values",
                          systemImage: "arrow.clockwise")
                }
                .disabled(isRecalculating)

                Button {
                    exportCollectionCSV()
                } label: {
                    Label("Export Collection (CSV)", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(collection.userCards.isEmpty)

                // "Share as Wall image…" removed per user feedback —
                // it duplicated the Display → Wall option (both opened
                // CollectionWallSheet, which has its own Save/Share
                // controls inline).
            }

            Divider()

            // Walkthrough re-launcher per §6.10.1.
            Button {
                WalkthroughsManager.shared.relaunch(.collectionTab)
                walkthrough = .collectionTab
            } label: {
                Label("Show walkthrough", systemImage: "questionmark.circle")
            }
        } label: {
            if isRecalculating {
                ProgressView().tint(Design.Colors.bobaOrange)
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
        }
        .walkthroughAnchor("collection.displayMode")
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

    /// Replaces the legacy horizontal scrolling pill row (the
    /// "scrolling pills" anti-pattern the user flagged across the app)
    /// with a native segmented Picker. iOS-built-in, no horizontal
    /// scroll, fits all five designations across the bar at standard
    /// iPhone widths because the labels are short ("Personal", "Sale",
    /// "Trade", "Wanted", "Grails").
    private var designationPicker: some View {
        Picker("Designation", selection: $selectedDesignation) {
            ForEach(UserCard.Designation.allCases) { d in
                Text(d.shortDisplayName).tag(d)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface)
        .walkthroughAnchor("collection.scopeBar")
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
                    } else if displayMode == .grid {
                        // GRID mode (§8.4 default) — visual scan, card art focal.
                        // Tap a tile → card detail. Same identifier list as List
                        // mode so designation badge / count are derived
                        // identically.
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: Design.Spacing.sm),
                                           count: max(1, gridColumns)),
                            spacing: Design.Spacing.md
                        ) {
                            ForEach(Array(identifiers.enumerated()), id: \.element) { idx, identifier in
                                // matchedTransitionSource MUST be the
                                // LAST (outermost) modifier so iOS sees
                                // it on the rendered cell, not inside
                                // the function-returned view. Otherwise
                                // iOS prints the "nil view" warning and
                                // falls back to the standard transition
                                // (the forehead).
                                if idx == 0 {
                                    collectionGridCell(identifier: identifier)
                                        .onTapGesture { navigationPath.append(identifier) }
                                        .walkthroughAnchor("collection.cardCell")
                                        .compactZoomSource(id: identifier, in: cardZoomNamespace)
                                } else {
                                    collectionGridCell(identifier: identifier)
                                        .onTapGesture { navigationPath.append(identifier) }
                                        .compactZoomSource(id: identifier, in: cardZoomNamespace)
                                }
                            }
                        }
                        .padding(Design.Spacing.md)
                    } else {
                        // LIST mode — compact rows. The matchedTransitionSource
                        // is attached INSIDE collectionRow (around the small
                        // thumb on the leading edge) so the hero zoom
                        // appears to come from the card art, not the whole
                        // row card. iOS draws the zoom from the matched
                        // source's frame, so anchoring to the thumb gives
                        // a tight, art-led transition.
                        LazyVStack(spacing: Design.Spacing.sm) {
                            ForEach(Array(identifiers.enumerated()), id: \.element) { idx, identifier in
                                if idx == 0 {
                                    collectionRow(identifier: identifier)
                                        .onTapGesture { navigationPath.append(identifier) }
                                        .walkthroughAnchor("collection.cardCell")
                                } else {
                                    collectionRow(identifier: identifier)
                                        .onTapGesture { navigationPath.append(identifier) }
                                }
                            }
                        }
                        .padding(Design.Spacing.lg)
                    }
                }
                .scrollEdgeEffectStyle(.hard, for: .top)  // §5.6 dense scroll
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
                                navigationPath.append(row.coverCard.id)
                            }
                    }
                }
                .padding(Design.Spacing.lg)
            }
        }
        .scrollEdgeEffectStyle(.hard, for: .top)  // §5.6 dense scroll
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

    /// Grid-mode tile per DESIGN.md §8.4. Card art focal point with a
    /// designation badge in the corner so cards visible across multiple
    /// designations stay scannable from a single grid view.
    @ViewBuilder
    private func collectionGridCell(identifier: String) -> some View {
        let catalog = cardStore.displayCards.first { $0.id == identifier }
                   ?? cardStore.displayCards.first { $0.cardNumber == identifier }
        let allDesignations = Set(collection.entries(forBobaId: identifier).map { $0.designation })

        if let card = catalog {
            BOBACardGridItem(card: card, columnCount: gridColumns)
                .overlay(alignment: .topTrailing) {
                    if allDesignations.count > 1 {
                        HStack(spacing: 2) {
                            ForEach(Array(allDesignations).sorted(by: { $0.rawValue < $1.rawValue })) { d in
                                Image(systemName: d.icon)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                        }
                        .padding(4)
                    }
                }
                // iPad cross-window drag-drop per DESIGN.md §6.6.
                // Drag a Collection card into a Decks editor window
                // to add it to the current draft. Catalog-miss
                // placeholder branch below isn't draggable (no Card).
                .draggable(card)
        } else {
            // Catalog miss — render a placeholder + identifier so the
            // user sees something rather than a blank slot.
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: BOBACardCell.cornerRadius)
                    .fill(Design.Colors.glass)
                    .aspectRatio(BOBACardCell.aspectRatio, contentMode: .fit)
                Text(identifier)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .lineLimit(1)
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
            // Thumbnail — bumped from 44×62 to 60×84 to match the larger
            // body text. matchedTransitionSource lives HERE (not on
            // the whole row) so the zoom-into-detail animation
            // appears to originate from the actual card art, mirroring
            // grid-mode's behavior.
            Group {
                if let card = catalog {
                    CardImageView(card: card, size: .thumb)
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                } else {
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .fill(Design.Colors.surface2)
                }
            }
            .frame(width: 60, height: 84)
            .compactZoomSource(id: identifier, in: cardZoomNamespace)

            VStack(alignment: .leading, spacing: 4) {
                // Title + qty pill on the same row so the count stays
                // visible on long names (lineLimit(1) was clipping it).
                // Pill shows total across ALL designations; if some of
                // those copies live elsewhere, append "(N here)" so the
                // current-tab share is still readable at a glance.
                HStack(spacing: Design.Spacing.xs) {
                    Text(catalog?.name ?? catalog?.cardNumber ?? identifier)
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                    if totalCopiesAllDesignations > 1 {
                        let label = totalCopiesAllDesignations == copies.count
                            ? "×\(totalCopiesAllDesignations)"
                            : "×\(totalCopiesAllDesignations) (\(copies.count) here)"
                        Text(label)
                            .font(Design.Fonts.mono(11, weight: .bold))
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
                            .font(Design.Fonts.mono(12, weight: .bold))
                            .foregroundStyle(Design.Colors.element(element))
                    }
                    if let power = catalog?.power, power > 0 {
                        Text("⚡\(power)")
                            .font(Design.Fonts.mono(12, weight: .bold))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    Text(catalog?.cardNumber ?? identifier)
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                // Treatment — separate line so long treatments wrap
                // gracefully without crowding the stat strip.
                if let treatment = catalog?.treatment, !treatment.isEmpty {
                    Text(treatment)
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                        .lineLimit(1)
                }
                // Date added — small relative-date hint so coaches know
                // how recently they acquired the card.
                if let added = earliestAdded {
                    Text("Added \(formatAddedDate(added))")
                        .font(Design.Fonts.mono(11))
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
                            .font(Design.Fonts.mono(15, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                        Text("VALUE")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    } else if totalPaid > 0 {
                        Text(formatCurrency(totalPaid))
                            .font(Design.Fonts.mono(15, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("PAID")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    } else {
                        Text("$—")
                            .font(Design.Fonts.mono(15))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    if estimatedTotal > 0 && totalPaid > 0 {
                        Text("paid \(formatCurrency(totalPaid))")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                } else {
                    Text(selectedDesignation.displayName.uppercased())
                        .font(Design.Fonts.mono(11, weight: .bold))
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
    /// Routes Collection-tab scan invocation through ScanCoordinator.
    /// Until ScanStore gains a beginCollectionSession (designation chooser
    /// + per-card destination), Collection scans land in the queue
    /// identify-only via .find — coaches still review and add via the
    /// queue's existing "save to designation" picker. This wraps the
    /// invocation in the canonical pattern so a future upgrade only
    /// requires switching the destination case.
    private func presentScanner() {
        scanCoordinator.start(.find, scanStore: scanStore)
    }

    /// Per DESIGN.md §8.4 — share the active designation as a deep link
    /// to the web fallback (`bobaplaybook.com/u/{username}/{designation}`)
    /// plus the existing CSV export. iOS share sheet lets the user pick
    /// destination (Messages / Mail / AirDrop / Notes / Files).
    private func presentShareDeepLink() {
        var items: [Any] = []
        if let userId = auth.userId {
            // Public-designation deep link. Web fallback honors the same
            // bobaplaybook.com/u/{username}/{designation} URL contract.
            // For now we don't have usernames; fall back to user UUID
            // until the public-profile feature lands.
            let url = URL(string: "https://bobaplaybook.com/u/\(userId)/\(selectedDesignation.rawValue)")!
            items.append(url)
        }
        items.append("My \(selectedDesignation.displayName) on BOBA Playbook")
        shareItems = items
        showingShareSheet = true
    }

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
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            owned = owned.filter { id in
                let card = cardStore.displayCards.first { $0.id == id }
                          ?? cardStore.displayCards.first { $0.cardNumber == id }
                guard let card else { return false }
                // FREE / 0 HD shortcut — Plays + Bonus Plays with
                // playCost == 0 don't have "FREE" or "0" in their name
                // / hero / cardNumber, so the literal substring search
                // misses them. Mirror the DecksView pool filter
                // pattern so coaches scanning their collection for
                // free plays can find them. Same special-case applies
                // to typing "1 hd", "2hd", etc.
                if let cost = freeCostQuery(trimmed),
                   let cardCost = card.playCost {
                    return cardCost == cost
                }
                return card.name.lowercased().contains(trimmed)
                    || card.cardNumber.lowercased().contains(trimmed)
                    || card.hero.lowercased().contains(trimmed)
            }
        }
        return sortIdentifiers(owned, designation: designation)
    }

    /// Maps a normalized search query to a play-cost integer when the
    /// user is asking for free / N HD plays. Returns nil for queries
    /// that should fall through to the substring matcher.
    private func freeCostQuery(_ q: String) -> Int? {
        if q == "free" || q == "0 hd" || q == "0hd" { return 0 }
        // "1 hd" / "1hd" / "2 hd" / etc. up through 8.
        for n in 1...8 {
            if q == "\(n) hd" || q == "\(n)hd" { return n }
        }
        return nil
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

