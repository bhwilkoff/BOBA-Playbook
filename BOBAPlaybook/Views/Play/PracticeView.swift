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
    /// UX#8 — discard inspector. Side that the user wants to inspect,
    /// or nil when no sheet is open. Wrapped so SwiftUI's
    /// `sheet(item:)` (which needs `Identifiable`) can carry it.
    @State private var inspectingDiscardSide: InspectingSide? = nil

    /// Identifiable wrapper around PlayExecContext.Side for sheet(item:).
    struct InspectingSide: Identifiable {
        let side: PlayExecContext.Side
        var id: String { side.rawValue }
    }
    @AppStorage("bp_practiceTutorialSeen_v1") private var tutorialSeen = false
    @State private var showTutorial = false

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
                        PracticeTopBar(
                            store: store,
                            onExit: { showExitConfirm = true },
                            onInspectCpuDiscard: { inspectingDiscardSide = .init(side: .cpu) },
                            onShowWalkthrough: {
                                // Reset the seen flag and re-fire the
                                // tutorial. Anchors are already attached
                                // to subviews via .tutorialTarget(_:),
                                // so the spotlight ring picks them up
                                // immediately on the next frame.
                                tutorialSeen = false
                                showTutorial = true
                            }
                        )

                        // Active persistent-effects banner — sits BELOW the
                        // top bar so the HD counter + exit button stay
                        // tappable. Previously overlaid on top of the
                        // top bar via an overlay VStack, which blocked
                        // both. Renders nothing when no effects in scope.
                        if !store.activeEffectsForUI.isEmpty {
                            activeEffectsBanner
                        }

                        // Scrollable battle arena
                        arenaView(geo: geo)

                        PracticeBottomToolbar(
                            store: store,
                            showBenchPanel: $showBenchPanel,
                            showPlaysPanel: $showPlaysPanel,
                            onAction: { store.advancePhase() },
                            onInspectPlayerDiscard: { inspectingDiscardSide = .init(side: .player) }
                        )
                    }
                    .sheet(item: $inspectingDiscardSide) { wrapper in
                        DiscardInspectorSheet(store: store, side: wrapper.side)
                    }
                    // Hand-discard chooser — surfaced when a play
                    // (Damage on Discard, Trash Bandit, etc.) asks
                    // the player to pick N cards to discard.
                    .sheet(item: Binding(
                        get: { store.pendingHandDiscard },
                        set: { newValue in if newValue == nil { store.cancelHandDiscard() } }
                    )) { choice in
                        HandDiscardChooserSheet(
                            store: store,
                            count: choice.count
                        )
                    }
                    // Hero-discard chooser — Don't Call It a Comeback
                    // and similar plays let the player pick a hero
                    // from their discard pile to replace the active.
                    .sheet(item: Binding(
                        get: { store.pendingHeroDiscardChoice },
                        set: { newValue in if newValue == nil { store.cancelHeroDiscardSwap() } }
                    )) { choice in
                        HeroDiscardChooserSheet(
                            store: store,
                            pool: choice.pool,
                            weaponFilter: choice.weaponFilter
                        )
                    }
                    // Generic player choice — Add Firepower's per-heads
                    // chooser, It's Gonna Cost Ya's HD-amount chooser,
                    // Adding Depth's draw-Hero-vs-Play, etc.
                    .sheet(item: Binding(
                        get: { store.pendingPlayerChoice },
                        set: { newValue in if newValue == nil { store.cancelPlayerChoice() } }
                    )) { choice in
                        PlayerChoiceSheet(store: store, choice: choice)
                    }
                    // Scare Tactics reveal — pick a play to "reveal".
                    .sheet(item: Binding(
                        get: { store.pendingScareReveal },
                        set: { newValue in if newValue == nil { store.cancelScareReveal() } }
                    )) { state in
                        ScareRevealChooserSheet(store: store, pool: state.pool)
                    }
                    // Pre-Game Spy / peek_opponent_hand reveal — shows
                    // the actual cards in a dismissible sheet rather
                    // than a 2s toast that vanished before coaches
                    // could read both names.
                    .sheet(item: Binding(
                        get: { store.pendingPeekedHand },
                        set: { newValue in if newValue == nil { store.dismissPeekedHand() } }
                    )) { reveal in
                        PeekedHandSheet(store: store, reveal: reveal)
                    }
                    // Delayed Recovery / "choose one of your unrevealed
                    // Heroes" — chooser sheet listing candidate future
                    // battles. Was previously a silent random pick
                    // because the engine ignored the JSON's selector.
                    .sheet(item: Binding(
                        get: { store.pendingFutureBattlePick },
                        set: { newValue in if newValue == nil { store.cancelFutureBattlePick() } }
                    )) { pick in
                        FutureBattlePickSheet(store: store, pick: pick)
                    }
                    // Rules-clarification alert (handoff §6.A): warns
                    // when Recycle / Reload / Return from the Depths
                    // would clear active rest_of_game effects.
                    .alert(
                        "Recycle these plays?",
                        isPresented: Binding(
                            get: { store.pendingRecycleCard != nil },
                            set: { newValue in if !newValue { store.cancelPendingRecycle() } }
                        ),
                        presenting: store.pendingRecycleCard
                    ) { _ in
                        Button("Recycle", role: .destructive) {
                            store.confirmPendingRecycle()
                        }
                        Button("Cancel", role: .cancel) {
                            store.cancelPendingRecycle()
                        }
                    } message: { _ in
                        Text("Picking plays back up from your discard ends any rest-of-game effects attached to them. Currently active:\n\n• \(store.pendingRecycleVictimSummary)")
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
                    // First-run spotlight tutorial — reads targetFrames from
                    // `.tutorialTarget(_:)` preferences on the subviews above.
                    .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
                        if showTutorial {
                            GeometryReader { proxy in
                                let frames: [TutorialTarget: CGRect] = anchors.reduce(into: [:]) { acc, pair in
                                    acc[pair.key] = proxy[pair.value]
                                }
                                PracticeTutorialOverlay(
                                    targetFrames: frames,
                                    containerSize: proxy.size
                                ) {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        tutorialSeen = true
                                        showTutorial = false
                                    }
                                }
                            }
                        }
                    }

                    // ── CPU Play Card Overlay (one at a time) ───────────────
                    if let play = store.currentCpuPlay {
                        cpuPlayOverlay(play)
                    }

                    // ── Animated dice / coin reveal ─────────────────────────
                    // Plays through a ~1s spin/tumble before the rest of the
                    // effect resolves visually. Auto-clears when done.
                    if let reveal = store.pendingReveal {
                        DiceCoinRevealOverlay(reveal: reveal) {
                            store.pendingReveal = nil
                        }
                        .transition(.opacity)
                        .zIndex(50)
                    }

                    // ── Honors-roll setup overlay ───────────────────────────
                    // First-of-match dice roll for who acts first. Auto-
                    // dismisses when the player taps "Begin Battle 1."
                    if let setup = store.pendingSetupHonors {
                        SetupHonorsRollOverlay(roll: setup) {
                            store.pendingSetupHonors = nil
                        }
                        .transition(.opacity)
                        .zIndex(60)
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

                    // ── First-run hints (now top-floating, not inside the
                    //    bench panel — when the banner sat inside the panel
                    //    it pushed the bench thumbs + detail off-screen and
                    //    blocked the SUBSTITUTE button).
                    if showBenchPanel && store.phase == .sub
                       && HintsManager.shared.shouldShow(.substitutionPositioning) {
                        VStack {
                            HintBanner(
                                id: .substitutionPositioning,
                                title: "TIP — SUBSTITUTION POSITIONING",
                                message: "Put your lowest-power Hero in Battle 1 so you can substitute it cheaply if you have HDs to spare. Your strongest cards are wasted in the early slots."
                            )
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.top, Design.Spacing.md)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(true)
                        .zIndex(70)
                    }
                }
            }
        }
        .onAppear {
            Task { @MainActor in OrientationManager.shared.allowLandscape() }
            // Delay showing the tutorial so `.tutorialTarget(_:)` anchors have
            // a chance to propagate through the preference system before we
            // try to render the spotlight ring.
            if !tutorialSeen {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    showTutorial = true
                }
            }
        }
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
                                mode: store.mode,
                                playerEffectiveWeapon: store.effectiveWeapon(of: slot.playerCard, side: .player),
                                cpuEffectiveWeapon:    store.effectiveWeapon(of: slot.cpuCard,    side: .cpu),
                                playerPulseTrigger:    store.playerHeroPulse,
                                cpuPulseTrigger:       store.cpuHeroPulse
                            )
                            .frame(width: activeWidth)
                            .id(slot.id)
                        } else {
                            BattleColumnView(
                                slot: slot,
                                isActive: false,
                                phase: store.phase,
                                mode: store.mode,
                                pendingPlayerBonus: store.previewPersistentPower(for: slot.id, side: .player),
                                pendingCpuBonus: store.previewPersistentPower(for: slot.id, side: .cpu)
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

    // MARK: - Discard inspector — see DiscardInspectorSheet below

    // MARK: - Active persistent-effects banner
    //
    // Shows every weapon transform + persistent effect currently in
    // scope as a horizontal pill strip just under the top bar. Each
    // pill carries owner side (cyan = you, violet = CPU), an icon for
    // the effect family, and a one-line summary built by the store.
    // Coaches can read the whole "what's currently affecting this
    // battle" surface at a glance without opening anything.
    private var activeEffectsBanner: some View {
        HStack(spacing: 0) {
            // Eyebrow label on the leading edge — anchors the band
            // visually so it reads as "this is the active-effects
            // strip" instead of an unstyled rectangle. Mirrors the
            // PracticeTopBar's eyebrow styling for continuity.
            HStack(spacing: 4) {
                Image(systemName: "infinity")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                Text("ACTIVE")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .tracking(1.2)
            }
            .padding(.leading, Design.Spacing.md)
            .padding(.trailing, 8)

            // Vertical divider between eyebrow and chip strip.
            Rectangle()
                .fill(Design.Colors.bobaOrange.opacity(0.35))
                .frame(width: 1, height: 22)

            // Scrollable chip strip.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.activeEffectsForUI, id: \.id) { row in
                        chipPill(row: row)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .frame(height: 36)
        .background(
            // Layered background that reads as part of the playmat:
            // surface tone like the top bar, with a subtle orange
            // wash on the leading edge to tie into the arena's
            // orange-bordered container below.
            ZStack {
                Design.Colors.surface.opacity(0.95)
                LinearGradient(
                    colors: [
                        Design.Colors.bobaOrange.opacity(0.10),
                        Design.Colors.bobaOrange.opacity(0.02),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .overlay(alignment: .top) {
            Divider().background(Design.Colors.glass)
        }
        .overlay(alignment: .bottom) {
            // Orange-tinted bottom edge connects visually to the
            // orange-bordered active battle area below.
            Rectangle()
                .fill(Design.Colors.bobaOrange.opacity(0.45))
                .frame(height: 1)
        }
    }

    /// One pill in the active-effects strip — extracted so the body
    /// stays readable.
    @ViewBuilder
    private func chipPill(row: (id: UUID, owner: PlayExecContext.Side, label: String, icon: String, color: String, remaining: Int?, sourceCard: String)) -> some View {
        HStack(spacing: 5) {
            // Owner side tab — cyan for you, violet for CPU.
            Capsule()
                .fill(row.owner == .player
                      ? Design.Colors.bobaCyan
                      : Design.Colors.bobaViolet)
                .frame(width: 3, height: 14)
            Image(systemName: row.icon)
                .font(.system(size: 10, weight: .bold))
            // Source-card eyebrow when known: "BABY PHOENIX · End-
            // of-turn +10" reads more clearly than a bare summary.
            if !row.sourceCard.isEmpty {
                Text(row.sourceCard.uppercased())
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Color(hex: row.color).opacity(0.78))
                    .tracking(0.6)
                    .lineLimit(1)
                Text("·")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Color(hex: row.color).opacity(0.55))
            }
            Text(row.label)
                .font(Design.Fonts.mono(11, weight: .bold))
                .lineLimit(1)
            if let r = row.remaining, r > 0 {
                Text("\(r) BTL")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            } else if row.remaining == nil {
                Text("∞")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
        }
        .foregroundStyle(Color(hex: row.color))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Design.Colors.nearBlack.opacity(0.55))
                .overlay(
                    Capsule()
                        .fill(Color(hex: row.color).opacity(0.10))
                )
                .overlay(
                    Capsule().strokeBorder(Color(hex: row.color).opacity(0.55), lineWidth: 1)
                )
        )
    }

    // MARK: - Match Over Overlay

    private var matchOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: Design.Spacing.md) {
                // Verdict banner
                VStack(spacing: 4) {
                    if let winner = store.matchWinner {
                        if winner == .player {
                            Text("VICTORY!").font(Design.Fonts.display(40))
                                .foregroundStyle(Color(hex: "4CAF50"))
                            Text("You won the match")
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textSecondary)
                        } else {
                            Text("DEFEAT").font(Design.Fonts.display(40))
                                .foregroundStyle(Color(hex: "C0392B"))
                            Text("CPU won the match")
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                    } else {
                        Text("SUDDEN DEATH").font(Design.Fonts.display(30))
                            .foregroundStyle(Design.Colors.bobaOrange)
                        Text("The match ended in a tie")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    Text("\(store.playerScore) — \(store.cpuScore)")
                        .font(Design.Fonts.display(28))
                        .foregroundStyle(Design.Colors.textPrimary)
                }

                // Trophy progression — one icon per battle. Lets coaches
                // read the match flow at a glance: where they held, where
                // they lost, which battles went to tiebreaker.
                trophyStrip

                // Per-battle play summary — scrollable so 7 battles worth
                // of plays never get clipped on a small phone.
                ScrollView {
                    VStack(spacing: Design.Spacing.sm) {
                        ForEach(store.battles) { slot in
                            battleSummaryRow(slot: slot)
                        }
                    }
                    .padding(.vertical, Design.Spacing.xs)
                }
                .frame(maxHeight: 260)

                HStack(spacing: Design.Spacing.md) {
                    Button("PLAY AGAIN") { store.startMatch(allCards: []) }
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
                    Button("EXIT") { dismiss() }
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.glass))
                }
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 20).fill(Design.Colors.surface)
                .shadow(color: .black.opacity(0.5), radius: 20))
            .padding(.horizontal, Design.Spacing.md)
        }
    }

    // MARK: - Match summary pieces

    private var trophyStrip: some View {
        VStack(spacing: 6) {
            Text("BATTLE PROGRESSION")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            HStack(spacing: 6) {
                ForEach(store.battles) { slot in
                    trophyIcon(for: slot)
                }
            }
        }
    }

    /// One trophy per battle. Green = player won, red = CPU won,
    /// orange = tie, muted = battle not played. Always renders 7 slots
    /// so the row visually matches "first to 4" pacing.
    @ViewBuilder
    private func trophyIcon(for slot: BattleSlot) -> some View {
        let (symbol, color): (String, Color) = {
            switch slot.result {
            case .win:  return ("trophy.fill", Color(hex: "4CAF50"))
            case .lose: return ("xmark.shield.fill", Color(hex: "C0392B"))
            case .tie:  return ("equal.circle.fill", Design.Colors.bobaOrange)
            case .none: return ("circle", Design.Colors.textMuted)
            }
        }()
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(color)
            Text("\(slot.id + 1)")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(width: 32)
    }

    private func battleSummaryRow(slot: BattleSlot) -> some View {
        let verdict: String
        let verdictColor: Color
        switch slot.result {
        case .win:  verdict = "YOU WON";  verdictColor = Color(hex: "4CAF50")
        case .lose: verdict = "CPU WON";  verdictColor = Color(hex: "C0392B")
        case .tie:  verdict = "TIE";       verdictColor = Design.Colors.bobaOrange
        case .none: verdict = "—";         verdictColor = Design.Colors.textMuted
        }
        let playerPlays = slot.playerPlayedCards.map { $0.name }.joined(separator: ", ")
        let cpuPlays    = slot.cpuPlayedCards.map    { $0.name }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("BATTLE \(slot.id + 1)")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text("·")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                Text(verdict)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(verdictColor)
                Spacer()
                Text("\(slot.playerFinalPower) — \(slot.cpuFinalPower)")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            summaryPlayLine(label: "YOU", plays: playerPlays, hero: slot.playerCard?.hero)
            summaryPlayLine(label: "CPU", plays: cpuPlays,    hero: slot.cpuCard?.hero)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass.opacity(0.5)))
    }

    private func summaryPlayLine(label: String, plays: String, hero: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let h = hero, !h.isEmpty {
                    Text(h)
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                Text(plays.isEmpty ? "(no plays)" : plays)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(plays.isEmpty ? Design.Colors.textMuted : Design.Colors.bobaCyan)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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

                // Show the displaced hero face-up so the player can
                // see what power level the CPU just replaced. The new
                // hero stays face-down (sub happens before reveal).
                if let card = callout.card, let file = card.imageFile, !file.isEmpty {
                    VStack(spacing: 4) {
                        Text("SUBBED OUT")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                            .aspectRatio(5.0/7.0, contentMode: .fit)
                            .frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(hex: callout.color).opacity(0.5), lineWidth: 2))
                    }
                }

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
            // Horizontal layout for landscape iPhone — image on the
            // left, all text on the right. Frees vertical space for
            // legible ability copy without forcing the user to squint.
            HStack(alignment: .top, spacing: Design.Spacing.md) {
                if let card = play.card, let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fill)
                        .frame(width: 130, height: 182)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Design.Colors.bobaViolet.opacity(0.5), lineWidth: 2)
                        )
                }

                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    Text("CPU PLAYS A CARD")
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.bobaViolet)
                        .tracking(2)

                    if let card = play.card {
                        Text(card.name)
                            .font(Design.Fonts.display(20))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 6) {
                            let cost = card.playCost ?? 0
                            Text(cost == 0 ? "FREE" : "\(cost) HD")
                                .font(Design.Fonts.mono(12, weight: .bold))
                                .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill((cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan).opacity(0.15)))
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

                    // Ability text — primary content, sized for comfortable
                    // reading. Wraps freely; landscape iPhone has plenty
                    // of horizontal room for prose.
                    if let card = play.card, let ability = card.playAbility, !ability.isEmpty {
                        Text(ability)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Power deltas — secondary, shown after ability
                    HStack(spacing: 8) {
                        if play.cpuDelta > 0 {
                            deltaPill("+\(play.cpuDelta) CPU", color: Color(hex: "C0392B"))
                        } else if play.cpuDelta < 0 {
                            deltaPill("\(play.cpuDelta) CPU", color: Color(hex: "4CAF50"))
                        }
                        if play.playerDelta < 0 {
                            deltaPill("\(play.playerDelta) YOU", color: Color(hex: "C0392B"))
                        } else if play.playerDelta > 0 {
                            deltaPill("+\(play.playerDelta) YOU", color: Color(hex: "4CAF50"))
                        }
                        if play.cpuDelta == 0 && play.playerDelta == 0 {
                            Text("No power change")
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.dismissCpuPlay()
                        }
                    } label: {
                        Text(store.cpuPlayQueue.isEmpty ? "CONTINUE" : "NEXT CARD")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.nearBlack)
                            .padding(.horizontal, 22)
                            .frame(height: 36)
                            .background(Capsule().fill(Design.Colors.bobaViolet))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Design.Spacing.lg)
            .frame(maxWidth: 540)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Design.Colors.bobaViolet.opacity(0.4), lineWidth: 2))
            .padding(.horizontal, Design.Spacing.lg)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func deltaPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Effect Callout

    private func effectCalloutBanner(_ callout: PracticeStore.ActionCallout) -> some View {
        // Detect cancelled-by-gate callouts so we can show the
        // killed card with a red CANCELLED stamp — gives the user
        // a clear visual signal of which card got blocked.
        let isCancellation = callout.message.contains("cancelled")
            || callout.message.contains("Cancelled")
        return VStack {
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                if let card = callout.card,
                   let file = card.imageFile, !file.isEmpty {
                    ZStack {
                        CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                            .frame(width: 50, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(hex: callout.color).opacity(0.6), lineWidth: 2)
                            )
                            .opacity(isCancellation ? 0.4 : 1.0)
                        if isCancellation {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color(hex: "C0392B"))
                                .background(Circle().fill(.white).frame(width: 20, height: 20))
                        }
                    }
                } else {
                    Image(systemName: callout.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: callout.color))
                }
                Text(callout.message)
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Spacing.md)
            .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.surface.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: callout.color).opacity(0.4), lineWidth: 1))
            .padding(.bottom, 80)
            .padding(.horizontal, 24)
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

