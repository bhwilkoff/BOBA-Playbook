//
//  DeckRulesSheet.swift
//  BOBAPlaybook
//
//  Rule-set inspector + toggle panel for the Deck Builder.
//
//  Shows every rule currently active for the user's deck (per the 2026
//  Nationals PDF formats) and lets them flip optional rules like the
//  retired 6-per-hero cap or the Bonus Plays / HTD Plays toggles.
//
//  Spirit: the coach should never wonder WHY a card was rejected — the
//  rule list makes every constraint visible, and every toggle has a
//  reason attached.
//

import SwiftUI

struct DeckRulesSheet: View {
    @Bindable var store: DeckBuilderStore
    /// Wrap content in a NavigationStack when presented as a sheet.
    /// Set to false when used as a NavigationDestination push from
    /// the deck editor — the parent stack already provides the nav
    /// chrome, and a nested stack creates back-button conflicts.
    var wrapInNavStack: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if wrapInNavStack {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            presetPickerSection
            activeRulesSection
            specialRulesSection
            toggleableSection
            footerNote
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
        .navigationTitle("Deck Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Done button only when presented as a sheet — pushed
            // mode uses the back chevron instead.
            if wrapInNavStack {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset") {
                    store.ruleOverrides = DeckRuleOverrides()
                }
                .disabled(!store.ruleOverrides.hasAnyUserOverride)
            }
        }
    }

    // MARK: - Preset picker

    private var presetPickerSection: some View {
        Section {
            // Nationals presets
            DisclosureGroup {
                ForEach(RulePresets.nationalsPresets) { preset in
                    presetRow(preset)
                }
            } label: {
                presetHeaderRow(
                    title: "2026 Nationals Events",
                    subtitle: "\(RulePresets.nationalsPresets.count) preset rule sets from the DRAFT PDF",
                    accent: Design.Colors.bobaOrange
                )
            }

            // Casual presets
            DisclosureGroup {
                ForEach(RulePresets.casualPresets) { preset in
                    presetRow(preset)
                }
            } label: {
                presetHeaderRow(
                    title: "Casual Rule Sets",
                    subtitle: "Home-rules + legacy presets",
                    accent: Design.Colors.bobaCyan
                )
            }

            // Custom-rule-set indicator — shown when the coach has modified
            // overrides beyond the attached preset (or built with no preset).
            if store.isCustomRuleSet {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Rule Set")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text(store.activePresetID == nil
                             ? "Building under format defaults — no preset attached."
                             : "Based on '\(store.activePreset?.name ?? "?")' with your customizations.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Rule Set")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        } footer: {
            Text("Pick a preset to auto-configure the format + rules. Toggle anything below to create a custom rule set on top.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .listRowBackground(Design.Colors.surface)
    }

    private func presetHeaderRow(title: String, subtitle: String, accent: Color) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(subtitle)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
    }

    private func presetRow(_ preset: RulePreset) -> some View {
        Button {
            store.applyPreset(preset)
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                Image(systemName: store.activePresetID == preset.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.activePresetID == preset.id ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                    .frame(width: 20)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.name)
                            .font(Design.Fonts.mono(12, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        if let purse = preset.divisionPurse {
                            Text("$\(purse/1000)k")
                                .font(Design.Fonts.mono(9, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaCyan)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Design.Colors.bobaCyan.opacity(0.12)))
                        }
                    }
                    Text(preset.description)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Preset-driven special rules

    @ViewBuilder
    private var specialRulesSection: some View {
        if let preset = store.activePreset, !preset.specialRules.isEmpty {
            Section {
                ForEach(preset.specialRules) { rule in
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: rule.isSelfVerify ? "person.fill.checkmark" : "scalemass")
                            .font(.system(size: 14))
                            .foregroundStyle(rule.isSelfVerify ? Design.Colors.bobaOrange : Design.Colors.bobaCyan)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.label)
                                .font(Design.Fonts.mono(13))
                                .foregroundStyle(Design.Colors.textPrimary)
                            if let note = rule.note {
                                Text(note)
                                    .font(Design.Fonts.mono(10))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if rule.isSelfVerify {
                            Text("SELF-VERIFY")
                                .font(Design.Fonts.mono(8, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaOrange)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Design.Colors.bobaOrange.opacity(0.15)))
                        }
                    }
                }
            } header: {
                Text("Division-Specific Rules")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
            } footer: {
                Text("SELF-VERIFY rules can't be machine-checked against the current catalog — you confirm compliance yourself.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .listRowBackground(Design.Colors.surface)
        }
    }

    // MARK: - Active rules (read-only list)

    private var activeRulesSection: some View {
        Section {
            ForEach(store.activeRules) { rule in
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: rule.isOverride ? "slider.horizontal.3" : "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(rule.isOverride ? Design.Colors.bobaOrange : Design.Colors.bobaCyan)
                        .frame(width: 20)
                    Text(rule.label)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Spacer()
                    if rule.isOverride {
                        Text("CUSTOM")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Design.Colors.bobaOrange.opacity(0.15)))
                    }
                }
            }
            .listRowBackground(Design.Colors.surface)
        } header: {
            Text("\(store.format.displayName) — Active Rules")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        } footer: {
            Text("Rules come from the hero-deck format shown above. Toggle the optional rules below to customize the rule set for your deck.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }

    // MARK: - Toggleable rules

    private var toggleableSection: some View {
        Section {
            // 6-per-hero opt-in
            let sixOn = Binding(
                get: { store.ruleOverrides.perHeroNameLimit == 6 },
                set: { store.ruleOverrides.perHeroNameLimit = $0 ? 6 : nil }
            )
            Toggle(isOn: sixOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max 6 of same hero (legacy)")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("Pre-2026 rule. Retired in the 2026 Nationals PDF but still useful for casual play.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Design.Colors.bobaOrange)

            // Per-power limit override (3/6/off)
            perPowerPicker

            // Bonus / HTD toggles (only shown when Playbook is relevant)
            if store.format.needsPlaybook {
                Toggle(isOn: $store.ruleOverrides.bonusPlaysEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bonus Plays enabled")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("Off in Spec Playmaker / Brawl Playmaker per 2026 PDF; on elsewhere.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .tint(Design.Colors.bobaOrange)

                Toggle(isOn: $store.ruleOverrides.htdPlaysEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HTD Plays enabled")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("Off in Spec Playmaker / Brawl Playmaker; N/A in Tecmo Bowl.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .tint(Design.Colors.bobaOrange)

                // DBS enforcement toggle
                let dbsOn = Binding(
                    get: { store.effectiveEnforceDBS },
                    set: { store.ruleOverrides.enforceDBS = $0 }
                )
                Toggle(isOn: dbsOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DBS budget enforced")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("1,000 DBS cap for Playmaker divisions. Flip off for casual builds.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .tint(Design.Colors.bobaOrange)

                // Custom DBS budget — only meaningful when the budget is
                // actually being enforced. Shows format's default (1,000)
                // as placeholder; nil override = defer to format.
                if store.effectiveEnforceDBS {
                    dbsBudgetField
                }
            }
        } header: {
            Text("Optional Rule Toggles")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        }
        .listRowBackground(Design.Colors.surface)
    }

    // Custom DBS budget — surfaces `ruleOverrides.dbsBudgetOverride`.
    // Segmented preset picker for the common event budgets, plus a
    // free-form numeric field for custom coach-set budgets. The store
    // already reads dbsBudgetOverride ?? format.dbsBudget when computing
    // the effective cap, so no deckvalidator changes are needed.
    private var dbsBudgetField: some View {
        let defaultBudget = store.format.dbsBudget
        let effective = store.ruleOverrides.dbsBudgetOverride ?? defaultBudget
        let presets: [Int] = [500, 750, 1_000, 1_250, 1_500]
        let presetBinding = Binding<Int>(
            get: { store.ruleOverrides.dbsBudgetOverride ?? defaultBudget },
            set: { new in
                store.ruleOverrides.dbsBudgetOverride = (new == defaultBudget) ? nil : new
            }
        )
        return VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                Text("DBS budget")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                Text("\(effective)")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(store.ruleOverrides.dbsBudgetOverride == nil
                                     ? Design.Colors.textMuted
                                     : Design.Colors.bobaOrange)
            }
            Text("Default for \(store.format.displayName): \(defaultBudget). Override for house-rule events.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
            Picker("DBS budget", selection: presetBinding) {
                ForEach(presets, id: \.self) { v in
                    Text("\(v)").tag(v)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
            if store.ruleOverrides.dbsBudgetOverride != nil {
                Button("Reset to \(defaultBudget)") {
                    store.ruleOverrides.dbsBudgetOverride = nil
                }
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.bobaCyan)
                .padding(.top, 2)
            }
        }
    }

    private var perPowerPicker: some View {
        let binding = Binding(
            get: { store.ruleOverrides.perPowerLimit ?? store.format.perPowerDefaultLimit },
            set: { new in
                if new == store.format.perPowerDefaultLimit {
                    store.ruleOverrides.perPowerLimit = nil   // back to format default
                } else {
                    store.ruleOverrides.perPowerLimit = new
                }
            }
        )
        return VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("Per-power-value limit")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Default: \(store.format.perPowerDefaultLimit). Blast division uses 3.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
            Picker("Per-power limit", selection: binding) {
                Text("3 (Blast)").tag(3)
                Text("6 (standard)").tag(6)
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
        }
    }

    private var footerNote: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("2026 BoBA National Events")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                Text("Rule definitions mirror the DRAFT 2026 PDF. Division-specific toggles (Brawl/Blast/Granny's Gum) will auto-configure this panel once the division picker ships in Phase 4.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
    }
}
