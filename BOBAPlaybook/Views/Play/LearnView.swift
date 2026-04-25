//
//  LearnView.swift
//  BOBAPlaybook
//
//  The "Learn" tab — Rules, Strategy, Browse, Collect, Tournament.
//  Was previously part of the combined PlayView; split out in the nav
//  refactor so informational content has its own tab and practice /
//  decks each get their own tabs.
//

import SwiftUI

// ════════════════════════════════════════════════════════════════
// MARK: - Section Enum
// ════════════════════════════════════════════════════════════════

private enum PlaySection: String, CaseIterable, Identifiable {
    case setup      = "Setup"
    case rules      = "Rules"
    case strategy   = "Strategy"
    case browse     = "Browse"
    case collect    = "Collect"
    case glossary   = "Glossary"
    case tournament = "Tournament"
    var id: String { rawValue }
}

// ════════════════════════════════════════════════════════════════
// MARK: - LearnView
// ════════════════════════════════════════════════════════════════

struct LearnView: View {
    @Environment(CardStore.self) private var cardStore
    @State private var selectedSection: PlaySection = .rules

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlaySectionPicker(selected: $selectedSection)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface)

                switch selectedSection {
                case .setup:      SetupView()
                case .rules:      RulesView()
                case .strategy:   StrategyView()
                case .browse:     BrowseView()
                case .collect:    CollectView()
                case .glossary:   GlossaryView()
                case .tournament: TournamentView()
                }
            }
            .frame(maxWidth: .infinity)
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BOBAWordmark() }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Section Picker (horizontal scroll)
// ════════════════════════════════════════════════════════════════

private struct PlaySectionPicker: View {
    @Binding var selected: PlaySection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.xs) {
                ForEach(PlaySection.allCases) { section in
                    pill(for: section)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
        }
    }

    /// Per-pill renderer broken out so the body's type chain stays
    /// short — Swift 6's checker can't infer the full ScrollView →
    /// HStack → ForEach → Button → 5 chained modifiers tree fast
    /// enough when the section count grows.
    @ViewBuilder
    private func pill(for section: PlaySection) -> some View {
        let isSelected = selected == section
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selected = section }
        } label: {
            Text(section.rawValue)
                .font(Design.Fonts.mono(13, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                .padding(.horizontal, Design.Spacing.md)
                .frame(height: 34)
                .background(Capsule().fill(isSelected ? Design.Colors.bobaOrange : Design.Colors.glass))
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Mini Card View (card image + stats used throughout)
// ════════════════════════════════════════════════════════════════

private enum CardOutcome { case win, lose, neutral }

private struct MiniCardView: View {
    let imageFile: String
    let hero: String
    let power: Int
    let element: String
    var outcome: CardOutcome = .neutral
    var width: CGFloat = 86
    /// When set, replaces the element·power row with a custom label (e.g. "HOT DOG").
    var subtitle: String? = nil
    /// When set, overrides the border color (e.g. green for Hot Dog cards).
    var borderOverride: Color? = nil

    private var borderColor: Color {
        if let override = borderOverride { return override.opacity(0.7) }
        switch outcome {
        case .win:     return Color(hex: "4CAF50")
        case .lose:    return Color(hex: "C0392B").opacity(0.8)
        case .neutral: return Design.Colors.element(element).opacity(0.5)
        }
    }
    private var powerColor: Color {
        switch outcome {
        case .win:     return Color(hex: "4CAF50")
        case .lose:    return Color(hex: "C0392B")
        case .neutral: return Design.Colors.textPrimary
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            AsyncImage(url: CDN.thumb(for: imageFile)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass)
                        .overlay(Text(String(hero.prefix(2)).uppercased())
                            .font(Design.Fonts.display(22))
                            .foregroundStyle(Design.Colors.element(element)))
                }
            }
            .frame(width: width, height: width * 7 / 5)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: outcome == .neutral ? 1.5 : 2.5))
            .shadow(color: outcome == .neutral ? .clear : borderColor.opacity(0.6), radius: 8)

            VStack(spacing: 2) {
                Text(hero)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let sub = subtitle {
                    Text(sub)
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                } else {
                    HStack(spacing: 4) {
                        Text(element)
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.element(element))
                        Text("·")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textMuted)
                        Text("\(power)")
                            .font(Design.Fonts.display(18))
                            .foregroundStyle(powerColor)
                    }
                }
            }
        }
        .frame(width: width)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Mini Play Card View
// ════════════════════════════════════════════════════════════════

private struct MiniPlayCardView: View {
    let imageFile: String
    let name: String
    let cost: Int
    var width: CGFloat = 86

    var body: some View {
        VStack(spacing: 5) {
            AsyncImage(url: CDN.thumb(for: imageFile)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass)
                        .overlay(Text(String(name.prefix(2)).uppercased())
                            .font(Design.Fonts.display(22))
                            .foregroundStyle(Design.Colors.bobaCyan))
                }
            }
            .frame(width: width, height: width * 7 / 5)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Design.Colors.bobaCyan.opacity(0.5), lineWidth: 1.5))

            VStack(spacing: 2) {
                Text(name)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                if cost == 0 {
                    Text("FREE")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Color(hex: "4CAF50"))
                } else {
                    HStack(spacing: 3) {
                        Text("\(cost)")
                            .font(Design.Fonts.display(18))
                            .foregroundStyle(Design.Colors.bobaCyan)
                        Text("HOT DOGS")
                            .font(Design.Fonts.mono(7, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .fixedSize()
                    }
                }
            }
        }
        .frame(width: width)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Rules View
// ════════════════════════════════════════════════════════════════

private enum GameMode: String, CaseIterable, Hashable {
    case rookie       = "Rookie"
    case substitution = "Substitution"
    case playmaker    = "Playmaker"
}

// ════════════════════════════════════════════════════════════════
// MARK: - Setup & Edge Cases
// ════════════════════════════════════════════════════════════════
//
// Step-by-step match setup walkthrough + the rules edge cases that
// veteran players debate at the table. Sourced from the Brad+Rob
// 160-Spec tutorial transcript and Cowork's UI handoff §4 + §6.
private struct SetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {

                // ── Pre-match flow ──────────────────────────────
                RulesSectionHeader(title: "Before Battle 1")
                RuleCard(lines: [
                    .init(label: "Roll for Honors",
                          body: "Each player rolls 2d6. Highest total wins initial Honors — the right to act first in every phase of Battle 1. Re-roll on a tie. The practice mode replays this roll on screen so you see who won and why."),
                    .init(label: "Direction (table-only)",
                          body: "In a physical match the Honors player picks the direction the Hero lineup reads (left-to-right or right-to-left). The app uses one consistent visual convention so this step is invisible."),
                    .init(label: "Hero deck",
                          body: "Shuffle your 60-card Hero Deck and place 7 face-down in your Battle row — one per battle slot."),
                    .init(label: "Bench draw",
                          body: "After your 7 are placed, draw 4 more Heroes from the top of the deck for your Bench. The Bench is hidden from your opponent."),
                    .init(label: "Hot Dogs",
                          body: "Both players start with 10 Hot Dogs in their pool. The count is always public information — your opponent can see how many you have at any time."),
                    .init(label: "Playbook (Playmaker only)",
                          body: "Your 30-card Playbook is shuffled and placed face-down. Draw 5 plays for your starting hand. Bonus Plays draw automatically when their trigger fires (gold border in your hand)."),
                ])

                // ── Battle loop ──────────────────────────────────
                RulesSectionHeader(title: "Each Battle Has 5 Phases")
                RuleCard(lines: [
                    .init(label: "1. Substitution",
                          body: "Honors player decides first. Pay 2 Hot Dogs to swap your face-down Hero for one from the Bench. Cost is always 2 — even when a play modifier inflates other costs."),
                    .init(label: "2. Reveal",
                          body: "Both players flip their Hero simultaneously. Element-triggered Bonus Plays fire automatically (e.g., a Glow hero reveal triggers Glow Bonus draws)."),
                    .init(label: "3. Play Window",
                          body: "Players alternate plays, each paying its Hot Dog cost. Pass when you're done. Both must pass to advance to Resolution."),
                    .init(label: "4. Resolution",
                          body: "Powers are compared. Higher wins. Equal power = tie unless one Hero is a Super-weapon type (Playmaker only — Super wins ties). The on-mat power breakdown shows every modifier that contributed."),
                    .init(label: "5. Cleanup",
                          body: "Both players draw 1 Play. Honors moves to the battle winner. Scope-limited effects tick down. The next battle begins automatically."),
                ])

                // ── Edge cases ──────────────────────────────────
                RulesSectionHeader(title: "Common Edge Cases")
                RuleCard(lines: [
                    .init(label: "Substitution cost is always 2",
                          body: "Cost-modifier plays like Dog On Inflation (+2 to plays) do NOT affect Substitution. The Substitute button always shows 2 HD regardless of active modifiers."),
                    .init(label: "Pull The Plug only cancels rest-of-game effects",
                          body: "Persistent effects scoped to specific battles (next 2 battles, battle 7, etc.) survive Pull The Plug. After playing it, you'll see a CANCELLED / UNCHANGED breakdown so you know exactly what was hit."),
                    .init(label: "Recycle clears attached effects",
                          body: "When a play is shuffled out of your discard back into your Playbook, any rest-of-game effect it had stops applying. If Flash Sale is active, recycling it removes the −1 cost discount."),
                    .init(label: "Play Booster recounts every time",
                          body: "Play Booster's draw amount = plays used this battle, including itself. If you play it again later in the same battle, the recount includes the previous Play Booster."),
                    .init(label: "Deck exhaustion auto-reshuffles",
                          body: "When your Playbook hits 0 cards, the discard pile shuffles back in automatically. You'll see a brief 'Playbook reshuffled · N cards back into deck' notification."),
                    .init(label: "Bonus Plays don't count against the 30-card limit",
                          body: "Cards with the gold ★ BONUS tag are extras — they enter the deck through element triggers and don't count against the 30-Play deckbuilding cap. They're surfaced visually so you can plan around them."),
                ])

                // ── Reading the playmat ─────────────────────────
                RulesSectionHeader(title: "Reading the Playmat")
                RuleCard(lines: [
                    .init(label: "Persistent-effects banner (top)",
                          body: "Every active effect with its scope and remaining battles. Cyan tab = your effect, violet tab = opponent's. The number badge ticks down every battle."),
                    .init(label: "Plays-used row (under each Hero)",
                          body: "Every play used this battle, in order. Drives Play Booster / 10 Per Play / No Huddle math you can verify visually."),
                    .init(label: "Effective-cost display (in hand)",
                          body: "Plays whose cost has been modified show 3→5 with the original struck through. Green = discounted, amber = inflated but affordable, red = unaffordable."),
                    .init(label: "Power breakdown (after resolution)",
                          body: "Itemized list of every modifier that contributed: base power, each played card, each persistent. Footings to the engine's verdict so you can audit the math."),
                    .init(label: "Discard inspector (tap discard chip)",
                          body: "Tap the DISCARD chip in the bottom toolbar (or the play count next to CPU) to see the full list of cards used so far."),
                ])
            }
            .padding(Design.Spacing.lg)
        }
        .background(Design.Colors.nearBlack)
    }
}

private struct RulesView: View {
    @State private var selectedMode: GameMode = .rookie

