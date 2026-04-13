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
    @Environment(CardStore.self) private var cardStore
    @State private var store = DeckBuilderStore()
    @State private var showTemplates = true
    @State private var showDeckList = false
    @State private var showExport = false
    @State private var exportText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Format selector
                formatPicker
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
                        cardBrowser
                        deckPanel
                    }
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("DECK BUILDER")
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Templates") { withAnimation { showTemplates = true } }
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Design.Spacing.sm) {
                        Button {
                            exportText = store.deckListText
                            showExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(Design.Colors.textSecondary)

                        Button("Done") { dismiss() }
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(text: exportText, deckName: store.deckName)
        }
        .sheet(isPresented: $showTemplates) {
            TemplateGallerySheet(store: store, cards: cardStore.cards)
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

                ForEach(DeckTemplate.all) { template in
                    TemplateCard(template: template) {
                        store.loadTemplate(template, allCards: cardStore.cards)
                        showTemplates = false
                    }
                }

                Button {
                    store.clearDeck()
                    showTemplates = false
                } label: {
                    Text("Start from scratch")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Design.Colors.glass, lineWidth: 1))
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xl)
        }
    }

    // MARK: - Card Browser

    private var cardBrowser: some View {
        VStack(spacing: 0) {
            // Browser tab pills
            browserTabPicker
                .padding(Design.Spacing.sm)
                .background(Design.Colors.surface)

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
                            BrowserCardCell(card: card, store: store)
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
        return cardStore.cards.filter { card in
            // Card type filter
            switch store.browserTab {
            case .hero:
                guard card.cardType == "Hero" && (card.power ?? 0) > 0 else { return false }
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
            // Power cap warning (SPEC)
            return true
        }
    }

    // MARK: - Deck Panel

    private var deckPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Deck name
                HStack {
                    TextField("Deck name", text: $store.deckName)
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Spacer()
                    Button {
                        withAnimation { showDeckList.toggle() }
                    } label: {
                        Image(systemName: showDeckList ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .padding(Design.Spacing.md)

                if showDeckList || !store.heroes.isEmpty || !store.plays.isEmpty {
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
        }
        .background(Design.Colors.surface.opacity(0.5))
        .frame(minHeight: 200)
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
                        AsyncImage(url: CDN.thumb(for: file)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass)
                            }
                        }
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
                    // Dim overlay if violates rule
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
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    pressed = false
                    guard !wouldViolate else { return }
                    store.addCard(card, role: store.browserTab)
                }
        )
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
                    AsyncImage(url: CDN.thumb(for: file)) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        else { RoundedRectangle(cornerRadius: 4).fill(Design.Colors.glass) }
                    }
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
// MARK: - Template Gallery Sheet
// ════════════════════════════════════════════════════════════════

private struct TemplateGallerySheet: View {
    let store: DeckBuilderStore
    let cards: [Card]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    ForEach(DeckTemplate.all) { template in
                        TemplateCard(template: template) {
                            store.loadTemplate(template, allCards: cards)
                            dismiss()
                        }
                    }

                    Button {
                        store.clearDeck()
                        dismiss()
                    } label: {
                        Text("Start from scratch")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Design.Colors.glass, lineWidth: 1))
                    }
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Starter Decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Export Sheet
// ════════════════════════════════════════════════════════════════

private struct ExportSheet: View {
    let text: String
    let deckName: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.lg)
                    .textSelection(.enabled)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Decklist — \(deckName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied!" : "Copy") {
                        UIPasteboard.general.string = text
                        copied = true
                        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = false }
                    }
                    .foregroundStyle(copied ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                }
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
