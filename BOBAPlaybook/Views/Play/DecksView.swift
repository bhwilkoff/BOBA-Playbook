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

    /// Persistent bottom sheet — flipped on .onAppear and never dismissed
    /// (interactiveDismissDisabled). Detents are .height(120) + .medium
    /// only — .large would cover the navigation toolbar AND tab bar,
    /// making it impossible to leave the Decks tab without an awkward
    /// drag-down gesture. .medium gives ample room to inspect the deck
    /// list while keeping every chrome element reachable.
    @State private var showDeckSheet     = false
    @State private var sheetDetent       : PresentationDetent = .height(120)

    // Pool filters
    @State private var search            = ""
    @State private var tokens            : [BOBAFilterToken] = []
    @State private var collectionOnly    = false
    /// Per user feedback: defaults to TAP=VIEW (false) so coaches can
    /// explore a card by tapping. Toggle on in the search-bar pill to
    /// switch to one-tap deck adding when batch-building. Persisted so
    /// power users who prefer Quick Add stay in that mode across launches.
    @AppStorage("bp_deckPoolQuickAdd_v1") private var quickAdd: Bool = false
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
        NavigationStack {
            ZStack(alignment: .top) {
                cardPoolCanvas
                addedBannerOverlay
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
            .searchable(
                text: $search,
                tokens: $tokens,
                suggestedTokens: .constant(suggestedTokens),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search · weapon, cost, or hero"
            ) { token in
                Label(token.label, systemImage: token.systemImageName)
            }
            .onSubmit(of: .search) { searchFocused = false }
            // Single persistent bottom sheet — never dismissed. Detents
            // exclude .large so the nav toolbar + tab bar stay visible
            // regardless of sheet state (fixes the "no way to exit
            // Decks" + "Profile button unreliable" bugs).
            .sheet(isPresented: $showDeckSheet) {
                deckSheetContent
                    .presentationDetents(
                        [.height(120), .medium],
                        selection: $sheetDetent
                    )
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationContentInteraction(.scrolls)
                    .presentationCornerRadius(28)
                    .interactiveDismissDisabled(true)
                    .presentationDragIndicator(.visible)
            }
            // Single secondary-sheet host attached to the parent (NOT
            // to the bottom sheet's content). Stacks above the bottom
            // sheet without state propagation issues.
            .sheet(item: $secondarySheet) { sheet in
                switch sheet {
                case .profile:        ProfileView()
                case .rules:          DeckRulesSheet(store: store)
                case .legality:       LegalityReportSheet(store: store)
                case .deckManagement: DeckManagementSheet(store: store, cards: cardStore.displayCards)
                }
            }
            // Card-detail (long-press in pool) — independent of the bottom sheet.
            // Lives at the parent level so dismissal returns to the canvas.
            .sheet(item: $selectedBrowserCard) { card in
                BrowserCardDetailSheet(card: card, store: store, tab: pickRoleForCard(card))
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
            .walkthroughOverlay($walkthrough)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { secondarySheet = .profile } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.bobaCyan)
            }
            .accessibilityLabel("Profile")
        }
        ToolbarItem(placement: .principal) {
            BOBAWordmark()
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: Design.Spacing.sm) {
                // Save — primary action, tinted glass per §5.4.
                Button {
                    Task { await saveDeck() }
                } label: {
                    Text("SAVE")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(saveButtonForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(saveButtonBackground)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!auth.isAuthenticated || deckIsEmpty || store.isSaving)
                .walkthroughAnchor("decks.saveButton")
                .accessibilityLabel("Save deck")

                // Overflow menu — collapses every secondary destination
                // per §8.3 ("Save / Templates / Import / Export / Delete /
                // Duplicate / Rules") and adds Scan + Walkthrough.
                Menu {
                    // Tap behavior — restores the legacy DeckBuilderView's
                    // explicit choice between "Tap to view" (default) and
                    // "Tap to add". Long-press always opens detail in
                    // either mode.
                    Picker("Card tap action", selection: $quickAdd) {
                        Label("Tap to view", systemImage: "eye.fill").tag(false)
                        Label("Tap to add",  systemImage: "plus.circle.fill").tag(true)
                    }

                    Button {
                        secondarySheet = .deckManagement
                    } label: {
                        Label("Saved decks · Templates · Import / Export", systemImage: "tray.full")
                    }
                    Button {
                        secondarySheet = .rules
                    } label: {
                        Label(store.ruleOverrides.hasAnyUserOverride ? "Custom rules…" : "Rules…",
                              systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        secondarySheet = .legality
                    } label: {
                        Label("Legality audit", systemImage: "checkmark.seal")
                    }
                    Divider()
                    Button {
                        presentScanner()
                    } label: {
                        Label("Scan into deck", systemImage: "camera.viewfinder")
                    }
                    Divider()
                    Button {
                        WalkthroughsManager.shared.relaunch(.decksTab)
                        walkthrough = .decksTab
                    } label: {
                        Label("Show walkthrough", systemImage: "questionmark.circle")
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
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { searchFocused = false }
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
        }
    }

    private var saveButtonForeground: Color {
        (auth.isAuthenticated && !deckIsEmpty) ? Design.Colors.nearBlack : Design.Colors.textMuted
    }
    private var saveButtonBackground: Color {
        (auth.isAuthenticated && !deckIsEmpty) ? Design.Colors.bobaOrange : Design.Colors.glass
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
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: Design.Spacing.sm)],
                    spacing: Design.Spacing.md
                ) {
                    ForEach(Array(filtered.prefix(200).enumerated()), id: \.element.id) { idx, card in
                        BrowserCardCell(
                            card: card,
                            store: store,
                            quickAdd: quickAdd
                        ) { tappedCard in
                            // BrowserCardCell calls onSelect when quickAdd
                            // is OFF — open the card detail sheet for
                            // exploration. When quickAdd is ON, the cell
                            // adds directly and onSelect is unused.
                            selectedBrowserCard = tappedCard
                        }
                        // Long-press always opens detail (works in either
                        // mode), so coaches can dig into a card mid-batch
                        // without flipping the toggle.
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in selectedBrowserCard = card }
                        )
                        .modifier(FirstCellAnchor(isFirst: idx == 0))
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

    // MARK: - Bottom sheet content

    @ViewBuilder
    private var deckSheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeaderRow
                .walkthroughAnchor("decks.sheetHandle")

            // .medium and .large get the format chip strip + the deck list.
            if sheetDetent != .height(120) {
                Divider().background(Design.Colors.glass)
                formatChipStrip
                    .walkthroughAnchor("decks.formatChip")
                Divider().background(Design.Colors.glass)
                deckListScroll
            }
        }
        // No .background — let iOS 26 apply Liquid Glass automatically (§3.10).
        // Secondary sheets are hosted at the parent view via $secondarySheet
        // so a single .sheet(item:) handles all four destinations reliably.
    }

    /// Always-visible header at .height(120) — deck name + per-section counts +
    /// format badge + legality pill.
    private var sheetHeaderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Design.Spacing.sm) {
                TextField("Deck name", text: $store.deckName)
                    .font(Design.Fonts.display(18))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .submitLabel(.done)
                    .textFieldStyle(.plain)
                Spacer()
                if !deckIsEmpty {
                    legalityPill
                }
            }
            HStack(spacing: Design.Spacing.md) {
                statCount(label: "Heroes", value: store.heroes.count, target: store.format.heroTarget)
                if store.format.needsPlaybook {
                    statCount(label: "Plays", value: store.plays.count, target: 30)
                    if !store.bonusPlays.isEmpty {
                        statCount(label: "Bonus", value: store.bonusPlays.count, target: nil)
                    }
                }
                if store.format.needsHotDogs {
                    statCount(label: "Hot Dogs", value: store.hotDogs.count, target: 10)
                }
                Spacer()
                Text(store.format.displayName)
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Design.Colors.bobaOrange.opacity(0.15)))
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .padding(.bottom, Design.Spacing.sm)
    }

    private func statCount(label: String, value: Int, target: Int?) -> some View {
        let ok = target.map { value == $0 } ?? true
        return HStack(spacing: 3) {
            Text(label)
                .font(Design.Fonts.mono(9))
                .foregroundStyle(Design.Colors.textMuted)
            if let target {
                Text("\(value)/\(target)")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(ok ? Color(hex: "4CAF50") : Design.Colors.textPrimary)
            } else {
                Text("\(value)")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        }
    }

    private var legalityPill: some View {
        let isLegal = store.validationErrors.isEmpty && !deckIsEmpty
        return Text(isLegal ? "LEGAL" : "ILLEGAL")
            .font(Design.Fonts.mono(9, weight: .bold))
            .foregroundStyle(isLegal ? Color(hex: "4CAF50") : Color(hex: "C0392B"))
            .padding(.horizontal, 8)
            .frame(height: 20)
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
        ScrollView {
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
                    Button {
                        store.loadTemplate(template, allCards: cardStore.displayCards)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            sheetDetent = .medium
                        }
                    } label: {
                        HStack(alignment: .top, spacing: Design.Spacing.md) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Design.Colors.bobaCyan)
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
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.md)
                                .strokeBorder(Design.Colors.glass, lineWidth: 1)
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
            // Free-text search — runs after token filters.
            if !q.isEmpty {
                let h = card.hero.lowercased().contains(q)
                let n = card.name.lowercased().contains(q)
                let c = card.cardNumber.lowercased().contains(q)
                let e = card.element.lowercased().contains(q)
                guard h || n || c || e else { return false }
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
        // Always present the bottom sheet.
        if !showDeckSheet { showDeckSheet = true }
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
        // After adding, pop the sheet up a notch so the user sees the deck
        // change. Only nudges from the smallest detent — never collapses
        // a user who's already inspecting the deck list.
        guard sheetDetent == .height(120) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            sheetDetent = .medium
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
