//
//  PracticeSetupView.swift
//  BOBAPlaybook
//
//  Pre-game setup: choose mode and deck, then launch the playmat.
//

import SwiftUI

struct PracticeSetupView: View {
    @Environment(CardStore.self) private var cardStore
    @State private var store = PracticeStore()
    @State private var showPlaymat = false
    @State private var savedDecks: [SavedDeck] = []
    @State private var isLoadingSaved = false
    @State private var isStarting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.xl) {

                    // ── Mode selection ──────────────────────────────────────
                    sectionHeader("GAME MODE")
                    modeSelector

                    // ── Your deck ───────────────────────────────────────────
                    sectionHeader("YOUR DECK")
                    deckSourcePicker(isPlayer: true)

                    // ── CPU deck ────────────────────────────────────────────
                    sectionHeader("CPU DECK")
                    deckSourcePicker(isPlayer: false)

                    // ── Mode rules summary ──────────────────────────────────
                    modeRulesSummary

                    // ── Resume button (if saved match exists) ────────────────
                    if PracticeStore.hasSavedMatch {
                        Button {
                            if store.restoreMatch() {
                                showPlaymat = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("RESUME MATCH")
                                    .font(Design.Fonts.display(18))
                            }
                            .foregroundStyle(Design.Colors.nearBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Design.Colors.bobaCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Start button ────────────────────────────────────────
                    Button {
                        Task { await startPractice() }
                    } label: {
                        HStack {
                            if isStarting {
                                ProgressView().tint(Design.Colors.nearBlack)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isStarting ? "PREPARING…" : "START PRACTICE")
                                .font(Design.Fonts.display(18))
                        }
                        .foregroundStyle(Design.Colors.nearBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Design.Colors.bobaOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                    .padding(.bottom, Design.Spacing.xl)
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PRACTICE BATTLE")
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Design.Colors.textSecondary)
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
            switch row.cardType {
            case "hero": r.heroes.append(card)
            case "play", "bonus_play": r.plays.append(card)
            case "hot_dog": r.hotDogs.append(card)
            default: break
            }
        }
        return r
    }

    private func startPractice() async {
        isStarting = true
        defer { isStarting = false }

        // Resolve saved decks ahead of startMatch (templates resolve synchronously inside the store).
        if case .saved(let id) = store.playerDeckSource {
            store.playerResolvedDeck = await resolveSavedDeck(id)
        } else {
            store.playerResolvedDeck = nil
        }
        if case .saved(let id) = store.cpuDeckSource {
            store.cpuResolvedDeck = await resolveSavedDeck(id)
        } else {
            store.cpuResolvedDeck = nil
        }

        store.startMatch(allCards: cardStore.displayCards)
        showPlaymat = true
    }

    // MARK: - Section Header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Design.Fonts.mono(11, weight: .bold))
            .foregroundStyle(Design.Colors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mode Selector

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

    // MARK: - Deck Source Picker

    @ViewBuilder
    private func deckSourcePicker(isPlayer: Bool) -> some View {
        VStack(spacing: Design.Spacing.xs) {
            // Random
            deckSourceOption(
                title: "Random Deck",
                subtitle: "Auto-generated from the full catalog",
                isSelected: isPlayer ? store.playerDeckSource == .random : store.cpuDeckSource == .random,
                systemImage: "shuffle"
            ) {
                if isPlayer { store.playerDeckSource = .random }
                else { store.cpuDeckSource = .random }
            }

            // Templates
            ForEach(DeckTemplate.all) { template in
                deckSourceOption(
                    title: template.name,
                    subtitle: template.description,
                    isSelected: isPlayer
                        ? store.playerDeckSource == .template(template)
                        : store.cpuDeckSource == .template(template),
                    systemImage: templateIcon(template.id)
                ) {
                    if isPlayer { store.playerDeckSource = .template(template) }
                    else { store.cpuDeckSource = .template(template) }
                }
            }

            // Saved decks (user-built)
            if !savedDecks.isEmpty {
                Text("YOUR SAVED DECKS")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                ForEach(savedDecks, id: \.id) { deck in
                    let isSelected = isPlayer
                        ? store.playerDeckSource == .saved(deck.id)
                        : store.cpuDeckSource == .saved(deck.id)
                    deckSourceOption(
                        title: deck.name,
                        subtitle: "\(deck.format.uppercased()) · your saved deck",
                        isSelected: isSelected,
                        systemImage: "bookmark.fill"
                    ) {
                        if isPlayer { store.playerDeckSource = .saved(deck.id) }
                        else { store.cpuDeckSource = .saved(deck.id) }
                    }
                }
            } else if isLoadingSaved {
                Text("Loading saved decks…")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(.top, 4)
            }
        }
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
                        .lineLimit(1)
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
}