    var body: some View {
        VStack(spacing: 0) {
            // One mode picker — the only control for mode selection
            HStack(spacing: Design.Spacing.xs) {
                ForEach(GameMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedMode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(Design.Fonts.mono(13, weight: selectedMode == mode ? .bold : .regular))
                            .foregroundStyle(selectedMode == mode ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Capsule().fill(selectedMode == mode ? Design.Colors.bobaCyan : Design.Colors.glass))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
            .background(Design.Colors.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                    modeCallout(for: selectedMode)

                    switch selectedMode {
                    case .rookie:       RookieBattleScenario()
                    case .substitution: SubstitutionScenario()
                    case .playmaker:    PlaymakerScenario()
                    }

                    StaticBattleFlowView()

                    switch selectedMode {
                    case .rookie:       RookieRulesContent()
                    case .substitution: SubstitutionRulesContent()
                    case .playmaker:    PlaymakerRulesContent()
                    }

                    CardZonesSection()
                    DeckbuildingSection()
                }
                .frame(maxWidth: .infinity)
                .padding(Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .id(selectedMode)
        }
        .frame(maxWidth: .infinity)
    }

    private func modeCallout(for mode: GameMode) -> some View {
        let color: Color = mode == .rookie ? Design.Colors.bobaOrange : mode == .substitution ? .yellow : Design.Colors.bobaCyan
        let desc: String
        let components: [(String, Color)]
        switch mode {
        case .rookie:
            desc = "Pure power comparison. No substitutions, no Play cards. Perfect for learning the basics."
            components = [("Hero Deck (60 cards)", Design.Colors.bobaOrange)]
        case .substitution:
            desc = "Add hand management and resource decisions. Spend 2 Hot Dogs to substitute a Hero before cards are revealed."
            components = [("Hero Deck (60)", Design.Colors.bobaOrange), ("Hot Dog Deck (10)", .yellow)]
        case .playmaker:
            desc = "The full game. Tournament standard. Play cards add powerful effects before each battle resolves."
            components = [("Hero Deck (60)", Design.Colors.bobaOrange), ("Hot Dog Deck (10)", .yellow), ("Playbook (30 Plays)", Design.Colors.bobaCyan)]
        }

        return VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text(mode.rawValue.uppercased() + " MODE")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(color)
                .tracking(1.5)
            Text(desc)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: Design.Spacing.xs) {
                ForEach(components, id: \.0) { comp in
                    HStack(spacing: 5) {
                        Circle().fill(comp.1).frame(width: 7, height: 7)
                        Text(comp.0)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(comp.1.opacity(0.1))
                        .overlay(Capsule().strokeBorder(comp.1.opacity(0.3), lineWidth: 1)))
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(color.opacity(0.3), lineWidth: 1)))
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Static Battle Flow (all phases always visible)
// ════════════════════════════════════════════════════════════════

private struct StaticBattleFlowView: View {
    private struct Phase {
        let number: String; let label: String; let desc: String
        let modes: String; let color: Color
    }
    private let phases: [Phase] = [
        Phase(number: "1", label: "SUB",     desc: "Pay 2 HD to substitute (face-down)", modes: "Sub +", color: .yellow),
        Phase(number: "2", label: "REVEAL",  desc: "Flip both Heroes face-up",     modes: "All modes",  color: Design.Colors.bobaOrange),
        Phase(number: "3", label: "PLAYS",   desc: "Play cards from hand",         modes: "PM only",    color: Design.Colors.bobaCyan),
        Phase(number: "4", label: "RESOLVE", desc: "Higher Power wins",            modes: "All modes",  color: Color(hex: "4CAF50")),
    ]

    var body: some View {
        VStack(alignment: .center, spacing: Design.Spacing.sm) {
            Text("EACH BATTLE — ALL PHASES")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Design.Spacing.lg)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.offset) { idx, phase in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle().fill(phase.color).frame(width: 38, height: 38)
                                .shadow(color: phase.color.opacity(0.45), radius: 6)
                            Text(phase.number).font(Design.Fonts.display(16)).foregroundStyle(.white)
                        }
                        Text(phase.label)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(phase.color).tracking(0.4)
                        Text(phase.desc)
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(phase.modes)
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(phase.color.opacity(0.8))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(phase.color.opacity(0.12))
                                .overlay(Capsule().strokeBorder(phase.color.opacity(0.3), lineWidth: 0.5)))
                    }
                    .frame(maxWidth: .infinity)

                    if idx < phases.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted.opacity(0.4))
                            .padding(.top, 14)
                    }
                }
            }
            .padding(Design.Spacing.md)

            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                Text("Honors (right to act first) passes to the battle winner. Coin flip decides Honors for Battle 1.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Design.Spacing.sm).padding(.bottom, Design.Spacing.sm)
        }
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1)))
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Battle Scenarios (visual card examples per mode)
// ════════════════════════════════════════════════════════════════

// MARK: Rookie — Showtime (ICE 135) beats Kettle-Bell (ICE 110)
private struct RookieBattleScenario: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            scenarioHeader("EXAMPLE BATTLE", sub: "Both players flip their Hero — higher Power wins")

            HStack(alignment: .bottom) {
                Spacer()
                MiniCardView(imageFile: "2-Showtime-Base_Set-First_Edition.webp",       hero: "Showtime",   power: 135, element: "ICE",  outcome: .win)
                Spacer()
                vsLabel
                Spacer()
                MiniCardView(imageFile: "96-Kettle-Bell-Base_Set-First_Edition.webp",   hero: "Kettle-Bell", power: 110, element: "ICE", outcome: .lose)
                Spacer()
            }

            resultBanner(icon: "checkmark.circle.fill", color: Color(hex: "4CAF50"),
                         text: "Showtime wins — 135 > 110. Honors passes to the Showtime player for the next battle.")
        }
        .padding(Design.Spacing.md)
        .background(scenarioBg)
    }
}

// MARK: Substitution — D-Hop (STEEL 85) is losing → sub to LeBoss (FIRE 135) → wins vs Matata (STEEL 130)
private struct SubstitutionScenario: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            scenarioHeader("EXAMPLE BATTLE", sub: "Player B has a weak Hero — a blind substitution before reveal turns the tide")

            phaseLabel("① SUB (cards face-down)")
            HStack(alignment: .bottom) {
                Spacer()
                MiniCardView(imageFile: "6-Matata-Base_Set-First_Edition.webp",    hero: "Matata", power: 130, element: "STEEL", outcome: .neutral)
                Spacer()
                vsLabel
                Spacer()
                MiniCardView(imageFile: "175-D-Hop-Base_Set-First_Edition.webp",    hero: "D-Hop",  power: 85,  element: "STEEL", outcome: .lose)
                Spacer()
            }

            resultBanner(icon: "arrow.triangle.2.circlepath", color: .yellow,
                         text: "Player B substitutes — Pays 2 Hot Dogs · Sends D-Hop to Discard · Places LeBoss face-down from Bench · Draws a new Hero to Bench")

            phaseLabel("② REVEAL — both cards flipped")
            HStack(alignment: .bottom) {
                Spacer()
                MiniCardView(imageFile: "6-Matata-Base_Set-First_Edition.webp",  hero: "Matata",  power: 130, element: "STEEL", outcome: .lose)
                Spacer()
                vsLabel
                Spacer()
                MiniCardView(imageFile: "1-LeBoss-Base_Set-First_Edition.webp",   hero: "LeBoss",  power: 135, element: "FIRE",  outcome: .win)
                Spacer()
            }

            resultBanner(icon: "checkmark.circle.fill", color: Color(hex: "4CAF50"),
                         text: "LeBoss wins — 135 > 130. A blind sub flipped a 45-point deficit into a 5-point win at the cost of 2 Hot Dogs.")
        }
        .padding(Design.Spacing.md)
        .background(scenarioBg)
    }
}

// MARK: Playmaker — Crosbow (BRAWL 120) losing vs Caliber (STEEL 135) → plays "Buff Up 20" → wins
private struct PlaymakerScenario: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            scenarioHeader("EXAMPLE BATTLE", sub: "Player A is losing — a Play card swings the battle")

            phaseLabel("② REVEAL")
            HStack(alignment: .bottom) {
                Spacer()
                MiniCardView(imageFile: "185-Crosbow-Base_Set-First_Edition.webp", hero: "Crosbow", power: 120, element: "BRAWL", outcome: .lose)
                Spacer()
                vsLabel
                Spacer()
                MiniCardView(imageFile: "24-Caliber-Base_Set-First_Edition.webp",  hero: "Caliber", power: 135, element: "STEEL", outcome: .win)
                Spacer()
            }

            phaseLabel("③ PLAY WINDOW — Player A plays a card")
            HStack(spacing: Design.Spacing.md) {
                // Play card art
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.5), lineWidth: 1.5))
                        .frame(width: 60, height: 84)
                    VStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 18)).foregroundStyle(Color.purple)
                        Text("PLAY").font(Design.Fonts.mono(8, weight: .bold)).foregroundStyle(Color.purple)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Buff Up 20")
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Color.purple)
                    HStack(spacing: 4) {
                        Text("Cost:")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                        Text("2 Hot Dogs")
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(.yellow)
                    }
                    Text("+20 Power to your Hero this battle.")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                    Text("Crosbow: 120 + 20 = 140 effective power")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
            }
            .padding(Design.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: Design.Radius.sm).fill(Color.purple.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm).strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)))

            phaseLabel("④ RESOLVE")
            HStack(alignment: .bottom) {
                Spacer()
                VStack(spacing: 5) {
                    AsyncImage(url: CDN.thumb(for: "185-Crosbow-Base_Set-First_Edition.webp")) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        else { RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass) }
                    }
                    .frame(width: 86, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "4CAF50"), lineWidth: 2.5))
                    .shadow(color: Color(hex: "4CAF50").opacity(0.6), radius: 8)
                    VStack(spacing: 2) {
                        Text("Crosbow").font(Design.Fonts.mono(10, weight: .bold)).foregroundStyle(Design.Colors.textPrimary)
                        HStack(spacing: 3) {
                            Text("120").font(Design.Fonts.display(13)).foregroundStyle(Design.Colors.textMuted).strikethrough()
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Design.Colors.bobaCyan)
                            Text("140").font(Design.Fonts.display(18)).foregroundStyle(Color(hex: "4CAF50"))
                        }
                    }
                }
                .frame(width: 86)
                Spacer()
                vsLabel
                Spacer()
                MiniCardView(imageFile: "24-Caliber-Base_Set-First_Edition.webp", hero: "Caliber", power: 135, element: "STEEL", outcome: .lose)
                Spacer()
            }

            resultBanner(icon: "bolt.fill", color: Design.Colors.bobaCyan,
                         text: "Crosbow wins — 140 > 135. A 2-Hot-Dog Play turned a 15-point deficit into a 5-point win.")
        }
        .padding(Design.Spacing.md)
        .background(scenarioBg)
    }
}

// MARK: - Scenario helpers
private func scenarioHeader(_ title: String, sub: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title).font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
        Text(sub).font(Design.Fonts.mono(13)).foregroundStyle(Design.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private var vsLabel: some View {
    Text("VS").font(Design.Fonts.display(13)).foregroundStyle(Design.Colors.textMuted).padding(.bottom, 28)
}

private func phaseLabel(_ text: String) -> some View {
    Text(text).font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(0.8)
}

private func resultBanner(icon: String, color: Color, text: String) -> some View {
    HStack(spacing: Design.Spacing.sm) {
        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
        Text(text).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Design.Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Design.Radius.sm).fill(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm).strokeBorder(color.opacity(0.25), lineWidth: 1)))
}

private var scenarioBg: some View {
    RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
}

// ════════════════════════════════════════════════════════════════
// MARK: - Shared Rules Components
// ════════════════════════════════════════════════════════════════

private struct RulesSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Design.Fonts.mono(12, weight: .bold))
            .foregroundStyle(Design.Colors.textMuted)
            .tracking(1.5)
            .padding(.bottom, Design.Spacing.xs)
    }
}

private struct RuleCard: View {
    let lines: [RuleLine]
    struct RuleLine: Identifiable {
        let id = UUID(); let label: String?; let body: String
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: Design.Spacing.sm) {
                    Text("·").font(Design.Fonts.mono(15)).foregroundStyle(Design.Colors.bobaOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        if let label = line.label {
                            Text(label).font(Design.Fonts.mono(15, weight: .bold)).foregroundStyle(Design.Colors.textPrimary)
                        }
                        Text(line.body).font(Design.Fonts.mono(14)).foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1)))
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Mode-specific Rules Content
// ════════════════════════════════════════════════════════════════

