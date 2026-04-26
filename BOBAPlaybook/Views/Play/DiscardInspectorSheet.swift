//
//  DiscardInspectorSheet.swift
//  BOBAPlaybook
//
//  UX#8 — tap-to-inspect discard pile from the practice playmat.
//  Player side renders the actual list of discarded plays (engine
//  tracks them as Card objects). CPU side renders the per-battle
//  play history reconstructed from `battles[].cpuPlayedCards` since
//  the CPU's discard pile isn't tracked as individual cards.
//

import SwiftUI

struct DiscardInspectorSheet: View {
    let store: PracticeStore
    let side: PlayExecContext.Side
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(side == .player ? "Your Discard Pile" : "CPU Plays Used")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch side {
        case .player: playerDiscardList
        case .cpu:    cpuPlayHistory
        }
    }

    // MARK: - Player side — flat list of discarded play cards

    private var playerDiscardList: some View {
        let plays = store.playerPlayDiscard
        let heroes = store.playerHeroDiscard
        let hotDogs = store.playerHotDogDiscard
        let isEmpty = plays.isEmpty && heroes.isEmpty && hotDogs == 0
        return ScrollView {
            if isEmpty {
                emptyState(message: "No cards in discard yet")
            } else {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    if !heroes.isEmpty {
                        sectionHeader("\(heroes.count) HERO\(heroes.count == 1 ? "" : "ES")", color: Design.Colors.bobaOrange)
                        ForEach(Array(heroes.reversed().enumerated()), id: \.offset) { _, card in
                            cardRow(card: card)
                        }
                    }
                    if !plays.isEmpty {
                        sectionHeader("\(plays.count) PLAY\(plays.count == 1 ? "" : "S")", color: Design.Colors.bobaCyan)
                        ForEach(Array(plays.reversed().enumerated()), id: \.offset) { _, card in
                            cardRow(card: card)
                        }
                    }
                    if hotDogs > 0 {
                        sectionHeader("\(hotDogs) HOT DOG\(hotDogs == 1 ? "" : "S") SPENT",
                                      color: Color(hex: "4CAF50"))
                        // Show N actual Hot Dog cards from the
                        // captured deck. Engine tracks Hot Dogs as
                        // an Int count (not which specific card was
                        // spent), so we render the deck's first N
                        // entries — gives coaches real card visuals
                        // matching the heroes + plays sections.
                        let spent = Array(store.playerHotDogDeckCards.prefix(hotDogs))
                        ForEach(Array(spent.enumerated()), id: \.offset) { _, card in
                            cardRow(card: card)
                        }
                    }
                }
                .padding(Design.Spacing.lg)
            }
        }
        .background(Design.Colors.nearBlack)
    }

    private func sectionHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(color)
            .tracking(1.5)
    }

    // MARK: - CPU side — grouped per-battle history

    private var cpuPlayHistory: some View {
        // Walk every closed battle (and the active one) and pull
        // cpuPlayedCards. The CPU's "discard pile" is the union
        // of these across all battles.
        let battles = store.battles
        let totalCount = battles.reduce(0) { $0 + $1.cpuPlayedCards.count }
        return ScrollView {
            if totalCount == 0 {
                emptyState(message: "CPU hasn't played any cards yet")
            } else {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    Text("\(totalCount) PLAY\(totalCount == 1 ? "" : "S") USED · GROUPED BY BATTLE")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1)
                    ForEach(battles) { slot in
                        if !slot.cpuPlayedCards.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("BATTLE \(slot.id + 1)")
                                    .font(Design.Fonts.mono(9, weight: .bold))
                                    .foregroundStyle(Design.Colors.bobaViolet)
                                    .tracking(1)
                                ForEach(Array(slot.cpuPlayedCards.enumerated()), id: \.offset) { _, card in
                                    cardRow(card: card)
                                }
                            }
                        }
                    }
                }
                .padding(Design.Spacing.lg)
            }
        }
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Shared row

    private func cardRow(card: Card) -> some View {
        DiscardCardRow(card: card)
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(Design.Colors.textMuted)
            Text(message)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.xl * 2)
    }
}

