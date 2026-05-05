//
//  DecksView.swift
//  BOBAPlaybook
//
//  The "Decks" tab — built per DESIGN.md §8.3 (Maps pattern).
//
//    Card pool grid = canvas (full screen)
//    Current deck   = bottom sheet with detents [.height(120), .medium, .large]
//
//  - Tap any card in the pool → adds it to the deck. Long-press → detail sheet.
//    No quick-add toggle (one consistent interaction rule per §8.3).
//  - .height(120): deck name + count + format badge + drag handle.
//  - .medium: format chip strip on top, then grouped deck list.
//  - .large: full deck list with validation + legality badge + access to rules.
//  - Toolbar: Profile (top-leading) · BOBAWordmark (principal) · Save +
//    overflow Menu (top-trailing). Save is the only tinted glass action per
//    §5.4. The Menu collapses Templates / Saved decks / Import / Export /
//    Rules / Legality / Scan / Walkthrough / Clear deck.
//  - Search: `.searchable` over the card pool with a single Collection-only
//    toggle inside the sheet (replaces the 5 filter rows in the legacy view).
//    Token-driven filtering is a §32 cleanups follow-up.
//
//  The legacy `DeckBuilderView` is still used as a sheet from CardDetailView's
//  "Add to Custom Deck" flow with a `pendingCard`; both views share the same
//  on-disk DeckBuilderStore draft so adding from a card detail and opening
//  the Decks tab show the same in-progress deck.
//

import SwiftUI

struct DecksView: View {

    // MARK: - Environment + store

    @Environment(CardStore.self)        private var cardStore
    @Environment(CollectionStore.self)  private var collection
    @Environment(AuthManager.self)      private var auth
    @Environment(ScanStore.self)        private var scanStore
    @Environment(ScanCoordinator.self)  private var scanCoordinator

    @State private var store = DeckBuilderStore()

    // MARK: - Sheet + UI state

    /// Inline drawer at the bottom of the tab content. Truly free
    /// drag — release commits to wherever the finger left off (with
    /// a small momentum carry from velocity), clamped only to the
    /// minimum (header-only collapsed) and the maximum (full tab
    /// content height — covers all cards). No snap points fighting
    /// the drag.
    ///
    /// Tap on the header toggles between the two extremes (collapsed
    /// vs. fully expanded) for users who prefer click-to-resize.
    ///
    /// Drawer lives INSIDE tab content so the tab bar at the TabView
    /// level stays visible underneath regardless of height.
    private static let drawerCollapsedHeight: CGFloat = 132

    /// Music-pattern editor presentation. Tapping the bottom summary
    /// pill (or the strip — Stage 2) zooms into a full-screen deck
    /// editor. Replaces the v2.038 custom drawer entirely. The
    /// shared @Namespace lets `.matchedTransitionSource` on the pill
    /// pair with `.navigationTransition(.zoom(...))` on the cover for
    /// Photos-app-style hero zoom.
    @State private var editorOpen = false
    @Namespace private var deckZoomNamespace

    /// NavigationStack path INSIDE the editor. Manage Decks / Rules /
    /// Legality push as destinations so they slide in from the right
    /// with a back chevron — Music's "drill into next layer" pattern
    /// instead of the previous "drawer on top of drawer" sheet stack.
    @State private var editorPath = NavigationPath()

    /// User-selectable grid density for the card pool (1 / 2 / 3
    /// across). Persisted per tab so Decks can stay denser than Find.
    @AppStorage("bp_decksGridColumns_v1") private var gridColumns: Int = 3

    /// Music-pattern zoom transition namespace + path for the card
    /// pool. Tap a pool cell → BrowserCardDetailSheet zooms in from
    /// the cell via .matchedTransitionSource + .navigationTransition.
    @Namespace private var poolZoomNamespace
    @State private var poolNavigationPath = NavigationPath()

    /// Routes within the editor's NavigationStack.
    enum EditorRoute: Hashable {
        case deckManagement
        case rules
        case legality
    }

    // Pool filters
    @State private var search            = ""
    @State private var tokens            : [BOBAFilterToken] = []
    @State private var collectionOnly    = false
    /// Tap = open detail; long-press = add to deck. The earlier
    /// quickAdd toggle was removed because long-press is the
    /// canonical add gesture now (per user feedback #6) and the
    /// walkthrough copy already says so.
    @FocusState private var searchFocused: Bool

    /// Single secondary-sheet enum so .sheet(item:) hosts ONE modal at
    /// a time. Replaces the four .sheet(isPresented:) modifiers stacked
    /// on the bottom-sheet content, which presented unreliably (the
    /// reported "Profile button doesn't consistently work" bug).
    enum SecondarySheet: Identifiable {
        case profile, rules, legality, deckManagement
        var id: Int { hashValue }
    }
    @State private var secondarySheet: SecondarySheet? = nil
    @State private var selectedBrowserCard   : Card? = nil

    // Scan + alerts + transient feedback. Scan presentation lives at
    // ContentView per DESIGN.md §6.5 — DecksView calls scanCoordinator
    // .start(.deck(...)). No local showScan / fullScreenCover here.
    @State private var confirmingClearDeck   = false
    @State private var addedBanner           : String? = nil
    @State private var saveBanner            : String? = nil