private struct RookieRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            RulesSectionHeader(title: "Setup")
            RuleCard(lines: [
                .init(label: "Hero Deck",    body: "Shuffle your 60-card Hero Deck and place it face-down."),
                .init(label: "Battle Slots", body: "Place 7 Heroes face-down in a row — one per Battle slot."),
                .init(label: "Honors",       body: "Flip a coin. Winner earns Honors — the right to act first each battle."),
            ])
            RulesSectionHeader(title: "Winning")
            RuleCard(lines: [
                .init(label: "Win condition",         body: "First player to win 4 of 7 Battles wins the game. A sweep can end in Battle 4 (4–0)."),
                .init(label: "Tied battle",           body: "If both Heroes have equal Power, the battle is a draw — no trophy is awarded. Honors stays with the same player."),
                .init(label: "Tied game → Sudden Death", body: "If both players win the same number of battles after all 7, each reveals the top card of their Hero Deck. Higher Power wins. Repeat until broken."),
                .init(label: "Honors after a battle", body: "Passes to the winner of each battle. On a draw, Honors stays with the same player."),
            ])
        }
    }
}

private struct SubstitutionRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            RulesSectionHeader(title: "Additional Setup")
            RuleCard(lines: [
                .init(label: "Bench",        body: "After placing your 7 face-down Battle Heroes, draw 4 additional Heroes from your Hero Deck and place them in your Bench (kept hidden from opponent)."),
                .init(label: "Hot Dog Pile", body: "All 10 Hot Dogs go into your Hot Dog pile. The count is always public information."),
            ])
            RulesSectionHeader(title: "Substitution Phase")
            RuleCard(lines: [
                .init(label: "When",      body: "Before Heroes are revealed — cards are still face-down. This is a blind decision."),
                .init(label: "Cost",      body: "Pay 2 Hot Dogs. Send the face-down Hero to the Discard Pile. Place a Hero from your Bench face-down into the Battle Zone. Draw a new Hero from your Hero Deck to refill your Bench."),
                .init(label: "Order",     body: "Honors player decides first — your opponent sees whether you substituted before making their own decision."),
                .init(label: "Limit",     body: "Each player may substitute at most once per battle."),
            ])
            RulesSectionHeader(title: "Resource Note")
            RuleCard(lines: [
                .init(label: nil, body: "10 Hot Dogs total — at most 5 substitutions all game. Having Honors means you act first and reveal your intention. Sometimes passing forces your opponent to commit before you respond.")
            ])
        }
    }
}

private struct PlaymakerRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            RulesSectionHeader(title: "Additional Setup")
            RuleCard(lines: [
                .init(label: "Playbook", body: "Shuffle your 30 unique Play cards. Draw 4 as your starting hand."),
                .init(label: "Draw",     body: "Draw 1 Play at the end of each battle (during cleanup)."),
            ])
            RulesSectionHeader(title: "Play Window")
            RuleCard(lines: [
                .init(label: "When",        body: "After Heroes are revealed, before the battle winner is decided."),
                .init(label: "Who first",   body: "The player with Honors may run one or more Plays, then passes."),
                .init(label: "Then",        body: "The other player may run one or more Plays, then passes."),
                .init(label: "Cost",        body: "Pay the Hot Dog cost shown on the card and resolve its effect."),
                .init(label: "One opportunity", body: "Each player gets only one opportunity per battle to run Plays. Once you pass, you cannot play more cards that battle."),
            ])
            RulesSectionHeader(title: "Super Tiebreaker")
            RuleCard(lines: [
                .init(label: nil, body: "If a battle ends in a tie and one Hero has the SUPER weapon type, that Hero wins automatically. No Sudden Death.")
            ])
            RulesSectionHeader(title: "Formats")
            RuleCard(lines: [
                .init(label: "Standard", body: "Playmaker is the competitive and tournament-standard format."),
                .init(label: "SPEC",     body: "No single Hero may have Power above 160. Sideboard of up to 45 standard Plays + unlimited Bonus Plays. Players may swap Plays between matches, but NOT between games within a match."),
            ])
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Card Zones & Deckbuilding
// ════════════════════════════════════════════════════════════════

private struct CardZonesSection: View {
    private let zones: [(String, String)] = [
        ("Hero Deck",       "Your 60-card main deck — the source for battle Heroes"),
        ("Battle Slots",    "7 face-down positions; one Hero per slot revealed in sequence"),
        ("Bench / Hand",    "4 Heroes drawn after setup (for substitution) and Play cards drawn from Playbook"),
        ("Active Battle",   "The current face-up Hero in the active battle position"),
        ("Discard Pile",    "Face-up; always public information"),
        ("Playbook",        "Your 30-card Play deck (Playmaker only)"),
        ("Hot Dog Pile",    "10-card resource pile; count is always public"),
        ("Hot Dog Discard", "Spent Hot Dogs go here"),
        ("Abyss",           "Removed from game permanently — cannot be retrieved"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            RulesSectionHeader(title: "Card Zones Reference")
            VStack(spacing: 1) {
                ForEach(zones, id: \.0) { zone in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(zone.0)
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                        Text(zone.1)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.md).padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
        }
    }
}

private struct DeckbuildingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            RulesSectionHeader(title: "Deckbuilding Rules")
            RuleCard(lines: [
                .init(label: "Hero Deck",     body: "Exactly 60 cards (minimum 40 for Draft/Sealed limited events)."),
                .init(label: "Power rule",    body: "Maximum 6 copies of any single Power value in your Hero Deck."),
                .init(label: "Variation",     body: "Only 1 copy per variation. BoJax First Edition and BoJax 2026 Edition are different variations — both legal together."),
                .init(label: "Hero copies",   body: "Up to 6 total copies of the same hero name across all variations."),
                .init(label: "Hot Dog Deck",  body: "Exactly 10 cards. Duplicates are allowed."),
                .init(label: "Playbook",      body: "Exactly 30 Plays, all unique names. Bonus Plays (special treatment) may be added beyond 30."),
            ])
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Strategy View
// ════════════════════════════════════════════════════════════════

private struct StrategyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                PowerCurveSection()
                SubstitutionStrategySection()
                WeaponSynergySection()
                PlayCardTypesSection()
                ResourceManagementSection()
                ArchetypesSection()
            }
            .frame(maxWidth: .infinity)
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
    }
}

// MARK: Shared strategy components

private struct StrategyDisclosure<Content: View>: View {
    let title: String; let subtitle: String
    @State private var isExpanded = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Design.Fonts.display(17)).foregroundStyle(Design.Colors.textPrimary)
                        Text(subtitle).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Design.Colors.bobaOrange)
                }
                .padding(Design.Spacing.md)
            }
            .buttonStyle(.plain)
            if isExpanded {
                VStack(alignment: .leading, spacing: Design.Spacing.md) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.md).padding(.bottom, Design.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1)))
    }
}

