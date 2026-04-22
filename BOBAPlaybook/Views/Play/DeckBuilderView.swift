//
//  DeckBuilderView.swift
//  BOBAPlaybook
//
//  Full deck construction UI. Format selector, card browser, deck sections,
//  real-time validation, and Supabase save for authenticated users.
//

import SwiftUI

// ════════════════════════════════════════════════════════════════
// MARK: - DeckBuilderView
// ════════════════════════════════════════════════════════════════

struct DeckBuilderView: View {
    /// Optional card to add to the deck as soon as the builder opens —
    /// lets the "Add to Custom Deck" flow from CardDetailView seed the
    /// deck builder with the card the coach tapped.
    let pendingCard: Card?

    @Environment(CardStore.self) private var cardStore
    @State private var store = DeckBuilderStore()
    @State private var showTemplates = true
    @State private var showDeckManagement = false
    @State private var showDeckList = false
    @State private var showRulesSheet = false
    @AppStorage("bp_deckBuilderTutorialSeen_v1") private var deckTutorialSeen = false
    @State private var showDeckTutorial = false
    @State private var pendingCardAddedBanner: String?

    init(pendingCard: Card? = nil) {
        self.pendingCard = pendingCard
    }
    @State private var quickAdd = false
    @State private var selectedBrowserCard: Card? = nil
    @State private var elementFilter = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Format picker + Stats bar
                HStack {
                    formatPicker
                        .deckBuilderTutorialTarget(.formatPicker)
                    Spacer()
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .background(Design.Colors.surface)

                // Stats bar
                statsBar

                // Main content
                if showTemplates && store.heroes.isEmpty && store.plays.isEmpty {
                    templateGallery
                } else {
                    HSplitOrVStack {
                        cardBrowser.deckBuilderTutorialTarget(.browser)
                        deckPanel.deckBuilderTutorialTarget(.deckList)
                    }
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDeckManagement = true
                    } label: {
                        Image(systemName: "line.3.horizontal.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    .deckBuilderTutorialTarget(.deckMenu)
                }
                ToolbarItem(placement: .principal) {
                    Text("DECK BUILDER")
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Design.Spacing.md) {
                        Button {
                            showRulesSheet = true
                        } label: {
                            Image(systemName: store.ruleOverrides.hasAnyUserOverride
                                  ? "list.bullet.rectangle.fill"
                                  : "list.bullet.rectangle")
                                .font(.system(size: 18))
                                .foregroundStyle(store.ruleOverrides.hasAnyUserOverride
                                                 ? Design.Colors.bobaOrange
                                                 : Design.Colors.bobaCyan)
                        }
                        .accessibilityLabel("Deck rules")
                        .deckBuilderTutorialTarget(.rulesButton)
                        Button("Done") { dismiss() }
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .overlayPreferenceValue(DeckBuilderAnchorKey.self) { anchors in
            if showDeckTutorial {
                GeometryReader { proxy in
                    let frames: [DeckBuilderTutorialTarget: CGRect] = anchors.reduce(into: [:]) { acc, pair in
                        acc[pair.key] = proxy[pair.value]
                    }
                    DeckBuilderTutorialOverlay(
                        targetFrames: frames,
                        containerSize: proxy.size
                    ) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            deckTutorialSeen = true
                            showDeckTutorial = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showDeckManagement) {
            DeckManagementSheet(store: store, cards: cardStore.displayCards)
        }
        .sheet(isPresented: $showRulesSheet) {
            DeckRulesSheet(store: store)
        }
        .sheet(item: $selectedBrowserCard) { card in
            BrowserCardDetailSheet(card: card, store: store, tab: store.browserTab)
        }
        .onAppear {
            // Auto-restore any in-progress deck. Silently loads the last draft
            // so coaches can wander off (answer a call, check a card detail,
            // etc.) and return without losing their work.
            if store.heroes.isEmpty && store.plays.isEmpty && store.hotDogs.isEmpty {
                let restored = store.restoreDraft(allCards: cardStore.displayCards)
                if restored { showTemplates = false }
            }
            // "Add to Custom Deck" flow from CardDetailView: drop the tapped
            // card into its appropriate role so the coach lands in the builder
            // with their card already in the deck.
            if let card = pendingCard {
                let role: DeckCardRole = card.isHero ? .hero
                                      : card.isHotDog ? .hotDog
                                      : (card.isBonusPlay == true ? .bonusPlay : .play)
                store.addCard(card, role: role)
                showTemplates = false
                withAnimation(.easeOut(duration: 0.25)) {
                    pendingCardAddedBanner = "Added \(card.name) to your deck"
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeOut(duration: 0.3)) {
                        pendingCardAddedBanner = nil
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let msg = pendingCardAddedBanner {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "4CAF50"))
                    Text(msg)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "4CAF50").opacity(0.4), lineWidth: 1))
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Fire the walkthrough AFTER the template splash dismisses — otherwise
        // steps for the card browser + deck list have no anchors yet.
        .onChange(of: showTemplates) { _, newValue in
            if !newValue && !deckTutorialSeen {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    showDeckTutorial = true
                }
            }
        }
        .onDisappear {
            // Snapshot on the way out. No-op for empty decks.
            store.saveDraft()
        }
    }

    // MARK: - Format Picker

    private var formatPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.xs) {
                ForEach(DeckFormat.allCases) { fmt in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { store.format = fmt }
                    } label: {
                        Text(fmt.rawValue)
                            .font(Design.Fonts.mono(12, weight: store.format == fmt ? .bold : .regular))
                            .foregroundStyle(store.format == fmt ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                            .padding(.horizontal, Design.Spacing.md)
                            .frame(height: 30)
                            .background(Capsule().fill(store.format == fmt ? Design.Colors.bobaOrange : Design.Colors.glass))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.lg) {
                statChip(label: "HEROES", value: "\(store.heroes.count)/\(store.format.heroTarget)",
                         ok: store.isHeroSectionComplete)
                if let min = store.heroPowerMin, let max = store.heroPowerMax {
                    statChip(label: "POWER", value: "\(min)–\(max)", ok: true)
                }
                if store.format.needsPlaybook {
                    statChip(label: "PLAYS", value: "\(store.plays.count)/30",
                             ok: store.plays.count == 30)
                    if !store.bonusPlays.isEmpty {
                        statChip(label: "BONUS", value: "+\(store.bonusPlays.count)", ok: true)
                    }
                    if store.effectiveEnforceDBS {
                        statChip(
                            label: "DBS",
                            value: "\(store.totalDBS)/\(store.effectiveDBSBudget)",
                            ok: store.totalDBS <= store.effectiveDBSBudget
                        )
                    }
                }
                if store.format.needsHotDogs {
                    statChip(label: "HOT DOGS", value: "\(store.hotDogs.count)/10",
                             ok: store.hotDogs.count == 10)
                }
                // Legality badge
                if store.validationErrors.isEmpty && store.heroes.count > 0 {
                    Text("LEGAL")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .padding(.horizontal, Design.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "4CAF50").opacity(0.15)))
                } else if !store.heroes.isEmpty {
                    Text("ILLEGAL")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Color(hex: "C0392B"))
                        .padding(.horizontal, Design.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "C0392B").opacity(0.15)))
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.sm)
        }
        .background(Design.Colors.surface.opacity(0.6))
    }

    private func statChip(label: String, value: String, ok: Bool) -> some View {
        VStack(spacing: 1) {
            Text(label).font(Design.Fonts.mono(9)).foregroundStyle(Design.Colors.textMuted)
            Text(value).font(Design.Fonts.display(15)).foregroundStyle(ok ? Design.Colors.textPrimary : Design.Colors.bobaOrange)
        }
    }

    // MARK: - Template Gallery (initial state)

    private var templateGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                Text("Choose a starting point")
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .padding(.top, Design.Spacing.lg)

                // Build Custom Deck — top of the splash so coaches see it first
                Button {
                    store.clearDeck()
                    store.discardDraft()
                    showTemplates = false
                } label: {
                    HStack(spacing: Design.Spacing.md) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Design.Colors.nearBlack)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build Custom Deck")
                                .font(Design.Fonts.display(16))
                                .foregroundStyle(Design.Colors.nearBlack)
                            Text("Start from an empty deck and pick your own cards")
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.nearBlack.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Design.Colors.nearBlack.opacity(0.7))
                    }
                    .padding(Design.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaOrange))
                }
                .buttonStyle(.plain)

                Text("OR START FROM A TEMPLATE")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(.top, Design.Spacing.md)

                ForEach(DeckTemplate.all) { template in
                    TemplateCard(template: template) {
                        store.loadTemplate(template, allCards: cardStore.displayCards)
                        showTemplates = false
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xl)
        }
    }

    // MARK: - Card Browser

    private var cardBrowser: some View {
        VStack(spacing: 0) {
            // Browser tab pills + Quick-Add toggle
            HStack {
                browserTabPicker
                Spacer()
                Button {
                    quickAdd.toggle()
                    elementFilter = ""
                } label: {
                    Label(quickAdd ? "Quick Add" : "Tap to View", systemImage: quickAdd ? "plus.circle.fill" : "eye.fill")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(quickAdd ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Capsule().fill(quickAdd ? Design.Colors.bobaOrange.opacity(0.15) : Design.Colors.glass))
                }
                .buttonStyle(.plain)
                .padding(.trailing, Design.Spacing.sm)
            }
            .padding(.vertical, Design.Spacing.xs)
            .background(Design.Colors.surface)

            // Element filter pills (heroes only)
            if store.browserTab == .hero {
                elementFilterPills
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                    .background(Design.Colors.surface)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Design.Colors.textMuted).font(.system(size: 14))
                TextField("Search cards...", text: $store.browserSearch)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .autocorrectionDisabled()
                if !store.browserSearch.isEmpty {
                    Button { store.browserSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Design.Colors.textMuted)
                    }
                }
            }
            .padding(Design.Spacing.sm)
            .background(Design.Colors.glass)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)

            // Card grid
            let filtered = filteredCards
            if filtered.isEmpty {
                ContentUnavailableView("No cards found", systemImage: "rectangle.stack", description: Text("Try a different search or filter"))
                    .foregroundStyle(Design.Colors.textMuted)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: Design.Spacing.sm)],
                              spacing: Design.Spacing.md) {
                        ForEach(filtered.prefix(200)) { card in
                            BrowserCardCell(card: card, store: store, quickAdd: quickAdd) { tappedCard in
                                selectedBrowserCard = tappedCard
                            }
                        }
                    }
                    .padding(Design.Spacing.md)
                    if filtered.count > 200 {
                        Text("\(filtered.count - 200) more — refine search")
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                            .padding(.bottom, Design.Spacing.lg)
                    }
                }
            }
        }
    }

    // MARK: - Element Filter Pills

    private var elementFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.xs) {
                elementPill("ALL", element: nil)
                ForEach(["FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER"], id: \.self) { el in
                    elementPill(el, element: el)
                }
            }
        }
    }

    private func elementPill(_ label: String, element: String?) -> some View {
        let isSelected = (element == nil && elementFilter.isEmpty) || element == elementFilter
        return Button {
            elementFilter = element ?? ""
        } label: {
            Text(label)
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(isSelected
                    ? (element == nil ? Design.Colors.textPrimary : Design.Colors.element(element!))
                    : Design.Colors.textMuted)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(isSelected
                    ? (element == nil ? Design.Colors.glass : Design.Colors.element(element!).opacity(0.18))
                    : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected
                    ? (element == nil ? Design.Colors.glass : Design.Colors.element(element!).opacity(0.4))
                    : Design.Colors.glass.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var browserTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.xs) {
                browserTabButton(.hero, label: "Heroes")
                if store.format.needsPlaybook {
                    browserTabButton(.play, label: "Plays")
                    browserTabButton(.bonusPlay, label: "Bonus")
                }
                if store.format.needsHotDogs {
                    browserTabButton(.hotDog, label: "Hot Dogs")
                }
            }
            .padding(.horizontal, Design.Spacing.sm)
        }
    }

    private func browserTabButton(_ tab: DeckCardRole, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { store.browserTab = tab }
        } label: {
            Text(label)
                .font(Design.Fonts.mono(12, weight: store.browserTab == tab ? .bold : .regular))
                .foregroundStyle(store.browserTab == tab ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                .padding(.horizontal, Design.Spacing.sm)
                .frame(height: 28)
                .background(Capsule().fill(store.browserTab == tab ? Design.Colors.bobaCyan : Design.Colors.glass))
        }
        .buttonStyle(.plain)
    }

    private var filteredCards: [Card] {
        let query = store.browserSearch.lowercased()
        let cards = cardStore.displayCards.filter { card in
            // Card type filter
            switch store.browserTab {
            case .hero:
                guard card.cardType == "Hero" && (card.power ?? 0) > 0 else { return false }
                if !elementFilter.isEmpty && card.element != elementFilter { return false }
            case .play:
                guard card.cardType == "Play" && card.cardNumber.hasPrefix("BPL") == false
                    && card.treatment != "Bonus Plays" else { return false }
            case .bonusPlay:
                guard card.cardType == "Play" &&
                    (card.cardNumber.hasPrefix("BPL") || card.treatment == "Bonus Plays") else { return false }
            case .hotDog:
                guard card.cardType == "HotDog" || (card.cardType == "Hero" && (card.treatment?.contains("Hot Dog") == true || card.treatment?.contains("Hotdog") == true)) else { return false }
            case .sideboard:
                guard card.cardType == "Play" else { return false }
            }
            // Search
            if !query.isEmpty {
                let matchesHero = card.hero.lowercased().contains(query)
                let matchesName = card.name.lowercased().contains(query)
                let matchesNum  = card.cardNumber.lowercased().contains(query)
                guard matchesHero || matchesName || matchesNum else { return false }
            }
            return true
        }
        // Sort: cards with images first, then by power/cost
        switch store.browserTab {
        case .hero:
            return cards.sorted { a, b in
                let aHasImg = !(a.imageFile ?? "").isEmpty
                let bHasImg = !(b.imageFile ?? "").isEmpty
                if aHasImg != bHasImg { return aHasImg }
                return (a.power ?? 0) > (b.power ?? 0)
            }
        case .play, .bonusPlay, .sideboard:
            return cards.sorted { a, b in
                let aHasImg = !(a.imageFile ?? "").isEmpty
                let bHasImg = !(b.imageFile ?? "").isEmpty
                if aHasImg != bHasImg { return aHasImg }
                return (a.playCost ?? 0) < (b.playCost ?? 0)
            }
        default:
            return cards.sorted { a, b in
                let aHasImg = !(a.imageFile ?? "").isEmpty
                let bHasImg = !(b.imageFile ?? "").isEmpty
                return aHasImg && !bHasImg
            }
        }
    }

    // MARK: - Deck Panel

    private var deckPanel: some View {
        VStack(spacing: 0) {
            // Deck header — always visible
            VStack(spacing: 2) {
                // Section label + collapsible toggle — makes deck name row context explicit
                HStack {
                    Text("CURRENT CARDS")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                    Spacer()
                    // Card count summary when collapsed — written with words so
                    // "0 Heroes · 0 Plays" doesn't read as "OH OP" at a glance.
                    if !showDeckList {
                        Text("\(store.heroes.count) Heroes")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                        if store.format.needsPlaybook {
                            Text("·")
                                .font(Design.Fonts.mono(10))
                                .foregroundStyle(Design.Colors.textMuted)
                            Text("\(store.plays.count) Plays")
                                .font(Design.Fonts.mono(10))
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showDeckList.toggle() }
                    } label: {
                        Image(systemName: showDeckList ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // Deck name row with a pencil indicator so it's clearly editable
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.textMuted)
                    TextField("Deck name", text: $store.deckName)
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Design.Colors.glass.opacity(0.3)))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .background(Design.Colors.surface)
            .overlay(Divider().background(Design.Colors.glass), alignment: .top)

            // Expandable deck contents
            if showDeckList {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Validation errors
                        if !store.validationErrors.isEmpty {
                            validationSection
                        }
                        // Hero Deck section
                        DeckSection(title: "HERO DECK (\(store.heroes.count)/\(store.format.heroTarget))",
                                    isEmpty: store.heroes.isEmpty) {
                            ForEach(groupedHeroes, id: \.power) { group in
                                HStack {
                                    Text("PWR \(group.power)")
                                        .font(Design.Fonts.mono(10, weight: .bold))
                                        .foregroundStyle(Design.Colors.textMuted)
                                    Text("(\(group.cards.count)/6)")
                                        .font(Design.Fonts.mono(10))
                                        .foregroundStyle(group.cards.count > 6 ? Color(hex: "C0392B") : Design.Colors.textMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, Design.Spacing.md)
                                .padding(.top, Design.Spacing.xs)
                                ForEach(group.cards) { card in
                                    DeckCardRow(card: card) { store.removeCard(card, role: .hero) }
                                }
                            }
                        }
                        // Playbook
                        if store.format.needsPlaybook {
                            DeckSection(title: "PLAYS (\(store.plays.count)/30)", isEmpty: store.plays.isEmpty) {
                                ForEach(store.plays) { card in
                                    DeckCardRow(card: card) { store.removeCard(card, role: .play) }
                                }
                            }
                            if !store.bonusPlays.isEmpty {
                                DeckSection(title: "BONUS PLAYS (\(store.bonusPlays.count))", isEmpty: false) {
                                    ForEach(store.bonusPlays) { card in
                                        DeckCardRow(card: card) { store.removeCard(card, role: .bonusPlay) }
                                    }
                                }
                            }
                        }
                        // Hot Dogs
                        if store.format.needsHotDogs {
                            DeckSection(title: "HOT DOGS (\(store.hotDogs.count)/10)", isEmpty: store.hotDogs.isEmpty) {
                                ForEach(store.hotDogs) { card in
                                    DeckCardRow(card: card) { store.removeCard(card, role: .hotDog) }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 200)
            }
        }
        .background(Design.Colors.surface.opacity(0.5))
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.validationErrors) { err in
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

    private var groupedHeroes: [(power: Int, cards: [Card])] {
        let groups = Dictionary(grouping: store.heroes) { $0.power ?? 0 }
        return groups.map { (power: $0.key, cards: $0.value) }.sorted { $0.power > $1.power }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Browser Card Cell
// ════════════════════════════════════════════════════════════════

private struct BrowserCardCell: View {
    let card: Card
    let store: DeckBuilderStore
    let quickAdd: Bool
    let onSelect: (Card) -> Void
    @State private var pressed = false

    private var inDeck: Bool { store.isInDeck(card) }
    private var wouldViolate: Bool {
        store.browserTab == .hero && store.heroWouldViolate(card)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Card image
                Group {
                    if let file = card.imageFile, !file.isEmpty {
                        CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass)
                            .overlay(Text(String((card.hero.isEmpty ? card.name : card.hero).prefix(2)).uppercased())
                                .font(Design.Fonts.display(20))
                                .foregroundStyle(Design.Colors.element(card.element)))
                    }
                }
                .frame(width: 90, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: inDeck ? 2.5 : 1.5)
                )
                .overlay(
                    wouldViolate ? RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.5)) : nil
                )

                // Checkmark badge if already in deck
                if inDeck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .background(Circle().fill(Design.Colors.nearBlack).padding(2))
                        .padding(4)
                }

                // Quick-add "+" badge when in quick-add mode and not in deck
                if quickAdd && !inDeck && !wouldViolate {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .background(Circle().fill(Design.Colors.nearBlack).padding(2))
                        .padding(4)
                }
            }

            // Card name
            Text(card.hero.isEmpty ? card.name : card.hero)
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)

            // Power or play cost
            if card.cardType == "Hero", let power = card.power {
                HStack(spacing: 3) {
                    Text(card.element).font(Design.Fonts.mono(8, weight: .bold))
                        .foregroundStyle(Design.Colors.element(card.element))
                    Text("·").font(Design.Fonts.mono(8)).foregroundStyle(Design.Colors.textMuted)
                    Text("\(power)").font(Design.Fonts.display(16)).foregroundStyle(Design.Colors.textPrimary)
                }
            } else if let cost = card.playCost {
                Text(cost == 0 ? "FREE" : "\(cost) HD")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
            }
        }
        .frame(width: 90)
        .opacity(wouldViolate ? 0.5 : 1)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.easeInOut(duration: 0.1), value: pressed)
        .onTapGesture {
            guard !wouldViolate else { return }
            // Brief press feedback
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pressed = false }
            if quickAdd {
                store.addCard(card, role: store.browserTab)
            } else {
                onSelect(card)
            }
        }
    }

    private var borderColor: Color {
        if inDeck { return Design.Colors.bobaCyan }
        if wouldViolate { return Color(hex: "C0392B").opacity(0.6) }
        return Design.Colors.element(card.element).opacity(0.4)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Deck Section
// ════════════════════════════════════════════════════════════════

private struct DeckSection<Content: View>: View {
    let title: String
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content
    @State private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .background(Design.Colors.glass.opacity(0.3))
            }
            .buttonStyle(.plain)

            Divider().background(Design.Colors.glass)

            if !collapsed {
                if isEmpty {
                    Text("Empty — add cards from the browser")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(Design.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    content()
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Deck Card Row
// ════════════════════════════════════════════════════════════════

private struct DeckCardRow: View {
    let card: Card
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            // Small thumb
            Group {
                if let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Design.Colors.glass)
                }
            }
            .frame(width: 32, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                if card.cardType == "Hero" {
                    HStack(spacing: 4) {
                        Text(card.element)
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.element(card.element))
                        Text(card.treatment ?? "Base")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(1)
                    }
                } else if let ability = card.playAbility {
                    Text(ability)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let power = card.power, card.cardType == "Hero" {
                Text("\(power)")
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .frame(minWidth: 40, alignment: .trailing)
            } else if let cost = card.playCost {
                VStack(spacing: 1) {
                    Text(cost == 0 ? "FREE" : "\(cost)")
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                    if cost > 0 {
                        Text("HD").font(Design.Fonts.mono(8)).foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .frame(minWidth: 32, alignment: .trailing)
            }

            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Template Card
// ════════════════════════════════════════════════════════════════

private struct TemplateCard: View {
    let template: DeckTemplate
    let onSelect: () -> Void

    private var accentColor: Color {
        switch template.id {
        case "fire-aggro":        return Design.Colors.element("FIRE")
        case "ice-control":       return Design.Colors.element("ICE")
        case "steel-wall":        return Design.Colors.element("STEEL")
        case "mixed-toolbox":     return Design.Colors.bobaCyan
        case "economy-attrition": return Color(hex: "4CAF50")
        default:                  return Design.Colors.bobaOrange
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Design.Spacing.md) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(accentColor.opacity(0.5), lineWidth: 1.5))
                    .frame(width: 44, height: 60)
                    .overlay(Text(String(template.name.prefix(1)))
                        .font(Design.Fonts.display(28))
                        .foregroundStyle(accentColor))

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text(template.description)
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(2)
                    Text(template.format.rawValue.uppercased())
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .padding(Design.Spacing.md)
            .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accentColor.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Unified Deck Management Sheet
// ════════════════════════════════════════════════════════════════

private struct DeckManagementSheet: View {
    let store: DeckBuilderStore
    let cards: [Card]
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case save = "Save", load = "Load", share = "Import/Export" }
    @State private var tab: Tab = .load

    // My Decks state
    @State private var decks: [SavedDeck] = []
    @State private var isLoadingList = true
    @State private var loadError: String? = nil
    @State private var isLoadingDeck = false
    @State private var isSaving = false
    @State private var saveMessage: String? = nil

    // Export state
    @State private var copied = false
    @State private var showImportPicker = false
    @State private var importBanner: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(Design.Spacing.md)

                // Tab content
                switch tab {
                case .save:  saveTab
                case .load:  loadTab
                case .share: shareTab
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("MANAGE DECKS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Save Tab

    private var saveTab: some View {
        VStack(spacing: Design.Spacing.lg) {
            Spacer()
            if store.heroes.isEmpty && store.plays.isEmpty {
                ContentUnavailableView("No deck to save", systemImage: "tray", description: Text("Add cards to your deck first"))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: Design.Spacing.md) {
                    VStack(spacing: 6) {
                        Text("DECK NAME")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                        TextField("Untitled", text: Binding(
                            get: { store.deckName },
                            set: { store.deckName = $0 }
                        ))
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Design.Colors.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                        .padding(.horizontal, Design.Spacing.xl)
                    }

                    Text("\(store.heroes.count) Heroes · \(store.plays.count) Plays")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)

                    Button {
                        Task { await saveDeck() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "icloud.and.arrow.up")
                            }
                            Text(saveMessage ?? "Save to Cloud")
                                .font(Design.Fonts.mono(14, weight: .bold))
                        }
                        .foregroundStyle(saveMessage == "Saved!" ? Color(hex: "4CAF50") : Design.Colors.nearBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(
                            saveMessage == "Saved!" ? Color(hex: "4CAF50") : Design.Colors.bobaOrange))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Design.Spacing.xl)
                }
            }
            Spacer()
        }
    }

    // MARK: - Load Tab

    private var loadTab: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.lg) {
                // Saved Custom Decks section (top — coaches see their own work first)
                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    Text("SAVED CUSTOM DECKS")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(.horizontal, Design.Spacing.lg)

                    if isLoadingList {
                        ProgressView("Loading saved decks…")
                            .tint(Design.Colors.bobaCyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Design.Spacing.xl)
                    } else if let err = loadError {
                        Text(err)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                            .padding(.horizontal, Design.Spacing.lg)
                    } else if decks.isEmpty {
                        Text("No saved decks yet")
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                            .padding(.horizontal, Design.Spacing.lg)
                            .padding(.vertical, Design.Spacing.md)
                    } else {
                        // Row-as-tap pattern: SwiftUI's List + Button can swallow taps when
                        // `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` are in play.
                        // Use an explicit tap gesture with contentShape so the whole row is
                        // the hit target. Swipe-to-delete still works.
                        List {
                            ForEach(decks) { deck in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(deck.name)
                                            .font(Design.Fonts.display(16))
                                            .foregroundStyle(Design.Colors.textPrimary)
                                        Text(deck.format.uppercased())
                                            .font(Design.Fonts.mono(11))
                                            .foregroundStyle(Design.Colors.textMuted)
                                    }
                                    Spacer()
                                    if isLoadingDeck {
                                        ProgressView().tint(Design.Colors.bobaCyan)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Design.Colors.textMuted)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isLoadingDeck else { return }
                                    Task { await loadDeck(deck) }
                                }
                                .listRowBackground(Design.Colors.surface)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await deleteDeck(deck) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: CGFloat(decks.count) * 60)
                        .padding(.horizontal, Design.Spacing.sm)
                    }
                }

                // Build Custom Deck — prominent, primary action
                Button {
                    store.clearDeck()
                    store.discardDraft()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Design.Colors.nearBlack)
                        Text("Build Custom Deck")
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.nearBlack)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaOrange))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Design.Spacing.lg)

                Divider().background(Design.Colors.glass).padding(.horizontal, Design.Spacing.lg)

                // Starter Decks section (below — pre-built templates)
                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    Text("STARTER DECKS")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(.horizontal, Design.Spacing.lg)

                    ForEach(DeckTemplate.all) { template in
                        TemplateCard(template: template) {
                            store.loadTemplate(template, allCards: cards)
                            dismiss()
                        }
                        .padding(.horizontal, Design.Spacing.lg)
                    }
                }
            }
            .padding(.vertical, Design.Spacing.md)
        }
        .task { await fetchDecks() }
    }

    // MARK: - Share Tab — CSV import/export (matches deck-builder.bobattlearena.com)

    private var shareTab: some View {
        VStack(spacing: 0) {
            // Action toolbar
            HStack(spacing: Design.Spacing.sm) {
                Button {
                    UIPasteboard.general.string = store.deckListCSV
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy CSV", systemImage: "doc.on.doc")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(copied ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                }
                Spacer()
                ShareLink(item: csvExportURL(), preview: SharePreview(csvExportFilename())) {
                    Label("Export .csv", systemImage: "square.and.arrow.up")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                Button {
                    showImportPicker = true
                } label: {
                    Label("Import .csv", systemImage: "square.and.arrow.down")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .padding(Design.Spacing.md)

            if let banner = importBanner {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "4CAF50"))
                    Text(banner)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.sm)
            }

            Text("CSV format matches the official deckbuilder at deck-builder.bobattlearena.com. Playbook + Bonus Plays only — heroes + hot dogs stay in the builder.")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Design.Colors.textMuted)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.sm)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(Design.Colors.glass)

            ScrollView {
                Text(store.deckListCSV)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.lg)
                    .textSelection(.enabled)
            }
        }
        .fileImporter(isPresented: $showImportPicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let csv = String(data: data, encoding: .utf8) else {
                    importBanner = "Couldn't read file"
                    return
                }
                let res = store.importDeckCSV(csv, allCards: cards)
                var msg = "Imported \(res.plays) plays + \(res.bonus) bonus"
                if !res.unresolved.isEmpty {
                    msg += " · \(res.unresolved.count) unresolved"
                }
                importBanner = msg
                Task { try? await Task.sleep(nanoseconds: 3_500_000_000); importBanner = nil }
            case .failure(let err):
                importBanner = "Import failed: \(err.localizedDescription)"
            }
        }
    }

    private func csvExportFilename() -> String {
        let safeName = store.deckName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "boba-deck-\(safeName).csv"
    }

    private func csvExportURL() -> URL {
        let csv = store.deckListCSV
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(csvExportFilename())
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Actions

    private func fetchDecks() async {
        do {
            decks = try await SupabaseClient.shared.fetchDecks()
        } catch {
            loadError = "Couldn't load decks"
        }
        isLoadingList = false
    }

    @MainActor
    private func saveDeck() async {
        guard !store.heroes.isEmpty else { return }
        isSaving = true
        saveMessage = nil
        defer { isSaving = false }
        do {
            try await SupabaseClient.shared.saveDeck(store)
            saveMessage = "Saved!"
            // Refresh the list
            await fetchDecks()
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); saveMessage = nil }
        } catch {
            saveMessage = "Failed"
        }
    }

    private func deleteDeck(_ deck: SavedDeck) async {
        do {
            try await SupabaseClient.shared.deleteDeck(deckId: deck.id)
            decks.removeAll { $0.id == deck.id }
            // If we just deleted the currently loaded deck, clear the reference
            if store.currentDeckId == deck.id {
                store.currentDeckId = nil
            }
        } catch {
            // Silently fail — deck stays in list
        }
    }

    private func loadDeck(_ deck: SavedDeck) async {
        isLoadingDeck = true
        defer { isLoadingDeck = false }
        do {
            let rows = try await SupabaseClient.shared.fetchDeckCards(deckId: deck.id)
            let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
            // Apply to the store
            store.clearDeck()
            store.deckName = deck.name
            store.currentDeckId = deck.id
            // Format comes back as a Supabase slug — resolve to a DeckFormat case
            if let f = DeckFormat.allCases.first(where: { $0.supabaseValue == deck.format }) {
                store.format = f
            }
            var loaded = 0
            for row in rows {
                guard let card = byId[row.bobaId] else { continue }
                let role: DeckCardRole = switch row.cardType {
                    case "hero":       .hero
                    case "play":       .play
                    case "bonus_play": .bonusPlay
                    case "hot_dog":    .hotDog
                    case "sideboard":  .sideboard
                    default:           .hero
                }
                store.addCard(card, role: role)
                loaded += 1
            }
            print("[DeckBuilder] loaded \(loaded)/\(rows.count) cards for deck '\(deck.name)'")
            // Give SwiftUI a tick to settle state before dismissing, so the parent
            // deck builder sees the updated store when the sheet closes.
            await Task.yield()
            dismiss()
        } catch {
            print("[DeckBuilder] loadDeck failed: \(error)")
            saveMessage = "Couldn't load deck"
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Browser Card Detail Sheet
// ════════════════════════════════════════════════════════════════

private struct BrowserCardDetailSheet: View {
    let card: Card
    let store: DeckBuilderStore
    let tab: DeckCardRole
    @Environment(\.dismiss) private var dismiss

    private var inDeck: Bool { store.isInDeck(card) }
    private var wouldViolate: Bool { tab == .hero && store.heroWouldViolate(card) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    // Full card image
                    Group {
                        if let file = card.imageFile, !file.isEmpty {
                            CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fit)
                                .aspectRatio(3.0/4.0, contentMode: .fit)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Design.Colors.glass)
                                .aspectRatio(3.0/4.0, contentMode: .fit)
                                .overlay(Text(card.hero.isEmpty ? card.name : card.hero)
                                    .font(Design.Fonts.display(24))
                                    .foregroundStyle(Design.Colors.element(card.element)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Design.Colors.element(card.element).opacity(0.4), radius: 16, y: 6)
                    .padding(.horizontal, Design.Spacing.xl)

                    // Stats
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        HStack {
                            Text(card.hero.isEmpty ? card.name : card.hero)
                                .font(Design.Fonts.display(22))
                                .foregroundStyle(Design.Colors.textPrimary)
                            Spacer()
                            if card.cardType == "Hero", let power = card.power {
                                Text("\(power)")
                                    .font(Design.Fonts.display(30))
                                    .foregroundStyle(Design.Colors.element(card.element))
                            } else if let label = card.playCostLabel {
                                Text(label)
                                    .font(Design.Fonts.display(22))
                                    .foregroundStyle(card.playCost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                            }
                        }

                        HStack(spacing: Design.Spacing.sm) {
                            Text(card.element)
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(Design.Colors.element(card.element))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Design.Colors.element(card.element).opacity(0.15)))
                            if let t = card.treatment, !t.isEmpty {
                                Text(t.uppercased())
                                    .font(Design.Fonts.mono(10))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Design.Colors.glass))
                            }
                            Spacer()
                            Text(card.cardNumber)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textMuted)
                        }

                        if let ability = card.playAbility, !ability.isEmpty {
                            Text(ability)
                                .font(Design.Fonts.mono(13))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .padding(Design.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass))
                        }
                    }
                    .padding(.horizontal, Design.Spacing.lg)

                    // Add to deck / Remove button
                    if wouldViolate {
                        Text("Cannot add — rule violation")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Color(hex: "C0392B"))
                            .padding()
                    } else if inDeck {
                        Button {
                            store.removeCard(card, role: tab)
                            dismiss()
                        } label: {
                            Label("Remove from Deck", systemImage: "minus.circle.fill")
                                .font(Design.Fonts.mono(14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "C0392B")))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Design.Spacing.lg)
                    } else {
                        Button {
                            store.addCard(card, role: tab)
                            dismiss()
                        } label: {
                            Label("Add to Deck", systemImage: "plus.circle.fill")
                                .font(Design.Fonts.mono(14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaOrange))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Design.Spacing.lg)
                    }

                    Spacer(minLength: Design.Spacing.xl)
                }
                .padding(.top, Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle(card.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Layout helper (vertical on iPhone, side-by-side on iPad)
// ════════════════════════════════════════════════════════════════

private struct HSplitOrVStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder let content: () -> Content

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 0) { content() }
        } else {
            VStack(spacing: 0) { content() }
        }
    }
}
