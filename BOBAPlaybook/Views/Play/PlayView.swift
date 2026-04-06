//
//  PlayView.swift
//  BOBAPlaybook
//
//  M4 Play tab — Rules and Strategy sections.
//  All sub-views are private structs in this file.
//

import SwiftUI

// MARK: - PlayView

struct PlayView: View {
    @State private var selectedSection: PlaySection = .rules

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlaySectionPicker(selected: $selectedSection)
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.vertical, Design.Spacing.md)
                    .background(Design.Colors.surface)

                Group {
                    switch selectedSection {
                    case .rules:
                        RulesView()
                    case .strategy:
                        StrategyView()
                    }
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Section enum

private enum PlaySection: String, CaseIterable {
    case rules    = "Rules"
    case strategy = "Strategy"
}

// MARK: - Section Picker (pill-style)

private struct PlaySectionPicker: View {
    @Binding var selected: PlaySection

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            ForEach(PlaySection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selected = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(Design.Fonts.mono(13, weight: selected == section ? .bold : .regular))
                        .foregroundStyle(selected == section ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Capsule()
                                .fill(selected == section ? Design.Colors.bobaOrange : Design.Colors.glass)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - RulesView

private struct RulesView: View {
    @State private var selectedMode: GameMode = .rookie

    var body: some View {
        VStack(spacing: 0) {
            GameModePicker(selected: $selectedMode)
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                    ModeOverviewCards(selectedMode: selectedMode)
                    BattleFlowDiagram(mode: selectedMode)

                    switch selectedMode {
                    case .rookie:
                        RookieRulesContent()
                    case .substitution:
                        SubstitutionRulesContent()
                    case .playmaker:
                        PlaymakerRulesContent()
                    }

                    CardZonesSection()
                    DeckbuildingSection()
                }
                .id(selectedMode)
                .padding(Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.xxl)
            }
        }
    }
}

// MARK: - Game Mode enum

private enum GameMode: String, CaseIterable {
    case rookie       = "Rookie"
    case substitution = "Substitution"
    case playmaker    = "Playmaker"
}

// MARK: - Game Mode Picker (3-pill horizontal row)

private struct GameModePicker: View {
    @Binding var selected: GameMode

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(GameMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selected = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(Design.Fonts.mono(12, weight: selected == mode ? .bold : .regular))
                        .foregroundStyle(selected == mode ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule()
                                .fill(selected == mode ? Design.Colors.bobaCyan : Design.Colors.glass)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Shared rule-block components

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
        let id = UUID()
        let label: String?
        let body: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: Design.Spacing.sm) {
                    Text("·")
                        .font(Design.Fonts.mono(15))
                        .foregroundStyle(Design.Colors.bobaOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        if let label = line.label {
                            Text(label)
                                .font(Design.Fonts.mono(15, weight: .bold))
                                .foregroundStyle(Design.Colors.textPrimary)
                        }
                        Text(line.body)
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Mode Overview Cards

private struct ModeOverviewCards: View {
    let selectedMode: GameMode

    private struct ModeInfo: Identifiable {
        let id: GameMode
        let components: [(name: String, color: Color)]
        let description: String
    }

    private let modes: [ModeInfo] = [
        ModeInfo(id: .rookie,       components: [("Hero Deck", Design.Colors.bobaOrange)],                                                                      description: "Pure power comparison"),
        ModeInfo(id: .substitution, components: [("Hero Deck", Design.Colors.bobaOrange), ("Hot Dogs", .yellow)],                                               description: "Add hand management"),
        ModeInfo(id: .playmaker,    components: [("Hero Deck", Design.Colors.bobaOrange), ("Hot Dogs", .yellow), ("Playbook", Design.Colors.bobaCyan)],          description: "Full game · tournament")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("GAME MODES")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)

            HStack(spacing: Design.Spacing.sm) {
                ForEach(modes) { entry in
                    let active = entry.id == selectedMode
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        Text(entry.id.rawValue.uppercased())
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(active ? Design.Colors.bobaCyan : Design.Colors.textMuted)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entry.components, id: \.name) { comp in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(comp.color)
                                        .frame(width: 6, height: 6)
                                    Text(comp.name)
                                        .font(Design.Fonts.mono(11))
                                        .foregroundStyle(active ? Design.Colors.textSecondary : Design.Colors.textMuted)
                                }
                            }
                        }
                        Text(entry.description)
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(active ? Design.Colors.textMuted : Design.Colors.textMuted.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Design.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(active ? Design.Colors.bobaCyan.opacity(0.08) : Design.Colors.glass)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radius.sm)
                                    .strokeBorder(
                                        active ? Design.Colors.bobaCyan.opacity(0.5) : Design.Colors.glassBorder,
                                        lineWidth: active ? 1.5 : 1
                                    )
                            )
                    )
                }
            }
        }
    }
}