private struct StrategyBody: View {
    let text: String
    var body: some View {
        Text(text).font(Design.Fonts.mono(14)).foregroundStyle(Design.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StrategyBullet: View {
    let text: String; var accent: Color = Design.Colors.bobaOrange
    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Text("·").font(Design.Fonts.mono(15)).foregroundStyle(accent)
            Text(text).font(Design.Fonts.mono(14)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Power Curve — 3 example cards showing low / mid / high tiers

private struct PowerCurveSection: View {
    private let tiers: [(label: String, range: String, file: String, hero: String, power: Int, el: String, color: Color)] = [
        ("LOW",  "85–115\nPosition wisely",  "175-D-Hop-Base_Set-First_Edition.webp",      "D-Hop",   85,  "STEEL", Color(hex: "8A9BB0")),
        ("MID",  "120–155\nConsistency",     "185-Crosbow-Base_Set-First_Edition.webp",   "Crosbow", 120, "BRAWL", Color(hex: "C0392B")),
        ("HIGH", "160+\nSave for clutch",    "1-LeBoss-Base_Set-First_Edition.webp",       "LeBoss",  135, "FIRE",  Design.Colors.bobaOrange),
    ]

    var body: some View {
        StrategyDisclosure(title: "Power Curve Management",
                           subtitle: "Spread your deck across power bands; slot Heroes strategically") {
            StrategyBody(text: "The 6-per-power-value rule forces you to spread across levels. A smart build balances three tiers:")

            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                ForEach(tiers, id: \.label) { tier in
                    VStack(spacing: Design.Spacing.xs) {
                        MiniCardView(imageFile: tier.file, hero: tier.hero, power: tier.power, element: tier.el, width: 78)
                        Text(tier.label)
                            .font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(tier.color)
                        Text(tier.range)
                            .font(Design.Fonts.mono(10)).foregroundStyle(Design.Colors.textMuted)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xs)

            StrategyBullet(text: "Front-load strong Heroes to establish Honors momentum early.")
            StrategyBullet(text: "Save High-tier Heroes for Battles 5–7 — games are often decided in the final stretch.")
            StrategyBullet(text: "Late Hit (+35 in Battle 7) and The Closer (+40 in Battle 7) amplify back-loaded positioning.")
        }
    }
}

// MARK: Substitution Strategy

private struct SubstitutionStrategySection: View {
    @Environment(CardStore.self) private var cardStore

    /// Resolve a Hot Dog by name so art is pulled from the real catalog
    /// entry instead of relying on hardcoded (and now stale) filenames.
    private func hotDog(_ name: String) -> Card? {
        cardStore.displayCards.first { $0.isHotDog && $0.name == name && $0.imageFile?.isEmpty == false }
    }

    var body: some View {
        StrategyDisclosure(title: "Substitution Strategy",
                           subtitle: "10 Hot Dogs total — max 5 substitutions all game") {
            HStack(alignment: .top, spacing: Design.Spacing.md) {
                if let frank = hotDog("Frank") {
                    strategyThumbnail(card: frank, width: 80, accent: Color(hex: "4CAF50"))
                }
                if let grillbert = hotDog("Grillbert") {
                    strategyThumbnail(card: grillbert, width: 80, accent: Color(hex: "4CAF50"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("10 total")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("Pay 2 to substitute a Hero.\nPay 0–6 to play Play cards.\nBoth draw from the same pool.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Design.Spacing.xs)

            StrategyBody(text: "Hot Dogs fund both substitutions (2 each) and Play cards. Every sub is a potential Play card foregone. Never substitute reflexively.")
            StrategyBullet(text: "Substitute only when the power gap justifies the cost. Going from -45 to +5 is a steal. Going from -2 to +2 may not be worth it.")
            StrategyBullet(text: "Watch your opponent's Hot Dog count. At 0, they cannot sub or play paid cards — this is your strongest attacking window.")
            StrategyBullet(text: "Honors means you act first. Sometimes passing forces your opponent to commit before you respond.")
            StrategyBullet(text: "Save subs for Battles 5–7. Early battles rarely decide games; late battles always do.")
        }
    }
}

/// Small reusable thumbnail used by the Strategy sections — pulls art
/// from the catalog via CardImageView (cache-aware), shows card name
/// + a subtitle (HOT DOG / 2 HOT DOGS / FREE). Keeps the Strategy cards
/// visually in sync with the real catalog so a hero / play rename
/// doesn't silently break a hardcoded filename.
private struct strategyThumbnail: View {
    let card: Card
    var width: CGFloat = 80
    var accent: Color = .clear

    var body: some View {
        VStack(spacing: 5) {
            CardImageView(card: card, size: .thumb)
                .frame(width: width, height: width * 7 / 5)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent == .clear
                                  ? Design.Colors.element(card.element).opacity(0.5)
                                  : accent.opacity(0.7),
                                  lineWidth: 1.5))
            Text(card.hero.isEmpty ? card.name : card.hero)
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            if card.isHotDog {
                Text("HOT DOG")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            } else if card.isPlay, let cost = card.playCost {
                Text(cost == 0 ? "FREE" : "\(cost) HD")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(cost == 0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
            } else if card.isHero, let p = card.power {
                HStack(spacing: 4) {
                    Text(card.element)
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.element(card.element))
                    Text("·")
                        .font(Design.Fonts.mono(9))
                        .foregroundStyle(Design.Colors.textMuted)
                    Text("\(p)")
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
            }
        }
        .frame(width: width)
    }
}

// MARK: Weapon Synergy

private struct WeaponSynergySection: View {
    private let synergies: [(weapon: String, plays: [String])] = [
        ("FIRE",  ["Fire Boost", "Fire Crew", "Flame Wall", "Burning Fever", "Eternal Flame", "Smitty"]),
        ("ICE",   ["Ice Boost", "Ice Crew", "Icy Shield", "Frozen Resolve", "Frozen Lineup", "Unbreakable Ice"]),
        ("STEEL", ["Steel Boost", "Steel Crew", "Steel Defense", "Steel Shield", "Chrome Will", "Steel Cage"]),
    ]
    var body: some View {
        StrategyDisclosure(title: "Weapon Synergy",
                           subtitle: "Build around 1–2 weapon types; many Plays reward consistency") {
            StrategyBody(text: "Focused weapon builds outperform toolbox builds when the engine runs. Use weapon-agnostic Plays (Weapon Mixer, Edge Rush, Brothers In Arms) if mixing types.")
            ForEach(synergies, id: \.weapon) { entry in
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text(entry.weapon)
                        .font(Design.Fonts.mono(13, weight: .bold)).foregroundStyle(Design.Colors.element(entry.weapon))
                    FlowLayout(spacing: Design.Spacing.xs) {
                        ForEach(entry.plays, id: \.self) { play in
                            Text(play).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.element(entry.weapon))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Design.Colors.element(entry.weapon).opacity(0.1))
                                    .overlay(Capsule().strokeBorder(Design.Colors.element(entry.weapon).opacity(0.3), lineWidth: 1)))
                        }
                    }
                }
                .padding(Design.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Design.Radius.sm).fill(Design.Colors.surface2))
            }
        }
    }
}

// MARK: Play Card Types

private struct PlayCardTypesSection: View {
    @Environment(CardStore.self) private var cardStore

    private struct PlayType {
        let name: String
        let desc: String
        let color: Color
        /// Resolved from the catalog by name — no more stale filenames.
        let cardName: String
    }
    private let types: [PlayType] = [
        PlayType(name: "Tempo",        desc: "Immediate one-time power boost.",                      color: Design.Colors.bobaOrange,
                 cardName: "Buff Up 15"),
        PlayType(name: "Value",        desc: "Ongoing effect that compounds across battles.",        color: Design.Colors.bobaCyan,
                 cardName: "Fire Boost"),
        PlayType(name: "Disruption",   desc: "Deny opponent options for a battle or permanently.",   color: Color(hex: "8B00FF"),
                 cardName: "Bench Blocker"),
        PlayType(name: "Economy",      desc: "Recover Hot Dogs — sustain your resource advantage.",  color: .yellow,
                 cardName: "Trash Bandit"),
        PlayType(name: "Game-Changer", desc: "High-cost, match-defining effects that flip any battle.", color: Color(hex: "FF0090"),
                 cardName: "By Any Means Necessary"),
    ]

    private func play(_ name: String) -> Card? {
        // Prefer First Edition Plays so the thumbnail is the canonical art.
        let candidates = cardStore.displayCards.filter {
            $0.isPlay && $0.name == name && $0.imageFile?.isEmpty == false
        }
        return candidates.first { $0.variation == "First Edition" && $0.treatment == "Plays" }
            ?? candidates.first { $0.treatment == "Plays" }
            ?? candidates.first
    }

    var body: some View {
        StrategyDisclosure(title: "Play Card Types",
                           subtitle: "Tempo · Value · Disruption · Economy · Game-changer") {
            ForEach(Array(types.enumerated()), id: \.offset) { _, type_ in
                HStack(alignment: .top, spacing: Design.Spacing.sm) {
                    if let card = play(type_.cardName) {
                        strategyThumbnail(card: card, width: 80, accent: type_.color)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type_.name)
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(type_.color)
                        Text(type_.desc)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textSecondary)
                        // Pull the ability text live from the catalog so
                        // card-text changes flow through automatically.
                        if let card = play(type_.cardName), let ability = card.playAbility, !ability.isEmpty {
                            Text("\u{201C}\(ability)\u{201D}")
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textMuted)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Design.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Design.Radius.sm).fill(type_.color.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm).strokeBorder(type_.color.opacity(0.2), lineWidth: 1)))
            }
        }
    }
}

// MARK: Resource Management

private struct ResourceManagementSection: View {
    var body: some View {
        StrategyDisclosure(title: "Resource Management",
                           subtitle: "Plays and Hot Dogs are finite — track both publicly") {
            StrategyBody(text: "Start with 4 Plays in hand. Draw 1 at the end of each battle — up to 11 total across a full game. Your Playbook has 30 unique Plays; spent Plays are visible and countable.")
            StrategyBullet(text: "Hot Dogs fund both subs (2 each) and Plays — every paid Play is a potential sub foregone.")
            StrategyBullet(text: "Free (0-cost) Plays are disproportionately strong — they preserve Hot Dogs while adding power.")
            StrategyBullet(text: "At 0 Hot Dogs, a player cannot sub or play paid cards. This is the most exploitable position in the game.")
            StrategyBullet(text: "Count the opponent's Play count. Heavy early spending depletes their options in the critical late battles.")
        }
    }
}

// MARK: Archetypes

private struct ArchetypesSection: View {
    private let archetypes: [Archetype] = [
        Archetype(name: "Fire Aggro",          element: "FIRE",
                  tagline: "Stack Fire synergies early; lock opponents with Flame Wall",
                  strategy: "Establish Fire Boost and Fire Crew for a persistent +10 power bump on every FIRE Hero. Flame Wall prevents the opponent from neutralizing your type advantage. Close games with Burning Fever and Eternal Flame. Requires a deep FIRE Hero roster.",
                  weakness: "Fire Extinguisher · Fire Hose · Only Ice",
                  keyPlays: ["Fire Boost","Fire Crew","Flame Wall","Burning Fever","Eternal Flame","Smitty"]),
        Archetype(name: "Ice Control",         element: "ICE",
                  tagline: "Deny substitutions; protect key Heroes behind layers of ice",
                  strategy: "Icy Shield and Unbreakable Ice make Heroes impossible to substitute against. Frozen Lineup locks opponent Heroes in place. ICE Control wins through attrition — be patient, preserve Hot Dogs, and outlast your opponent over 7 battles.",
                  weakness: "Ice Pick · Icevantage · Frost-Hardened",
                  keyPlays: ["Ice Boost","Ice Crew","Icy Shield","Frozen Resolve","Frozen Lineup","Unbreakable Ice"]),
        Archetype(name: "Steel Wall",          element: "STEEL",
                  tagline: "Layer Steel protections until your Heroes are nearly invulnerable",
                  strategy: "Stack Steel Defense, Shield, and Chrome Will until opponents can't remove your Heroes effectively. Steel Cage prevents removal entirely. Mid-range STEEL Heroes become formidable threats with enough protection stacked.",
                  weakness: "Stain-Less-Steel · Rusted Edge · Molten Steel",
                  keyPlays: ["Steel Boost","Steel Crew","Steel Defense","Steel Shield","Chrome Will","Steel Cage"]),
        Archetype(name: "Mixed Toolbox",       element: "NONE",
                  tagline: "Maximum flexibility — adapt to any opponent in real time",
                  strategy: "Weapon-agnostic Plays adapt to any matchup. Edge Rush and Deadline Deal let you react to any power level. Brothers In Arms rewards diverse Hero rosters. No weakness to weapon-specific hate, but also no dominant synergy engine.",
                  weakness: "No single synergy as powerful as a focused build",
                  keyPlays: ["Weapon Mixer","Weapon Tangle","Brothers In Arms","Different Leagues","Edge Rush"]),
        Archetype(name: "Economy / Attrition", element: "NONE",
                  tagline: "Recover Hot Dogs faster than your opponent can spend them",
                  strategy: "Continuously refresh your Hot Dog supply while draining your opponent's. Bun Shortage limits their recovery. Mutually Assured Dogstruction resets both piles — play it when you're already low to equalize. Win in the late game when they're resource-starved.",
                  weakness: "Loses quickly to fast aggro when recovery stalls",
                  keyPlays: ["Trash Bandit","Victory Dinner","Make Up Meal","Too Full To Fight","Bun Shortage","Mutually Assured Dogstruction"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("ARCHETYPE TEMPLATES")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(2)
            ForEach(archetypes) { arch in ArchetypeCard(archetype: arch) }
        }
    }
}

private struct Archetype: Identifiable {
    let id = UUID(); let name, element, tagline, strategy, weakness: String; let keyPlays: [String]
}

private struct ArchetypeCard: View {
    let archetype: Archetype
    @Environment(CardStore.self) private var cardStore
    @State private var isExpanded = false
    @State private var selectedCard: Card? = nil
    private var accent: Color { Design.Colors.element(archetype.element) }

    /// Resolves each key-play name to an actual Play card so the archetype
    /// can show art, not just text chips. Picks a Play with an imageFile
    /// (First Edition Base if available) so no example is a blank square.
    private var keyPlayCards: [Card] {
        archetype.keyPlays.compactMap { name in
            let candidates = cardStore.displayCards.filter { c in
                c.name == name && c.isPlay && (c.imageFile?.isEmpty == false)
            }
            // Prefer First Edition Base Set for a clean-looking archetype
            // thumbnail row; otherwise the first hit wins.
            return candidates.first { $0.variation == "First Edition" && $0.treatment == "Plays" }
                ?? candidates.first { $0.treatment == "Plays" }
                ?? candidates.first
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Design.Spacing.md) {
                    Circle().fill(accent).frame(width: 10, height: 10).shadow(color: accent.opacity(0.6), radius: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(archetype.name).font(Design.Fonts.display(17)).foregroundStyle(Design.Colors.textPrimary)
                        Text(archetype.tagline).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                }
                .padding(Design.Spacing.md)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    Divider().background(Design.Colors.glassBorder)
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        Text("KEY PLAYS").font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
                        Text("Tap any card to see its full detail.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                                ForEach(keyPlayCards) { card in
                                    keyPlayThumbnail(card)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STRATEGY").font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
                        Text(archetype.strategy).font(Design.Fonts.mono(14)).foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEAKNESS").font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
                        Text(archetype.weakness).font(Design.Fonts.mono(14)).foregroundStyle(Color(hex: "C0392B").opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Design.Spacing.md).padding(.bottom, Design.Spacing.md)
            }
        }
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(accent.opacity(0.25), lineWidth: 1)))
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
    }

    private func keyPlayThumbnail(_ card: Card) -> some View {
        Button {
            selectedCard = card
        } label: {
            VStack(spacing: 4) {
                CardImageView(card: card, size: .thumb)
                    .frame(width: 76, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.35), lineWidth: 1))
                Text(card.name)
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Browse View (Curated Card Lists)
// ════════════════════════════════════════════════════════════════

private struct ListFilter: Identifiable, Equatable {
    let id: String; let name: String; let description: String
    let count: String; let color: Color
    let matches: (Card) -> Bool
    static func == (l: ListFilter, r: ListFilter) -> Bool { l.id == r.id }
}

private struct BrowseView: View {
    @Environment(CardStore.self) private var cardStore
    @State private var activeList: ListFilter? = nil
    @State private var selectedCard: Card? = nil

    private let featuredLists: [ListFilter] = [
        ListFilter(id: "woba", name: "WOBA",
                   description: "Women of BOBA — heroes inspired by 17 legendary female athletes across every sport.",
                   count: "884 cards", color: Color(hex: "FF69B4")) { card in
            let heroes: Set<String> = ["AJax","Belladonna","Brandi","C.C.","Cameleon","Cheryl Bomb",
                                       "Coopanova","Eraser","Halo","JPEG","Lady Magic","Leducky",
                                       "PB Buckets","Pauldron","Peek-A-Boo","Ramponage","Swoopes"]
            return heroes.contains(card.hero)
        },
        ListFilter(id: "bojax", name: "Bo Jackson",
                   description: "The man who inspired it all — every BoJax card across every set and treatment.",
                   count: "147 cards", color: Design.Colors.bobaOrange) { card in
            card.athleteInspiration == "Bo Jackson" || card.hero == "BoJax" || card.hero == "Bojax"
        },
        ListFilter(id: "kid", name: "Ken Griffey Jr.",
                   description: "The Kid — one of baseball's most beloved players.",
                   count: "~76 cards", color: Design.Colors.bobaCyan) { card in
            card.athleteInspiration == "Ken Griffey Jr." || card.hero == "The Kid"
        },
        ListFilter(id: "drj", name: "Dr. J",
                   description: "Julius Erving — the original aerial artist of basketball.",
                   count: "70 cards", color: Color(hex: "8B00FF")) { card in
            card.athleteInspiration == "Julius Erving" || card.hero == "Dr. J"
        },
    ]

    private let weaponFilters: [(element: String, label: String)] = [
        ("FIRE","Fire"), ("ICE","Ice"), ("STEEL","Steel"),
        ("BRAWL","Brawl"), ("GLOW","Glow"), ("HEX","Hex"), ("GUM","Gum"), ("SUPER","Super"),
    ]

    private let sportFilters: [(label: String, athletes: Set<String>)] = [
        ("Basketball", ["LeBron James","Lebron James","Steph Curry","Kevin Durant","Giannis Antetokounmpo",
                        "Giannis Anteokounmpo","Giannis Antetetokounmpo","Nikola Jokic","Luka Doncic",
                        "Cooper Flagg","Paige Bueckers","Julius Erving","Magic Johnson","Allen Iverson",
                        "Kawhi Leonard","Ja Morant","Jayson Tatum","Jason Tatum","Caitlin Clark",
                        "Angel Reese","A'ja Wilson","Cynthia Cooper","Cheryl Miller","Sheryl Swoopes",
                        "Nancy Lieberman","Elena Delle Donne","Devin Booker","Anthony Edwards","Damian Lillard"]),
        ("Football",   ["Patrick Mahomes","Josh Allen","Lamar Jackson","Travis Kelce","Bo Jackson",
                        "Barry Sanders","Adrian Peterson","Derrick Henry","Justin Jefferson","Joe Burrow",
                        "Justin Herbert","CJ Stroud","Caleb Williams","Jordan Love","Aaron Rodgers",
                        "Saquan Barkley","Christian McCaffrey","Christian McCaffery","Tyreek Hill",
                        "Travis Hunter","Dak Prescott","Jalen Hurts","Jayden Daniels"]),
        ("Baseball",   ["Ken Griffey Jr.","Ken Griffey Sr.","Shohei Ohtani","Aaron Judge","Mike Trout",
                        "Mookie Betts","Juan Soto","Bo Jackson","Ronald Acuna Jr.","Fernando Tatis Jr.",
                        "Fernando Tatís Jr.","Vladimir Guerrero Jr.","Julio Rodriguez","Jackson Holliday",
                        "Paul Skenes","Rafael Devers","Bobby Witt Jr","Bobby Witt Jr.","Elly De La Cruz",
                        "Gunnar Henderson","Corbin Carroll","Jackson Chourio"]),
        ("Hockey",     ["Sidney Crosby","Alexander Ovechkin","Henrik Lundqvist"]),
        ("Tennis",     ["Jessica Pegula","Paula Badosa"]),
        ("Golf",       ["Bryson DeChambeau","Jordan Spieth"]),
        ("Soccer",     ["Brandi Chastain","Chastain","Christie Pearce Rampone","Jozy Altidore"]),
    ]

    private func filteredCards(for filter: ListFilter) -> [Card] {
        cardStore.displayCards
            .filter(filter.matches)
            .filter { $0.imageFile != nil && !($0.imageFile!.isEmpty) }
            .prefix(60).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                featuredSection
                weaponSection
                sportSection
            }
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
        .sheet(item: $selectedCard) { card in CardDetailView(card: card) }
    }

    // MARK: Featured collections
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("FEATURED COLLECTIONS")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)

            ForEach(featuredLists) { list in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeList = activeList == list ? nil : list
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name).font(Design.Fonts.display(17))
                                    .foregroundStyle(activeList == list ? list.color : Design.Colors.textPrimary)
                                Text(list.description).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(list.count).font(Design.Fonts.mono(11, weight: .bold))
                                    .foregroundStyle(list.color.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: activeList == list ? "chevron.up" : "chevron.right")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(list.color)
                        }
                        .padding(Design.Spacing.md)
                    }
                    .buttonStyle(.plain)

                    if activeList == list {
                        Divider().background(Design.Colors.glassBorder)
                        cardGridOrLoading(for: list)
                            .padding(Design.Spacing.sm)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(activeList == list ? list.color.opacity(0.06) : Design.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(activeList == list ? list.color.opacity(0.45) : Design.Colors.glassBorder, lineWidth: 1)))
            }
        }
    }

    // MARK: Weapon type section
    private var weaponSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("BY WEAPON TYPE")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)

            FlowLayout(spacing: Design.Spacing.sm) {
                ForEach(weaponFilters, id: \.element) { wf in
                    let filterId = "weapon_\(wf.element)"
                    let active = activeList?.id == filterId
                    Button {
                        let filter = ListFilter(id: filterId, name: "\(wf.label) Heroes",
                                               description: "", count: "", color: Design.Colors.element(wf.element)) { $0.element == wf.element }
                        withAnimation { activeList = active ? nil : filter }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Design.Colors.element(wf.element)).frame(width: 8, height: 8)
                            Text(wf.label)
                                .font(Design.Fonts.mono(13, weight: .bold))
                                .foregroundStyle(active ? .white : Design.Colors.element(wf.element))
                        }
                        .padding(.horizontal, Design.Spacing.md).padding(.vertical, 8)
                        .background(Capsule().fill(active ? Design.Colors.element(wf.element) : Design.Colors.element(wf.element).opacity(0.1))
                            .overlay(Capsule().strokeBorder(Design.Colors.element(wf.element).opacity(active ? 0 : 0.4), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let active = activeList, active.id.hasPrefix("weapon_") {
                cardGridOrLoading(for: active).padding(.top, Design.Spacing.xs)
            }
        }
    }

    // MARK: Sport section
    private var sportSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("BY SPORT")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)

            FlowLayout(spacing: Design.Spacing.sm) {
                ForEach(sportFilters, id: \.label) { sport in
                    let filterId = "sport_\(sport.label)"
                    let active = activeList?.id == filterId
                    Button {
                        let athletes = sport.athletes
                        let filter = ListFilter(id: filterId, name: sport.label,
                                               description: "", count: "", color: Design.Colors.bobaOrange) { card in
                            guard let insp = card.athleteInspiration else { return false }
                            return athletes.contains(insp)
                        }
                        withAnimation { activeList = active ? nil : filter }
                    } label: {
                        Text(sport.label)
                            .font(Design.Fonts.mono(13, weight: active ? .bold : .regular))
                            .foregroundStyle(active ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                            .padding(.horizontal, Design.Spacing.md).padding(.vertical, 8)
                            .background(Capsule().fill(active ? Design.Colors.bobaOrange : Design.Colors.glass))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let active = activeList, active.id.hasPrefix("sport_") {
                cardGridOrLoading(for: active).padding(.top, Design.Spacing.xs)
            }
        }
    }

    // MARK: Card grid helper
    @ViewBuilder
    private func cardGridOrLoading(for filter: ListFilter) -> some View {
        let cards = filteredCards(for: filter)
        if cardStore.isLoading {
            HStack { Spacer(); ProgressView().tint(Design.Colors.bobaOrange); Spacer() }.padding()
        } else if cards.isEmpty && cardStore.isLoadingMore {
            HStack(spacing: Design.Spacing.sm) {
                ProgressView().tint(Design.Colors.bobaOrange).scaleEffect(0.8)
                Text("Loading full catalog…").font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted)
            }
            .padding()
        } else if cards.isEmpty {
            Text("No cards found.").font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted).padding()
        } else {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Design.Spacing.sm), count: 3),
                         spacing: Design.Spacing.sm) {
                    ForEach(cards) { card in
                        BrowseCardCell(card: card, onTap: { selectedCard = card })
                    }
                }
                if cards.count >= 60 {
                    Text("Showing first 60 — use Search for full results")
                        .font(Design.Fonts.mono(11)).foregroundStyle(Design.Colors.textMuted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct BrowseCardCell: View {
    let card: Card; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            // Use the shared CardImageView so the thumbnail benefits from
            // the NSCache + URLCache already populated by the main grid.
            // Previously this cell used a bare AsyncImage which rendered
            // the fallback shape (and the power badge overlay) instantly
            // while the card art faded in behind it — making the power
            // and rect feel like they "pop up from below" ahead of the
            // card art itself.
            ZStack(alignment: .bottomLeading) {
                CardImageView(card: card, size: .thumb)
                    .aspectRatio(5/7, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let power = card.power, power > 0 {
                    Text("\(power)").font(Design.Fonts.display(12)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Design.Colors.element(card.element).opacity(0.85)).clipShape(Capsule())
                        .padding(4)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.Colors.element(card.element).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Glossary View (Game terms + Trading vocabulary)
// ════════════════════════════════════════════════════════════════
//
// Content sourced from the 2026-04-22 Discord terminology handoff
// (DISCORD_TERMINOLOGY.md §4.1 + §5). Two grouped lists: game-glossary
// terms coaches ask about in-rules ("HTD", "DBS", "Honors", "Rainbow"),
// and trading-room shorthand players use in the `For Sale`/`ISO` /
// trade channels. Authored as inline Swift structs so the content
// ships without an external JSON round-trip; promote to a JSON asset
// later if the list keeps growing.

private struct GlossaryView: View {
    private struct Term: Identifiable {
        let term: String
        let definition: String
        var id: String { term }
    }

    private let gameTerms: [Term] = [
        .init(term: "Coach",       definition: "How a BoBA player refers to themselves in any gameplay setting. You lead a squad of heroes into battle — the Heroes bring the power, you bring the strategy."),
        .init(term: "Honors",      definition: "The right to act first in a battle — choose to substitute first, play first, and resolve first. After each battle, Honors passes to the battle winner."),
        .init(term: "Sub / Substitute", definition: "Swap the revealed Hero for one from your hand by paying 2 Hot Dogs during the Substitution Window. Only the Honors player can decide whether to substitute first."),
        .init(term: "HTD",         definition: "Home Team Discount — a treatment on 60 Play cards in the Alpha Blast set that reduces the Hot Dog cost by 1 when used by the Honors player. Many tournament formats toggle HTD Plays on or off; always check the event's rules."),
        .init(term: "Bonus Play",  definition: "Card-number prefix BPL. Supplemental Plays (Alpha Update / Griffey / specialty sets) you can include beyond the 30-card Playbook. Some formats toggle Bonus Plays off entirely."),
        .init(term: "Hot Dog",     definition: "The energy resource of the game. Pay Hot Dogs to substitute or play Plays. Your Hot Dog Deck has exactly 10 cards, and they also serve as Power 0 placeholders."),
        .init(term: "DBS",         definition: "Deck Balancing System — each Play card has a DBS score (Low / Medium / High / Very High). All Playmaker divisions at the 2026 Nationals cap a deck's total DBS at 1,000 unless specified otherwise. High-DBS plays are individually powerful but crowd out the rest of the deck."),
        .init(term: "Playbook",    definition: "The 30 unique-named Plays you bring to the table. Draw 1 after each battle."),
        .init(term: "Rainbow",     definition: "Community collecting goal — owning every treatment variation of a single hero (Base + all foils + autos). Tracked in the Collection tab's Rainbow view."),
        .init(term: "Chillin' / Grillen", definition: "Chillin' is an active treatment name (Chillin' Battlefoil). In older Spec rules, players sometimes say 'chillin' for Ice and 'grillen' for Fire — those are legacy slang for the weapon elements. The current rules use Ice and Fire."),
        .init(term: "Double-Up (Press / Fold)", definition: "Optional betting mechanic any game mode can add. Each Coach gets one Press per game to double the game's point value; the opponent then Folds (ends the game) or Presses back. A whole new \"Laundry Phase\" between battles."),
    ]

    private let tradingTerms: [Term] = [
        .init(term: "ISO",   definition: "In Search Of — you want to acquire this card. Posted with a hero name or card number."),
        .init(term: "PC",    definition: "Personal Collect (or Personal Collection) — a card you're keeping and not trading/selling. Often paired with a hero name: 'Bo Jackson PC.'"),
        .init(term: "OBO",   definition: "Or Best Offer — the listed price is negotiable."),
        .init(term: "FS / F/S", definition: "For Sale — shorthand for a listing. Almost always followed by a price."),
        .init(term: "WTB / WTS / WTT", definition: "Wants To Buy / Sell / Trade — explicit intent tags on a post."),
        .init(term: "shipped", definition: "The listed price includes shipping. 'Raw $50 shipped' means no separate shipping fee."),
        .init(term: "PWE",   definition: "Plain White Envelope — cheap, untracked shipping. Fine for low-value cards; risky for expensive ones."),
        .init(term: "BMWT",  definition: "Bubble Mailer With Tracking — the safer default for anything above ~$20."),
        .init(term: "G&S / F&F", definition: "PayPal Goods & Services (buyer-protected, has fees) vs. Friends & Family (no protection). Sellers asking for F&F are a scam signal."),
        .init(term: "coin / coined", definition: "A photo of the card with the seller's handwritten username + current date (+ sometimes price). Community-enforced proof-of-possession; ask for one before sending funds for high-value trades."),
        .init(term: "vouch", definition: "A community endorsement of a trader's trustworthiness. New traders often ask for vouches before a first deal."),
        .init(term: "hit",   definition: "A valuable card pulled from a pack or box. 'Got a big hit in my Griffey box' = pulled something notable."),
        .init(term: "break", definition: "A livestream-style pack or box opening where seats are sold and cards are distributed to buyers by hero, team, or random draw."),
        .init(term: "breaker", definition: "The person running a break."),
        .init(term: "rip",   definition: "Opening a pack or box — 'ripping.'"),
        .init(term: "raw",   definition: "Ungraded. The opposite of PSA/BGS/CGC/TAG graded."),
        .init(term: "graded", definition: "Encapsulated and scored by a third-party grader (PSA, BGS, CGC, TAG). 'PSA 10' is the top grade at PSA."),
        .init(term: "TAG",   definition: "TAG Grading — an emerging alternative grader using laser-scored analysis. Ask your event organizer whether TAG slabs are accepted as proxies."),
        .init(term: "comps", definition: "Comparable recent sales — used to sanity-check a price. The card detail view's pricing panel pulls comps from Radish + eBay."),
        .init(term: "dumper", definition: "A card sold cheaply — often the lower-value hit in a break-day liquidation."),
        .init(term: "banger", definition: "An impressive or high-value pull. Affectionate."),
        .init(term: "scam / scammer", definition: "Don't engage, report to moderators, and check the vouch history before any trade with a new account."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                glossarySection(title: "GAME GLOSSARY",    blurb: "Terms you'll hear in rules discussions, deck building, and battle flow.", terms: gameTerms)
                glossarySection(title: "TRADING GLOSSARY", blurb: "Community shorthand used in the Discord trade room, Whatnot streams, and eBay listings.", terms: tradingTerms)
            }
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
    }

    private func glossarySection(title: String, blurb: String, terms: [Term]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text(title)
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            Text(blurb)
                .font(Design.Fonts.mono(13)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, Design.Spacing.xs)
            VStack(spacing: 1) {
                ForEach(terms) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.term)
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                        Text(t.definition)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.md)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
        }
    }

}

// ════════════════════════════════════════════════════════════════
// MARK: - Collect View (Rarity & Treatments)
// ════════════════════════════════════════════════════════════════

private struct CollectView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                WeaponRaritySection()
                TreatmentsSection()
                ParallelsSection()
                VariationSection()
            }
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
    }
}

// Community vernacular distinguishes *rarity* (intrinsic to a hero, tied to
// weapon type) from *parallels / treatments* (print variants of a given
// card). The Collect page leads with rarity so the mental model is set
// before the Parallels list appears.
private struct WeaponRaritySection: View {
    private let weapons: [(String, String, String, Color)] = [
        ("Steel", "Most common",     "Entry-level weapon — the bulk of any collection.",                 Design.Colors.element("STEEL")),
        ("Ice",   "Common",          "Frequent pulls alongside Steel.",                                  Design.Colors.element("ICE")),
        ("Fire",  "Rare",            "Notably rarer than Steel/Ice.",                                    Design.Colors.element("FIRE")),
        ("Glow",  "Ultra rare",      "A meaningful chase — often a box-topper.",                         Design.Colors.element("GLOW")),
        ("Gum",   "Secret rare",     "Chase-tier with very limited supply.",                             Design.Colors.element("GUM")),
        ("Hex",   "Rarest",          "The apex weapon — the hardest pull in a standard product run.",   Design.Colors.element("HEX")),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("RARITY BY WEAPON TYPE")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            Text("In BOBA, a hero's rarity is tied to its weapon type. From most common to most rare:")
                .font(Design.Fonts.mono(13)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, Design.Spacing.xs)
            VStack(spacing: 1) {
                ForEach(weapons, id: \.0) { weapon in
                    HStack(alignment: .center, spacing: Design.Spacing.md) {
                        Circle().fill(weapon.3).frame(width: 14, height: 14)
                            .shadow(color: weapon.3.opacity(0.55), radius: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(weapon.0).font(Design.Fonts.mono(14, weight: .bold)).foregroundStyle(weapon.3)
                            Text(weapon.2).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(weapon.1).font(Design.Fonts.mono(10, weight: .bold)).foregroundStyle(weapon.3.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(weapon.3.opacity(0.12)))
                            .fixedSize()
                    }
                    .padding(.horizontal, Design.Spacing.md).padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            Text("Brawl, Super, Alt, and Cyber sit outside this six-weapon spectrum — Super especially is tie-breaker-only and typically appears serialized.")
                .font(Design.Fonts.mono(11)).foregroundStyle(Design.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Spacing.xs)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Treatments (canonical list, sourced from Griffey checklist)
// ════════════════════════════════════════════════════════════════
//
// Per the BoBA expert audit (2026-04-24): Treatments are print
// variants of a single card — Battlefoils, the various themed foils,
// Inspired Ink (which IS the Serialized series), and Superfoil.
// Parallels are entirely separate runs (Billy Cameos, SideKicks).
// Mixing the two — which the previous "Parallels & Treatments"
// section did — confused users; the official `/collecting-basics`
// page treats them as different concepts.
//
// Tags below match the prefixes from the Griffey checklist CSV so
// collectors can map a card # they're holding directly to a row.
private struct TreatmentsSection: View {
    /// (id, name, prefix, description, group)
    /// Group = "Standard" | "Themed" | "Premium"
    private struct Treatment: Identifiable {
        let id: Int
        let name: String
        let prefix: String
        let description: String
        let group: Group
        let color: Color
        enum Group: String, CaseIterable { case standard = "STANDARD", themed = "THEMED", premium = "PREMIUM" }
    }

    private let treatments: [Treatment] = [
        // Standard / starter treatments — what you pull from a typical pack
        .init(id: 1, name: "Base Set",
              prefix: "(no prefix)",
              description: "The card's plain printing. Most common in any set — your entry point for any collection.",
              group: .standard, color: Design.Colors.textSecondary),
        .init(id: 2, name: "Grandma's Linoleum Battlefoil",
              prefix: "GLBF",
              description: "Linoleum-textured foil border. One of the most common foil treatments; community calls it Lino or Grandma.",
              group: .standard, color: Color(hex: "FFD700")),
        .init(id: 3, name: "80's Rad Battlefoil",
              prefix: "RAD",
              description: "Retro 80's-inspired holographic finish. Common alongside GLBF.",
              group: .standard, color: Color(hex: "AAAAFF")),

        // Battlefoil family — the umbrella treatment with named subsets
        .init(id: 4, name: "Battlefoil",
              prefix: "BF",
              description: "Generic foil border treatment. Comes in seven color subsets: Red (RBF), Silver (SBF), Blue (BBF), Orange (OBF), Green (GBF), Pink (PBF), and Bubble Gum (BGBF). Each subset is its own pull.",
              group: .standard, color: Design.Colors.bobaCyan),

        // Themed Battlefoils — each its own treatment, not subsets of BF
        .init(id: 5, name: "Blizzard Battlefoil",
              prefix: "BLBF",
              description: "Snowy/icy themed foil border. Distinct from the Battlefoil color family.",
              group: .themed, color: Color(hex: "00BFFF")),
        .init(id: 6, name: "Alpha Battlefoil",
              prefix: "ABF",
              description: "Premium foil tied to Alpha Edition releases.",
              group: .themed, color: Color(hex: "9B59B6")),
        .init(id: 7, name: "Headlines Battlefoil",
              prefix: "HBF",
              description: "Newspaper-style headline border treatment. Has Blue (BHBF) and Red (RHBF) subset variants.",
              group: .themed, color: Color(hex: "ECF0F1")),
        .init(id: 8, name: "Power Glove Battlefoil",
              prefix: "PG",
              description: "Power Glove division themed foil. Tied to the Power Glove tournament division.",
              group: .themed, color: Color(hex: "FF4D00")),
        .init(id: 9, name: "Great Grandma Linoleum Battlefoil",
              prefix: "GGL",
              description: "2026 Edition exclusive — distinctive linoleum texture. Rarer than the standard GLBF.",
              group: .themed, color: Color(hex: "FFC107")),
        .init(id: 10, name: "Chillin' Battlefoil",
              prefix: "CHILL",
              description: "Chillin' themed foil treatment. Community-flavor naming.",
              group: .themed, color: Color(hex: "00F5FF")),
        .init(id: 11, name: "Grillin' Battlefoil",
              prefix: "GRILL",
              description: "Grillin' themed foil treatment. Pairs visually with Chillin' as a thematic duo.",
              group: .themed, color: Color(hex: "E67E22")),
        .init(id: 12, name: "Icon Battlefoil",
              prefix: "IBF",
              description: "Icon-themed foil border for the iconic athlete heroes.",
              group: .themed, color: Color(hex: "F39C12")),
        .init(id: 13, name: "Mixtape Battlefoil",
              prefix: "MIX",
              description: "Mixtape-themed retro audio aesthetic foil border.",
              group: .themed, color: Color(hex: "FF1493")),
        .init(id: 14, name: "Miami Ice Battlefoil",
              prefix: "MI",
              description: "Miami-inspired neon-on-ice foil border. Visually distinctive themed treatment.",
              group: .themed, color: Color(hex: "FF6EC7")),
        .init(id: 15, name: "Fire Tracks Battlefoil",
              prefix: "FT",
              description: "Fiery track-pattern themed foil border.",
              group: .themed, color: Color(hex: "FF4500")),
        .init(id: 16, name: "Colosseum Battlefoil",
              prefix: "CBF",
              description: "2026 Edition exclusive — stadium-arena themed foil border.",
              group: .themed, color: Design.Colors.bobaCyan),
        .init(id: 17, name: "Logofoil",
              prefix: "LOGO",
              description: "2026 Edition exclusive — logo foil print. Not available in First Edition.",
              group: .themed, color: Color(hex: "FFD700")),
        .init(id: 18, name: "Slime Battlefoil",
              prefix: "SL",
              description: "Slime-textured foil border — distinctive viscous-effect finish.",
              group: .themed, color: Color(hex: "7CFC00")),

        // Premium / chase treatments
        .init(id: 19, name: "Inspired Ink Battlefoil",
              prefix: "AAA",
              description: "Standard Inspired Ink treatment — autograph-style art with athlete tribute. The serialized base.",
              group: .premium, color: Color(hex: "FF69B4")),
        .init(id: 20, name: "Inspired Ink Bubble Gum Battlefoil",
              prefix: "ABA",
              description: "Inspired Ink with Bubble Gum foil overlay — a serialized variant of the IIBF treatment.",
              group: .premium, color: Color(hex: "FF8FCA")),
        .init(id: 21, name: "Inspired Ink Metallic Battlefoil",
              prefix: "ABA",
              description: "Inspired Ink with Metallic foil overlay — a higher-tier serialized variant.",
              group: .premium, color: Color(hex: "C0C0C0")),
        .init(id: 22, name: "Inspired Ink Superfoil",
              prefix: "AAA",
              description: "Inspired Ink + Superfoil — premium chase combining autograph art with full-card holographic. The pinnacle Inspired Ink variant.",
              group: .premium, color: Color(hex: "FF00FF")),
        .init(id: 23, name: "Superfoil",
              prefix: "SF",
              description: "Full-card holographic foil treatment covering the entire card face. The most visually striking pull in most collections.",
              group: .premium, color: Color(hex: "FF00FF")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("TREATMENTS")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            Text("Treatments are the different ways a given card can be printed — Base Set, the Battlefoil family, themed foils, and the premium Inspired Ink / Superfoil chase tiers. The prefix on the card number maps to its treatment.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing.xs)

            // Inspired Ink serial-number callout — surfaces the
            // Hex /5, Glow /10, Fire /25, Ice /50 ladder collectors
            // need to know.
            inspiredInkCallout
                .padding(.bottom, Design.Spacing.xs)

            ForEach(Treatment.Group.allCases, id: \.rawValue) { group in
                let rows = treatments.filter { $0.group == group }
                if !rows.isEmpty {
                    Text(group.rawValue)
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.2)
                        .padding(.top, Design.Spacing.sm)
                    VStack(spacing: 1) {
                        ForEach(rows) { row in
                            treatmentRow(row)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                }
            }
        }
    }

    private func treatmentRow(_ t: Treatment) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.md) {
            // Prefix chip — mappable to the card number on the card
            // collectors are holding.
            Text(t.prefix)
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(t.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(t.color.opacity(0.12))
                    .overlay(Capsule().strokeBorder(t.color.opacity(0.4), lineWidth: 0.75)))
                .frame(minWidth: 60, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(t.color)
                Text(t.description)
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
    }

    private var inspiredInkCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "signature")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "FF69B4"))
                Text("INSPIRED INK = SERIALIZED")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Color(hex: "FF69B4"))
                    .tracking(1)
            }
            Text("Inspired Ink cards carry hand-stamped serial numbers tied to the hero's weapon type:")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                serialChip("Hex", "/5",  Design.Colors.element("HEX"))
                serialChip("Glow", "/10", Design.Colors.element("GLOW"))
                serialChip("Fire", "/25", Design.Colors.element("FIRE"))
                serialChip("Ice", "/50", Design.Colors.element("ICE"))
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md)
            .fill(Color(hex: "FF69B4").opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                .strokeBorder(Color(hex: "FF69B4").opacity(0.35), lineWidth: 1)))
    }

    private func serialChip(_ weapon: String, _ serial: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(weapon)
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(color)
            Text(serial)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.18))
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1)))
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Parallels (separate from Treatments per expert taxonomy)
// ════════════════════════════════════════════════════════════════
//
// Parallels are entirely separate card-runs that share the format —
// not print variants of a base card. Billy Cameos, SideKicks, the
// Plays/Bonus Plays/Hot Dogs subsystems, and the Prize/Promo line
// all sit here. Surfaced as its own section so the visual taxonomy
// matches the community's mental model.
private struct ParallelsSection: View {
    private let parallels: [(prefix: String, name: String, description: String, color: Color)] = [
        ("ALT",  "Billy Cameo Alt Arts",
         "Alternate art featuring Billy, the iconic BOBA hot dog mascot, in cameo on each card. Among the rarest and most sought-after cards in the game.",
         Color(hex: "FF4500")),
        ("FFA",  "SideKicks",
         "SideKicks parallel run — separate cards built around supporting/companion characters. Distinct numbering from the main Hero set.",
         Color(hex: "9B59B6")),
        ("PL",   "Plays",
         "The Playbook subsystem — non-Hero cards used during Battle to modify outcomes. Tracked separately from Heroes for deck-building purposes.",
         Design.Colors.bobaViolet),
        ("BPL",  "Bonus Plays",
         "Element-triggered Plays that don't count against the 30-card Playbook limit. Drawn automatically when their trigger fires; surfaced with a gold ★ BONUS tag in the practice playmat.",
         Color(hex: "FFD700")),
        ("P",    "Prize & Promo",
         "Prize cards (tournament rewards) and Promo cards (event/release exclusives). Limited distribution; not part of standard pack rotation.",
         Color(hex: "FFA500")),
        ("HD",   "Hot Dogs",
         "The 10-card Hot Dog deck that powers play costs. Each player starts each match with the same 10. Some are themed but mechanically identical.",
         Color(hex: "4CAF50")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("PARALLELS")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            Text("Parallels are separate card runs that share the BoBA format but aren't print variants of the base set. They have their own numbering and collectibility profile.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing.xs)
            VStack(spacing: 1) {
                ForEach(parallels, id: \.prefix) { p in
                    HStack(alignment: .top, spacing: Design.Spacing.md) {
                        Text(p.prefix)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(p.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(p.color.opacity(0.12))
                                .overlay(Capsule().strokeBorder(p.color.opacity(0.4), lineWidth: 0.75)))
                            .frame(minWidth: 60, alignment: .leading)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(Design.Fonts.mono(13, weight: .bold))
                                .foregroundStyle(p.color)
                            Text(p.description)
                                .font(Design.Fonts.mono(12))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
        }
    }
}

private struct VariationSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("VARIATIONS")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            Text("Variations are distinct print runs of the same card. The same hero in the same treatment can exist across multiple variations — each is separately collectible with its own scarcity and value.")
                .font(Design.Fonts.mono(13)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, Design.Spacing.xs)
            VStack(spacing: Design.Spacing.sm) {
                VariationDetailCard(
                    name: "First Edition", count: "8,926 cards", color: Design.Colors.textSecondary,
                    bullets: [
                        "The original print run — the baseline for all sets",
                        "Most widely available; the first cards released for every hero",
                        "All treatments from Base Set through chase exist in First Edition",
                        "Look for the First Edition stamp to confirm authenticity",
                    ]
                )
                VariationDetailCard(
                    name: "2026 Edition", count: "880 cards", color: Design.Colors.bobaCyan,
                    bullets: [
                        "Second print run of select Alpha and Griffey Edition cards",
                        "Introduces three exclusive treatments: Logofoil, Colosseum Battlefoil, and Great Grandma's Linoleum Battlefoil — these treatments do not exist in First Edition",
                        "Typically harder to find than equivalent First Edition cards",
                        "Often features revised or updated card art",
                    ]
                )
                VariationDetailCard(
                    name: "Debut", count: "70 per hero", color: Design.Colors.bobaOrange,
                    bullets: [
                        "Each hero's official introduction card into the BOBA universe",
                        "Only 70 printed per hero — meaningful scarcity even for common heroes",
                        "Many Debut cards carry serial numbers, making individual copies uniquely identifiable",
                        "The definitive collector piece for fans of any specific hero or athlete",
                    ]
                )
                VariationDetailCard(
                    name: "Unmasked", count: "70 per hero", color: Color(hex: "FF69B4"),
                    bullets: [
                        "Reveals the real-world athlete behind the hero mask",
                        "Features athlete-focused art rather than the hero persona",
                        "Only 70 printed per hero — as scarce as Debut variations",
                        "Typically commands the highest value of any variation for a given hero",
                        "The premier card for collectors building athlete-specific portfolios",
                    ]
                )
            }
        }
    }
}

private struct VariationDetailCard: View {
    let name: String
    let count: String
    let color: Color
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Text(name)
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text(count)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(color.opacity(0.8))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(color.opacity(0.6))
                        Text(bullet)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(color.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(color.opacity(0.2), lineWidth: 1)))
    }
}

