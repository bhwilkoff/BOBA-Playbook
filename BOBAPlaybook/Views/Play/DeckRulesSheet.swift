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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                activeRulesSection
                toggleableSection
                footerNote
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Deck Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        store.ruleOverrides = DeckRuleOverrides()
                    }
                    .disabled(!store.ruleOverrides.hasAnyUserOverride)
                }
            }
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
            }
        } header: {
            Text("Optional Rule Toggles")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        }
        .listRowBackground(Design.Colors.surface)
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