    // Walkthrough
    @State private var walkthrough: BOBAWalkthrough.Script? = nil

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $poolNavigationPath) {
            ZStack(alignment: .top) {
                cardPoolCanvas
                addedBannerOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // .safeAreaInset auto-sizes the inset to the pill's actual
            // height (≈60pt) and reflows around the keyboard when search
            // is active. Replaces the fixed 132pt padding that left a
            // visible gap below the canvas.
            .safeAreaInset(edge: .bottom) {
                DeckSummaryPill(
                    store: store,
                    onTap: { editorOpen = true },
                    namespace: deckZoomNamespace
                )
                .padding(.horizontal, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.sm)
                .walkthroughAnchor("decks.summaryPill")
            }
            .searchable(
                text: $search,
                tokens: $tokens,
                suggestedTokens: .constant(suggestedTokens),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search · weapon, cost, or hero"
            ) { token in
                Label(token.label, systemImage: token.systemImageName)
                    .foregroundStyle(token.tint)
            }
            .toolbar { toolbarContent }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible,         for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            // Search tokens per DESIGN.md §6.4 — replaces every filter
            // pill row in the legacy view. Suggested tokens are
            // contextual (every weapon, the 0–4 HD costs, hero matches
            // for the current search query). The store's
            // filteredPoolCards reads $tokens to narrow results.
            // Search is intentionally NOT in the nav bar — `.searchable`
            // (in any placement) made iOS take over the toolbar with a
            // Cancel button when the field focused, blocking the SAVE
            // pill and the overflow Menu. Per user feedback #2 the
            // search lives inside the drawer header now (custom
            // TextField), which never affects the nav bar at all and
            // gets a proper Done button on the keyboard via the
            // .keyboard ToolbarItemGroup below.
            // Card-detail push — Music's tap-to-zoom pattern. Cells
            // mark their identity via .matchedTransitionSource and
            // the destination renders BrowserCardDetailSheet with
            // .navigationTransition(.zoom(...)) so the sheet grows
            // out of the tapped cell. Tab bar stays visible.
            .navigationDestination(for: Card.self) { card in
                BrowserCardDetailSheet(card: card,
                                       store: store,
                                       tab: pickRoleForCard(card),
                                       wrapInNavStack: false)
                    .navigationTransition(.zoom(sourceID: card.id, in: poolZoomNamespace))
            }
            // Music-pattern full-screen editor — zooms in from the
            // summary pill via matchedTransitionSource. The closure
            // captures self, so existing private helpers
            // (sheetHeaderRow, formatChipStrip, deckListScroll) are
            // accessible without needing to extract them into a
            // standalone struct.
            //
            // Secondary sheets (Profile / Rules / Legality / Manage)
            // and the Clear-deck alert are attached INSIDE the cover
            // so they present on top of the editor. Previously they
            // were on the parent — iOS would dismiss the cover before
            // showing them, which broke the "open Manage Decks while
            // editing" flow.
            .fullScreenCover(isPresented: $editorOpen) {
                NavigationStack(path: $editorPath) {
                    VStack(spacing: 0) {
                        sheetHeaderRow
                        Divider().background(Design.Colors.glass)
                        formatChipStrip
                            .walkthroughAnchor("decks.formatChip")
                        Divider().background(Design.Colors.glass)
                        deckListScroll
                    }
                    .toolbar { editorToolbar }
                    .toolbarBackground(.regularMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: EditorRoute.self) { route in
                        switch route {
                        case .deckManagement:
                            DeckManagementSheet(store: store, cards: cardStore.displayCards, wrapInNavStack: false)
                        case .rules:
                            DeckRulesSheet(store: store, wrapInNavStack: false)
                        case .legality:
                            LegalityReportSheet(store: store, wrapInNavStack: false)
                        }
                    }
                    // Profile is the lone exception — stays a sheet
                    // because SignInView (which Profile hosts) is
                    // designed as a modal account/auth surface and
                    // doesn't fit a push back-chevron context.
                    .sheet(item: $secondarySheet) { sheet in
                        switch sheet {
                        case .profile:        ProfileView()
                        // Other cases retained for compile parity but
                        // no longer fired from the editor — they push
                        // via editorPath instead.
                        case .rules:          DeckRulesSheet(store: store)
                        case .legality:       LegalityReportSheet(store: store)
                        case .deckManagement: DeckManagementSheet(store: store, cards: cardStore.displayCards)
                        }
                    }
                    .alert("Clear deck?", isPresented: $confirmingClearDeck) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear deck", role: .destructive) {
                            store.clearDeck()
                            store.discardDraft()
                        }
                    } message: {
                        Text("Removes every Hero, Play, Bonus Play, and Hot Dog. Your deck name and rule overrides stay.")
                    }
                }
                .navigationTransition(.zoom(sourceID: "deck-draft", in: deckZoomNamespace))
            }
        }
        // .walkthroughOverlay MUST sit OUTSIDE NavigationStack so its
        // GeometryReader measures the full screen, not the inner
        // content. When attached inside the NavigationStack the host
        // sized to a single card cell (147×68) and every step's
        // anchor came back as off-screen.
        .walkthroughOverlay($walkthrough) { stage in
            handleWalkthroughStage(stage)
        }
        .onAppear(perform: handleAppear)
        .onDisappear { store.saveDraft() }
        .onChange(of: scanStore.pendingScannedCardsForActiveDeck.count) { _, count in
            guard count > 0 else { return }
            let cards = scanStore.pendingScannedCardsForActiveDeck
            scanStore.pendingScannedCardsForActiveDeck = []
            ingestScannedCards(cards)
        }
    }

    // MARK: - Toolbar

    /// DecksView toolbar (the card-pool tab) — wordmark + scan
    /// shortcut + walkthrough relaunch. Save / Manage Decks / Rules /
    /// Legality / Clear all moved into the editor's toolbar where
    /// they're contextually correct. Pool only needs to look up cards
    /// and start a scan.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            BOBAWordmark()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Columns") {
                    Picker("Columns", selection: $gridColumns) {
                        Label("1 across", systemImage: "rectangle.portrait").tag(1)
                        Label("2 across", systemImage: "rectangle.split.2x1").tag(2)
                        Label("3 across", systemImage: "rectangle.split.3x1").tag(3)
                    }
                }
                Section {
                    Button {
                        presentScanner()
                    } label: {
                        Label("Scan into deck", systemImage: "camera.viewfinder")
                    }
                }
                Divider()
                Button {
                    WalkthroughsManager.shared.relaunch(.decksTab)
                    walkthrough = .decksTab
                } label: {
                    Label("Show walkthrough", systemImage: "questionmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.bobaCyan)
            }
            .accessibilityLabel("Pool options")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { searchFocused = false }
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
        }
    }

    /// Editor toolbar — appears inside the full-screen cover. Close
    /// (X) leading + Save trailing + overflow Menu with the deck-
    /// management actions.
    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                editorOpen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Close editor")
        }
        ToolbarItem(placement: .principal) {
            BOBAWordmark()
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: Design.Spacing.sm) {
                Button {
                    if auth.isAuthenticated {
                        Task { await saveDeck() }
                    } else {
                        secondarySheet = .profile
                    }
                } label: {
                    Text(auth.isAuthenticated ? "SAVE" : "SIGN IN")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(saveButtonForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(saveButtonBackground))
                }
                .buttonStyle(.plain)
                .disabled((auth.isAuthenticated && deckIsEmpty) || store.isSaving)
                .walkthroughAnchor("decks.saveButton")
                .accessibilityLabel(auth.isAuthenticated ? "Save deck" : "Sign in to save")

                Menu {
                    Button {
                        editorPath.append(EditorRoute.deckManagement)
                    } label: {
                        Label("Manage Decks", systemImage: "tray.full")
                    }
                    Button {
                        editorPath.append(EditorRoute.rules)
                    } label: {
                        Label(store.ruleOverrides.hasAnyUserOverride ? "Custom rules…" : "Rules…",
                              systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        editorPath.append(EditorRoute.legality)
                    } label: {
                        Label("Legality audit", systemImage: "checkmark.seal")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingClearDeck = true
                    } label: {
                        Label("Clear deck", systemImage: "trash")
                    }
                    .disabled(deckIsEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                .accessibilityLabel("Deck options")
            }
        }
    }

    /// Save button is enabled when:
    ///   - signed in + non-empty deck → "SAVE" (orange)
    ///   - signed out → "SIGN IN" (cyan, always enabled)
    /// Disabled state is signed-in + empty deck (orange dimmed).
    private var saveButtonForeground: Color {
        if !auth.isAuthenticated { return Design.Colors.nearBlack }
        return deckIsEmpty ? Design.Colors.textMuted : Design.Colors.nearBlack
    }
    private var saveButtonBackground: Color {
        if !auth.isAuthenticated { return Design.Colors.bobaCyan }
        return deckIsEmpty ? Design.Colors.glass : Design.Colors.bobaOrange
    }

    // MARK: - Card pool canvas

    @ViewBuilder
    private var cardPoolCanvas: some View {
        let filtered = filteredPoolCards
        if filtered.isEmpty {
            poolEmptyState
        } else {
            ScrollView {
                // Tiny breathing room so the first row of cards isn't hard
                // against the .searchable bar.
                Color.clear.frame(height: Design.Spacing.xs)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Design.Spacing.sm),
                                   count: max(1, min(3, gridColumns))),
                    spacing: Design.Spacing.md
                ) {
                    ForEach(Array(filtered.prefix(200).enumerated()), id: \.element.id) { idx, card in
                        BOBACardGridItem(card: card, columnCount: gridColumns)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                poolNavigationPath.append(card)
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.35)
                                    .onEnded { _ in
                                        addCardToDeck(card)
                                    }
                            )
                            .modifier(FirstCellAnchor(isFirst: idx == 0))
                            // matchedTransitionSource MUST be the LAST
                            // (outermost) modifier so iOS sees it on
                            // the visible, rendered cell — not on an
                            // inner view that gets wrapped by gesture
                            // containers. Otherwise iOS can't find the
                            // source and prints the "nil view will
                            // trigger a fallback transition" warning,
                            // which is what produces the forehead.
                            .matchedTransitionSource(id: card.id, in: poolZoomNamespace)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.md)

                // Bottom inset so cards aren't covered by the .height(120)
                // sheet at minimum detent. ~140pt = sheet height + buffer.
                Color.clear.frame(height: 140)

                if filtered.count > 200 {
                    Text("\(filtered.count - 200) more — refine search")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(.bottom, 160)
                }
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
    }

    private var poolEmptyState: some View {
        BOBAEmptyState(
            title: "No cards match",
            systemImage: "rectangle.stack.badge.minus",
            message: "Try clearing the search or your collection-only filter."
        ) {
            Button {
                search = ""
                collectionOnly = false
            } label: {
                Text("Clear filters")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Capsule().fill(Design.Colors.bobaOrange))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 160)  // breathing room above the bottom sheet
    }

    // MARK: - Banner overlay (transient confirmations)

    @ViewBuilder
    private var addedBannerOverlay: some View {
        if let msg = addedBanner ?? saveBanner {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "4CAF50"))
                Text(msg)
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))
            .padding(.top, Design.Spacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel(msg)
        }
    }

    /// Always-visible header — deck name + per-section counts +
    /// format badge + legality pill. (Search lives ABOVE the canvas,
    /// not in this header — see `poolSearchBar`.)
    private var sheetHeaderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Design.Spacing.sm) {
                TextField("Deck name", text: $store.deckName)
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .submitLabel(.done)
                    .textFieldStyle(.plain)
                Spacer()
                if !deckIsEmpty {
                    legalityPill
                }
            }
            // Stat row — Heroes / Plays / Bonus / Hot Dogs / DBS budget.
            // The DBS budget cell is the most important number for
            // building a legitimate deck (per CLAUDE.md), so it shows
            // alongside the other counts whenever the active format
            // enforces a DBS budget.
            HStack(spacing: Design.Spacing.md) {
                statCount(label: "Heroes", value: store.heroes.count, target: store.format.heroTarget)
                if store.format.needsPlaybook {
                    statCount(label: "Plays", value: store.plays.count, target: 30)
                    if !store.bonusPlays.isEmpty {
                        statCount(label: "Bonus", value: store.bonusPlays.count, target: nil)
                    }
                    if store.effectiveEnforceDBS {
                        dbsCount(value: store.totalDBS, budget: store.effectiveDBSBudget)
                    }
                }
                if store.format.needsHotDogs {
                    statCount(label: "Hot Dogs", value: store.hotDogs.count, target: 10)
                }
                Spacer()
                Text(store.format.displayName)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(Design.Colors.bobaOrange.opacity(0.15)))
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .padding(.bottom, Design.Spacing.sm)
    }

    private func statCount(label: String, value: Int, target: Int?) -> some View {
        let ok = target.map { value == $0 } ?? true
        return HStack(spacing: 4) {
            Text(label)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
            if let target {
                Text("\(value)/\(target)")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(ok ? Color(hex: "4CAF50") : Design.Colors.textPrimary)
            } else {
                Text("\(value)")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        }
    }

    /// DBS budget tracker. Same shape as statCount but tinted by the
    /// over/under state — green when on budget, orange near the cap,
    /// red when over. This is the number coaches build around.
    private func dbsCount(value: Int, budget: Int) -> some View {
        let color: Color = {
            if value > budget { return Color(hex: "C0392B") }
            if value > Int(Double(budget) * 0.9) { return Design.Colors.bobaOrange }
            return Color(hex: "4CAF50")
        }()
        return HStack(spacing: 4) {
            Text("DBS")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
            Text("\(value)/\(budget)")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var legalityPill: some View {
        let isLegal = store.validationErrors.isEmpty && !deckIsEmpty
        return Text(isLegal ? "LEGAL" : "ILLEGAL")
            .font(Design.Fonts.mono(11, weight: .bold))
            .foregroundStyle(isLegal ? Color(hex: "4CAF50") : Color(hex: "C0392B"))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill((isLegal ? Color(hex: "4CAF50") : Color(hex: "C0392B")).opacity(0.15)))
    }

    /// Format picker — single persistent strip per §8.3 (replaces the
    /// 5-row pile-up). Lives inside the .medium detent at the top.
    private var formatChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.xs) {
                ForEach(DeckFormat.allCases) { fmt in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { store.format = fmt }
                    } label: {
                        Text(fmt.displayName)
                            .font(Design.Fonts.mono(11, weight: store.format == fmt ? .bold : .regular))
                            .foregroundStyle(store.format == fmt ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(store.format == fmt ? Design.Colors.bobaOrange : Design.Colors.glass))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
    }

    // MARK: - Deck list (scrolling content of the sheet)

    @ViewBuilder
    private var deckListScroll: some View {
        // Vertical-only ScrollView. The .frame(maxWidth: .infinity)
        // on the inner VStack stops SwiftUI from proposing a wider
        // width when a child (e.g., a long DeckCardRow ability text)
        // briefly demands more horizontal space — without it the
        // ScrollView starts allowing horizontal rubber-banding even
        // though we never asked for a horizontal axis.
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if !auth.isAuthenticated && !deckIsEmpty {
                    BOBASignInPrompt(
                        actionDescription: "save this deck and access it on every device",
                        onSignIn: { secondarySheet = .profile }
                    )
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                }

                // Collection-only toggle — the single survivor of the legacy
                // 5-filter-row stack. Hidden when the user isn't signed in.
                if auth.isAuthenticated {
                    HStack {
                        Toggle(isOn: $collectionOnly) {
                            Text("Show only cards I own")
                                .font(Design.Fonts.mono(12))
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .toggleStyle(.switch)
                        .tint(Design.Colors.bobaCyan)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                }

                if deckIsEmpty {
                    emptyDeckCTA
                } else {
                    if !visibleValidationErrors.isEmpty {
                        validationSection
                    }
                    if !store.heroes.isEmpty {
                        DeckSection(
                            title: "HEROES (\(store.heroes.count)/\(store.format.heroTarget))",
                            isEmpty: false
                        ) {
                            // Cross-tier hero repeat banner — flags the
                            // "6-per-hero across variations" rule. Silent
                            // when no hero is repeated, so it stays out of
                            // the way during normal deck building.
                            // (Restored from legacy DeckBuilderView.)
                            if !heroRepeats.isEmpty {
                                heroRepeatBanner
                            }
                            ForEach(groupedHeroes, id: \.power) { group in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("PWR \(group.power)")
                                            .font(Design.Fonts.mono(10, weight: .bold))
                                            .foregroundStyle(Design.Colors.textMuted)
                                        Text("(\(group.cards.count)/6)")
                                            .font(Design.Fonts.mono(10))
                                            .foregroundStyle(group.cards.count > 6 ? Color(hex: "C0392B") : Design.Colors.textMuted)
                                        Spacer()
                                    }
                                    // Hero × weapon breakdown — restores the
                                    // legacy "Maverick (FIRE×2, ICE)" line so
                                    // coaches can see weapon spread per tier.
                                    let breakdown = heroWeaponBreakdown(for: group.cards)
                                    if !breakdown.isEmpty {
                                        Text(breakdown)
                                            .font(Design.Fonts.mono(9))
                                            .foregroundStyle(Design.Colors.textMuted)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.horizontal, Design.Spacing.md)
                                .padding(.top, Design.Spacing.xs)
                                ForEach(group.cards) { card in
                                    DeckCardRow(card: card) {
                                        store.removeCard(card, role: .hero)
                                    }
                                }
                            }
                        }
                    }
                    if store.format.needsPlaybook {
                        if !store.plays.isEmpty {
                            DeckSection(
                                title: "PLAYS (\(store.plays.count)/30)",
                                isEmpty: false
                            ) {
                                ForEach(store.plays) { card in
                                    DeckCardRow(card: card) {
                                        store.removeCard(card, role: .play)
                                    }
                                }
                            }
                        }
                        if !store.bonusPlays.isEmpty {
                            // Hint surfaces above the soft ceiling Brad calls out
                            // in the deck-builder transcript ([00:23:31]).
                            if store.bonusPlays.count >= 7 {
                                HintBanner(
                                    id: .bonusPlayCeiling,
                                    title: "TIP — BONUS PLAY CEILING",
                                    message: "More than 6 bonus plays dilutes your Playbook. Consider trimming back."
                                )
                                .padding(.horizontal, Design.Spacing.md)
                            }
                            DeckSection(
                                title: "BONUS PLAYS (\(store.bonusPlays.count))",
                                isEmpty: false
                            ) {
                                ForEach(store.bonusPlays) { card in
                                    DeckCardRow(card: card) {
                                        store.removeCard(card, role: .bonusPlay)
                                    }
                                }
                            }
                        }
                    }
                    if store.format.needsHotDogs && !store.hotDogs.isEmpty {
                        DeckSection(
                            title: "HOT DOGS (\(store.hotDogs.count)/10)",
                            isEmpty: false
                        ) {
                            ForEach(store.hotDogs) { card in
                                DeckCardRow(card: card) {
                                    store.removeCard(card, role: .hotDog)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, Design.Spacing.lg)
            // Pin the inner column to the ScrollView's full width so
            // children can't propose a wider intrinsic size and trigger
            // horizontal rubber-banding (per
            // memory/feedback_swiftui_scrollview_width.md).
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Per user feedback — color each starter deck by its archetype's
    /// dominant weapon so the cards visually telegraph their gameplan.
    private func templateAccent(for templateId: String) -> Color {
        switch templateId {
        case "lockdown-locker": return Design.Colors.element("STEEL")
        case "frozen-tempo":    return Design.Colors.element("ICE")
        case "draw-and-adapt":  return Design.Colors.bobaCyan         // engine — generic cyan accent
        case "glow-sacrifice":  return Design.Colors.element("GLOW")
        case "brawl-beatdown":  return Design.Colors.element("BRAWL")
        default:                return Design.Colors.bobaCyan
        }
    }

    /// Empty-deck state with template gallery as inline actions per §8.3
    /// ("ContentUnavailableView with template gallery as actions").
    private var emptyDeckCTA: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            BOBAEmptyState(
                title: "Build your first deck",
                systemImage: "rectangle.stack.badge.plus",
                message: "Tap any card from the pool above to start. Or pick a template below."
            ) {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                BOBASectionHeader("START FROM A TEMPLATE")
                    .padding(.horizontal, Design.Spacing.md)
                ForEach(DeckTemplate.all) { template in
                    let accent = templateAccent(for: template.id)
                    Button {
                        store.loadTemplate(template, allCards: cardStore.displayCards)
                    } label: {
                        HStack(alignment: .top, spacing: Design.Spacing.md) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(accent)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(Design.Fonts.display(15))
                                    .foregroundStyle(Design.Colors.textPrimary)
                                Text(template.description)
                                    .font(Design.Fonts.mono(11))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                        .padding(Design.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Design.Radius.md)
                                .fill(accent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.md)
                                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Design.Spacing.md)
                }
            }
        }
        .padding(.top, Design.Spacing.lg)
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleValidationErrors) { err in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.bobaOrange)
                    Text(err.message)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.bobaOrange.opacity(0.08))
    }

    // MARK: - Filtering + sorting

    private var filteredPoolCards: [Card] {
        let q = search.lowercased()
        // Pre-compute owned ids once per filter pass.
        let ownedBobaIds: Set<String> = collectionOnly
            ? Set(collection.userCards.filter { $0.designation.isOwned }.compactMap { $0.bobaId })
            : []
        let ownedNumbers: Set<String> = collectionOnly
            ? Set(collection.userCards.filter { $0.designation.isOwned && $0.bobaId == nil }.map { $0.cardNumber })
            : []
        // Group tokens by type so multi-weapon (FIRE OR ICE) is
        // an OR, but weapon + cost is an AND. Same pattern as
        // SearchView's filter precedence.
        let weaponTokens = tokens.compactMap { token -> String? in
            if case .weapon(let e) = token { return e } else { return nil }
        }
        let costTokens = tokens.compactMap { token -> Int? in
            if case .cost(let c) = token { return c } else { return nil }
        }
        let heroTokens = tokens.compactMap { token -> String? in
            if case .hero(let h) = token { return h.lowercased() } else { return nil }
        }

        let cards = cardStore.displayCards.filter { card in
            // Catalog covers Heroes / Plays / HotDogs / Sealed Products.
            // Sealed are explicitly out — the deck builder builds player decks.
            guard card.cardType != "Sealed Product" else { return false }

            // Per user feedback #4 — hide cards that aren't legal for
            // the current format instead of dimming them. The pool now
            // only shows additions the coach can actually make.
            guard isFormatEligibleForDeck(card) else { return false }

            if collectionOnly,
               !ownedBobaIds.contains(card.id),
               !ownedNumbers.contains(card.cardNumber) {
                return false
            }
            // Token filters (OR within type, AND across types) — §6.4.
            if !weaponTokens.isEmpty, !weaponTokens.contains(card.element) {
                return false
            }
            if !costTokens.isEmpty {
                guard let cost = card.playCost, costTokens.contains(cost) else { return false }
            }
            if !heroTokens.isEmpty, !heroTokens.contains(card.hero.lowercased()) {
                return false
            }
            // Free-text search — runs after token filters. Adds two
            // synonyms the user expects (#3): "free" → cost-0 plays,
            // and treatment-name match (e.g. "battlefoil", "blizzard").
            if !q.isEmpty {
                let h = card.hero.lowercased().contains(q)
                let n = card.name.lowercased().contains(q)
                let c = card.cardNumber.lowercased().contains(q)
                let e = card.element.lowercased().contains(q)
                let t = (card.treatment ?? "").lowercased().contains(q)
                let isFree = (q == "free") && (card.playCost == 0)
                guard h || n || c || e || t || isFree else { return false }
            }
            return true
        }
        return cards.sorted { a, b in
            let ai = !(a.imageFile ?? "").isEmpty
            let bi = !(b.imageFile ?? "").isEmpty
            if ai != bi { return ai }
            // Heroes by power desc, Plays by cost asc — same convention as legacy.
            if a.cardType == "Hero" && b.cardType == "Hero" {
                return (a.power ?? 0) > (b.power ?? 0)
            }
            if a.cardType == "Play" && b.cardType == "Play" {
                return (a.playCost ?? 0) < (b.playCost ?? 0)
            }
            return a.cardType < b.cardType
        }
    }

    /// Per user feedback #4 — hide cards that can't legally be in the
    /// active deck format (Spec heroes > 160 power, etc.) instead of
    /// dimming. Mirrors DeckBuilderStore's heroWouldViolate checks but
    /// excludes the "already in deck / dup" predicates so the pool
    /// shows what's CATEGORICALLY eligible, not what's addable right
    /// now (the long-press add gesture handles dup-check internally).
    private func isFormatEligibleForDeck(_ card: Card) -> Bool {
        let fmt = store.format

        // Banned card types (e.g. Trainer in Elite).
        if fmt.bannedCardTypes.contains(card.cardType) { return false }

        // Hero-specific eligibility.
        if card.cardType == "Hero" {
            guard let power = card.power else { return false }
            // Per-hero power cap (Spec: 160). SPEC+ allows specific
            // tiered powers above 160 (165, 170, 175...).
            if let cap = fmt.heroPowerCap, power > cap {
                if fmt == .specPlus, fmt.specPlusTieredLimits[power] != nil {
                    // Allowed in a tiered slot.
                } else {
                    return false
                }
            }
            // Absolute ceiling (SPEC+: 200).
            if let absMax = fmt.absoluteHeroPowerMax, power > absMax {
                return false
            }
        }
        return true
    }

    /// Suggested tokens for the .searchable suggestions list. Default
    /// shows every weapon + the canonical cost steps (0/1/2/3 HD); when
    /// the user types text, also surfaces matching hero names.
    private var suggestedTokens: [BOBAFilterToken] {
        var out: [BOBAFilterToken] = BOBAFilterToken.weapons + BOBAFilterToken.costs
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        if q.count >= 2 {
            // De-dup heroes that match the query, ranked by hero
            // frequency. Cap at 5 suggestions so the list doesn't
            // dominate the keyboard.
            var heroCounts: [String: Int] = [:]
            for card in cardStore.displayCards where card.cardType == "Hero" {
                if card.hero.lowercased().contains(q) {
                    heroCounts[card.hero, default: 0] += 1
                }
            }
            let topHeroes = heroCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
            out.append(contentsOf: topHeroes.map { BOBAFilterToken.hero($0) })
        }
        return out
    }

    private var groupedHeroes: [(power: Int, cards: [Card])] {
        let groups = Dictionary(grouping: store.heroes) { $0.power ?? 0 }
        return groups.map { (power: $0.key, cards: $0.value) }.sorted { $0.power > $1.power }
    }

    /// One-line "Hero (FIRE×2, ICE)" breakdown for a single power tier.
    /// Restored from the legacy DeckBuilderView so coaches still see
    /// weapon spread per tier in the new Maps-pattern Decks view.
    private func heroWeaponBreakdown(for cards: [Card]) -> String {
        var byHero: [String: [String: Int]] = [:]
        for c in cards {
            let hero = c.hero.isEmpty ? c.name : c.hero
            byHero[hero, default: [:]][c.element, default: 0] += 1
        }
        let elementOrder = ["FIRE","ICE","STEEL","BRAWL","GLOW","HEX","GUM","SUPER","CYBER","ALT","NONE"]
        let sortedHeroes = byHero.keys.sorted { a, b in
            let aTotal = byHero[a]!.values.reduce(0, +)
            let bTotal = byHero[b]!.values.reduce(0, +)
            if aTotal != bTotal { return aTotal > bTotal }
            return a.localizedCompare(b) == .orderedAscending
        }
        return sortedHeroes.map { hero -> String in
            let weapons = byHero[hero]!.sorted { a, b in
                let ai = elementOrder.firstIndex(of: a.key) ?? 99
                let bi = elementOrder.firstIndex(of: b.key) ?? 99
                return ai < bi
            }
            let weaponFrag = weapons.map { "\($0.key)\($0.value > 1 ? "×\($0.value)" : "")" }.joined(separator: ", ")
            return "\(hero) (\(weaponFrag))"
        }.joined(separator: " · ")
    }

    /// Heroes appearing more than once across the full Hero Deck (counting
    /// all variations). The 6-per-hero rule caps this at 6; the banner
    /// shows current counts so coaches spot crowding early.
    private var heroRepeats: [(hero: String, count: Int, weapons: [String])] {
        var byHero: [String: [Card]] = [:]
        for c in store.heroes {
            let key = c.hero.isEmpty ? c.name : c.hero
            byHero[key, default: []].append(c)
        }
        let elementOrder = ["FIRE","ICE","STEEL","BRAWL","GLOW","HEX","GUM","SUPER","CYBER","ALT","NONE"]
        var rows: [(hero: String, count: Int, weapons: [String])] = []
        for (hero, cards) in byHero {
            guard cards.count > 1 else { continue }
            var weapons: [String: Int] = [:]
            for c in cards { weapons[c.element, default: 0] += 1 }
            let sorted = weapons.sorted { a, b in
                let ai = elementOrder.firstIndex(of: a.key) ?? 99
                let bi = elementOrder.firstIndex(of: b.key) ?? 99
                return ai < bi
            }
            let frag = sorted.map { "\($0.key)\($0.value > 1 ? "×\($0.value)" : "")" }
            rows.append((hero: hero, count: cards.count, weapons: frag))
        }
        rows.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.hero < rhs.hero
        }
        return rows
    }

    /// Restored from legacy DeckBuilderView. Cyan-tinted block above
    /// the HEROES section flagging when any hero name appears more than
    /// once. Red text when count > 6 (the per-hero cap). Hidden when
    /// no hero is repeated.
    private var heroRepeatBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HERO REPEATS · 6 per hero max across variations")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1)
            ForEach(heroRepeats, id: \.hero) { row in
                HStack(spacing: 4) {
                    Text(row.hero)
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(row.count > 6 ? Color(hex: "C0392B") : Design.Colors.textPrimary)
                    Text("(\(row.count)/6)")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(row.count > 6 ? Color(hex: "C0392B") : Design.Colors.textMuted)
                    Text(row.weapons.joined(separator: ", "))
                        .font(Design.Fonts.mono(9))
                        .foregroundStyle(Design.Colors.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.bobaCyan.opacity(0.06))
    }

    /// Validation errors surfaced in the deck panel's warning bubble.
    /// "Need X more {hero|play|hot dog}" rows are dropped because the
    /// header already shows X/N for each role.
    private var visibleValidationErrors: [DeckValidationError] {
        store.validationErrors.filter { !$0.message.hasPrefix("Need ") }
    }

    private var deckIsEmpty: Bool {
        store.heroes.isEmpty
            && store.plays.isEmpty
            && store.bonusPlays.isEmpty
            && store.hotDogs.isEmpty
    }

    private func pickRoleForCard(_ card: Card) -> DeckCardRole {
        if card.isHero { return .hero }
        if card.isHotDog { return .hotDog }
        if card.isBonusPlay == true { return .bonusPlay }
        return .play
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        // Auto-restore any in-progress draft.
        if deckIsEmpty {
            _ = store.restoreDraft(allCards: cardStore.displayCards)
        }
        // Walkthrough on first visit.
        if WalkthroughsManager.shared.shouldShow(.decksTab) {
            walkthrough = .decksTab
        }
    }

    // MARK: - Actions

    private func saveDeck() async {
        guard auth.isAuthenticated, !deckIsEmpty else { return }
        await store.saveDeck()
        if store.saveError == nil {
            saveBanner = "Saved \(store.deckName)"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.3)) { saveBanner = nil }
            }
        }
    }

    private func presentScanner() {
        scanCoordinator.start(
            .deck(label: store.deckName, savedDecks: store.savedDecks),
            scanStore: scanStore
        )
    }

    /// Long-press handler — adds the card to the current deck via
    /// the store's role-aware addCard, fires haptic feedback, and
    /// surfaces a transient "Added X" banner. Skips invisible
    /// rule-violating cards (the format-eligibility filter already
    /// hides them from the pool, but the dup check happens here).
    private func addCardToDeck(_ card: Card) {
        let role = pickRoleForCard(card)
        let beforeCount = countForRole(role)
        store.addCard(card, role: role)
        let afterCount = countForRole(role)
        // Only show feedback if the card was actually added (the
        // store silently skips dupes / cap violations).
        guard afterCount > beforeCount else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let label = card.hero.isEmpty ? card.name : card.hero
        withAnimation(.easeOut(duration: 0.25)) {
            addedBanner = "Added \(label)"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { addedBanner = nil }
        }
    }

    private func countForRole(_ role: DeckCardRole) -> Int {
        switch role {
        case .hero:      return store.heroes.count
        case .play:      return store.plays.count
        case .bonusPlay: return store.bonusPlays.count
        case .hotDog:    return store.hotDogs.count
        case .sideboard: return store.sideboard.count
        }
    }

    private func ingestScannedCards(_ cards: [Card]) {
        guard !cards.isEmpty else { return }
        for card in cards {
            store.addCard(card, role: pickRoleForCard(card))
        }
        let msg = cards.count == 1
            ? "Added \(cards[0].name) to your deck"
            : "Added \(cards.count) cards to your deck"
        withAnimation(.easeOut(duration: 0.25)) { addedBanner = msg }
        popSheetIfNeeded()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { addedBanner = nil }
        }
    }

    private func popSheetIfNeeded() {
        // No-op — drawer state is user-controlled via drag/tap. Kept
        // as a hook for future "auto-open deck panel after scan."
    }

    /// Walkthrough host hook — `decksDrawerExpanded` now opens the
    /// full-screen editor so the format chip and other deck-builder
    /// surfaces are visible during the walkthrough. Closes on
    /// stage=nil so the user lands back on the card pool.
    private func handleWalkthroughStage(_ stage: BOBAWalkthrough.Stage?) {
        switch stage {
        case .decksDrawerExpanded:
            editorOpen = true
        case nil:
            editorOpen = false
        }
    }
}

