//
//  PracticeView.swift
//  BOBAPlaybook
//
//  Landscape-only playmat for Practice Battle mode.
//  Scrollable arena (3-4 visible columns), overlay bench/plays panels,
//  compact bottom toolbar. Respects Dynamic Island + rounded corners.
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
    @State private var showBenchPanel = false
    @State private var showPlaysPanel = false
    @State private var isExiting = false
    @State private var showPhaseBanner = true

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.width < geo.size.height

            ZStack {
                // Background fills behind notch/Dynamic Island
                Design.Colors.nearBlack.ignoresSafeArea()

                if isExiting && !portrait {
                    // ── Exiting: show rotate-back prompt ────────────────────
                    exitRotatePrompt
                } else if isExiting && portrait {
                    // Portrait achieved while exiting — dismiss
                    Color.clear.onAppear { dismiss() }
                } else if portrait {
                    // ── Portrait: show rotate prompt only ────────────────────
                    rotatePrompt
                } else {
                    // ── Landscape: full playmat ─────────────────────────────
                    VStack(spacing: 0) {
                        PracticeTopBar(store: store) {
                            showExitConfirm = true
                        }

                        // Scrollable battle arena
                        arenaView(geo: geo)

                        PracticeBottomToolbar(
                            store: store,
                            showBenchPanel: $showBenchPanel,
                            showPlaysPanel: $showPlaysPanel
                        ) {
                            store.advancePhase()
                        }
                    }
                    // Bench panel overlay
                    .safeAreaInset(edge: .bottom) {
                        if showBenchPanel && store.mode.showBench {
                            PracticeBenchPanel(
                                store: store,
                                selectedBenchIdx: $selectedBenchIdx,
                                isVisible: $showBenchPanel
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    // Plays panel overlay
                    .safeAreaInset(edge: .bottom) {
                        if showPlaysPanel && store.mode.showPlays {
                            PracticePlaysPanel(
                                store: store,
                                isVisible: $showPlaysPanel
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    // ── CPU Play Card Overlay (one at a time) ───────────────
                    if let play = store.currentCpuPlay {
                        cpuPlayOverlay(play)
                    }

                    // ── Effect Callout (coin flip / dice / power change) ────
                    if let callout = store.lastEffectCallout {
                        effectCalloutBanner(callout)
                    }

                    // ── Match Over Overlay ───────────────────────────────────
                    if store.matchOver {
                        matchOverOverlay
                    }

                    // ── Phase Banner (auto-dismiss after 2s) ────────────────
                    // Don't show phase banner while CPU sub callout is active
                    if showPhaseBanner && !store.battles.isEmpty && store.cpuSubCallout == nil {
                        if store.phase == .reveal && !store.battles[store.currentBattle].isRevealed {
                            phaseBanner
                        } else if store.phase == .sub && !store.battles[store.currentBattle].isRevealed {
                            subPhaseBanner
                        }
                    }

                    // ── CPU Sub Callout (shown after phase banner clears) ───
                    if let callout = store.cpuSubCallout {
                        cpuSubOverlay(callout)
                    }
                }
            }
        }
        .onAppear { Task { @MainActor in OrientationManager.shared.allowLandscape() } }
        .onDisappear { Task { @MainActor in OrientationManager.shared.lockPortrait() } }
        .alert("Exit Practice?", isPresented: $showExitConfirm) {
            if !store.matchOver {
                Button("Save & Exit") {
                    store.saveMatch()
                    isExiting = true
                }
            }
            Button("Exit Without Saving", role: .destructive) {
                PracticeStore.deleteSavedMatch()
                isExiting = true
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text(store.matchOver
                 ? "This match has ended. Starting again will begin a new one."
                 : "You can save your match and resume later.")
        }
        // Auto-dismiss the initial phase banner (onChange doesn't fire for the initial value)
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.5)) { showPhaseBanner = false }
        }
        // Close panels when phase changes away from their relevant phase
        .onChange(of: store.phase) { _, newPhase in
            withAnimation(.easeInOut(duration: 0.2)) {
                if newPhase != .sub { showBenchPanel = false }
                if newPhase != .play { showPlaysPanel = false }
            }
            // Show phase banner briefly on each phase change
            withAnimation(.easeInOut(duration: 0.3)) { showPhaseBanner = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.5)) { showPhaseBanner = false }
            }
        }
        // Also auto-dismiss banner on battle change
        .onChange(of: store.currentBattle) { _, _ in
            withAnimation(.easeInOut(duration: 0.3)) { showPhaseBanner = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.5)) { showPhaseBanner = false }
            }
        }
    }

    // MARK: - Arena View

    private func arenaView(geo: GeometryProxy) -> some View {
        let activeWidth = geo.size.width * 0.82
        let inactiveWidth: CGFloat = 90

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.battles) { slot in
                        if slot.id == store.currentBattle {
                            ActiveBattleView(
                                slot: slot,
                                phase: store.phase,
                                mode: store.mode
                            )
                            .frame(width: activeWidth)
                            .id(slot.id)
                        } else {
                            BattleColumnView(
                                slot: slot,
                                isActive: false,
                                phase: store.phase,
                                mode: store.mode
                            )
                            .frame(width: inactiveWidth)
                            .id(slot.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: store.currentBattle) { _, newBattle in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newBattle, anchor: .center)
                }
            }
        }
    }

    // MARK: - Rotate Prompt

    private var rotatePrompt: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Exit Rotate Prompt

    private var exitRotatePrompt: some View {
        VStack(spacing: Design.Spacing.xl) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 56))
                .foregroundStyle(Design.Colors.bobaCyan)
                .rotationEffect(.degrees(0))
            Text("ROTATE BACK")
                .font(Design.Fonts.display(28))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Rotate your device to portrait to exit")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Match Over Overlay

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

                    Button("EXIT") { dismiss() }
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.glass))
                }
            }
            .padding(Design.Spacing.xl)
            .background(RoundedRectangle(cornerRadius: 20).fill(Design.Colors.surface).shadow(color: .black.opacity(0.5), radius: 20))
        }
    }

    // MARK: - CPU Sub Overlay

    private func cpuSubOverlay(_ callout: PracticeStore.ActionCallout) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: Design.Spacing.md) {
                Image(systemName: callout.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: callout.color))

                Text("CPU SUBSTITUTION")
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(callout.message)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.dismissCpuSub()
                    }
                } label: {
                    Text("OK")
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.nearBlack)
                        .padding(.horizontal, 40)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.bobaOrange))
                }
                .buttonStyle(.plain)
            }
            .padding(Design.Spacing.xl)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: callout.color).opacity(0.4), lineWidth: 2))
            .padding(.horizontal, 40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - CPU Play Overlay (one at a time)

    private func cpuPlayOverlay(_ play: PracticeStore.ActionCallout) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: Design.Spacing.md) {
                Text("CPU PLAYS A CARD")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.bobaViolet)

                // Card image if available
                if let card = play.card, let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                        .aspectRatio(5.0/7.0, contentMode: .fit)
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.Colors.bobaViolet.opacity(0.5), lineWidth: 2))
                }

                // Card name and cost
                if let card = play.card {
                    Text(card.name)
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Cost: \(card.playCost ?? 0) Hot Dogs")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }

                // Effect description
                VStack(spacing: 4) {
                    if play.cpuDelta > 0 {
                        Text("+\(play.cpuDelta) to CPU")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Color(hex: "C0392B"))
                    }
                    if play.cpuDelta < 0 {
                        Text("\(play.cpuDelta) to CPU")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Color(hex: "4CAF50"))
                    }
                    if play.playerDelta < 0 {
                        Text("\(play.playerDelta) to You")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Color(hex: "C0392B"))
                    }
                    if play.playerDelta > 0 {
                        Text("+\(play.playerDelta) to You")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Color(hex: "4CAF50"))
                    }
                    if play.cpuDelta == 0 && play.playerDelta == 0 {
                        Text("No power change")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }

                // Ability text
                if let card = play.card, let ability = card.playAbility, !ability.isEmpty {
                    Text(ability)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, Design.Spacing.md)
                }

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.dismissCpuPlay()
                    }
                } label: {
                    Text(store.cpuPlayQueue.isEmpty ? "CONTINUE" : "NEXT CARD")
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.nearBlack)
                        .padding(.horizontal, 40)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.bobaViolet))
                }
                .buttonStyle(.plain)
            }
            .padding(Design.Spacing.xl)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Design.Colors.bobaViolet.opacity(0.4), lineWidth: 2))
            .padding(.horizontal, 40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Effect Callout

    private func effectCalloutBanner(_ callout: PracticeStore.ActionCallout) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: callout.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: callout.color))
                Text(callout.message)
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .padding(Design.Spacing.md)
            .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.surface.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: callout.color).opacity(0.4), lineWidth: 1))
            .padding(.bottom, 80)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Phase Banner

    private var subPhaseBanner: some View {
        VStack {
            Spacer()
            VStack(spacing: 4) {
                Text("SUBSTITUTION")
                    .font(Design.Fonts.display(28))
                    .foregroundStyle(Design.Colors.bobaOrange)
                Text("Choose subs before cards are revealed")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            .padding(.horizontal, Design.Spacing.xl)
            .padding(.vertical, Design.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Colors.surface.opacity(0.95)))
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            Spacer()
        }
        .allowsHitTesting(false)
    }

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
// MARK: - Landscape orientation support (retained for compatibility)
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
