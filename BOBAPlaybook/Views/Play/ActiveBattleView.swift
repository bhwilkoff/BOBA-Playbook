//
//  ActiveBattleView.swift
//  BOBAPlaybook
//
//  Large side-by-side view for the current/active battle.
//  Shows full card art for both player and CPU heroes.
//  Includes phase-appropriate action buttons overlaid on the battle.
//

import SwiftUI

struct ActiveBattleView: View {
    let slot: BattleSlot
    let phase: BattlePhase
    let mode: PracticeMode

    var body: some View {
        activeBattleBody.tutorialTarget(.activeBattle)
    }

    private var activeBattleBody: some View {
        VStack(spacing: 6) {
            // Battle label
            Text("BATTLE \(slot.id + 1)")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.bobaOrange)
                .padding(.top, Design.Spacing.sm)

            GeometryReader { geo in
                let cardH = geo.size.height - 28
                HStack(spacing: 0) {
                    // Player card (left)
                    heroCard(
                        card: slot.playerCard,
                        revealed: true,
                        isOpponent: false,
                        effectBonus: slot.playerEffectPower,
                        height: cardH
                    )
                    .frame(maxWidth: .infinity)

                    // VS indicator
                    vsIndicator
                        .frame(width: 44)

                    // CPU card (right)
                    heroCard(
                        card: slot.isRevealed ? slot.cpuCard : nil,
                        revealed: slot.isRevealed,
                        isOpponent: true,
                        effectBonus: slot.cpuEffectPower,
                        height: cardH
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Design.Colors.bobaOrange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 2)
                )
        )
    }

    // MARK: - VS Indicator

    private var vsIndicator: some View {
        VStack(spacing: 4) {
            Spacer()
            if let result = slot.result {
                Text(result == .win ? "WIN" : (result == .lose ? "LOSS" : "TIE"))
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(resultColor(result))
            } else {
                Text("VS")
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
            Spacer()
        }
    }

    // MARK: - Hero Card

    private func heroCard(card: Card?, revealed: Bool, isOpponent: Bool, effectBonus: Int, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            if let card = card {
                ZStack(alignment: .bottom) {
                    // Card image
                    Group {
                        if let file = card.imageFile, !file.isEmpty {
                            CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fill)
                        } else {
                            placeholderFace(card: card, isOpponent: isOpponent)
                        }
                    }
                    .frame(maxHeight: height - 20)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Design.Colors.element(card.element).opacity(0.5), lineWidth: 2)
                    )

                    // Power badge
                    HStack(spacing: 4) {
                        if effectBonus != 0 {
                            Text(effectBonus > 0 ? "+\(effectBonus)" : "\(effectBonus)")
                                .font(Design.Fonts.mono(12, weight: .bold))
                                .foregroundStyle(effectBonus > 0 ? Design.Colors.bobaCyan : Color(hex: "C0392B"))
                        }
                        Text("\((card.power ?? 0) + effectBonus)")
                            .font(Design.Fonts.display(28))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .shadow(color: .black, radius: 4)
                    .padding(.bottom, 6)
                }

                // Hero name
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
            } else {
                // Facedown card
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOpponent ? Color(hex: "C0392B").opacity(0.2) : Design.Colors.bobaOrange.opacity(0.15))
                    .aspectRatio(5.0/7.0, contentMode: .fit)
                    .frame(maxHeight: height - 20)
                    .overlay(
                        Image(systemName: "shield.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(isOpponent ? Color(hex: "C0392B").opacity(0.4) : Design.Colors.bobaOrange.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Design.Colors.glass, lineWidth: 1)
                    )

                Text(isOpponent ? "CPU" : "YOU")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
    }

    // MARK: - Helpers

    private func placeholderFace(card: Card, isOpponent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Design.Colors.element(card.element).opacity(isOpponent ? 0.15 : 0.25))
            .aspectRatio(5.0/7.0, contentMode: .fit)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 24))
                    Text(String(card.hero.prefix(5)).uppercased())
                        .font(Design.Fonts.display(16))
                }
                .foregroundStyle(Design.Colors.element(card.element).opacity(0.6))
            )
    }

    private func resultColor(_ result: BattleResult) -> Color {
        switch result {
        case .win:  return Color(hex: "4CAF50")
        case .lose: return Color(hex: "C0392B")
        case .tie:  return Design.Colors.textMuted
        }
    }
}
