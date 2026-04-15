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
                    .frame(maxHeight: 80)
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxHeight: 240)
        .background(Design.Colors.surface.opacity(0.98))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
    }

    // MARK: - Play Card Thumbnail

    private func playCardThumb(card: Card) -> some View {
        let isSelected = selectedCard == card
        let canAfford = (card.playCost ?? 0) <= store.playerHotDogs

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
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                        isSelected ? Design.Colors.bobaCyan : Design.Colors.glass, lineWidth: isSelected ? 3 : 1))

                    // Cost badge
                    Text(card.playCost == 0 ? "FREE" : "\(card.playCost ?? 0) HD")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(canAfford ? Design.Colors.bobaCyan : Color(hex: "C0392B")))
                        .padding(.bottom, 4)
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
        let canAfford = (card.playCost ?? 0) <= store.playerHotDogs
        let isPlayPhase = store.phase == .play

        return HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)

                Text("Cost: \(card.playCost == 0 ? "FREE" : "\(card.playCost ?? 0) HD")")
                    .font(Design.Fonts.mono(9))
                    .foregroundStyle(canAfford ? Color(hex: "4CAF50") : Color(hex: "C0392B"))

                Text(PracticeStore.effectDescription(for: card))
                    .font(Design.Fonts.mono(9))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPlayPhase && !store.playerPassedPlays {
                Button {
                    guard canAfford else { return }
                    store.playerPlayCard(card)
                    selectedCard = nil
                } label: {
                    Text(canAfford ? "PLAY" : "CAN'T\nAFFORD")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(canAfford ? Design.Colors.nearBlack : Design.Colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .frame(width: 70, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(canAfford ? Design.Colors.bobaOrange : Design.Colors.glass))
                }
                .buttonStyle(.plain)
                .disabled(!canAfford)
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