// MARK: - Battle Flow Diagram

private struct BattleFlowDiagram: View {
    let mode: GameMode

    private struct Phase: Identifiable {
        let id = UUID()
        let number: String
        let label: String
        let detail: String
        let color: Color
        let appliesTo: Set<GameMode>
    }

    private let phases: [Phase] = [
        Phase(number: "1", label: "REVEAL",  detail: "Both flip Hero",           color: Design.Colors.bobaOrange, appliesTo: [.rookie, .substitution, .playmaker]),
        Phase(number: "2", label: "SUB",     detail: "Pay 2 Hot Dogs to swap",   color: .yellow,                  appliesTo: [.substitution, .playmaker]),
        Phase(number: "3", label: "PLAYS",   detail: "Alternate Play cards",     color: Design.Colors.bobaCyan,   appliesTo: [.playmaker]),
        Phase(number: "4", label: "RESOLVE", detail: "Higher Power wins",        color: Color(hex: "4CAF50"),     appliesTo: [.rookie, .substitution, .playmaker])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("BATTLE SEQUENCE")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.1.id) { idx, phase in
                    let active = phase.appliesTo.contains(mode)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(active ? phase.color : Design.Colors.glass)
                                .frame(width: 36, height: 36)
                                .shadow(color: active ? phase.color.opacity(0.5) : .clear, radius: 6)
                            Text(phase.number)
                                .font(Design.Fonts.display(15))
                                .foregroundStyle(active ? .white : Design.Colors.textMuted)
                        }
                        Text(phase.label)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(active ? phase.color : Design.Colors.textMuted)
                            .tracking(0.5)
                        Text(phase.detail)
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(active ? Design.Colors.textSecondary : Design.Colors.textMuted.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(active ? 1 : 0.4)

                    if idx < phases.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange.opacity(0.4))
                            .padding(.top, 12)
                    }
                }
            }
            .padding(.vertical, Design.Spacing.sm)

            if mode == .substitution || mode == .playmaker {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.bobaCyan.opacity(0.7))
                    Text(mode == .playmaker
                        ? "Ties go to Sudden Death — unless one Hero is SUPER weapon type (SUPER wins)."
                        : "Ties go to Sudden Death: each player reveals top of Hero Deck, higher Power wins.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Rookie Rules

private struct RookieRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            RulesSectionHeader(title: "Goal")
            RuleCard(lines: [
                .init(label: nil, body: "First player to win 4 of 7 Battles wins the game. The player with the higher Power wins each battle.")
            ])

            RulesSectionHeader(title: "Setup")
            RuleCard(lines: [
                .init(label: "Hero Deck", body: "Shuffle your 60-card Hero Deck."),
                .init(label: "Battle Slots", body: "Place 7 Heroes face-down in a row — one per Battle slot."),
                .init(label: "Honors", body: "Flip a coin. The winner earns Honors — the right to act first.")
            ])

            RulesSectionHeader(title: "Battle Sequence")
            RuleCard(lines: [
                .init(label: "Reveal",       body: "Both players simultaneously flip their Hero in the current Battle slot."),
                .init(label: "Compare",      body: "Higher Power wins the battle. The winning player takes the point."),
                .init(label: "Tie → Sudden Death", body: "Each player reveals the top card of their Hero Deck. Higher Power wins; if tied again, repeat until the tie is broken.")
            ])

            RulesSectionHeader(title: "Win Condition")
            RuleCard(lines: [
                .init(label: nil, body: "First player to reach 4 battle wins. The game can end as early as Battle 4 if one player sweeps.")
            ])
        }
    }
}

// MARK: - Substitution Rules