// MARK: - Helpers

/// Anchors only the FIRST grid cell as the walkthrough target so the
/// spotlight ring lands on a single cell rather than the whole grid.
private struct FirstCellAnchor: ViewModifier {
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst {
            content.walkthroughAnchor("decks.cardPool")
        } else {
            content
        }
    }
}

// MARK: - DeckSummaryPill

/// Bottom-anchored summary chip — Music's "now playing" pattern
/// applied to the deck-builder. Shows the active draft (deck name
/// + count + format badge) and zooms into the full-screen editor
/// on tap. Replaces the v2.038 custom drawer entirely; no drag, no
/// detents, no flash.
///
/// The `namespace` is the @Namespace owned by DecksView — pairing
/// `matchedTransitionSource(id: "deck-draft", in: ns)` here with
/// `.navigationTransition(.zoom(sourceID: "deck-draft", in: ns))`
/// on the cover gives the Photos-app-style hero zoom.
private struct DeckSummaryPill: View {
    let store: DeckBuilderStore
    let onTap: () -> Void
    let namespace: Namespace.ID

    private var totalCards: Int {
        store.heroes.count + store.plays.count + store.bonusPlays.count + store.hotDogs.count
    }

    private var hasDraft: Bool {
        totalCards > 0 || store.deckName != "New Deck"
    }

