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
    /// Resolved weapons for the player's + CPU's active hero, after
    /// any persistent_weapon_transform has been applied. When these
    /// differ from the printed card.element, the hero card's weapon
    /// badge shows a "transformed" indicator so the user can see
    /// at-a-glance that an effect is changing what their hero is.
    var playerEffectiveWeapon: String = ""
    var cpuEffectiveWeapon: String    = ""

    /// Carrier for the play-card review sheet. Tapping any chip in the
    /// plays-used strip sets this; SwiftUI's `sheet(item:)` then renders
    /// PlayReviewSheet so the player can read the full ability text.
    @State private var inspectedPlay: InspectedPlay? = nil

    private struct InspectedPlay: Identifiable {
        let id = UUID()
        let card: Card
    }

    var body: some View {
        activeBattleBody
            .tutorialTarget(.activeBattle)
            .sheet(item: $inspectedPlay) { wrapper in
                PlayReviewSheet(card: wrapper.card)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
    }

    private var activeBattleBody: some View {
        VStack(spacing: 6) {
            // Battle label
            Text("BATTLE \(slot.id + 1)")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.bobaOrange)
                .padding(.top, Design.Spacing.sm)

            // Power breakdown — appears once both sides have resolved
            // their plays and the battle's outcome is locked. Itemizes
            // every modifier that contributed to either side's effect
            // power so coaches can audit the math instead of squinting
            // at a +N badge. Hidden during the play phase to keep the
            // arena uncluttered while plays are still happening.
            if slot.result != nil {
                powerBreakdownPanel
            }

            GeometryReader { geo in
                let cardH = geo.size.height - 28
                HStack(spacing: 0) {
                    // Player card (left)
                    heroCard(
                        card: slot.playerCard,
                        revealed: true,
                        isOpponent: false,
                        effectBonus: slot.playerEffectPower,
                        effectiveWeapon: playerEffectiveWeapon,
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
                        effectiveWeapon: cpuEffectiveWeapon,
                        height: cardH
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.bottom, 10)
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

    private func heroCard(card: Card?, revealed: Bool, isOpponent: Bool, effectBonus: Int, effectiveWeapon: String = "", height: CGFloat) -> some View {
        // Constrain the whole heroCard VStack to the provided height
        // so it can never overflow the orange container, regardless
        // of how many chips show in the plays-used strip below. The
        // image inside flexes (`maxHeight: .infinity`) and is the
        // only element that absorbs space pressure when chip count
        // grows.
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
                    .frame(maxHeight: .infinity)
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

                // Hero name + weapon badge. Weapon resolves through
                // the persistent_weapon_transform stack — when an
                // effect like "Only Steel" is in force, the badge
                // shows STEEL with a small ⟲ "transformed" marker so
                // the user can see the change directly on the hero.
                VStack(spacing: 2) {
                    Text(card.hero.isEmpty ? card.name : card.hero)
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(1)
                    weaponBadge(card: card, effective: effectiveWeapon)
                }
                // Plays-used-this-battle strip — players literally lose
                // count of this in physical games (transcript [00:42:40])
                // and Play Booster / 10 Per Play / No Huddle all pivot
                // on it. Showing the strip live makes the math visible.
                playsUsedStrip(plays: isOpponent ? slot.cpuPlayedCards : slot.playerPlayedCards,
                               accent: isOpponent ? Color(hex: "8B00FF") : Design.Colors.bobaCyan)
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
        .frame(height: height)
        .clipped()
    }

    // MARK: - Helpers

    /// Side-by-side itemized power breakdown shown after a battle
    /// resolves. Reads `slot.playerBreakdown` / `slot.cpuBreakdown` —
    /// each contribution becomes its own line item with a +/- delta.
    /// Foots to the same `*FinalPower` value the engine compared.
    /// Hard-coded total height of the post-battle breakdown panel.
    /// Smaller = more room for the hero cards below it. The contribs
    /// list scrolls within `breakdownContribsHeight` so even 5+ plays
    /// per side can never push the panel past this number.
    private let breakdownPanelHeight: CGFloat = 92
    private let breakdownContribsHeight: CGFloat = 36

    private var powerBreakdownPanel: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            powerBreakdownColumn(
                title: "YOU",
                base: slot.playerTransformedToHotDog ? 0 : (slot.playerCard?.power ?? 0),
                contribs: slot.playerBreakdown,
                final: slot.playerFinalPower,
                won: slot.result == .win
            )
            powerBreakdownColumn(
                title: "CPU",
                base: slot.cpuTransformedToHotDog ? 0 : (slot.cpuCard?.power ?? 0),
                contribs: slot.cpuBreakdown,
                final: slot.cpuFinalPower,
                won: slot.result == .lose
            )
        }
        .padding(.horizontal, Design.Spacing.sm)
        // Hard fixed height — `.frame(height:)` (not maxHeight)
        // forces the panel to stay this size regardless of how
        // many contribs each side accumulated.
        .frame(height: breakdownPanelHeight)
    }

    private func powerBreakdownColumn(title: String, base: Int, contribs: [PowerContribution], final: Int, won: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.2)
                Spacer(minLength: 0)
                Text("Base \(base)")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            // Contribution rows live in a fixed-height scroll viewport
            // so 5+ plays per side never expand the panel — they just
            // become scrollable. Base + Total stay outside the scroller.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(contribs) { c in
                        HStack(spacing: 4) {
                            Text(c.label)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(c.delta > 0 ? "+\(c.delta)" : "\(c.delta)")
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(c.delta > 0 ? Design.Colors.bobaCyan : Color(hex: "C0392B"))
                        }
                    }
                }
            }
            .frame(height: breakdownContribsHeight)
            Divider().background(Design.Colors.glassBorder)
            HStack(spacing: 4) {
                Text("Total")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(won ? Color(hex: "4CAF50") : Design.Colors.textSecondary)
                Spacer(minLength: 0)
                Text("\(final)")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(won ? Color(hex: "4CAF50") : Design.Colors.textPrimary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Design.Colors.surface.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(won
                        ? Color(hex: "4CAF50").opacity(0.5)
                        : Design.Colors.glassBorder, lineWidth: 1))
        )
    }

    /// Horizontal strip showing every play card used by this side
    /// during the current battle. Each play renders as a small chip
    /// with the play name; a running count appears at the leading
    /// edge. Empty when no plays have been used yet.
    @ViewBuilder
    private func playsUsedStrip(plays: [Card], accent: Color) -> some View {
        if plays.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(plays.count) PLAY\(plays.count == 1 ? "" : "S") USED")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.0)
                // Horizontal scroll with edge insets so the first/last
                // chip never sits flush against the column edge — and
                // so a partially-visible chip looks like it's scrolled,
                // not clipped. `scrollClipDisabled(false)` (default)
                // keeps overflow content invisible outside the
                // ScrollView's bounds.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(plays.enumerated()), id: \.offset) { _, card in
                            Button {
                                inspectedPlay = InspectedPlay(card: card)
                            } label: {
                                Text(card.name)
                                    .font(Design.Fonts.mono(10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.72))
                                            .overlay(Capsule().strokeBorder(accent.opacity(0.85), lineWidth: 1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .contentMargins(.horizontal, 2, for: .scrollContent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Small weapon pill rendered under each hero. When `effective`
    /// is non-empty AND differs from the card's printed element, the
    /// pill shows the transformed weapon with a ⟲ icon so it reads
    /// as "this hero's weapon is currently being changed."
    private func weaponBadge(card: Card, effective: String) -> some View {
        let printed = card.element
        let display = effective.isEmpty ? printed : effective
        let isTransformed = !effective.isEmpty && effective != printed
        return HStack(spacing: 3) {
            if isTransformed {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(display)
                .font(Design.Fonts.mono(9, weight: .bold))
        }
        .foregroundStyle(isTransformed ? Color(hex: "8B00FF") : Design.Colors.element(display))
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill((isTransformed ? Color(hex: "8B00FF") : Design.Colors.element(display)).opacity(0.15))
                .overlay(Capsule().strokeBorder(
                    (isTransformed ? Color(hex: "8B00FF") : Design.Colors.element(display)).opacity(0.5),
                    lineWidth: 1
                ))
        )
    }

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

// ════════════════════════════════════════════════════════════════
// MARK: - PlayReviewSheet
// ════════════════════════════════════════════════════════════════
//
// Modal that opens when a player taps a chip in the plays-used strip
// (or any other surface that wants to show a single play card's full
// details). Mirrors the look of the CPU play overlay so review reads
// as the same visual language as in-the-moment notification.

struct PlayReviewSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if let file = card.imageFile, !file.isEmpty {
                        // Fixed 5:7 box (160×224) so the rounded border
                        // hugs the card image instead of stretching to
                        // VStack width. Outer frame centers it.
                        CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fill)
                            .frame(width: 160, height: 224)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Design.Colors.bobaViolet.opacity(0.5), lineWidth: 2)
                            )
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(Design.Fonts.display(22))
                            .foregroundStyle(Design.Colors.textPrimary)
                        HStack(spacing: 8) {
                            if let cost = card.playCost {
                                Text(cost == 0 ? "FREE" : "\(cost) HD")
                                    .font(Design.Fonts.mono(11, weight: .bold))
                                    .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill((cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan).opacity(0.15)))
                            }
                            if card.isBonusPlay == true {
                                Text("★ BONUS")
                                    .font(Design.Fonts.mono(10, weight: .bold))
                                    .foregroundStyle(Design.Colors.nearBlack)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color(hex: "FFD700")))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("EFFECT")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        Text(card.playAbility ?? "No effect text on file.")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.md)
                            .fill(Design.Colors.surface)
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                                .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                    )
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
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
    }
}