private struct SubstitutionRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            // Everything in Rookie, plus additions
            RookieRulesContent()

            additionsHeader

            RulesSectionHeader(title: "Additional Components")
            RuleCard(lines: [
                .init(label: "Hot Dog Deck", body: "10 Hot Dog cards. These are your substitution currency for the entire game.")
            ])

            RulesSectionHeader(title: "Setup Additions")
            RuleCard(lines: [
                .init(label: "Hand", body: "After placing your 7 Battle Heroes, draw the remaining Hero Deck cards into your hand."),
                .init(label: "Hot Dog Pile", body: "Draw all 10 Hot Dogs into your Hot Dog pile. The count is always public information.")
            ])

            RulesSectionHeader(title: "Substitution Window")
            RuleCard(lines: [
                .init(label: "When", body: "After both players reveal their Hero, before the winner is decided."),
                .init(label: "Who acts first", body: "The Honors player decides first whether to substitute."),
                .init(label: "Cost", body: "Pay 2 Hot Dogs. Send your revealed Hero to Discard; play a Hero from your hand face-up."),
                .init(label: "Limit", body: "Each player may only substitute once per battle."),
                .init(label: "Counter", body: "After the Honors player substitutes, their opponent sees the new Hero and may choose to substitute in response.")
            ])

            RulesSectionHeader(title: "Honors")
            RuleCard(lines: [
                .init(label: nil, body: "Honors passes to the winner of each battle. Having Honors means you substitute first — you reveal your intention before your opponent, giving them information. Sometimes it is better to hold off and see if your opponent substitutes first.")
            ])

            RulesSectionHeader(title: "Resource Management")
            RuleCard(lines: [
                .init(label: nil, body: "You only have 10 Hot Dogs for the entire game. Substitutions cost 2 each, so you can substitute at most 5 times. Never substitute reflexively — reserve Hot Dogs for battles that actually matter.")
            ])
        }
    }

    private var additionsHeader: some View {
        HStack {
            Rectangle()
                .fill(Design.Colors.glassBorder)
                .frame(height: 1)
            Text("SUBSTITUTION ADDITIONS")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
                .tracking(1.5)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Design.Colors.glassBorder)
                .frame(height: 1)
        }
        .padding(.vertical, Design.Spacing.sm)
    }
}

// MARK: - Playmaker Rules

private struct PlaymakerRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            // Everything in Substitution, plus additions
            SubstitutionRulesContent()

            additionsHeader

            RulesSectionHeader(title: "Additional Components")
            RuleCard(lines: [
                .init(label: "Playbook", body: "30 unique Play cards. These give you powerful in-game actions and ongoing effects.")
            ])

            RulesSectionHeader(title: "Setup Additions")
            RuleCard(lines: [
                .init(label: "Playbook", body: "Shuffle your Playbook. Draw 5 Plays as your starting hand.")
            ])

            RulesSectionHeader(title: "Play Window")
            RuleCard(lines: [
                .init(label: "When", body: "After the Substitution Window closes, before the battle winner is decided."),
                .init(label: "Who acts first", body: "The Honors player may play a Play card first."),
                .init(label: "Cost", body: "Pay the Hot Dog cost shown on the card."),
                .init(label: "Alternating", body: "Players alternate playing Play cards until both players pass consecutively."),
                .init(label: "Draw", body: "Draw 1 Play card at the start of each battle.")
            ])

            RulesSectionHeader(title: "Super Weapon Tiebreaker")
            RuleCard(lines: [
                .init(label: nil, body: "If a battle ends in a tie and one Hero has the Super weapon type, that Hero wins automatically. No Sudden Death is needed.")
            ])

            RulesSectionHeader(title: "Tournament & Formats")
            RuleCard(lines: [
                .init(label: "Standard",  body: "Playmaker is the competitive and tournament-standard format."),
                .init(label: "SPEC Format", body: "Special tournament variant: Hero Deck capped at ≤160 total Power; sideboard up to 45 Plays; players may swap Plays from sideboard between games in a match.")
            ])
        }
    }

    private var additionsHeader: some View {
        HStack {
            Rectangle()
                .fill(Design.Colors.glassBorder)
                .frame(height: 1)
            Text("PLAYMAKER ADDITIONS")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .tracking(1.5)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Design.Colors.glassBorder)
                .frame(height: 1)
        }
        .padding(.vertical, Design.Spacing.sm)
    }
}

// MARK: - Card Zones

