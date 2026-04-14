//
//  PracticeView.swift
//  BOBAPlaybook
//
//  Landscape-only playmat for Practice Battle mode.
//  Three bands: top bar (score + phase) · center (7 battle columns) · player zone.
//  All custom SVG icons — no emoji.
//

import SwiftUI

// ════════════════════════════════════════════════════════════════
// MARK: - PracticeView
// ════════════════════════════════════════════════════════════════

struct PracticeView: View {
    let store: PracticeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showExitConfirm = false
    @State private var selectedBenchIdx: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.width < geo.size.height
            ZStack {
                Design.Colors.nearBlack.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Top Bar ─────────────────────────────────────────────
                    topBar
                        .frame(height: topBarHeight(geo))

                    // ── Opponent Zone ────────────────────────────────────────
                    opponentZone
                        .frame(height: opponentZoneHeight(geo))

                    // ── Arena (7 battle columns) ─────────────────────────────
                    arenaZone(geo: geo)

                    // ── Player Zone ──────────────────────────────────────────
                    playerZone(geo: geo)
                }

                // ── Match Over Overlay ───────────────────────────────────────
                if store.matchOver {
                    matchOverOverlay
                }

                // ── Phase Banner ─────────────────────────────────────────────
                if store.phase == .reveal && !store.battles.isEmpty && !store.battles[store.currentBattle].isRevealed {
                    phaseBanner
                }
            }
            // ── Portrait Orientation Prompt — overlaid on the full view ───────
            .overlay {
                if portrait {
                    ZStack {
                        Color.black.opacity(0.93).ignoresSafeArea()
                        VStack(spacing: Design.Spacing.xl) {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 56))
                                .foregroundStyle(Design.Colors.bobaOrange)
                                .rotationEffect(.degrees(90))
                            Text("ROTATE TO PLAY")
                                .font(Design.Fonts.display(28))
                                .foregroundStyle(Design.Colors.textPrimary)
                            Text("Practice Battle requires landscape orientation")
                                .font(Design.Fonts.mono(13))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(Design.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea(.all, edges: .horizontal)
        .onAppear { Task { @MainActor in OrientationManager.shared.lockLandscape() } }
        .onDisappear { Task { @MainActor in OrientationManager.shared.lockPortrait() } }
        .alert("Exit Practice?", isPresented: $showExitConfirm) {
            Button("Exit", role: .destructive) { dismiss() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Your progress will be lost.")
        }
    }

    // MARK: - Height helpers

    private func topBarHeight(_ geo: GeometryProxy) -> CGFloat { geo.size.height > 400 ? 44 : 36 }
    private func opponentZoneHeight(_ geo: GeometryProxy) -> CGFloat { 60 }
    private func playerZoneHeight(_ geo: GeometryProxy) -> CGFloat { geo.size.height > 400 ? 110 : 90 }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Top Bar
    // ════════════════════════════════════════════════════════════════

    private var topBarModeTabs: some View {
        HStack(spacing: 4) {
            ForEach(PracticeMode.allCases) { mode in
                let isSelected = store.mode == mode
                Button {
                    if store.matchOver { store.mode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(Design.Fonts.mono(10, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Design.Colors.nearBlack : Design.Colors.textMuted)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(isSelected ? Design.Colors.bobaOrange : Design.Colors.glass))
                }
                .buttonStyle(.plain)
                .disabled(!store.matchOver)
            }
        }
    }

    private var topBarScoreboard: some View {
        HStack(spacing: 8) {
            Text("\(store.playerScore)")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Color(hex: "4CAF50"))
            battlePips
            Text("\(store.cpuScore)")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Color(hex: "C0392B"))
        }
    }

    private var topBarTrailing: some View {
        HStack(spacing: Design.Spacing.md) {
            phaseIndicator
            Button {
                showExitConfirm = true
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            topBarModeTabs.padding(.leading, Design.Spacing.md)
            Spacer()
            topBarScoreboard
            Spacer()
            topBarTrailing.padding(.trailing, Design.Spacing.md)
        }
        .background(Design.Colors.surface.opacity(0.95))
        .overlay(Divider().background(Design.Colors.glass), alignment: .bottom)
    }

    private var battlePips: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(pipColor(for: i))
                    .frame(width: 10, height: 10)
                    .overlay(
                        i == store.currentBattle && !store.matchOver
                        ? Circle().strokeBorder(Design.Colors.bobaOrange, lineWidth: 2) : nil
                    )
            }
        }
    }

    private func pipColor(for index: Int) -> Color {
        guard index < store.battles.count else { return Design.Colors.glass }
        switch store.battles[index].result {
        case .win:  return Color(hex: "4CAF50")
        case .lose: return Color(hex: "C0392B")
        case .tie:  return Design.Colors.textMuted
        case nil:
            return index == store.currentBattle ? Design.Colors.bobaOrange.opacity(0.4) : Design.Colors.glass
        }
    }

    private var phaseIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: store.phase.icon)
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text(store.phase.rawValue.uppercased())
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Opponent Zone
    // ════════════════════════════════════════════════════════════════

    private var opponentZone: some View {
        HStack(spacing: 0) {
            Text("OPP").font(Design.Fonts.mono(9, weight: .bold)).foregroundStyle(Design.Colors.textMuted)
                .rotationEffect(.degrees(-90)).frame(width: 20)

            // CPU bench
            if store.mode.showBench {
                HStack(spacing: 4) {
                    ForEach(store.cpuBench.prefix(4)) { card in
                        facedownHeroMini(element: card.element)
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            // CPU resources
            VStack(alignment: .trailing, spacing: 2) {
                if store.mode.showHotDogs {
                    Label("\(store.cpuHotDogs)/10", systemImage: "cloud.fill")
                        .font(Design.Fonts.mono(10)).foregroundStyle(Color(hex: "4CAF50"))
                }
                if store.mode.showPlays {
                    Label("\(store.cpuPlaysRemaining)", systemImage: "rectangle.stack")
                        .font(Design.Fonts.mono(10)).foregroundStyle(Design.Colors.bobaViolet)
                }
            }
            .padding(.trailing, Design.Spacing.md)
        }
        .background(Design.Colors.surface.opacity(0.5))
        .overlay(Divider().background(Design.Colors.glass), alignment: .bottom)
    }

    private func facedownHeroMini(element: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "C0392B").opacity(0.2))
            .frame(width: 28, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: "C0392B").opacity(0.4), lineWidth: 1))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: "C0392B").opacity(0.5))
            )
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Arena (7 Battle Columns)
    // ════════════════════════════════════════════════════════════════

    private func arenaZone(geo: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            ForEach(store.battles) { slot in
                BattleColumnView(
                    slot: slot,
                    isActive: slot.id == store.currentBattle,
                    phase: store.phase,
                    mode: store.mode
                )
            }
        }
        .padding(.horizontal, Design.Spacing.xs)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Player Zone
    // ════════════════════════════════════════════════════════════════

    private func playerZone(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Divider().background(Design.Colors.glass)
            HStack(alignment: .top, spacing: 0) {
                // Hero deck stack
                VStack(spacing: 2) {
                    heroStackIcon
                    Text("\(store.playerHeroDeck.count)").font(Design.Fonts.mono(10)).foregroundStyle(Design.Colors.textMuted)
                    Text("DECK").font(Design.Fonts.mono(8)).foregroundStyle(Design.Colors.textMuted)
                }
                .frame(width: 40)
                .padding(.leading, Design.Spacing.sm)

                Divider().background(Design.Colors.glass).padding(.horizontal, 4)

                // Bench
                if store.mode.showBench {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR BENCH").font(Design.Fonts.mono(8, weight: .bold)).foregroundStyle(Design.Colors.textMuted)
                        HStack(spacing: 4) {
                            ForEach(Array(store.playerBench.enumerated()), id: \.offset) { idx, card in
                                Button {
                                    guard store.phase == .sub, !store.playerSubstituted else { return }
                                    selectedBenchIdx = selectedBenchIdx == idx ? nil : idx
                                } label: {
                                    benchCard(card: card, active: store.phase == .sub && !store.playerSubstituted, selected: selectedBenchIdx == idx)
                                }
                                .buttonStyle(.plain)
                                .disabled(store.phase != .sub || store.playerSubstituted)
                            }
                        }
                        if store.phase == .sub && !store.playerSubstituted {
                            Button {
                                if let idx = selectedBenchIdx {
                                    store.playerSubstitute(benchIndex: idx)
                                    selectedBenchIdx = nil
                                }
                            } label: {
                                Text("SUBSTITUTE (2 HD)")
                                    .font(Design.Fonts.mono(8, weight: .bold))
                                    .foregroundStyle(selectedBenchIdx != nil && store.playerHotDogs >= 2 ? Design.Colors.nearBlack : Design.Colors.textMuted)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedBenchIdx != nil && store.playerHotDogs >= 2 ? Design.Colors.bobaOrange : Design.Colors.glass))
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedBenchIdx == nil || store.playerHotDogs < 2)
                        }
                    }
                    .padding(.horizontal, 4)
                    .opacity(store.phase == .sub ? 1 : 0.4)
                    .onChange(of: store.phase) { _, _ in selectedBenchIdx = nil }

                    Divider().background(Design.Colors.glass).padding(.horizontal, 4)
                }

                // Hand (play cards)
                if store.mode.showPlays {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PLAYS (TAP TO PLAY)").font(Design.Fonts.mono(8, weight: .bold)).foregroundStyle(Design.Colors.textMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(store.playerHand) { card in
                                    Button {
                                        guard store.phase == .play else { return }
                                        store.playerPlayCard(card)
                                    } label: {
                                        playCardMini(card: card, active: store.phase == .play)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.phase != .play || (card.playCost ?? 0) > store.playerHotDogs)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .opacity(store.phase == .play ? 1 : 0.4)

                    Divider().background(Design.Colors.glass).padding(.horizontal, 4)
                }

                Spacer()

                // Hot Dog resources
                if store.mode.showHotDogs {
                    VStack(spacing: 2) {
                        Text("HOT DOGS").font(Design.Fonts.mono(8, weight: .bold)).foregroundStyle(Color(hex: "4CAF50"))
                        Text("\(store.playerHotDogs)/10")
                            .font(Design.Fonts.display(16))
                            .foregroundStyle(Color(hex: "4CAF50"))
                        hotDogPips
                    }
                    .frame(width: 56)
                    .padding(.horizontal, 4)

                    Divider().background(Design.Colors.glass).padding(.horizontal, 4)
                }

                // Action button
                VStack(spacing: 6) {
                    if store.phase == .sub && !store.playerSubstituted {
                        Button("PASS SUBS") { store.advancePhase() }
                            .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.textMuted))
                    } else if store.phase == .play && !store.playerPassedPlays {
                        Button("PASS PLAYS") { store.playerPassPlays() }
                            .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaCyan))
                    } else {
                        Button(nextButtonLabel) { store.advancePhase() }
                            .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
                    }
                }
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.trailing, Design.Spacing.sm)
            }
            .padding(.vertical, Design.Spacing.xs)
        }
        .background(Design.Colors.surface.opacity(0.9))
    }

    private var nextButtonLabel: String {
        switch store.phase {
        case .reveal:     return "REVEAL"
        case .sub:        return "DONE SUBS"
        case .play:       return "DONE PLAYS"
        case .resolution: return "NEXT"
        case .cleanup:    return "NEXT BATTLE"
        case .matchOver:  return "DONE"
        }
    }

    private var heroStackIcon: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "C0392B").opacity(0.3))
            .frame(width: 28, height: 40)
            .overlay(Image(systemName: "person.fill").foregroundStyle(Color(hex: "C0392B").opacity(0.8)))
    }

    private func benchCard(card: Card, active: Bool, selected: Bool = false) -> some View {
        VStack(spacing: 2) {
            Group {
                if let file = card.imageFile, !file.isEmpty {
                    AsyncImage(url: CDN.thumb(for: file)) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        else { RoundedRectangle(cornerRadius: 4).fill(Design.Colors.glass) }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Design.Colors.glass)
                }
            }
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4).strokeBorder(
                    selected ? Design.Colors.bobaCyan : (active ? Design.Colors.bobaOrange.opacity(0.5) : Design.Colors.element(card.element).opacity(0.3)),
                    lineWidth: selected ? 2.5 : (active ? 1.5 : 1)
                )
            )
            .overlay(
                selected ? RoundedRectangle(cornerRadius: 4).fill(Design.Colors.bobaCyan.opacity(0.15)) : nil
            )

            Text("\(card.power ?? 0)")
                .font(Design.Fonts.display(12))
                .foregroundStyle(selected ? Design.Colors.bobaCyan : Design.Colors.textPrimary)
        }
    }

    private func playCardMini(card: Card, active: Bool) -> some View {
        let canAfford = (card.playCost ?? 0) <= store.playerHotDogs
        return VStack(spacing: 2) {
            Group {
                if let file = card.imageFile, !file.isEmpty {
                    AsyncImage(url: CDN.thumb(for: file)) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        else { RoundedRectangle(cornerRadius: 4).fill(Design.Colors.glass) }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Design.Colors.glass)
                }
            }
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                active && canAfford ? Design.Colors.bobaCyan : Design.Colors.glass, lineWidth: 1.5))
            .opacity(active && !canAfford ? 0.4 : 1)

            Text(card.playCost == 0 ? "FREE" : "\(card.playCost ?? 0)HD")
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        }
    }

    private var hotDogPips: some View {
        LazyVGrid(columns: [GridItem(.fixed(14)), GridItem(.fixed(14)), GridItem(.fixed(14)), GridItem(.fixed(14)), GridItem(.fixed(14))], spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                Button {
                    // Tap pip i: if all pips 0..i are filled, tapping pip i removes it (spends to i)
                    // If pip i is empty, tapping it fills up to i+1 (recovers)
                    let newVal = i < store.playerHotDogs ? i : i + 1
                    store.playerHotDogs = newVal
                } label: {
                    Circle()
                        .fill(i < store.playerHotDogs ? Color(hex: "4CAF50") : Design.Colors.glass)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color(hex: "4CAF50").opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Match Over Overlay
    // ════════════════════════════════════════════════════════════════

    private var matchOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: Design.Spacing.lg) {
                if let winner = store.matchWinner {
                    if winner == .player {
                        Text("VICTORY!").font(Design.Fonts.display(48)).foregroundStyle(Color(hex: "4CAF50"))
                        Text("You won the match").font(Design.Fonts.mono(16)).foregroundStyle(Design.Colors.textSecondary)
                    } else {
                        Text("DEFEAT").font(Design.Fonts.display(48)).foregroundStyle(Color(hex: "C0392B"))
                        Text("CPU won the match").font(Design.Fonts.mono(16)).foregroundStyle(Design.Colors.textSecondary)
                    }
                } else {
                    Text("SUDDEN DEATH").font(Design.Fonts.display(36)).foregroundStyle(Design.Colors.bobaOrange)
                    Text("The match ended in a tie").font(Design.Fonts.mono(16)).foregroundStyle(Design.Colors.textSecondary)
                }

                Text("\(store.playerScore) — \(store.cpuScore)")
                    .font(Design.Fonts.display(32))
                    .foregroundStyle(Design.Colors.textPrimary)

                HStack(spacing: Design.Spacing.lg) {
                    Button("PLAY AGAIN") {
                        store.startMatch(allCards: [])
                    }
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
                    // store.allCardsPool is reused inside startMatch when allCards is empty

                    Button("EXIT") { dismiss() }
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.glass))
                }
            }
            .padding(Design.Spacing.xl)
            .background(RoundedRectangle(cornerRadius: 20).fill(Design.Colors.surface).shadow(color: .black.opacity(0.5), radius: 20))
        }
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Phase Banner
    // ════════════════════════════════════════════════════════════════

    private var phaseBanner: some View {
        VStack {
            Spacer()
            Text(store.phase.rawValue.uppercased())
                .font(Design.Fonts.display(36))
                .foregroundStyle(Design.Colors.bobaOrange)
                .padding(.horizontal, Design.Spacing.xl)
                .padding(.vertical, Design.Spacing.lg)
                .background(RoundedRectangle(cornerRadius: 16).fill(Design.Colors.surface.opacity(0.95)))
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Battle Column View
// ════════════════════════════════════════════════════════════════

struct BattleColumnView: View {
    let slot: BattleSlot
    let isActive: Bool
    let phase: BattlePhase
    let mode: PracticeMode

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
            let cardW = colW - 4
            let heroH = (colH - 20) * 0.5

            VStack(spacing: 0) {
                // Battle label
                Text("B\(slot.id + 1)")
                    .font(Design.Fonts.mono(8, weight: .bold))
                    .foregroundStyle(isActive ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                    .frame(height: 12)

                // CPU hero (top half) — facedown until revealed
                Group {
                    if slot.isRevealed, let card = slot.cpuCard {
                        cardFace(card: card, width: cardW, height: heroH * 0.9, isOpponent: true, effectBonus: slot.cpuEffectPower)
                    } else {
                        facedownCard(width: cardW, height: heroH * 0.9, isOpponent: true)
                    }
                }
                .frame(width: cardW, height: heroH * 0.9)

                // VS divider
                vsBar

                // Player hero (bottom half)
                Group {
                    if let card = slot.playerCard {
                        cardFace(card: card, width: cardW, height: heroH, isOpponent: false, effectBonus: slot.playerEffectPower)
                    } else {
                        facedownCard(width: cardW, height: heroH, isOpponent: false)
                    }
                }
                .frame(width: cardW, height: heroH)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Design.Colors.bobaOrange.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? Design.Colors.bobaOrange.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        )
        .opacity(slot.result == nil && !isActive ? 0.45 : 1)
    }

    private var vsBar: some View {
        ZStack {
            vsBarColor
                .frame(height: 16)
            Text(slot.result == nil ? "VS" : (slot.result == .win ? "WIN" : (slot.result == .lose ? "LOSS" : "TIE")))
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func cardFace(card: Card, width: CGFloat, height: CGFloat, isOpponent: Bool, effectBonus: Int = 0) -> some View {
        ZStack {
            if let file = card.imageFile, !file.isEmpty {
                AsyncImage(url: CDN.thumb(for: file)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholderFace(card: card, isOpponent: isOpponent)
                    }
                }
            } else {
                placeholderFace(card: card, isOpponent: isOpponent)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            VStack(spacing: 0) {
                Spacer()
                if effectBonus > 0 {
                    Text("+\(effectBonus)")
                        .font(Design.Fonts.mono(8, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                }
                Text("\(( card.power ?? 0) + effectBonus)")
                    .font(Design.Fonts.display(height > 60 ? 18 : 14))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(.bottom, 2)
            }
        )
    }

    private func placeholderFace(card: Card, isOpponent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Design.Colors.element(card.element).opacity(isOpponent ? 0.15 : 0.25))
            .overlay(
                Text(String(card.hero.prefix(2)).uppercased())
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.element(card.element).opacity(0.7))
            )
    }

    private func facedownCard(width: CGFloat, height: CGFloat, isOpponent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isOpponent ? Color(hex: "C0392B").opacity(0.2) : Design.Colors.bobaOrange.opacity(0.15))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: height * 0.25))
                    .foregroundStyle(isOpponent ? Color(hex: "C0392B").opacity(0.4) : Design.Colors.bobaOrange.opacity(0.4))
            )
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Action Button Style
// ════════════════════════════════════════════════════════════════

struct PracticeActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Fonts.mono(11, weight: .bold))
            .foregroundStyle(color == Design.Colors.glass ? Design.Colors.textSecondary : Design.Colors.nearBlack)
            .padding(.horizontal, Design.Spacing.md)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color == Design.Colors.glass ? Design.Colors.glass : color)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Landscape orientation support
// ════════════════════════════════════════════════════════════════

private extension View {
    func supportedInterfaceOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        self.onAppear {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
            }
        }
        .onDisappear {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}
