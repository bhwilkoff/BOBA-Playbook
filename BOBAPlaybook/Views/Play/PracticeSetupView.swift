//
//  PracticeSetupView.swift
//  BOBAPlaybook
//
//  Pre-game setup. Three tabs (Game Mode / Your Deck / CPU Deck)
//  driven by a top segmented picker. The Start button moves to the
//  top-right toolbar so it's reachable from every tab without
//  scrolling.
//

import SwiftUI

struct PracticeSetupView: View {
    /// True when this view is presented as a tab root (no sheet chrome).
    /// Hides the Cancel button since there's nothing to dismiss.
    var isRootView: Bool = false

    enum Tab: String, CaseIterable, Identifiable {
        case gameMode = "Game Mode"
        case yourDeck = "Your Deck"
        case cpuDeck  = "CPU Deck"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .gameMode: return "rectangle.3.group.fill"
            case .yourDeck: return "person.fill"
            case .cpuDeck:  return "cpu.fill"
            }
        }
    }

    @Environment(CardStore.self) private var cardStore
    @State private var store = PracticeStore()
    @State private var showPlaymat = false
    @State private var savedDecks: [SavedDeck] = []
    @State private var isLoadingSaved = false
    @State private var isStarting = false
    @State private var selectedTab: Tab = .gameMode
    @State private var customRulesExpanded = false
    @State private var custom = PracticeCustomRules()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                ScrollView {
                    VStack(spacing: Design.Spacing.lg) {
                        // RESUME pill always sits at the top of any
                        // tab when a saved match exists — coaches can
                        // restore without hunting through tabs.
                        if PracticeStore.hasSavedMatch {
                            resumeButton
                        }
                        tabContent
                    }
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.top, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.xl * 2)
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isRootView {
                        BOBAWordmark()
                    } else {
                        Text("PRACTICE BATTLE")
                            .font(Design.Fonts.display(18))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                }
                if !isRootView {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startPractice() }
                    } label: {
                        if isStarting {
                            ProgressView()
                                .tint(Design.Colors.bobaOrange)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Design.Colors.nearBlack)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Design.Colors.bobaOrange))
                        }
                    }
                    .disabled(isStarting)
                    .accessibilityLabel("Start practice")
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await loadSavedDecks() }
        }
        .fullScreenCover(isPresented: $showPlaymat) {
            PracticeView(store: store)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(tab.rawValue)
                                .font(Design.Fonts.mono(12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedTab == tab
                                          ? Design.Colors.bobaOrange
                                          : Design.Colors.textMuted)
                        Rectangle()
                            .fill(selectedTab == tab
                                   ? Design.Colors.bobaOrange
                                   : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.vertical, Design.Spacing.sm)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Design.Colors.surface)
        .overlay(
            Rectangle()
                .fill(Design.Colors.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Tab content router

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .gameMode: gameModeTab
        case .yourDeck: deckTab(side: .player)
        case .cpuDeck:  deckTab(side: .cpu)
        }
    }

    private var resumeButton: some View {
        Button {
            if store.restoreMatch() { showPlaymat = true }
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("RESUME MATCH")
                    .font(Design.Fonts.display(16))
            }
            .foregroundStyle(Design.Colors.nearBlack)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Design.Colors.bobaCyan)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Game Mode tab

    private var gameModeTab: some View {
        VStack(spacing: Design.Spacing.lg) {
            sectionHeader("GAME MODE")
            modeSelector
            modeRulesSummary
            customRulesDisclosure
        }
    }

    private var modeSelector: some View {
        VStack(spacing: Design.Spacing.sm) {
            ForEach(PracticeMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { store.mode = mode }
                } label: {
                    HStack(spacing: Design.Spacing.md) {
                        Image(systemName: store.mode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(store.mode == mode ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(Design.Fonts.display(16))
                                .foregroundStyle(Design.Colors.textPrimary)
                            Text(modeSubtitle(mode))
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(Design.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(store.mode == mode ? Design.Colors.bobaOrange.opacity(0.1) : Design.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(store.mode == mode ? Design.Colors.bobaOrange.opacity(0.4) : Color.clear, lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modeSubtitle(_ mode: PracticeMode) -> String {
        switch mode {
        case .rookie:       return "Hero deck only — pure power comparison"
        case .substitution: return "Hero + Hot Dogs — swap heroes mid-battle"
        case .playmaker:    return "Full game — subs + play cards (tournament standard)"
        }
    }

    // MARK: - Mode Rules Summary

    private var modeRulesSummary: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("BATTLE SEQUENCE")
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)

            HStack(spacing: 0) {
                phaseChip("REVEAL", active: true)
                phaseSeparator
                if store.mode != .rookie {
                    phaseChip("SUBS", active: true)
                    phaseSeparator
                }
                if store.mode == .playmaker {
                    phaseChip("PLAYS", active: true)
                    phaseSeparator
                }
                phaseChip("RESOLVE", active: true)
                phaseSeparator
                phaseChip("CLEANUP", active: true)
            }
        }
        .padding(Design.Spacing.md)
        .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.surface))
    }

    private func phaseChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(Design.Fonts.mono(9, weight: .bold))
            .foregroundStyle(active ? Design.Colors.bobaOrange : Design.Colors.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Capsule().fill(active ? Design.Colors.bobaOrange.opacity(0.15) : Color.clear))
    }

    private var phaseSeparator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8))
            .foregroundStyle(Design.Colors.textMuted)
            .padding(.horizontal, 2)
    }

    // MARK: - Custom rules disclosure

    /// Expandable section with rule-set knobs that change which
    /// variant of the chosen mode is in play. Sourced from the
    /// Comprehensive Rules Guide v1 + 2026 National Events Rules.
    /// Settings are captured in `custom` and will be wired into the
    /// engine in a follow-on session — for now they describe the
    /// intended ruleset and persist in UI state.
    private var customRulesDisclosure: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    customRulesExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Design.Colors.bobaCyan)
                    Text("CUSTOM RULES")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .tracking(1.0)
                    Spacer()
                    if !custom.isDefault {
                        Text("\(custom.activeOverrideCount) override\(custom.activeOverrideCount == 1 ? "" : "s")")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    Image(systemName: customRulesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .padding(Design.Spacing.md)
            }
            .buttonStyle(.plain)
            if customRulesExpanded {
                VStack(spacing: Design.Spacing.md) {
                    Divider().background(Design.Colors.glassBorder)
                    customRuleRows
                    Text("Custom rule changes are tracked here for future ruleset support — engine wiring lands in an upcoming session. Default values match the standard mode.")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.bottom, Design.Spacing.md)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customRuleRows: some View {
        VStack(spacing: Design.Spacing.sm) {
            customRuleRow(label: "Match length") {
                Picker("", selection: $custom.matchLength) {
                    ForEach(PracticeCustomRules.MatchLength.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            if store.mode == .playmaker {
                customRuleRow(label: "Hero deck format") {
                    Picker("", selection: $custom.heroFormat) {
                        ForEach(PracticeCustomRules.HeroFormat.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Design.Colors.bobaCyan)
                }
            }

            customRuleRow(label: "Starting Hot Dogs") {
                Picker("", selection: $custom.startingHotDogs) {
                    ForEach([5, 8, 10, 12, 15], id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .tint(Design.Colors.bobaCyan)
            }

            customRuleRow(label: "Super-weapon ties") {
                Toggle("", isOn: $custom.superBreaksTies)
                    .toggleStyle(SwitchToggleStyle(tint: Design.Colors.bobaCyan))
                    .labelsHidden()
            }

            customRuleRow(label: "Sudden Death") {
                Toggle("", isOn: $custom.suddenDeath)
                    .toggleStyle(SwitchToggleStyle(tint: Design.Colors.bobaCyan))
                    .labelsHidden()
            }
        }
        .padding(.horizontal, Design.Spacing.md)
    }

    private func customRuleRow<Trailing: View>(label: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textSecondary)
            Spacer()
            trailing()
        }
    }

    // MARK: - Deck tab

    @ViewBuilder
    private func deckTab(side: PlayExecContext.Side) -> some View {
        let header = side == .player ? "YOUR DECK" : "CPU DECK"
        VStack(spacing: Design.Spacing.lg) {
            sectionHeader(header)

            // ── Saved decks first (when authenticated) ─────────────
            if !savedDecks.isEmpty {
                Text("YOUR SAVED DECKS")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(savedDecks, id: \.id) { deck in
                    let isSelected = currentSource(side: side) == .saved(deck.id)
                    deckSourceOption(
                        title: deck.name,
                        subtitle: "\(deck.format.uppercased()) · your saved deck",
                        isSelected: isSelected,
                        systemImage: "bookmark.fill"
                    ) {
                        setSource(side: side, source: .saved(deck.id))
                    }
                }
            } else if isLoadingSaved {
                Text("Loading your saved decks…")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }

            // ── Starter decks (Random first, then templates) ───────
            Text("STARTER DECKS")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            deckSourceOption(
                title: "Random Deck",
                subtitle: "Realistic mix — 30 high / 24 mid / 6 low power, balanced playbook",
                isSelected: currentSource(side: side) == .random,
                systemImage: "shuffle"
            ) {
                setSource(side: side, source: .random)
            }

            ForEach(DeckTemplate.all) { template in
                deckSourceOption(
                    title: template.name,
                    subtitle: template.description,
                    isSelected: currentSource(side: side) == .template(template),
                    systemImage: templateIcon(template.id)
                ) {
                    setSource(side: side, source: .template(template))
                }
            }

            // ── Future-state hint ────────────────────────────────
            futureHint(side: side)
        }
    }

    private func currentSource(side: PlayExecContext.Side) -> PracticeStore.DeckSource {
        side == .player ? store.playerDeckSource : store.cpuDeckSource
    }

    private func setSource(side: PlayExecContext.Side, source: PracticeStore.DeckSource) {
        if side == .player { store.playerDeckSource = source }
        else               { store.cpuDeckSource = source }
    }

    private func deckSourceOption(title: String, subtitle: String, isSelected: Bool, systemImage: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Design.Colors.bobaCyan : Design.Colors.textMuted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text(subtitle)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .padding(Design.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Design.Colors.bobaCyan.opacity(0.08) : Design.Colors.surface))
        }
        .buttonStyle(.plain)
    }

    private func templateIcon(_ id: String) -> String {
        switch id {
        case "fire-aggro":        return "flame.fill"
        case "ice-control":       return "snowflake"
        case "steel-wall":        return "shield.fill"
        case "mixed-toolbox":     return "wrench.and.screwdriver.fill"
        case "economy-attrition": return "chart.line.downtrend.xyaxis"
        default:                  return "rectangle.stack.fill"
        }
    }

    @ViewBuilder
    private func futureHint(side: PlayExecContext.Side) -> some View {
        let isPlayer = side == .player
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: isPlayer ? "trophy.fill" : "cpu.fill")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.bobaViolet)
            Text(isPlayer ? "PLAYER RANKING — COMING SOON" : "CPU OPPONENTS — COMING SOON")
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.bobaViolet)
                .tracking(1.2)
            Text(isPlayer
                 ? "Your practice record + ELO-style ranking will appear here once enough match data is collected."
                 : "Named CPU opponents (Rookie / Coach / Master / GM) with ELO-tagged difficulty land in a future update.")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Design.Colors.bobaViolet.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Design.Colors.bobaViolet.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            Spacer()
        }
    }

    // MARK: - Saved decks

    private func loadSavedDecks() async {
        isLoadingSaved = true
        defer { isLoadingSaved = false }
        guard SupabaseClient.shared.isAuthenticated else { return }
        do { savedDecks = try await SupabaseClient.shared.fetchDecks() }
        catch { savedDecks = [] }
    }

    private func resolveSavedDeck(_ id: UUID) async -> PracticeStore.ResolvedDeck? {
        guard let rows = try? await SupabaseClient.shared.fetchDeckCards(deckId: id) else { return nil }
        var byId: [String: Card] = [:]
        for c in cardStore.displayCards { byId[c.id] = c }
        var r = PracticeStore.ResolvedDeck()
        for row in rows {
            guard let card = byId[row.bobaId] else { continue }
            switch card.cardType {
            case "Hero":   r.heroes.append(card)
            case "Play":   r.plays.append(card)
            case "HotDog": r.hotDogs.append(card)
            default: break
            }
        }
        return r
    }

    // MARK: - Start

    private func startPractice() async {
        isStarting = true
        defer { isStarting = false }

        // Resolve saved decks ahead of startMatch (templates resolve synchronously inside the store).
        if case .saved(let id) = store.playerDeckSource {
            store.playerResolvedDeck = await resolveSavedDeck(id)
        }
        if case .saved(let id) = store.cpuDeckSource {
            store.cpuResolvedDeck = await resolveSavedDeck(id)
        }

        store.startMatch(allCards: cardStore.displayCards)
        showPlaymat = true
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - PracticeCustomRules
// ════════════════════════════════════════════════════════════════
//
// Stores the user's selections in the Custom Rules disclosure.
// The engine doesn't read these yet — wiring lands in a follow-on
// session — but the choices persist in view state and `isDefault`
// drives the "N overrides" badge on the disclosure header.
//
// Variant taxonomy sourced from the Comprehensive Rules Guide v1
// (formats: standard / SPEC / SPEC+ / Limited) + 2026 National
// Events Rules (match length, sudden-death, super-tiebreaker).

struct PracticeCustomRules: Equatable {
    enum MatchLength: String, CaseIterable, Identifiable, Equatable {
        case bo7 = "Best of 7"
        case bo5 = "Best of 5"
        case bo3 = "Best of 3"
        var id: String { rawValue }
        var battleCount: Int {
            switch self { case .bo7: return 7; case .bo5: return 5; case .bo3: return 3 }
        }
    }
    enum HeroFormat: String, CaseIterable, Identifiable, Equatable {
        case standard = "Standard (60)"
        case spec     = "SPEC (160 power cap)"
        case specPlus = "SPEC+ (up to 70 heroes)"
        case limited  = "Limited (40-card)"
        var id: String { rawValue }
    }

    var matchLength: MatchLength = .bo7
    var heroFormat: HeroFormat   = .standard
    var startingHotDogs: Int     = 10
    var superBreaksTies: Bool    = true
    var suddenDeath: Bool        = true

    var isDefault: Bool {
        matchLength == .bo7 && heroFormat == .standard && startingHotDogs == 10
            && superBreaksTies && suddenDeath
    }

    var activeOverrideCount: Int {
        var n = 0
        if matchLength != .bo7 { n += 1 }
        if heroFormat != .standard { n += 1 }
        if startingHotDogs != 10 { n += 1 }
        if !superBreaksTies { n += 1 }
        if !suddenDeath { n += 1 }
        return n
    }
}
