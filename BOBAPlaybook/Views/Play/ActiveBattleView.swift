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
    /// Monotonic pulse counters from the store — bump to trigger
    /// a one-shot scale + glow on the relevant hero card whenever
    /// that side's effect power changes.
    var playerPulseTrigger: Int = 0
    var cpuPulseTrigger: Int = 0

    @State private var playerPulse: Bool = false
    @State private var cpuPulse: Bool = false

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
            // Pulse the affected hero on every store-side bump.
            // The .task(id:) blocks fire whenever the trigger int
            // changes; toggling the local `pulse` bool runs a one
            // -shot scale+glow animation tied to the hero card.
            .task(id: playerPulseTrigger) {
                guard playerPulseTrigger > 0 else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { playerPulse = true }
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.easeOut(duration: 0.4)) { playerPulse = false }
            }
            .task(id: cpuPulseTrigger) {
                guard cpuPulseTrigger > 0 else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { cpuPulse = true }
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.easeOut(duration: 0.4)) { cpuPulse = false }
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
                if isSuperTiebreaker {
                    superTiebreakerBanner
                }
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
                    .scaleEffect(playerPulse ? 1.06 : 1.0)
                    .shadow(color: Design.Colors.bobaCyan.opacity(playerPulse ? 0.85 : 0),
                            radius: playerPulse ? 18 : 0)

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
                    .scaleEffect(cpuPulse ? 1.06 : 1.0)
                    .shadow(color: Color(hex: "C77DFF").opacity(cpuPulse ? 0.85 : 0),
                            radius: cpuPulse ? 18 : 0)
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

    /// True when the result was decided by the SUPER tiebreaker
    /// (Comprehensive Rules Guide §4.5). Surfacing this teaches new
    /// coaches the rule at the moment it actually costs them — they
    /// see the totals tied + a SUPER-weapon hero on one side, and
    /// the result is no longer mysterious.
    private var isSuperTiebreaker: Bool {
        guard mode == .playmaker, let result = slot.result, result != .tie else { return false }
        let playerTotal = (slot.playerCard?.power ?? 0) + slot.playerEffectPower
        let cpuTotal    = (slot.cpuCard?.power    ?? 0) + slot.cpuEffectPower
        guard playerTotal == cpuTotal else { return false }
        let playerWeapon = playerEffectiveWeapon.isEmpty ? (slot.playerCard?.element ?? "") : playerEffectiveWeapon
        let cpuWeapon    = cpuEffectiveWeapon.isEmpty    ? (slot.cpuCard?.element    ?? "") : cpuEffectiveWeapon
        return (playerWeapon == "SUPER") != (cpuWeapon == "SUPER")
    }

    /// Full-width banner explaining a SUPER tiebreaker resolution.
    /// Renders only when isSuperTiebreaker == true. Names the SUPER
    /// hero by its display name and points at the rule so coaches can
    /// look it up.
    @ViewBuilder
    private var superTiebreakerBanner: some View {
        let result = slot.result
        let winnerCard = result == .win ? slot.playerCard : slot.cpuCard
        let winnerName = winnerCard?.hero ?? winnerCard?.name ?? "SUPER hero"
        let totalText = "\(slot.playerFinalPower)"
        HStack(spacing: 8) {
            Text("⚡")
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("SUPER WEAPON BREAKS TIE")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Color(hex: "FF00FF"))
                    .tracking(1.0)
                Text("Both heroes tied at \(totalText) power. \(winnerName)'s SUPER weapon wins automatically (Rules §4.5).")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "FF00FF").opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: "FF00FF").opacity(0.45), lineWidth: 1)
                )
        )
        .padding(.horizontal, Design.Spacing.sm)
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
                //
                // `.layoutPriority(1)` ensures the name + weapon
                // badge claim their natural size before the image
                // (priority 0) gets to flex. Without this, when the
                // breakdown panel grows tall enough to squeeze the
                // hero card area, the badge would get clipped at
                // the bottom of the orange container instead of the
                // image absorbing the space pressure.
                VStack(spacing: 2) {
                    Text(card.hero.isEmpty ? card.name : card.hero)
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(1)
                    weaponBadge(card: card, effective: effectiveWeapon)
                }
                .layoutPriority(1)
                // Plays-used-this-battle strip — players literally lose
                // count of this in physical games (transcript [00:42:40])
                // and Play Booster / 10 Per Play / No Huddle all pivot
                // on it. Showing the strip live makes the math visible.
                //
                // Hidden once the battle resolves — the breakdown panel
                // above already itemizes every contributing play by
                // name + delta, so the strip becomes redundant and just
                // competes for vertical space against the hero cards.
                if slot.result == nil {
                    playsUsedStrip(plays: isOpponent ? slot.cpuPlayedCards : slot.playerPlayedCards,
                                   accent: isOpponent ? Color(hex: "8B00FF") : Design.Colors.bobaCyan)
                }
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
    /// The breakdown panel sizes naturally to its tallest column —
    /// a single Heads-Up contrib renders short, a battle with 4
    /// plays + Heads-Up + a persistent trigger renders tall. We cap
    /// the inner contribs container at `breakdownContribsMaxHeight`
    /// so a chained 8-contrib battle scrolls inside the cap rather
    /// than swallowing the whole hero-card area.
    private let breakdownContribsMaxHeight: CGFloat = 110

    private var powerBreakdownPanel: some View {
        // Pool of every card played in this battle on either side —
        // used to resolve a contrib row's label back to its Card so
        // the row can open the same PlayReviewSheet the chips opened.
        let allPlays = slot.playerPlayedCards + slot.cpuPlayedCards
        // Tallest column drives the panel height so both sides stay
        // visually aligned even when one side has more contribs than
        // the other.
        let maxContribs = max(slot.playerBreakdown.count, slot.cpuBreakdown.count)

        return HStack(alignment: .top, spacing: Design.Spacing.sm) {
            powerBreakdownColumn(
                title: "YOU",
                base: slot.playerTransformedToHotDog ? 0 : (slot.playerCard?.power ?? 0),
                contribs: slot.playerBreakdown,
                final: slot.playerFinalPower,
                won: slot.result == .win,
                rowsToShow: maxContribs,
                playPool: allPlays
            )
            powerBreakdownColumn(
                title: "CPU",
                base: slot.cpuTransformedToHotDog ? 0 : (slot.cpuCard?.power ?? 0),
                contribs: slot.cpuBreakdown,
                final: slot.cpuFinalPower,
                won: slot.result == .lose,
                rowsToShow: maxContribs,
                playPool: allPlays
            )
        }
        .padding(.horizontal, Design.Spacing.sm)
        // No fixed height — the panel sizes to its content. One
        // Heads-Up contrib renders short; a 6-contrib battle renders
        // tall (capped via the inner container so the hero cards
        // below can never starve).
    }

    /// Strip parenthetical attribution suffixes the engine appends to
    /// disambiguate cross-side contributions ("Weapon Tangle (you
    /// played)") so the bare card name can be matched against the
    /// played-card pool.
    private func cardNameFromLabel(_ label: String) -> String {
        if let openParen = label.firstIndex(of: "(") {
            return label[..<openParen].trimmingCharacters(in: .whitespaces)
        }
        return label
    }

    private func powerBreakdownColumn(title: String, base: Int, contribs: [PowerContribution], final: Int, won: Bool, rowsToShow: Int, playPool: [Card]) -> some View {
        // Row height: mono(12) text + 1pt VStack spacing ≈ 14pt per
        // row. Cap the visible rows at 7 so a chained mega-battle
        // still leaves the hero cards a usable area below.
        let perRow: CGFloat = 14
        let visibleRows = min(rowsToShow, 7)
        let contribsHeight = max(perRow, CGFloat(visibleRows) * perRow)

        return VStack(alignment: .leading, spacing: 3) {
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
            // Contribution rows. Container height tracks the tallest
            // side's contrib count — so 1 Heads-Up renders a short
            // panel, 5 contribs renders taller. Capped at
            // breakdownContribsMaxHeight; if the cap kicks in, this
            // ScrollView absorbs the overflow instead of pushing the
            // hero cards offscreen.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(contribs) { c in
                        contribRow(c, playPool: playPool)
                    }
                }
            }
            .frame(height: min(contribsHeight, breakdownContribsMaxHeight))
            Divider().background(Design.Colors.glassBorder)
            HStack(spacing: 4) {
                Text("Total")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(won ? Color(hex: "4CAF50") : Design.Colors.textSecondary)
                Spacer(minLength: 0)
                Text("\(final)")
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(won ? Color(hex: "4CAF50") : Design.Colors.textPrimary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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

    /// One contribution line. If we can resolve a Card for the row's
    /// label, the row becomes a Button that opens PlayReviewSheet —
    /// preserving the tap-to-review behavior that lived on the chip
    /// strip before chips were hidden post-resolution.
    @ViewBuilder
    private func contribRow(_ c: PowerContribution, playPool: [Card]) -> some View {
        let baseName = cardNameFromLabel(c.label)
        let resolvedCard = playPool.first(where: { $0.name == baseName })
        let row = HStack(spacing: 4) {
            Text(c.label)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(resolvedCard != nil
                                 ? Design.Colors.bobaCyan
                                 : Design.Colors.textSecondary)
                .underline(resolvedCard != nil, color: Design.Colors.bobaCyan.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(c.delta == 0 ? "—" : (c.delta > 0 ? "+\(c.delta)" : "\(c.delta)"))
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(c.delta == 0
                                 ? Design.Colors.textMuted
                                 : (c.delta > 0 ? Design.Colors.bobaCyan : Color(hex: "C0392B")))
        }
        if let card = resolvedCard {
            Button {
                inspectedPlay = InspectedPlay(card: card)
            } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// Horizontal strip showing every play card used by this side
    /// during the current battle. Each play renders as a small chip
    /// with the play name; a running count appears at the leading
    /// edge. Empty when no plays have been used yet.
    ///
    /// Total strip height is hard-pinned at 38pt (12pt header + 2pt
    /// gap + 24pt chip row) so the heroCard VStack can never grow
    /// vertically when more plays accumulate — they just become
    /// horizontally scrollable.
    @ViewBuilder
    private func playsUsedStrip(plays: [Card], accent: Color) -> some View {
        if plays.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
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
                .frame(height: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38, alignment: .top)
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
