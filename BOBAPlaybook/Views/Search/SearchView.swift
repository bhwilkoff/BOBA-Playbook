import SwiftUI

struct SearchView: View {
    @Environment(CardStore.self) private var store
    @Environment(CollectionStore.self) private var collection
    @Environment(AuthManager.self) private var auth
    @State private var showFilters = false
    @State private var selectedCard: Card?
    @Environment(ScanStore.self) private var scanStore
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @State private var showProfile = false
    /// When true, tapping a grid card adds it to the user's Collection
    /// (as .personal) instead of opening the card detail sheet. Parallels
    /// the deck builder's Quick Add toggle. Sits on a pill next to the
    /// results count under the search bar.
    @State private var quickAdd = false
    @State private var quickAddToast: String? = nil
    @State private var quickAddError: String? = nil
    /// First-visit walkthrough trigger per DESIGN.md §6.10. Activates
    /// the .findTab script from §6.10.1 when the user opens Find for
    /// the first time. Re-triggerable via toolbar Menu.
    @State private var walkthrough: BOBAWalkthrough.Script? = nil

    /// Per user feedback: showing Card Showcases as the default empty-
    /// state surface isn't how people actually search for cards. The
    /// full grid is back as the default; Card Showcases is now an
    /// opt-in mode toggleable from the toolbar Menu. Persisted across
    /// launches so coaches who DO like browsing by Showcase keep it.
    @AppStorage("bp_findShowcaseMode_v1") private var showcaseMode: Bool = false
    /// Drives the keyboard-toolbar Done button. SwiftUI's only built-in
    /// way to dismiss the keyboard from the field is via a focus binding,
    /// so the search field needs its own @FocusState even though we don't
    /// otherwise route focus into it.
    @FocusState private var searchFocused: Bool
    /// Mirror of the Settings → App Icon choice. The profile icon's tint
    /// follows this so the accent stays consistent with the user's chosen
    /// icon color.
    @AppStorage("selectedIconName") private var selectedIconName: String = "default"

    /// User-selectable grid density (1 / 2 / 3 cards across). Persisted
    /// per tab so the user can pick a denser layout in Find without it
    /// affecting Decks or Collection.
    @AppStorage("bp_findGridColumns_v1") private var gridColumns: Int = 2

    /// Music-pattern zoom transitions. Each grid cell carries a
    /// .matchedTransitionSource(id: card.id, in: cardZoomNamespace)
    /// and the navigationDestination renders CardDetailView with
    /// .navigationTransition(.zoom(...)) — the destination grows out
    /// of the tapped cell, all native iOS 18+ APIs.
    @Namespace private var cardZoomNamespace