// MARK: - DiscardCardRow
//
// Self-contained row that toggles its own expansion. Tapping reveals
// the card's full ability text + a larger thumbnail so the player can
// review what each played card actually did. Each row owns its own
// `expanded` state so multiple rows can be open simultaneously.

private struct DiscardCardRow: View {
    let card: Card
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                header
                if expanded { detail }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(expanded
                                      ? Design.Colors.bobaCyan.opacity(0.5)
                                      : Design.Colors.glassBorder,
                                      lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: Design.Spacing.md) {
            Group {
                if let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Design.Colors.bobaViolet.opacity(0.15))
                }
            }
            .frame(width: 38, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                // Display name — prefer hero name for hero cards (the
                // catalog `name` field is often the variation, the
                // `hero` field is the recognizable persona).
                Text(displayName)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    headerChips
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }
        }
    }

    private var displayName: String {
        if card.cardType == "Hero", !card.hero.isEmpty { return card.hero }
        return card.name
    }

    /// Card-type-aware header chips. Plays show cost + bonus; heroes
    /// show power + weapon; hot dogs show a HOT DOG tag.
    @ViewBuilder
    private var headerChips: some View {
        switch card.cardType {
        case "Hero":
            if let pow = card.power {
                Text("\(pow) PW")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Design.Colors.bobaOrange))
            }
            if !card.element.isEmpty {
                Text(card.element)
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.element(card.element))
                    .tracking(0.6)
            }
        case "HotDog":
            Text("HOT DOG")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Color(hex: "4CAF50"))
                .tracking(0.8)
        default:
            if let cost = card.playCost {
                Text(cost == 0 ? "FREE" : "\(cost) HD")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
            }
            if card.isBonusPlay == true {
                Text("★ BONUS")
                    .font(Design.Fonts.mono(8, weight: .bold))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(hex: "FFD700")))
            }
        }
    }

    private var detail: some View {
        HStack(alignment: .top, spacing: Design.Spacing.md) {
            Group {
                if let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Design.Colors.bobaViolet.opacity(0.15))
                }
            }
            .frame(width: 96)
            .aspectRatio(5.0/7.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
            )

            detailBody
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// Card-type-aware detail body. Plays surface their ability text
    /// (the stat coaches review post-resolution); heroes surface
    /// their stat grid (power + weapon + set + athlete); hot dogs
    /// surface their variation + set so the flavor card identity
    /// reads cleanly. Prevents the "no effect on file" boilerplate
    /// that previously rendered for everything non-Play.
    @ViewBuilder
    private var detailBody: some View {
        switch card.cardType {
        case "Hero":
            VStack(alignment: .leading, spacing: 6) {
                Text("HERO")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                statRow("Power", "\(card.power ?? 0)")
                statRow("Weapon", card.element.isEmpty ? "—" : card.element)
                statRow("Set", card.set.isEmpty ? "—" : card.set)
                if let sub = card.subSet, !sub.isEmpty {
                    statRow("Sub-set", sub)
                }
                if let t = card.treatment, !t.isEmpty {
                    statRow("Treatment", t)
                }
                if let athlete = card.athleteInspiration, !athlete.isEmpty {
                    statRow("Inspired by", athlete)
                }
            }
        case "HotDog":
            VStack(alignment: .leading, spacing: 6) {
                Text("HOT DOG · SPENT")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Color(hex: "4CAF50"))
                    .tracking(1.5)
                if let v = card.variation, !v.isEmpty {
                    statRow("Variation", v)
                }
                if !card.set.isEmpty { statRow("Set", card.set) }
                if let t = card.treatment, !t.isEmpty {
                    statRow("Treatment", t)
                }
                Text("Spent for a substitution or play cost. Hot Dogs share the discard zone with heroes and plays.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("EFFECT")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text(card.playAbility ?? "No effect text on file.")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    /// One label/value row in the hero / hot-dog stat block.
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label.uppercased())
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