private struct CardZonesSection: View {
    private let zones: [(name: String, description: String)] = [
        ("Hero Deck",        "Your 60-card main deck. Battle Heroes are drawn or placed from here."),
        ("Battle Slots",     "7 face-down slots — one Hero per slot, revealed in sequence."),
        ("Hand",             "Heroes drawn from your deck after setup (Substitution and Playmaker modes)."),
        ("Active Battle",    "The current face-up Hero in the active battle position."),
        ("Discard Pile",     "Face-up; contents are always public information."),
        ("Playbook",         "Your 30-card Play deck (Playmaker mode). Draw from here."),
        ("Hot Dog Pile",     "Your 10 Hot Dog cards. Count is always public."),
        ("Hot Dog Discard",  "Spent Hot Dogs go here."),
        ("Abyss",            "Removed-from-game zone. Cards here are permanently out of play.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            RulesSectionHeader(title: "Card Zones Reference")
            VStack(spacing: 1) {
                ForEach(zones, id: \.name) { zone in
                    HStack(alignment: .top, spacing: Design.Spacing.md) {
                        Text(zone.name)
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .frame(width: 120, alignment: .leading)
                        Text(zone.description)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Deckbuilding Rules

private struct DeckbuildingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            RulesSectionHeader(title: "Deckbuilding Rules")

            RuleCard(lines: [
                .init(label: "Hero Deck size",      body: "Exactly 60 cards (minimum 40 for Draft/Sealed limited events)."),
                .init(label: "Power duplicates",    body: "Maximum 6 copies of any single Power value across your entire Hero Deck."),
                .init(label: "Variation rule",      body: "Only 1 copy per variation — e.g., BoJax First Edition and BoJax 2026 Edition are different variations and both legal together. Two copies of the same variation are not legal."),
                .init(label: "Hero copies",         body: "Up to 6 total copies of the same Hero across all their variations."),
                .init(label: "Hot Dog Deck",        body: "Exactly 10 cards. Duplicates are allowed."),
                .init(label: "Playbook",            body: "Exactly 30 Plays, all unique names. Bonus Plays (special treatment cards) may be added beyond the 30 limit.")
            ])
        }
    }
}

// MARK: - StrategyView

private struct StrategyView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Spacing.sm) {
                PowerCurveSection()
                WeaponSynergySection()
                SubstitutionStrategySection()
                PlayCardTypesSection()
                ResourceManagementSection()
                ArchetypesSection()
            }
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
    }
}

// MARK: - Strategy DisclosureGroup wrapper

private struct StrategyDisclosure<Content: View>: View {
    let title: String
    let subtitle: String
    @State private var isExpanded = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Design.Fonts.display(17))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text(subtitle)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                .padding(Design.Spacing.md)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    content()
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Strategy body text helper

private struct StrategyBody: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Design.Fonts.mono(14))
            .foregroundStyle(Design.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StrategyBullet: View {
    let text: String
    var accent: Color = Design.Colors.bobaOrange

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Text("·")
                .font(Design.Fonts.mono(15))
                .foregroundStyle(accent)
            Text(text)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StrategyKeyPlays: View {
    let plays: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("KEY PLAYS")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            FlowLayout(spacing: Design.Spacing.xs) {
                ForEach(plays, id: \.self) { play in
                    Text(play)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .padding(.horizontal, Design.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Design.Colors.bobaCyan.opacity(0.12))
                                .overlay(Capsule().strokeBorder(Design.Colors.bobaCyan.opacity(0.3), lineWidth: 1))
                        )
                }
            }
        }
    }
}

// MARK: - Individual Strategy Sections

private struct PowerCurveSection: View {
    var body: some View {
        StrategyDisclosure(
            title: "Power Curve Management",
            subtitle: "Spread your deck across power bands; place slots strategically"
        ) {
            StrategyBody(text: "The 6-per-power-value rule forces you to spread your deck across multiple power levels. A well-built deck balances all three bands:")
            StrategyBullet(text: "High-power Heroes (160–200) for critical battles")
            StrategyBullet(text: "Mid-range Heroes (120–155) for consistency")
            StrategyBullet(text: "Lower-power Heroes (85–115) are inevitable — plan for them")
            StrategyBody(text: "Place battle slots strategically. Front-loading establishes Honors momentum. Back-loading saves power for the close. Battle 7 is do-or-die — consider saving your strongest Hero there.")
            StrategyBody(text: "Plays that reward positioning: Late Hit (+35 in Battle 7), The Closer (+40 in Battle 7).")
        }
    }
}

private struct WeaponSynergySection: View {
    private let synergies: [(weapon: String, element: String, plays: [String])] = [
        ("FIRE",  "FIRE",  ["Fire Boost", "Fire Crew", "Flame Wall", "Burning Fever", "Eternal Flame", "Smitty"]),
        ("ICE",   "ICE",   ["Ice Boost", "Ice Crew", "Icy Shield", "Frozen Resolve", "Unbreakable Ice"]),
        ("STEEL", "STEEL", ["Steel Boost", "Steel Crew", "Steel Defense", "Steel Shield", "Chrome Will"])
    ]

