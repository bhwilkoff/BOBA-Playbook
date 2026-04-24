//
//  PracticePlaysPanel.swift
//  BOBAPlaybook
//
//  Slide-up overlay panel showing the player's play cards in hand.
//  Tap a card to see details; use the PLAY button to play it.
//

import SwiftUI

struct PracticePlaysPanel: View {
    let store: PracticeStore
    @Binding var isVisible: Bool
    @State private var selectedCard: Card?

    var body: some View {
        VStack(spacing: Design.Spacing.sm) {
            // Header
            HStack {
                Text("YOUR PLAYS")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text("(\(store.playerHand.count) in hand)")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Play cards
            if store.playerHand.isEmpty {
                Text("No plays in hand")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(.vertical, Design.Spacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.playerHand) { card in
                            playCardThumb(card: card)
                        }
                    }
                }
            }

            // Selected card detail — constrained height to prevent overflow
            if let card = selectedCard {
                cardDetail(card: card)
                    .frame(maxHeight: 120)
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxHeight: 280)
        .background(Design.Colors.surface.opacity(0.98))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
    }

    // MARK: - Play Card Thumbnail

    private func playCardThumb(card: Card) -> some View {
        let isSelected = selectedCard == card
        let nominalCost = card.playCost ?? 0
        let effCost = store.effectiveCost(for: card, side: .player)
        let canAfford = effCost <= store.playerHotDogs
        // UX#5 — when an active scope (Dog On Inflation, Flash Sale,
        // etc.) shifts the printed cost, surface that visually:
        // strike through the original and color the new cost red
        // (worse) or green (better). Cards with no modifier render
        // the simple "N HD" badge as before.
        let modified = effCost != nominalCost
        let isBonus  = effCost < nominalCost

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCard = isSelected ? nil : card
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Group {
                        if let file = card.imageFile, !file.isEmpty {
                            CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                        } else {
                            playPlaceholder(card: card)
                        }
                    }
                    .frame(width: 72, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(
                            isSelected
                                ? Design.Colors.bobaCyan
                                : (card.isBonusPlay == true ? Color(hex: "FFD700") : Design.Colors.glass),
                            lineWidth: isSelected ? 3 : (card.isBonusPlay == true ? 2 : 1)
                        )
                    )
                    // UX#10 — bonus-play distinction. Gold border + a
                    // small "★ BONUS" tag at the top so coaches can
                    // tell at a glance which plays don't count against
                    // the 30-card playbook total.
                    .overlay(alignment: .topLeading) {
                        if card.isBonusPlay == true {
                            Text("★ BONUS")
                                .font(Design.Fonts.mono(7, weight: .bold))
                                .foregroundStyle(Design.Colors.nearBlack)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color(hex: "FFD700")))
                                .padding(3)
                        }
                    }

                    // Cost badge — modified plays show "3→5" with the
                    // original struck through so coaches see at a
                    // glance how scopes are reshaping the playbook.
                    if modified {
                        HStack(spacing: 2) {
                            Text("\(nominalCost)")
                                .font(Design.Fonts.mono(8))
                                .strikethrough(true, color: .white.opacity(0.7))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("→")
                                .font(Design.Fonts.mono(8, weight: .bold))
                                .foregroundStyle(.white)
                            Text(effCost == 0 ? "FREE" : "\(effCost)")
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(
                            !canAfford ? Color(hex: "C0392B")
                            : isBonus  ? Color(hex: "4CAF50")
                            : Color(hex: "FFD166")  // amber for inflated but still affordable
                        ))
                        .padding(.bottom, 4)
                    } else {
                        Text(effCost == 0 ? "FREE" : "\(effCost) HD")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(canAfford ? Design.Colors.bobaCyan : Color(hex: "C0392B")))
                            .padding(.bottom, 4)
                    }
                }

                Text(card.name)
                    .font(Design.Fonts.mono(8, weight: .bold))
                    .foregroundStyle(isSelected ? Design.Colors.bobaCyan : Design.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
            .opacity(canAfford ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Detail

    private func cardDetail(card: Card) -> some View {
        let effCost = store.effectiveCost(for: card, side: .player)
        let canAfford = effCost <= store.playerHotDogs
        let canUse = PlayEffects.isPlayable(name: card.name, ctx: store.makeExecContext(self_: .player))
        let playable = canAfford && canUse
        let isPlayPhase = store.phase == .play
        let partial = PlayEffects.entryHasUnknownOps(PlayEffects.entry(for: card.name))

        return HStack(spacing: Design.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)

                Text("Cost: \(effCost == 0 ? "FREE" : "\(effCost) HD")")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(canAfford ? Color(hex: "4CAF50") : Color(hex: "C0392B"))

                Text(PracticeStore.effectDescription(for: card))
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if partial {
                    Text("⚠ Some effects not yet simulated")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Color(hex: "FFD166"))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPlayPhase && !store.playerPassedPlays {
                let label: String = !canAfford ? "CAN'T\nAFFORD" : (!canUse ? "NOT\nYET" : "PLAY")
                Button {
                    guard playable else { return }
                    store.playerPlayCard(card)
                    selectedCard = nil
                } label: {
                    Text(label)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(playable ? Design.Colors.nearBlack : Design.Colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .frame(width: 80, height: 52)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(playable ? Design.Colors.bobaOrange : Design.Colors.glass))
                }
                .buttonStyle(.plain)
                .disabled(!playable)
            }
        }
        .padding(Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass))
    }

    private func playPlaceholder(card: Card) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Design.Colors.bobaViolet.opacity(0.15))
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 16))
                    Text(String(card.name.prefix(6)))
                        .font(Design.Fonts.mono(8))
                }
                .foregroundStyle(Design.Colors.bobaViolet.opacity(0.6))
            )
    }
}