// (former TreatmentHighlightsSection removed — folded into the new
// TreatmentsSection / ParallelsSection split per the 2026-04-24
// expert taxonomy update.)

// ════════════════════════════════════════════════════════════════
// MARK: - Tournament View
// ════════════════════════════════════════════════════════════════

private struct TournamentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                ProTourIntroSection()
                HeroDeckFormatsSection()
                GameModesSection()
                DoubleUpSection()
                MadnessSection()
                NationalsDivisionsSection()
                MatchStructureSection()
                PenaltyReferenceSection()
            }
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
    }
}

// Intro card for the 2026 Pro-Tour — announces the Coach concept, the
// Nationals prize pool, and the community-culture framing from the
// "Welcome to BoBA 2026" opening of the draft.
private struct ProTourIntroSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("2026 PRO-TOUR")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                Text("$500,000+ Prize Pool")
                    .font(Design.Fonts.display(22))
                    .foregroundStyle(Design.Colors.bobaOrange)
                Text("The 2026 World Championships at The National offers an estimated $500,000+ in total prizing, with up to $375,000+ available as cash payouts. APEX events are free to enter.")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().background(Design.Colors.glassBorder)
                Text("You are a Coach.")
                    .font(Design.Fonts.display(14)).foregroundStyle(Design.Colors.bobaCyan)
                Text("As a Coach, you lead a squad of superheroes into battle. The Heroes bring the power; you bring the strategy. You decide the roster, call the Plays, and pick when to push or hold. Assistant Coaches are allowed in all events unless otherwise specified — a pairing to increase accessibility for younger Coaches or those with special needs.")
                    .font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.bobaOrange.opacity(0.3), lineWidth: 1)))
            Text("The draft is marked NOT YET FINALIZED — check the official rules PDF for the current published version before a tournament.")
                .font(Design.Fonts.mono(10)).foregroundStyle(Design.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

// Hero-deck build rules. The 2026 draft confirms four canonical build
// formats: Apex / Spec / Elite / SPEC+, with "max 6 per power" standard
// across all of them. Heroes may now appear unlimited times per deck
// (one-of still applies to an exact bobaId).
private struct HeroDeckFormatsSection: View {
    private let formats: [(name: String, cap: String, notes: String, color: Color)] = [
        ("Apex",   "No power limit",                "Standard deck rules (max 6 Heroes per power). The open-power-cap division.",                                       Design.Colors.bobaOrange),
        ("Spec",   "160 Power cap",                 "Every Hero ≤ 160 Power. Standard deck rules (max 6 per power).",                                                    Design.Colors.bobaCyan),
        ("Elite",  "8,250 total power cap",         "Combined Power across all Heroes ≤ 8,250. Starter cards legal; Trainer cards NOT legal. Otherwise standard rules.", Color(hex: "8B00FF")),
        ("SPEC+",  "Up to 70 Heroes (tiered)",      "60 Heroes ≤ 160 Power (a full Spec deck), plus up to 10 optional higher-power Heroes with these stacking limits:",  Color(hex: "FF00FF")),
    ]

    private let specPlusTiers: [(String, String)] = [
        ("165 Power", "max 2 per deck"),
        ("170 Power", "max 2 per deck"),
        ("175 Power", "max 1 per deck"),
        ("180 Power", "max 1 per deck"),
        ("185 Power", "max 1 per deck"),
        ("190 Power", "max 1 per deck"),
        ("195 Power", "max 1 per deck"),
        ("200 Power", "max 1 per deck"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("HERO DECK FORMATS")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            VStack(spacing: 1) {
                ForEach(formats, id: \.name) { fmt in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fmt.name).font(Design.Fonts.mono(14, weight: .bold)).foregroundStyle(fmt.color)
                            Spacer()
                            Text(fmt.cap).font(Design.Fonts.mono(11)).foregroundStyle(fmt.color.opacity(0.8))
                        }
                        Text(fmt.notes)
                            .font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if fmt.name == "SPEC+" {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(specPlusTiers, id: \.0) { tier in
                                    HStack {
                                        Text(tier.0).font(Design.Fonts.mono(11, weight: .bold)).foregroundStyle(fmt.color.opacity(0.85))
                                        Text(tier.1).font(Design.Fonts.mono(11)).foregroundStyle(Design.Colors.textMuted)
                                    }
                                }
                                Text("No Heroes above 200 Power. Heroes 165–200 are in the optional 10-slot overflow only.")
                                    .font(Design.Fonts.mono(11))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(Design.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            Text("All Playmaker divisions are 1,000 DBS unless specified otherwise. Heroes can now appear unlimited times per deck (\"one-of\" still applies to an exact card).")
                .font(Design.Fonts.mono(11)).foregroundStyle(Design.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Spacing.xs)
        }
    }
}

// Core three game modes. Rookie / Substitution / Playmaker apply across
// every division — the Hero Deck Format sits on top of the game mode.
private struct GameModesSection: View {
    private let modes: [(String, String, Color)] = [
        ("Rookie",       "Hero Deck only. Pure power comparison. At sanctioned events you must intentionally place Heroes one by one — no blind shuffle-and-place.", Design.Colors.bobaOrange),
        ("Substitution", "Hero Deck + Hot Dog Deck. Substitute at the start of a Battle by paying 2 Hot Dogs.",                                                      .yellow),
        ("Playmaker",    "The full game — Hero Deck + Hot Dog Deck + 30-card Playbook. The tournament standard.",                                                    Design.Colors.bobaCyan),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("GAME MODES")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            VStack(spacing: 1) {
                ForEach(modes, id: \.0) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.0).font(Design.Fonts.mono(14, weight: .bold)).foregroundStyle(m.2)
                        Text(m.1).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Design.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
        }
    }
}

// Double-Up is the 2026 add-on — a simple betting / bluffing mechanic
// that can layer onto any game mode. Condensed from the draft's
// "Laundry Phase Details" section.
private struct DoubleUpSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("DOUBLE-UP (OPTIONAL ADD-ON)")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                Text("Simple Press-and-Fold wagering layered onto any game mode. Adds the depth of a backgammon doubling cube to BoBA.")
                    .font(Design.Fonts.mono(13)).foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                bullet("Each Game of 7 Battles starts worth 1 point. First Coach to 7 points wins the match-up.")
                bullet("Each Coach gets one Press per Game — called after hands are dealt, or between Battles.")
                bullet("Opponent responds: Accept the Press, Press back (if they haven't used theirs), or Fold and end the game.")
                bullet("No Double-Up game ends in a tie — ties resolve by Top Deck (each Coach reveals the top of their Hero Deck until one wins).")
                bullet("Between-battles Press-and-Fold is called the \"Laundry Phase.\"")
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.bobaCyan.opacity(0.25), lineWidth: 1)))
        }
    }

    @ViewBuilder private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(Design.Fonts.mono(13, weight: .bold)).foregroundStyle(Design.Colors.bobaCyan)
            Text(text).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Team Play variants that show up across divisions. Three canonical forms
