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

    @State private var store = DeckBuilderStore()

    // MARK: - Sheet + UI state

    /// Persistent bottom sheet — flipped on .onAppear and never dismissed
    /// (interactiveDismissDisabled). Detent selection drives which sheet
    /// content blocks render.
    @State private var showDeckSheet     = false
    @State private var sheetDetent       : PresentationDetent = .height(120)

    // Pool filters
    @State private var search            = ""
    @State private var collectionOnly    = false
    @FocusState private var searchFocused: Bool

    // Secondary sheets — all attached inside the deck-sheet content so they
    // stack above it without dismissing it (per §3.4).
    @State private var showProfile           = false
    @State private var showRulesSheet        = false
    @State private var showLegalityReport    = false
    @State private var showDeckManagement    = false
    @State private var selectedBrowserCard   : Card? = nil

    // Scan + alerts + transient feedback
    @State private var showScan              = false
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
            .searchable(
                text: $search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search the catalog"
            )
            .onSubmit(of: .search) { searchFocused = false }
            // Single persistent bottom sheet — never dismissed.
            .sheet(isPresented: $showDeckSheet) {
                deckSheetContent
                    .presentationDetents(
                        [.height(120), .medium, .large],
                        selection: $sheetDetent
                    )
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationContentInteraction(.scrolls)
                    .presentationCornerRadius(28)
                    .interactiveDismissDisabled(true)
                    .presentationDragIndicator(.visible)
            }
            // Card-detail (long-press in pool) — independent of the bottom sheet.
            // Lives at the parent level so dismissal returns to the canvas.
            .sheet(item: $selectedBrowserCard) { card in
                BrowserCardDetailSheet(card: card, store: store, tab: pickRoleForCard(card))
            }
            // Scan — fullScreenCover is independent of any sheet.
            .fullScreenCover(isPresented: $showScan, onDismiss: {
                scanStore.endDeckBuilderSession()
            }) {
                ZStack(alignment: .topLeading) {
                    ScanView()
                    Button {
                        showScan = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .padding(Design.Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close scanner")
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
            .overlay {
                if let script = walkthrough {
                    BOBAWalkthrough(script: script) {
                        WalkthroughsManager.shared.dismiss(script.id)
                        walkthrough = nil
                    }
                }
            }
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
            Button { showProfile = true } label: {
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
                    Button {
                        showDeckManagement = true
                    } label: {
                        Label("Saved decks · Templates · Import / Export", systemImage: "tray.full")
                    }
                    Button {
                        showRulesSheet = true
                    } label: {
                        Label(store.ruleOverrides.hasAnyUserOverride ? "Custom rules…" : "Rules…",
                              systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        showLegalityReport = true
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
                            quickAdd: true                  // pool is "tap to add" per §8.3
                        ) { tappedCard in
                            // Path is unused (quickAdd=true short-circuits).
                            selectedBrowserCard = tappedCard
                        }
                        // Long-press → detail sheet. Tap → add (handled inside
                        // BrowserCardCell via store.addCard when quickAdd).
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in selectedBrowserCard = card }
                        )
                        // Anchor the first cell as the walkthrough target
                        // for "Tap any card to add it to your deck."
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
        // Layered sheets attach here so they stack above the bottom sheet
        // without dismissing it (per §3.4).
        .sheet(isPresented: $showProfile)        { ProfileView() }
        .sheet(isPresented: $showRulesSheet)     { DeckRulesSheet(store: store) }
        .sheet(isPresented: $showLegalityReport) { LegalityReportSheet(store: store) }
        .sheet(isPresented: $showDeckManagement) {
            DeckManagementSheet(store: store, cards: cardStore.displayCards)
        }
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
                        onSignIn: { showProfile = true }
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
                            ForEach(groupedHeroes, id: \.power) { group in
                                HStack {
                                    Text("PWR \(group.power)")
                                        .font(Design.Fonts.mono(10, weight: .bold))
                                        .foregroundStyle(Design.Colors.textMuted)
                                    Spacer()
                                    Text("\(group.cards.count)")
                                        .font(Design.Fonts.mono(10))
                                        .foregroundStyle(Design.Colors.textMuted)
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

        let cards = cardStore.displayCards.filter { card in
            // Catalog covers Heroes / Plays / HotDogs / Sealed Products.
            // Sealed are explicitly out — the deck builder builds player decks.
            guard card.cardType != "Sealed Product" else { return false }

            if collectionOnly,
               !ownedBobaIds.contains(card.id),
               !ownedNumbers.contains(card.cardNumber) {
                return false
            }
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

    private var groupedHeroes: [(power: Int, cards: [Card])] {
        let groups = Dictionary(grouping: store.heroes) { $0.power ?? 0 }
        return groups.map { (power: $0.key, cards: $0.value) }.sorted { $0.power > $1.power }
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
        let targets = store.savedDecks.map { ScanStore.DeckTarget(id: $0.id, name: $0.name) }
        scanStore.beginDeckBuilderSession(
            currentDeckLabel: store.deckName,
            availableSavedDecks: targets
        )
        showScan = true
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