// ════════════════════════════════════════════════════════════════
// MARK: - DiceCoinRevealOverlay
// ════════════════════════════════════════════════════════════════
//
// Animated overlay that plays whenever a Play card flips coins or
// rolls dice. Coins spin around the Y axis cycling HEADS/TAILS
// labels; dice rapidly cycle face glyphs. Both settle on the actual
// rolled result after `spinDuration`, hold briefly, then call
// `onFinished` so the store can clear `pendingReveal`.
//
// Side affects tint only: cyan for the player, purple for CPU.

private struct DiceCoinRevealOverlay: View {
    let reveal: PracticeStore.RevealState
    let onFinished: () -> Void

    private let spinDuration: Double = 0.85

    @State private var settled = false
    @State private var tick = 0

    private var accent: Color {
        reveal.side == .player ? Design.Colors.bobaCyan : Color(hex: "C77DFF")
    }

    private var title: String {
        if reveal.kind == .gate    { return "OPP GATE ROLL" }
        if reveal.kind == .versus  { return "VERSUS ROLL" }
        if reveal.kind == .summed  { return "DICE TOTAL" }
        if !reveal.coinFlips.isEmpty && !reveal.diceRolls.isEmpty { return "ROLL" }
        if !reveal.coinFlips.isEmpty {
            return reveal.coinFlips.count > 1 ? "COIN FLIPS" : "COIN FLIP"
        }
        return reveal.diceRolls.count > 1 ? "DICE ROLL" : "DIE ROLL"
    }