// per the draft: Apex / AlphaTrilogy Madness (full-power), and HiLo
// Madness (some players High Ball, others Low Ball).
private struct MadnessSection: View {
    private let variants: [(String, String, Color)] = [
        ("Apex & AlphaTrilogy Madness",
         "Head Coach runs a full Apex deck; teammates play Spec 160 decks that can unlock Apex cards by including 10-of-an-insert or 4 Foil Hot Dogs. Max-optimized teammate decks reach 70 Heroes with 6 Apex cards.",
         Design.Colors.bobaOrange),
        ("HiLo Madness",
         "Team format where Head Coaches play \"High Ball\" (highest Power wins) while teammates play \"Low Ball\" (lowest Power wins). Used in Granny's Gum, Brawl, and Tecmo Bowl divisions.",
         Design.Colors.bobaCyan),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("MADNESS (TEAM PLAY)")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            Text("4-Coach team formats. Each Coach brings 4 of their favorite Foil Hot Dogs to display as team mascots at every match.")
                .font(Design.Fonts.mono(13)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, Design.Spacing.xs)
            VStack(spacing: 1) {
                ForEach(variants, id: \.0) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.0).font(Design.Fonts.mono(13, weight: .bold)).foregroundStyle(v.2)
                        Text(v.1).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Design.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
        }
    }
}