    /// Compact section breakdown — shows what's actually in the deck so a
    /// coach can read it at a glance without opening the editor:
    /// "8/8 H · 30/30 P · 6 BP · 10/10 HD". Sections that don't apply to
    /// the current format are omitted.
    private var sectionBreakdown: String {
        var parts: [String] = []
        let heroTarget = store.format.heroTarget
        parts.append("\(store.heroes.count)/\(heroTarget) H")
        if store.format.needsPlaybook {
            parts.append("\(store.plays.count)/30 P")
            if store.bonusPlays.count > 0 {
                parts.append("\(store.bonusPlays.count) BP")
            }
        }
        if store.format.needsHotDogs {
            parts.append("\(store.hotDogs.count)/10 HD")
        }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: hasDraft ? "rectangle.stack.fill" : "rectangle.stack.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hasDraft ? Design.Colors.bobaOrange : Design.Colors.textSecondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    if hasDraft {
                        Text(store.deckName)
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(1)
                        Text(sectionBreakdown)
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else {
                        Text("Build a deck")
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("Tap to open the editor")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                Spacer(minLength: 4)
                if hasDraft {
                    Text(store.format.displayName)
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(Design.Colors.bobaOrange.opacity(0.15)))
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: -2)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "deck-draft", in: namespace)
        .accessibilityLabel(hasDraft ? "Open deck editor — \(store.deckName), \(totalCards) cards" : "Open deck editor")
    }
}