    @ViewBuilder
    private func versusColumn(label: String, rollValue: Int, won: Bool, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(won ? tint : Design.Colors.textMuted)
                .tracking(1.6)
            DieFace(finalRoll: rollValue, settled: settled, tick: tick, accent: tint)
                .opacity(settled && !won && rollValue != reveal.diceRolls.max() ? 0.55 : 1.0)
        }
    }

    // Extracted to keep the body simple — the versus / regular branch
    // pushed the parent VStack past the type-checker's complexity
    // budget when nested inside the reveal overlay's body.
    @ViewBuilder
    private var diceRow: some View {
        if reveal.kind == .versus, reveal.diceRolls.count == 2 {
            versusRollRow
        } else {
            HStack(spacing: 12) {
                ForEach(Array(reveal.diceRolls.enumerated()), id: \.offset) { _, finalRoll in
                    DieFace(finalRoll: finalRoll, settled: settled, tick: tick, accent: accent)
                }
            }
        }
    }

    @ViewBuilder
    private var versusRollRow: some View {
        let actorRoll = reveal.diceRolls[0]
        let oppRoll   = reveal.diceRolls[1]
        let actorWon  = settled && actorRoll > oppRoll
        let oppWon    = settled && oppRoll > actorRoll
        let actorLabel: String = reveal.side == .player ? "YOU" : "CPU"
        let oppLabel:   String = reveal.side == .player ? "CPU" : "YOU"
        let oppTint:    Color  = reveal.side == .player
            ? Color(hex: "C77DFF")
            : Design.Colors.bobaCyan
        HStack(spacing: 18) {
            versusColumn(label: actorLabel, rollValue: actorRoll, won: actorWon, tint: accent)
            Text("VS")
                .font(Design.Fonts.display(14))
                .foregroundStyle(Design.Colors.textMuted)
            versusColumn(label: oppLabel, rollValue: oppRoll, won: oppWon, tint: oppTint)
        }
    }

    // Extracted: the imperative if/else chain that computes `label`
    // returns `()` inside a @ViewBuilder, which the result builder
    // can't accept. Wrapping it in a helper isolates the computation
    // so only the final Text reaches the parent body.
    private var versusOutcomeLabel: some View {
        let actorRoll = reveal.diceRolls[0]
        let oppRoll   = reveal.diceRolls[1]
        let label: String
        if actorRoll == oppRoll {
            label = "TIE — no effect"
        } else if actorRoll > oppRoll {
            label = reveal.side == .player ? "YOU WIN THE ROLL" : "CPU WINS THE ROLL"
        } else {
            label = reveal.side == .player ? "CPU WINS THE ROLL" : "YOU WIN THE ROLL"
        }
        return Text(label)
            .font(Design.Fonts.mono(12, weight: .bold))
            .foregroundStyle(Design.Colors.textPrimary)
            .tracking(1.2)
    }

    var body: some View {
        ZStack {
            // Dim backdrop blocks taps from reaching anything underneath
            // — the user has to acknowledge the reveal before continuing.
            // Tap on backdrop dismisses ONLY after settled + a valid
            // payload exists, so an empty-state shell can never trap
            // the user with no way to dismiss.
            Color.black.opacity(0.55).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if settled, !reveal.coinFlips.isEmpty || !reveal.diceRolls.isEmpty {
                        onFinished()
                    }
                }

            VStack(spacing: 12) {
                if !reveal.sourceLabel.isEmpty {
                    Text(reveal.sourceLabel.uppercased())
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(2.0)
                        .lineLimit(1)
                }
                Text(title)
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(accent)
                    .tracking(2.5)

                if !reveal.coinFlips.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(Array(reveal.coinFlips.enumerated()), id: \.offset) { _, finalFace in
                            CoinFace(finalFace: finalFace, settled: settled, tick: tick, accent: accent)
                        }
                    }
                }

                if !reveal.diceRolls.isEmpty {
                    diceRow
                }

                if settled, reveal.kind == .summed, reveal.diceRolls.count > 1 {
                    Text("SUM \(reveal.diceRolls.reduce(0, +))")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .tracking(1.5)
                } else if settled, reveal.kind == .versus, reveal.diceRolls.count == 2 {
                    versusOutcomeLabel
                }

                // Continue button — appears once the dice/coin have
                // settled. Without this the overlay would auto-dismiss
                // and the user might miss what they rolled. Required
                // dismissal turns the moment into a beat the user
                // actually reads.
                if settled {
                    Button {
                        onFinished()
                    } label: {
                        Text("CONTINUE")
                            .font(Design.Fonts.mono(12, weight: .bold))
                            .foregroundStyle(Design.Colors.nearBlack)
                            .padding(.horizontal, 18)
                            .frame(height: 32)
                            .background(Capsule().fill(accent))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Design.Colors.surface.opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(accent.opacity(0.6), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 14)
            )
        }
        .task(id: reveal.id) {
            settled = false
            tick = 0
            // Cycle faces every ~50ms while spinning so the overlay
            // visibly tumbles. We don't need the loop to be exact —
            // just frequent enough that the eye reads it as motion.
            let frame = UInt64(50_000_000) // 50ms
            let frames = Int((spinDuration * 1000) / 50)
            for _ in 0..<frames {
                try? await Task.sleep(nanoseconds: frame)
                tick &+= 1
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                settled = true
            }
            // No auto-dismiss — user taps CONTINUE (or the backdrop)
            // to clear the overlay so they actually read the result.
        }
    }
}