    var body: some View {
        StrategyDisclosure(
            title: "Weapon Synergy",
            subtitle: "Build around 1–2 weapon types; many Plays reward consistency"
        ) {
            StrategyBody(text: "Focus on 1–2 primary weapon types. Synergy-based decks outperform general decks when the engine runs. Use weapon-agnostic Plays (Weapon Mixer, Edge Rush, Brothers In Arms) if mixing.")
            ForEach(synergies, id: \.weapon) { entry in
                HStack(alignment: .top, spacing: Design.Spacing.sm) {
                    Text(entry.weapon)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.element(entry.element))
                        .frame(width: 44, alignment: .leading)
                    FlowLayout(spacing: Design.Spacing.xs) {
                        ForEach(entry.plays, id: \.self) { play in
                            Text(play)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.element(entry.element))
                                .padding(.horizontal, Design.Spacing.sm)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Design.Colors.element(entry.element).opacity(0.1))
                                        .overlay(Capsule().strokeBorder(Design.Colors.element(entry.element).opacity(0.3), lineWidth: 1))
                                )
                        }
                    }
                }
            }
        }
    }
}

private struct SubstitutionStrategySection: View {
    var body: some View {
        StrategyDisclosure(
            title: "Substitution Strategy",
            subtitle: "10 Hot Dogs total — spend them where it counts"
        ) {
            StrategyBullet(text: "You only have 10 Hot Dogs total — at 2 per sub, that's 5 maximum substitutions all game.")
            StrategyBullet(text: "Substitute only when the power gap justifies the cost.")
            StrategyBullet(text: "Watch your opponent's Hot Dog count — at 0, they can neither substitute nor play paid cards.")
            StrategyBullet(text: "Honors means you substitute first. Sometimes deliberately hold off: if you pass, your opponent may tip their hand, letting you respond better.")
            StrategyBullet(text: "Save substitutions for battles 5–7. Early battles rarely decide the game; late battles always do.")
        }
    }
}

private struct PlayCardTypesSection: View {
    private let types: [(name: String, description: String, examples: String)] = [
        ("Tempo",     "Immediate one-time boosts.",                               "Buff Up 15 (+15 for 2 dogs)"),
        ("Value",     "Ongoing effects that compound over multiple battles.",      "Fire Boost (+10 all Fire Heroes, rest of game)"),
        ("Disruption","Deny opponent options for a battle or permanently.",        "Full Court Press (opponent can't play this battle), Bench Blocker (-20 + no sub)"),
        ("Economy",   "Recover Hot Dogs — extend your resource advantage.",        "Trash Bandit (free recovery), Victory Dinner (+3 on win)"),
        ("Game-changer","High-cost, high-impact swings that can flip any battle.", "Edge Rush (5 cost — set power 5 above opponent's), By Any Means Necessary (6 cost — search + play any Play free)")
    ]

    var body: some View {
        StrategyDisclosure(
            title: "Play Card Types",
            subtitle: "Tempo · Value · Disruption · Economy · Game-changer"
        ) {
            ForEach(types, id: \.name) { type_ in
                VStack(alignment: .leading, spacing: 4) {
                    Text(type_.name)
                        .font(Design.Fonts.mono(15, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                    Text(type_.description)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textSecondary)
                    Text(type_.examples)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textMuted)
                        .italic()
                }
                .padding(Design.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .fill(Design.Colors.surface2)
                )
            }
        }
    }
}

private struct ResourceManagementSection: View {
    var body: some View {
        StrategyDisclosure(
            title: "Resource Management",
            subtitle: "Plays and Hot Dogs are finite — track both carefully"
        ) {
            StrategyBullet(text: "Start with 5 Plays in hand; draw 1 per battle (7 total draws over a full game).")
            StrategyBullet(text: "Hot Dogs fund both substitutions (2 each) and Play cards — every paid Play is a potential substitution foregone.")
            StrategyBullet(text: "Don't spend all Hot Dogs on early Plays — late-game substitutions are often more decisive.")
            StrategyBullet(text: "Free (0-cost) Plays are extremely valuable. They preserve Hot Dogs while adding power.")
            StrategyBullet(text: "Always track your opponent's Hot Dog count. At 0, they can neither substitute nor play any paid card — this window is your strongest attacking position.")
        }
    }
}

