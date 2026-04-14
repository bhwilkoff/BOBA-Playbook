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

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.width < geo.size.height

            ZStack {
                // Background fills behind notch/Dynamic Island
                Design.Colors.nearBlack.ignoresSafeArea()

                if portrait {
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

                    // ── Match Over Overlay ───────────────────────────────────
                    if store.matchOver {
                        matchOverOverlay
                    }

                    // ── Phase Banner ─────────────────────────────────────────
                    if store.phase == .reveal && !store.battles.isEmpty && !store.battles[store.currentBattle].isRevealed {
                        phaseBanner
                    }
                }
            }
        }
        .onAppear { Task { @MainActor in OrientationManager.shared.lockLandscape() } }
        .onDisappear { Task { @MainActor in OrientationManager.shared.lockPortrait() } }
        .alert("Exit Practice?", isPresented: $showExitConfirm) {
            Button("Exit", role: .destructive) { dismiss() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Your progress will be lost.")
        }
        // Auto-show bench during sub phase, plays during play phase
        .onChange(of: store.phase) { _, newPhase in
            withAnimation(.easeInOut(duration: 0.2)) {
                if newPhase == .sub && store.mode.showBench {
                    showBenchPanel = true
                    showPlaysPanel = false
                } else if newPhase == .play && store.mode.showPlays {
                    showPlaysPanel = true
                    showBenchPanel = false
                } else {
                    showBenchPanel = false
                    showPlaysPanel = false
                }
            }
        }
    }

    // MARK: - Column Count

    private func visibleColumnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<480: return 3
        case ..<700: return 4
        default:     return 5
        }
    }

    // MARK: - Arena View

    private func arenaView(geo: GeometryProxy) -> some View {
        let count = visibleColumnCount(for: geo.size.width)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(store.battles) { slot in
                        BattleColumnView(
                            slot: slot,
                            isActive: slot.id == store.currentBattle,
                            phase: store.phase,
                            mode: store.mode
                        )
                        .containerRelativeFrame(.horizontal, count: count, span: 1, spacing: 8)
                        .id(slot.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, 4)
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

    // MARK: - Phase Banner

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