private struct CoinFace: View {
    let finalFace: Bool      // true = HEADS
    let settled: Bool
    let tick: Int
    let accent: Color

    private var displayedHeads: Bool {
        settled ? finalFace : (tick % 2 == 0)
    }

    var body: some View {
        Text(displayedHeads ? "HEADS" : "TAILS")
            .font(Design.Fonts.display(20))
            .foregroundStyle(.white)
            .frame(width: 90, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(displayedHeads ? Color(hex: "FFD700").opacity(0.85) : Color(hex: "8A9BB0").opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent.opacity(settled ? 0.85 : 0.4), lineWidth: settled ? 2 : 1))
            )
            .rotation3DEffect(
                .degrees(settled ? 0 : Double(tick) * 80),
                axis: (x: 0, y: 1, z: 0)
            )
            .scaleEffect(settled ? 1.05 : 1.0)
    }
}

private struct DieFace: View {
    let finalRoll: Int       // 1…6
    let settled: Bool
    let tick: Int
    let accent: Color

    /// SF Symbol names for each die face. SF Symbols sit on the
    /// proper baseline and center inside their layout box, unlike
    /// the Unicode dice characters (⚀⚁⚂⚃⚄⚅) which render with
    /// their ink stuck in the lower-left of the bounding box.
    private static let symbols = [
        "die.face.1.fill", "die.face.2.fill", "die.face.3.fill",
        "die.face.4.fill", "die.face.5.fill", "die.face.6.fill"
    ]