// MARK: - Archetypes Section

private struct ArchetypesSection: View {
    private let archetypes: [Archetype] = [
        Archetype(
            name: "Fire Aggro",
            element: "FIRE",
            tagline: "Stack Fire synergies; lock opponents with Flame Wall",
            keyPlays: ["Fire Boost", "Fire Crew", "Flame Wall", "Burning Fever", "Eternal Flame", "Smitty"],
            strategy: "Establish Fire synergy early with Fire Boost and Fire Crew, then close games with Burning Fever and Eternal Flame. Flame Wall prevents the opponent from neutralizing your element advantage. Go wide on Fire Heroes to maximize synergy triggers.",
            weakness: "Weak to Fire Extinguisher, Fire Hose, and Only Ice."
        ),
        Archetype(
            name: "Ice Control",
            element: "ICE",
            tagline: "Deny substitutions; protect key Heroes behind layers of ice",
            keyPlays: ["Ice Boost", "Ice Crew", "Icy Shield", "Frozen Resolve", "Frozen Lineup", "Unbreakable Ice"],
            strategy: "Use Icy Shield and Unbreakable Ice to make your Heroes difficult or impossible to substitute against. Frozen Lineup locks opponent Heroes in place. Play long games — Ice Control wins through attrition, not aggression.",
            weakness: "Weak to Ice Pick, Icevantage, and Frost-Hardened."
        ),
        Archetype(
            name: "Steel Wall",
            element: "STEEL",
            tagline: "Layer Steel protection until your Heroes are nearly invulnerable",
            keyPlays: ["Steel Boost", "Steel Crew", "Steel Defense", "Steel Shield", "Chrome Will", "Steel Cage"],
            strategy: "Stack Steel Defense, Steel Shield, and Chrome Will for protection that compounds. Steel Cage prevents removal entirely. Once your defense engine is running, opponents cannot substitute effectively against your mid-range Steel Heroes.",
            weakness: "Weak to Stain-Less-Steel, Rusted Edge, and Molten Steel."
        ),
        Archetype(
            name: "Mixed Toolbox",
            element: "NONE",
            tagline: "Adapt to any opponent; maximum flexibility",
            keyPlays: ["Weapon Mixer", "Weapon Tangle", "Brothers In Arms", "Different Leagues", "Edge Rush"],
            strategy: "Run weapon-agnostic Plays and adapt in real time. Edge Rush and Deadline Deal let you react to any power level regardless of weapon. Brothers In Arms rewards diverse Hero rosters. You have no weaknesses to weapon-specific hate, but no dominant synergy either.",
            weakness: "No single synergy is as powerful as a focused build."
        ),
        Archetype(
            name: "Economy / Attrition",
            element: "NONE",
            tagline: "Recover Hot Dogs faster than your opponent can spend them",
            keyPlays: ["Trash Bandit", "Victory Dinner", "Make Up Meal", "Too Full To Fight", "Bun Shortage", "Mutually Assured Dogstruction"],
            strategy: "Use Trash Bandit and Victory Dinner to continually refresh your Hot Dog supply while draining your opponent's. Bun Shortage limits opponent recovery. Mutually Assured Dogstruction resets both piles — play it when you're already at low count to equalize. Win late when opponent has no resources left.",
            weakness: "Less raw power boosting than synergy decks. Loses quickly to fast, aggro opponents."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("ARCHETYPES")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(2)
                .padding(.bottom, Design.Spacing.xs)

            ForEach(archetypes) { archetype in
                ArchetypeCard(archetype: archetype)
            }
        }
    }
}

private struct Archetype: Identifiable {
    let id = UUID()
    let name: String
    let element: String
    let tagline: String
    let keyPlays: [String]
    let strategy: String
    let weakness: String
}

private struct ArchetypeCard: View {
    let archetype: Archetype
    @State private var isExpanded = false

    private var accentColor: Color { Design.Colors.element(archetype.element) }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Design.Spacing.md) {
                    // Element dot
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: accentColor.opacity(0.6), radius: 4)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(archetype.name)
                            .font(Design.Fonts.display(17))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text(archetype.tagline)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .padding(Design.Spacing.md)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    Divider()
                        .background(Design.Colors.glassBorder)

                    StrategyKeyPlays(plays: archetype.keyPlays)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("STRATEGY")
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        Text(archetype.strategy)
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEAKNESS")
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        Text(archetype.weakness)
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Color(hex: "C0392B").opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