// 2026 World Championship divisions with prize pools. Event-level rules
// (DBS, BP/HTD toggles, weapon restrictions) live on the division card —
// transcribed from the 2026 National Events draft.
private struct NationalsDivisionsSection: View {
    private struct Division: Identifiable {
        let id = UUID()
        let name: String
        let prize: String
        let events: [String]     // event name + quick rules summary
        let color: Color
    }

    private let divisions: [Division] = [
        Division(name: "Apex",            prize: "$150,000 · free to enter",
                 events: [
                    "Apex Playmaker — 1,000 DBS · Bonus Plays ON · HTD Plays ON · Apex Deck Rules · needs Football Breaker Bojax /99 Auto",
                    "Apex Blitz — Rookie Mode · Apex Deck Rules",
                    "Apex Madness (team) — Apex Madness Deck Rules · 1× Football Breaker Bojax /99 Auto per team",
                 ], color: Design.Colors.bobaOrange),
        Division(name: "AlphaTrilogy",    prize: "$100,000",
                 events: [
                    "AlphaTrilogy Playmaker — 1,000 DBS · BP ON · HTD ON · Apex Deck Rules · needs Bat Breaker Bojax /99 Auto",
                    "AlphaTrilogy Blitz — Rookie Mode · Apex Deck Rules",
                    "AlphaTrilogy Madness (team) — Apex Madness Deck Rules · 1× Bat Breaker Bojax /99 Auto per team",
                 ], color: Color(hex: "8B00FF")),
        Division(name: "Tecmo Bowl",      prize: "$50,000",
                 events: [
                    "Tecmo Bowl SPEC+ Playmaker — ALL cards from Tecmo Bowl set · SPEC+ rules · 1,000 DBS · BP ON (Tecmo only) · HTD N/A",
                    "SPEC+ Rookie Double-Up — SPEC+ rules · Tecmo Heroes only",
                    "Tecmo Bowl HiLo Madness (team) — Tecmo Bowl set only · 4-player team",
                 ], color: Color(hex: "FF00FF")),
        Division(name: "Open",            prize: "up to $40,000",
                 events: [
                    "Spec Playmaker — in-rotation cards · 1,000 DBS · BP OFF · HTD OFF",
                    "Elite Playmaker — in-rotation cards except Trainers · 1,000 DBS · BP ON · HTD ON",
                    "SPEC+ Rookie Double-Up — SPEC+ rules · in-rotation cards",
                    "Single-insert bonus: finish in the money with a mono-insert Hero Deck and your cash prize doubles.",
                 ], color: Design.Colors.bobaCyan),
        Division(name: "Blast",           prize: "$20,000",
                 events: [
                    "Blast Substitution Double-Up — all cards Blast · 30 Heroes · max 3 per power · all Hot Dogs Blast",
                    "Blast Substitution Low Ball Double-Up — same rules, lowest Power wins",
                 ], color: Color(hex: "FF4D00")),
        Division(name: "Brawl",           prize: "$20,000",
                 events: [
                    "Brawl Playmaker — all Brawl weapons · 1,000 DBS · BP OFF · HTD OFF · all Hot Dogs must be \"Brawler\"",
                    "Brawl Rookie Double-Up — all Brawl weapons · standard deck rules",
                    "Brawl HiLo Madness (team) — all Brawl weapons · 6 per team, 4 play at a time",
                 ], color: Color(hex: "C0392B")),
        Division(name: "Granny's Gum",    prize: "$20,000",
                 events: [
                    "GG HiLo Madness (team) — all Heroes Grandma's Linoleum, Great Grandma's Linoleum, or Bubblegum · 6 per team, 4 at a time · min 10 of each legal insert type · no power cap",
                 ], color: Color(hex: "FFD700")),
        Division(name: "Power Glove",     prize: "$15,000",
                 events: [
                    "Power Glove Set Builder Bracket — verify ownership of 120+ unique Power Glove Inserts · everyone gets a promo card · full-set verification unlocks a $5,000 bonus",
                 ], color: Design.Colors.textMuted),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("2026 NATIONALS DIVISIONS")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            Text("Each division's cash prize is split across its events by Prize Pool Share (PPS). You can enter every Madness event plus up to 1 solo event per division, scheduling permitting.")
                .font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, Design.Spacing.xs)
            VStack(spacing: Design.Spacing.xs) {
                ForEach(divisions) { d in DivisionCard(division: d) }
            }
        }
    }

    private struct DivisionCard: View {
        let division: Division
        @State private var isExpanded = false
        var body: some View {
            VStack(spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(division.name).font(Design.Fonts.display(16)).foregroundStyle(division.color)
                            Text(division.prize).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(division.color)
                    }
                    .padding(Design.Spacing.md)
                }
                .buttonStyle(.plain)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(division.events, id: \.self) { event in
                            HStack(alignment: .top, spacing: 6) {
                                Text("›").font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(division.color.opacity(0.7))
                                Text(event).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(Design.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colors.surface2)
                }
            }
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(division.color.opacity(0.25), lineWidth: 1)))
        }
    }
}