    /// Navigation path for the Find NavigationStack. Cell taps push
    /// onto this so CardDetailView slides in from the right (with the
    /// tab bar still visible) instead of presenting as a sheet.
    @State private var navigationPath = NavigationPath()

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Design.Spacing.sm),
              count: max(1, min(3, gridColumns)))
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $navigationPath) {
            Group {
                if store.isLoading {
                    loadingView
                } else if let error = store.loadError {
                    errorView(error)
                } else {
                    contentView
                }
            }
            // Find uses Tab(role: .search) — let the role determine the
            // placement instead of forcing .navigationBarDrawer. The
            // search role is what gives Find the visually-distinctive
            // tab-bar slot and the iOS 26 search expansion behavior.
            .searchable(
                text: $store.searchText,
                prompt: "Cards, heroes, numbers…"
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { findToolbar }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay(alignment: .top) { quickAddToastOverlay }
            .alert("Couldn't add that card",
                   isPresented: quickAddErrorPresented,
                   presenting: quickAddError) { _ in
                Button("OK") { quickAddError = nil }
            } message: { error in
                Text(error)
            }
            .navigationDestination(for: Card.self) { card in
                CardDetailView(card: card,
                               navigationCards: store.filteredCards,
                               wrapInNavStack: false)
                    .navigationTransition(.zoom(sourceID: card.id, in: cardZoomNamespace))
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheetView(store: store)
        }
        // Scan presentation lives at ContentView per DESIGN.md §6.5
        // (single ScanView modal regardless of invoking tab). Find calls
        // ScanCoordinator.start(.find, scanStore:) — the coordinator
        // drives the centralized fullScreenCover.
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .walkthroughOverlay($walkthrough)
        // Deep-link: bobaplaybook://card/{number} sets store.pendingCardNumber.
        // Try to resolve it immediately (cards may already be loaded) and again
        // when the full catalog finishes loading.
        .onChange(of: store.pendingCardNumber) { _, cardNum in
            tryPresentPendingCard()
        }
        .onChange(of: store.isLoadingMore) { _, _ in
            tryPresentPendingCard()
        }
        // Deep-link: bobaplaybook://scan — present the scanner sheet.
        .onChange(of: store.pendingScan) { _, pending in
            if pending {
                scanCoordinator.start(.find, scanStore: scanStore)
                store.pendingScan = false
            }
        }
        // Deep-link: bobaplaybook://search?q=... — set by SearchCardIntent
        // (Spotlight / Siri / Action Button per DESIGN.md §7).
        .onChange(of: store.pendingSearchQuery) { _, q in
            if let q, !q.isEmpty {
                store.searchText = q
                store.pendingSearchQuery = nil
            }
        }
        .onAppear {
            // Reset filter state when the tab re-appears — moving
            // between Find ↔ Collection ↔ etc. starts with a clean
            // slate rather than dragging a forgotten element pill
            // along. Sheets / modals don't retrigger onAppear on the
            // presenter so in-tab navigation (open card → close) keeps
            // whatever was set.
            store.clearAllFilters()
            tryPresentPendingCard()
            if store.pendingScan {
                scanCoordinator.start(.find, scanStore: scanStore)
                store.pendingScan = false
            }
            if let q = store.pendingSearchQuery, !q.isEmpty {
                store.searchText = q
                store.pendingSearchQuery = nil
            }
            if WalkthroughsManager.shared.shouldShow(.findTab) {
                walkthrough = .findTab
            }
        }
    }

    // MARK: - Quick Add toggle
    //
    // Mirror of the DeckBuilder pill. When on, tapping a grid card
    // adds it to the user's Collection as .personal instead of opening
    // the card-detail sheet. A small confirmation toast flashes at
    // the top so the coach knows the add succeeded.
    private var quickAddToggle: some View {
        Button {
            quickAdd.toggle()
        } label: {
            Label(
                quickAdd ? "Quick Add" : "Tap to View",
                systemImage: quickAdd ? "plus.circle.fill" : "eye.fill"
            )
            .font(Design.Fonts.mono(11, weight: .bold))
            .foregroundStyle(quickAdd ? Design.Colors.bobaOrange : Design.Colors.textMuted)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(quickAdd ? Design.Colors.bobaOrange.opacity(0.15) : Design.Colors.glass)
            )
        }
        .buttonStyle(.plain)
    }

    /// Writes a fresh user_card row for this card at .personal
    /// designation, then animates a confirmation toast. Collisions
    /// (same bobaId already owned) are allowed — coaches often add
    /// multiple copies of the same hero from a pull.
    private func quickAddCard(_ card: Card) async {
        do {
            let entry = NewUserCard(
                cardNumber: card.cardNumber,
                bobaId: card.id,
                designation: .personal
            )
            try await collection.addCard(entry)
            withAnimation(.easeOut(duration: 0.25)) {
                quickAddToast = "Added \(card.name)"
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.3)) { quickAddToast = nil }
            }
        } catch {
            quickAddError = error.localizedDescription
        }
    }

    /// Stable Binding<Bool> for the quickAdd-error alert — pulled out
    /// of the body so the inline Binding(get:set:) doesn't blow up
    /// type inference.
    private var quickAddErrorPresented: Binding<Bool> {
        Binding(
            get: { quickAddError != nil },
            set: { if !$0 { quickAddError = nil } }
        )
    }

    /// Quick-add success toast — extracted from the body's .overlay so
    /// the body's expression chain stays small enough for the type
    /// checker.
    @ViewBuilder
    private var quickAddToastOverlay: some View {
        if let toast = quickAddToast {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "4CAF50"))
                Text(toast)
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "4CAF50").opacity(0.4), lineWidth: 1))
            .padding(.top, 56)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Toolbar extracted to break up the body's expression complexity —
    /// SwiftUI's type checker times out when the NavigationStack body
    /// chain grows past ~135 lines (per `unable to type-check this
    /// expression in reasonable time` error after the v2.050 zoom-
    /// transition wiring).
    @ToolbarContentBuilder
    private var findToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showProfile = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(AppIconOption.currentColor(for: selectedIconName))
            }
            .accessibilityLabel("Profile")
            .walkthroughAnchor("find.profile")
        }
        ToolbarItem(placement: .principal) {
            BOBAWordmark()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                scanCoordinator.start(.find, scanStore: scanStore)
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Design.Colors.bobaCyan)
            }
            .accessibilityLabel("Scan a card")
            .walkthroughAnchor("find.scan")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Columns") {
                    Picker("Columns", selection: $gridColumns) {
                        Label("1 across", systemImage: "rectangle").tag(1)
                        Label("2 across", systemImage: "square.grid.2x1").tag(2)
                        Label("3 across", systemImage: "square.grid.3x1.below.line.grid.1x2").tag(3)
                    }
                }
                Section {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage: "slider.horizontal.3")
                    }
                    Toggle(isOn: $showcaseMode) {
                        Label("Card Showcases", systemImage: "square.stack.3d.up.fill")
                    }
                }
                Divider()
                Button {
                    WalkthroughsManager.shared.relaunch(.findTab)
                    walkthrough = .findTab
                } label: {
                    Label("Show walkthrough", systemImage: "questionmark.circle")
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Design.Colors.textPrimary)
                    if store.activeFilterCount > 0 {
                        Circle()
                            .fill(Design.Colors.bobaOrange)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .walkthroughAnchor("find.menu")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { searchFocused = false }
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
        }
    }

    private func tryPresentPendingCard() {
        guard let cardNum = store.pendingCardNumber,
              !store.displayCards.isEmpty,
              let card = store.displayCards.first(where: { $0.cardNumber == cardNum }) else { return }
        navigationPath.append(card)
        store.pendingCardNumber = nil
    }

    // MARK: - Content
    private var contentView: some View {
        ScrollView {
            // Default: full card grid (results body) sorted by has-image.
            // Card Showcases is opt-in via the toolbar Menu — it's
            // useful for browsing curated lists but isn't how people
            // actually search for cards day-to-day.
            if showcaseMode && !isSearchingOrFiltering {
                featuredRibbons
                    .walkthroughAnchor("find.ribbons")
                    .padding(.top, Design.Spacing.sm)
            } else {
                resultsHeader
                resultsBody
            }
        }
        .background(Design.Colors.nearBlack)
        .scrollEdgeEffectStyle(.hard, for: .top)
    }

    /// True when the user is actively searching/filtering. Showcase mode
    /// auto-yields to results when the user types or filters.
    private var isSearchingOrFiltering: Bool {
        !store.searchText.isEmpty || store.activeFilterCount > 0
    }

    @ViewBuilder
    private var resultsHeader: some View {
        // Results count + Quick Add toggle. Authenticated users get
        // the toggle; anonymous users just see the count.
        HStack {
            Text("\(store.filteredCards.count) cards")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
            Spacer()
            if auth.isAuthenticated {
                quickAddToggle
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.sm)

        if store.isLoadingMore {
            HStack(spacing: Design.Spacing.sm) {
                ProgressView()
                    .tint(Design.Colors.bobaCyan)
                    .scaleEffect(0.7)
                Text("Searching first 500 cards — full catalog loading…")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xs)
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if store.filteredCards.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: Design.Spacing.sm) {
                ForEach(Array(store.filteredCards.enumerated()), id: \.element.id) { idx, card in
                    BOBACardGridItem(card: card, columnCount: gridColumns)
                        .aspectRatio(3/4, contentMode: .fit)
                        .matchedTransitionSource(id: card.id, in: cardZoomNamespace)
                        .onTapGesture {
                            if quickAdd {
                                Task { await quickAddCard(card) }
                            } else {
                                navigationPath.append(card)
                            }
                        }
                        // Anchor ONLY the first cell — PreferenceKey
                        // reduces to "last value wins", so attaching to
                        // every cell made the spotlight land on a random
                        // bottom row.
                        .modifier(IfFirstAnchor(isFirst: idx == 0, key: "find.cardCell"))
                }
            }
            .padding(.horizontal, Design.Spacing.lg)

            if store.isLoadingMore {
                HStack(spacing: Design.Spacing.sm) {
                    ProgressView()
                        .tint(Design.Colors.bobaOrange)
                        .scaleEffect(0.8)
                    Text("Loading full catalog…")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.lg)
            }

            Spacer().frame(height: Design.Spacing.xl)
        }
    }

    // MARK: - Featured ribbons (DESIGN.md §8.1)
    //
    // Default state when no search query or filter active. Three
    // grouped sections: hand-curated Featured Collections, By Weapon,
    // By Sport. Source data lives in `BrowseFeaturedData` (extracted
    // from the legacy LearnView.BrowseView during the §8.2 Learn
    // rebuild). Each ribbon is horizontally-scrolling card cells; tap
    // a card → CardDetailView push (or quickAdd if toggle is on).
    @ViewBuilder
    private var featuredRibbons: some View {
        LazyVStack(alignment: .leading, spacing: Design.Spacing.xl) {
            // Card Showcases (renamed from Featured Collections to
            // match the term used in the filter sheet, per user
            // feedback). Hand-curated cross-cuts that aren't easily
            // expressed as filters.
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                BOBASectionHeader("Card Showcases")
                ForEach(BrowseFeaturedData.collections) { coll in
                    featuredCollectionRow(coll)
                }
            }

            // By weapon
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                BOBASectionHeader("By Weapon")
                ForEach(BrowseFeaturedData.weapons, id: \.element) { wf in
                    weaponRibbon(element: wf.element, label: wf.label)
                }
            }

            // By sport
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                BOBASectionHeader("By Sport")
                ForEach(BrowseFeaturedData.sports, id: \.label) { sf in
                    sportRibbon(label: sf.label, athletes: sf.athletes)
                }
            }
        }
        .padding(.bottom, Design.Spacing.xxl)
    }

    /// Per user feedback #5: every view of the app should prioritize
    /// cards with art. Card Showcases ribbons previously took the
    /// first 20 matches in raw catalog order, which surfaced
    /// image-pending placeholders. This sorter pushes art-bearing
    /// cards to the front of every ribbon.
    private func sortedWithArt(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            let aImg = !(a.imageFile ?? "").isEmpty
            let bImg = !(b.imageFile ?? "").isEmpty
            if aImg != bImg { return aImg }
            return false
        }
    }

    @ViewBuilder
    private func featuredCollectionRow(_ coll: BrowseFeaturedData.Collection) -> some View {
        // Suffix the count label onto the description (e.g. "...female
        // athletes across every sport. · 884 cards") so the curated
        // count from the legacy BrowseView is preserved in the Find
        // ribbon migration.
        let subtitle = "\(coll.description) · \(coll.countLabel)"
        ribbon(
            title: coll.name,
            subtitle: subtitle,
            tint: coll.color,
            cards: Array(sortedWithArt(store.displayCards.filter(coll.matches)).prefix(20))
        )
    }

    @ViewBuilder
    private func weaponRibbon(element: String, label: String) -> some View {
        // Per user feedback — drop the "Heroes" suffix. Under the "By
        // Weapon" section header the noun is implied; the ribbon title
        // just needs the weapon name.
        ribbon(
            title: label,
            subtitle: nil,
            tint: Design.Colors.element(element),
            cards: Array(sortedWithArt(store.displayCards.filter { $0.element == element }).prefix(20))
        )
    }

    @ViewBuilder
    private func sportRibbon(label: String, athletes: Set<String>) -> some View {
        ribbon(
            title: label,
            subtitle: nil,
            tint: Design.Colors.bobaOrange,
            cards: Array(sortedWithArt(store.displayCards.filter { card in
                guard let insp = card.athleteInspiration else { return false }
                return athletes.contains(insp)
            }).prefix(20))
        )
    }

    @ViewBuilder
    private func ribbon(title: String, subtitle: String?, tint: Color, cards: [Card]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.sm) {
                    ForEach(cards) { card in
                        BOBACardGridItem(card: card, columnCount: gridColumns)
                            .frame(width: 110)
                            .aspectRatio(3/4, contentMode: .fit)
                            .matchedTransitionSource(id: card.id, in: cardZoomNamespace)
                            .onTapGesture {
                                if quickAdd {
                                    Task { await quickAddCard(card) }
                                } else {
                                    navigationPath.append(card)
                                }
                            }
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
            }
        }
    }

    // MARK: - Filter button
    private var filterButton: some View {
        Button {
            showFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)
                if store.activeFilterCount > 0 {
                    Circle()
                        .fill(Design.Colors.bobaOrange)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: Design.Spacing.lg) {
            ProgressView()
                .tint(Design.Colors.bobaOrange)
                .scaleEffect(1.4)
            Text("Loading card catalog…")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Error
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text("Could not load cards")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(message)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No cards match your search")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textSecondary)
            Button("Clear All Filters") {
                store.clearAllFilters()
            }
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// PreferenceKey-aware "anchor only the first item" modifier — the
/// walkthrough anchor PreferenceKey reduces to "last value wins", so
/// attaching .walkthroughAnchor() to every item in a ForEach makes
/// the spotlight land on a random item. This wraps the .walkthroughAnchor
/// call in a check so only `isFirst` carriers contribute.
private struct IfFirstAnchor: ViewModifier {
    let isFirst: Bool
    let key: String
    func body(content: Content) -> some View {
        if isFirst { content.walkthroughAnchor(key) } else { content }
    }
}