    private var displayedRoll: Int {
        if settled { return max(1, min(6, finalRoll)) }
        return (tick % 6) + 1
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: Self.symbols[displayedRoll - 1])
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(displayedRoll)")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(accent)
        }
        .frame(width: 70, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accent.opacity(settled ? 0.85 : 0.4), lineWidth: settled ? 2 : 1))
        )
        .rotationEffect(.degrees(settled ? 0 : Double(tick * 24).truncatingRemainder(dividingBy: 360)))
        .scaleEffect(settled ? 1.08 : 1.0)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - SetupHonorsRollOverlay
// ════════════════════════════════════════════════════════════════
//
// One-time pre-match overlay that walks through the BoBA setup
// procedure. Each player rolls 2d6; high total wins Honors for
// Battle 1. Mirrors the Setup section in Learn so newcomers see
// the same procedure they read about. Auto-tumbles for ~1.1s,
// settles, holds, then waits for "Begin Battle 1" tap.

private struct SetupHonorsRollOverlay: View {
    let roll: PracticeStore.SetupHonorsRoll
    let onFinished: () -> Void

    private let spinDuration: Double = 1.0
    @State private var settled = false
    @State private var tick = 0

    var body: some View {
        // Compact landscape layout — practice mat runs in landscape
        // on iOS, where vertical room is ~330–390 pt before clipping
        // safe areas. The original tall stack ran past the bottom of
        // the screen on iPhone 14/15. This version uses a horizontal
        // dice row with a single-line title and a single-line result
        // so the whole overlay fits inside ~280 pt.
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            VStack(spacing: 10) {
                Text("ROLL FOR HONORS")
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .tracking(2)

                Text("High roll acts first in Battle 1.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)

                HStack(spacing: Design.Spacing.lg) {
                    rollColumn(
                        title: "YOU",
                        rollValue: roll.playerRoll,
                        accent: Design.Colors.bobaCyan,
                        won: settled && roll.winner == .player
                    )
                    rollColumn(
                        title: "CPU",
                        rollValue: roll.cpuRoll,
                        accent: Color(hex: "C77DFF"),
                        won: settled && roll.winner == .cpu
                    )
                }
                .padding(.vertical, 2)

                if settled {
                    HStack(spacing: 8) {
                        Text(roll.winner == .player ? "YOU WIN HONORS" : "CPU WINS HONORS")
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(roll.winner == .player
                                             ? Design.Colors.bobaCyan
                                             : Color(hex: "C77DFF"))
                        Button {
                            onFinished()
                        } label: {
                            Text("BEGIN BATTLE 1")
                                .font(Design.Fonts.mono(12, weight: .bold))
                                .foregroundStyle(Design.Colors.nearBlack)
                                .padding(.horizontal, 16)
                                .frame(height: 34)
                                .background(Capsule().fill(Design.Colors.bobaOrange))
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Design.Colors.surface.opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.6), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 14)
            )
            .padding(.horizontal, Design.Spacing.lg)
        }
        .task(id: roll.id) {
            settled = false
            tick = 0
            let frame = UInt64(50_000_000) // 50ms
            let frames = Int((spinDuration * 1000) / 50)
            for _ in 0..<frames {
                try? await Task.sleep(nanoseconds: frame)
                tick &+= 1
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                settled = true
            }
        }
    }

    private func rollColumn(title: String, rollValue: Int, accent: Color, won: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(won ? accent : Design.Colors.textMuted)
                .tracking(1.4)
            CompactDieFace(finalRoll: rollValue, settled: settled, tick: tick, accent: accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(won ? accent.opacity(0.12) : Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(won ? accent.opacity(0.85) : Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

/// Smaller die used in the setup honors overlay so the whole popup
/// fits inside iPhone landscape (~280pt of usable vertical space).
/// Visually echoes `DieFace` but at ~60% size and without the
/// stacked numeric label — the glyph speaks for itself at a glance.
private struct CompactDieFace: View {
    let finalRoll: Int
    let settled: Bool
    let tick: Int
    let accent: Color

    /// SF Symbols, not Unicode glyphs — see DieFace for rationale.
    private static let symbols = [
        "die.face.1.fill", "die.face.2.fill", "die.face.3.fill",
        "die.face.4.fill", "die.face.5.fill", "die.face.6.fill"
    ]

    private var displayedRoll: Int {
        if settled { return max(1, min(6, finalRoll)) }
        return (tick % 6) + 1
    }

    var body: some View {
        Image(systemName: Self.symbols[displayedRoll - 1])
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(settled ? 0.85 : 0.4),
                                      lineWidth: settled ? 2 : 1))
            )
            .rotationEffect(.degrees(settled ? 0 : Double(tick * 24).truncatingRemainder(dividingBy: 360)))
            .scaleEffect(settled ? 1.06 : 1.0)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - HandDiscardChooserSheet
// ════════════════════════════════════════════════════════════════
//
// Sheet that surfaces when a play card asks the user to pick N
// plays from their hand to discard. Examples: Damage on Discard
// (2), Trash Bandit, anything with `discard mode:"choice"`.
// Multi-select with a confirm button that's disabled until exactly
// `count` cards are picked.

struct HandDiscardChooserSheet: View {
    let store: PracticeStore
    let count: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Card> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: Design.Spacing.md) {
                instructions
                hand
                confirmButton
            }
            .padding(Design.Spacing.lg)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Discard \(count) Play\(count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        store.cancelHandDiscard()
                        dismiss()
                    }
                    .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick \(count) play\(count == 1 ? "" : "s") to discard from your hand.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
            Text("\(selected.count) of \(count) selected")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(selected.count == count ? Design.Colors.bobaCyan : Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hand: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(store.playerHand.enumerated()), id: \.offset) { _, card in
                    handRow(card)
                }
            }
        }
    }

    private func handRow(_ card: Card) -> some View {
        let isSelected = selected.contains(card)
        return Button {
            if isSelected {
                selected.remove(card)
            } else if selected.count < count {
                selected.insert(card)
            }
        } label: {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Design.Colors.bobaCyan : Design.Colors.textMuted)
                if let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                        .frame(width: 38, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                    if let cost = card.playCost {
                        Text(cost == 0 ? "FREE" : "\(cost) HD")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                    }
                    if let ability = card.playAbility {
                        Text(ability)
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(isSelected ? Design.Colors.bobaCyan.opacity(0.10) : Design.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(isSelected ? Design.Colors.bobaCyan : Design.Colors.glassBorder,
                                      lineWidth: isSelected ? 2 : 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var confirmButton: some View {
        let ready = selected.count == count
        return Button {
            store.confirmHandDiscard(Array(selected))
            dismiss()
        } label: {
            Text(ready ? "DISCARD \(count) PLAY\(count == 1 ? "" : "S")" : "PICK \(count - selected.count) MORE")
                .font(Design.Fonts.mono(14, weight: .bold))
                .foregroundStyle(ready ? Design.Colors.nearBlack : Design.Colors.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(ready ? Design.Colors.bobaOrange : Design.Colors.glass))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - HeroDiscardChooserSheet
// ════════════════════════════════════════════════════════════════
//
// Surfaced when a play card (Don't Call It a Comeback) lets the
// player swap their active hero for one from the hero-discard pile.
// Single-select — tapping any pool card immediately commits the
// swap.

struct HeroDiscardChooserSheet: View {
    let store: PracticeStore
    let pool: [Card]
    let weaponFilter: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    Text("Pick a hero to bring back from discard.")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                    if let wf = weaponFilter {
                        Text("Filter: \(wf) weapon only")
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(Array(pool.enumerated()), id: \.offset) { _, card in
                            heroTile(card)
                        }
                    }
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Choose Hero")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        store.cancelHeroDiscardSwap()
                        dismiss()
                    }
                    .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func heroTile(_ card: Card) -> some View {
        Button {
            store.confirmHeroDiscardSwap(card)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Group {
                        if let file = card.imageFile, !file.isEmpty {
                            CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Design.Colors.element(card.element).opacity(0.2))
                        }
                    }
                    .frame(width: 90, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Design.Colors.element(card.element).opacity(0.5), lineWidth: 2)
                    )
                    Text("\(card.power ?? 0)")
                        .font(Design.Fonts.display(20))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 4)
                }
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                Text(card.element)
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.element(card.element))
            }
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - PlayerChoiceSheet
// ════════════════════════════════════════════════════════════════
//
// Surfaces when a play card emits the `player_choice` op for the
// player's side. Shows a vertical stack of option buttons; tapping
// any one runs that option's nested effects through the executor.
// CPU side never sees this — it auto-picks via cpu_pick.

struct PlayerChoiceSheet: View {
    let store: PracticeStore
    let choice: PracticeStore.PlayerChoiceState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    Text(choice.prompt)
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: Design.Spacing.sm) {
                        ForEach(choice.options) { option in
                            optionButton(option)
                        }
                    }
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Choose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        store.cancelPlayerChoice()
                        dismiss()
                    }
                    .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func optionButton(_ option: PracticeStore.PlayerChoiceState.Option) -> some View {
        Button {
            store.confirmPlayerChoice(option: option)
            dismiss()
        } label: {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Text(option.label)
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.bobaCyan.opacity(0.4), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - ScareRevealChooserSheet
// ════════════════════════════════════════════════════════════════
//
// Surfaced when the player plays Scare Tactics with honors. The
// player picks any play from their hand to "reveal" (the card stays
// in hand). Next battle, if the CPU plays a card whose cost is at
// least the revealed card's cost, the revealed card fires for free.

struct ScareRevealChooserSheet: View {
    let store: PracticeStore
    let pool: [Card]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    Text("Pick a play to reveal. If the CPU plays a card of equal-or-greater cost next battle, your revealed play runs free.")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(Array(pool.enumerated()), id: \.offset) { _, card in
                            tile(card)
                        }
                    }
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Reveal a Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        store.cancelScareReveal()
                        dismiss()
                    }
                    .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tile(_ card: Card) -> some View {
        Button {
            store.confirmScareReveal(card)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let file = card.imageFile, !file.isEmpty {
                            CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Design.Colors.bobaViolet.opacity(0.15))
                        }
                    }
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Design.Colors.bobaCyan.opacity(0.5), lineWidth: 2)
                    )
                    Text("\(card.playCost ?? 0) HD")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(4)
                }
                Text(card.name)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - FutureBattlePickSheet
// ════════════════════════════════════════════════════════════════
//
// Delayed Recovery and other cards with selector
// `unrevealed_hero_player_pick`. Lists the candidate unrevealed
// future battles' heroes; tapping one registers the mark.

struct FutureBattlePickSheet: View {
    let store: PracticeStore
    let pick: PracticeStore.FutureBattlePick
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    Text("Choose an Unrevealed Hero")
                        .font(Design.Fonts.display(20))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("The card's effect triggers on the chosen hero's reveal.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    ForEach(pick.candidateBattleIndices, id: \.self) { idx in
                        Button {
                            store.confirmFutureBattlePick(battleIdx: idx)
                            dismiss()
                        } label: {
                            candidateRow(battleIdx: idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Design.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.cancelFutureBattlePick()
                        dismiss()
                    }
                    .font(Design.Fonts.mono(13, weight: .bold))
                }
            }
        }
    }