private struct MatchStructureSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("MATCH STRUCTURE")
                .font(Design.Fonts.mono(12, weight: .bold)).foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            RuleCard(lines: [
                .init(label: "Game",              body: "Best-of-7 Battles. First to 4 wins. A 3–3 tie after all 7 triggers Sudden Death on the final battle."),
                .init(label: "Match",             body: "Generally one game per match. The Tournament Organizer may announce a different number of games before the tournament begins."),
                .init(label: "Timed Rounds",      body: "If time expires mid-game, the current turn finishes plus one additional turn. If no winner, the game is a draw."),
                .init(label: "Elimination Tiebreaker", body: "Step 1: most games won. Step 2: most battles won in the current game. Step 3: each player reveals the top card of their Hero Deck — higher Power wins. Repeat Step 3 until broken."),
                .init(label: "Deck Registration",  body: "Decklists are mandatory for all tournaments. Register your exact 60/10/30 lists before Round 1."),
            ])
        }
    }
}

private struct PenaltyReferenceSection: View {
    @State private var isExpanded = false
    private let penalties: [(String, String, String, Color)] = [
        ("1", "Caution",          "Verbal only — not recorded.",                                         Design.Colors.textMuted),
        ("2", "Warning",          "Recorded. A second Warning for the same infraction upgrades to Game Loss.", .yellow),
        ("3", "Game Loss",        "You lose the current game in the match.",                              Design.Colors.bobaOrange),
        ("4", "Match Loss",       "You lose the entire match.",                                           Color(hex: "C0392B")),
        ("5", "Disqualification", "Removed from the event. Reserved for cheating or gross misconduct.",   Color(hex: "8B00FF")),
    ]
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Penalty Reference").font(Design.Fonts.display(17)).foregroundStyle(Design.Colors.textPrimary)
                        Text("5 levels from Caution to Disqualification").font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textMuted)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Design.Colors.bobaOrange)
                }
                .padding(Design.Spacing.md)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(penalties, id: \.0) { p in
                        HStack(alignment: .top, spacing: Design.Spacing.md) {
                            ZStack {
                                Circle().fill(p.3.opacity(0.15)).frame(width: 26, height: 26)
                                Text(p.0).font(Design.Fonts.display(12)).foregroundStyle(p.3)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.1).font(Design.Fonts.mono(13, weight: .bold)).foregroundStyle(p.3)
                                Text(p.2).font(Design.Fonts.mono(12)).foregroundStyle(Design.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(Design.Spacing.md).background(Design.Colors.surface2)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1)))
    }
}
