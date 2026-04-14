//
//  PracticePlaysPanel.swift
//  BOBAPlaybook
//
//  Slide-up overlay panel showing the player's play cards in hand.
//  Larger cards with cost labels and play action.
//

import SwiftUI

struct PracticePlaysPanel: View {
    let store: PracticeStore
    @Binding var isVisible: Bool

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
                if store.phase == .play && !store.playerPassedPlays {
                    Button {
                        store.playerPassPlays()
                    } label: {
                        Text("PASS PLAYS")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.nearBlack)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Design.Colors.bobaCyan))
                    }
                    .buttonStyle(.plain)
                }
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
                            playCardLarge(card: card)
                        }
                    }
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surface.opacity(0.98))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
    }

    // MARK: - Large Play Card

    private func playCardLarge(card: Card) -> some View {
        let canAfford = (card.playCost ?? 0) <= store.playerHotDogs
        let isPlayPhase = store.phase == .play

        return Button {
            guard isPlayPhase, canAfford else { return }
            store.playerPlayCard(card)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Group {
                        if let file = card.imageFile, !file.isEmpty {
                            AsyncImage(url: CDN.thumb(for: file)) { phase in
                                if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                                else { playPlaceholder(card: card) }
                            }
                        } else {
                            playPlaceholder(card: card)
                        }
                    }
                    .frame(width: 72, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                        isPlayPhase && canAfford ? Design.Colors.bobaCyan : Design.Colors.glass, lineWidth: 2))

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
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
            .opacity(isPlayPhase && !canAfford ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isPlayPhase || !canAfford)
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