    private func candidateRow(battleIdx: Int) -> some View {
        let slot = battleIdx < store.battles.count ? store.battles[battleIdx] : nil
        let card = pick.side == .player ? slot?.playerCard : slot?.cpuCard
        return HStack(spacing: Design.Spacing.md) {
            Group {
                if let card, let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Design.Colors.glass)
                        .overlay(
                            Image(systemName: "questionmark.square.dashed")
                                .font(.system(size: 24))
                                .foregroundStyle(Design.Colors.textMuted)
                        )
                }
            }
            .frame(width: 80, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Design.Colors.bobaCyan.opacity(0.4), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("BATTLE \(battleIdx + 1)")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                if let card {
                    Text(card.hero.isEmpty ? card.name : card.hero)
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textPrimary)
                    HStack(spacing: 8) {
                        if let pow = card.power {
                            Text("\(pow) POW")
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.7)))
                        }
                        Text(card.element.uppercased())
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.element(card.element))
                    }
                } else {
                    Text("Unknown hero")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        }
        .padding(Design.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glass, lineWidth: 1)
                )
        )
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - PeekedHandSheet
// ════════════════════════════════════════════════════════════════
//
// Pre-Game Spy and other peek_opponent_hand cards. Shows the
// revealed cards as full visuals (image + cost + ability text)
// instead of the previous 2-second toast that was unreadable
// before it disappeared.

