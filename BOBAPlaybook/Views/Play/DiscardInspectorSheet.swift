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
                        Text("Spent Hot Dogs share the discard zone per the rules; they don't render individually since they're tracked as a count.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
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
                Text(card.name)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
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
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                }
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
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}
