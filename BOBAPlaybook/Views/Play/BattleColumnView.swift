//
//  BattleColumnView.swift
//  BOBAPlaybook
//
//  Single battle column: CPU hero on top, VS bar, player hero on bottom.
//  Used inside the scrollable practice arena.
//

import SwiftUI

struct BattleColumnView: View {
    let slot: BattleSlot
    let isActive: Bool
    let phase: BattlePhase
    let mode: PracticeMode
    var pendingPlayerBonus: Int = 0
    var pendingCpuBonus: Int = 0

    private var vsBarColor: Color {
        switch slot.result {
        case .win:  return Color(hex: "4CAF50")
        case .lose: return Color(hex: "C0392B")
        case .tie:  return Design.Colors.textMuted
        case nil:   return isActive ? Design.Colors.bobaOrange.opacity(0.6) : Design.Colors.glass
        }
    }

    var body: some View {
        GeometryReader { geo in
            let colW = geo.size.width
            let colH = geo.size.height
            let cardW = colW - 8
            let vsH: CGFloat = 24
            let labelH: CGFloat = 16
            let heroH = (colH - vsH - labelH) * 0.5

            VStack(spacing: 0) {
                // Battle label
                Text("B\(slot.id + 1)")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(isActive ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                    .frame(height: labelH)

                // CPU hero (top half)
                Group {
                    if slot.isRevealed, let card = slot.cpuCard {
                        cardFace(card: card, width: cardW, height: heroH, isOpponent: true, effectBonus: slot.cpuEffectPower, pendingBonus: 0)
                    } else {
                        facedownCard(width: cardW, height: heroH, isOpponent: true, pendingBonus: pendingCpuBonus)
                    }
                }
                .frame(width: cardW, height: heroH)

                // VS divider
                vsBar(height: vsH)

                // Player hero (bottom half)
                Group {
                    if let card = slot.playerCard {
                        cardFace(card: card, width: cardW, height: heroH, isOpponent: false,
                                 effectBonus: slot.playerEffectPower,
                                 pendingBonus: slot.isRevealed ? 0 : pendingPlayerBonus)
                    } else {
                        facedownCard(width: cardW, height: heroH, isOpponent: false, pendingBonus: pendingPlayerBonus)
                    }
                }
                .frame(width: cardW, height: heroH)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Design.Colors.bobaOrange.opacity(0.06) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isActive ? Design.Colors.bobaOrange.opacity(0.5) : Color.clear, lineWidth: 2)
                )
        )
        .opacity(slot.result == nil && !isActive ? 0.4 : 1)
    }

    // MARK: - VS Bar

    private func vsBar(height: CGFloat) -> some View {
        ZStack {
            vsBarColor.clipShape(RoundedRectangle(cornerRadius: 4))
            Text(slot.result == nil ? "VS" : (slot.result == .win ? "WIN" : (slot.result == .lose ? "LOSS" : "TIE")))
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(height: height)
        .padding(.horizontal, 4)
    }

    // MARK: - Card Face

    private func cardFace(card: Card, width: CGFloat, height: CGFloat, isOpponent: Bool, effectBonus: Int = 0, pendingBonus: Int = 0) -> some View {
        ZStack(alignment: .bottom) {
            if let file = card.imageFile, !file.isEmpty {
                CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
            } else {
                placeholderFace(card: card, isOpponent: isOpponent)
            }

            // Gradient + power overlay
            LinearGradient(
                colors: [.black.opacity(0.9), .black.opacity(0.4), .clear],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: height * 0.5)

            VStack(spacing: 1) {
                // Hero name
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if effectBonus != 0 {
                        Text(effectBonus > 0 ? "+\(effectBonus)" : "\(effectBonus)")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(effectBonus > 0 ? Design.Colors.bobaCyan : Color(hex: "C0392B"))
                    }
                    Text("\(max(0, (card.power ?? 0) + effectBonus))")
                        .font(Design.Fonts.display(height > 80 ? 24 : 20))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black, radius: 3)

                // Pending persistent preview (dotted) — shown on unrevealed future battles
                if pendingBonus != 0 {
                    Text(pendingBonus > 0 ? "+\(pendingBonus) pending" : "\(pendingBonus) pending")
                        .font(Design.Fonts.mono(8, weight: .bold))
                        .foregroundStyle(pendingBonus > 0 ? Design.Colors.bobaCyan : Color(hex: "C0392B"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [2,2]))
                            .foregroundStyle(pendingBonus > 0 ? Design.Colors.bobaCyan.opacity(0.6) : Color(hex: "C0392B").opacity(0.6)))
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: width, maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Placeholder & Facedown

    private func placeholderFace(card: Card, isOpponent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Design.Colors.element(card.element).opacity(isOpponent ? 0.15 : 0.25))
            .overlay(
                Text(String(card.hero.prefix(3)).uppercased())
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.element(card.element).opacity(0.7))
            )
    }

    private func facedownCard(width: CGFloat, height: CGFloat, isOpponent: Bool, pendingBonus: Int = 0) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isOpponent ? Color(hex: "C0392B").opacity(0.2) : Design.Colors.bobaOrange.opacity(0.15))
                .overlay(
                    Image(systemName: "shield.fill")
                        .font(.system(size: height * 0.2))
                        .foregroundStyle(isOpponent ? Color(hex: "C0392B").opacity(0.4) : Design.Colors.bobaOrange.opacity(0.4))
                )

            if pendingBonus != 0 {
                Text(pendingBonus > 0 ? "+\(pendingBonus) pending" : "\(pendingBonus) pending")
                    .font(Design.Fonts.mono(8, weight: .bold))
                    .foregroundStyle(pendingBonus > 0 ? Design.Colors.bobaCyan : Color(hex: "C0392B"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(.bottom, 4)
            }
        }
    }
}