struct PeekedHandSheet: View {
    let store: PracticeStore
    let reveal: PracticeStore.PeekedHandReveal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    if !reveal.sourceCard.isEmpty {
                        Text(reveal.sourceCard.uppercased())
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(2.0)
                    }
                    Text("Opponent's Hand")
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("\(reveal.cards.count) play\(reveal.cards.count == 1 ? "" : "s") revealed.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textSecondary)

                    ForEach(reveal.cards) { card in
                        peekedCard(card: card)
                    }
                }
                .padding(Design.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.dismissPeekedHand()
                        dismiss()
                    }
                    .font(Design.Fonts.mono(13, weight: .bold))
                }
            }
        }
    }

    private func peekedCard(card: Card) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.md) {
            // Card image — fixed 5:7 box matches PlayReviewSheet.
            Group {
                if let file = card.imageFile, !file.isEmpty {
                    CachedAsyncCardImage(url: CDN.full(for: file), contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Design.Colors.glass)
                        .overlay(
                            Image(systemName: "questionmark.square.dashed")
                                .font(.system(size: 24))
                                .foregroundStyle(Design.Colors.textMuted)
                        )
                }
            }
            .frame(width: 100, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Design.Colors.bobaCyan.opacity(0.4), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                if let cost = card.playCost {
                    Text(cost == 0 ? "FREE" : "\(cost) HD")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.7)))
                }
                if let ability = card.playAbility, !ability.isEmpty {
                    Text(ability)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Design.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glass, lineWidth: 1)
                )
        )
    }
}
