//
//  LegalityReportSheet.swift
//  BOBAPlaybook
//
//  Runs the current deck against every preset in RulePresets and shows
//  which events the deck qualifies for — plus the top 1–2 reasons for
//  each event it doesn't. Auto-opens after a CSV import so coaches get
//  immediate feedback on a deck they just pulled in from another tool;
//  also available on demand via the deck builder toolbar.
//

import SwiftUI

struct LegalityReportSheet: View {
    @Bindable var store: DeckBuilderStore
    /// See DeckRulesSheet — wrap in NavigationStack only when used as
    /// a sheet. Editor pushes pass false.
    var wrapInNavStack: Bool = true
    @Environment(\.dismiss) private var dismiss

    /// Computed once on first body evaluation. Not recomputed during the
    /// view's lifetime — the report is a snapshot of the deck at open time.
    @State private var report: [DeckBuilderStore.LegalityReport] = []

    private var legalReports: [DeckBuilderStore.LegalityReport] {
        report.filter(\.legal)
    }
    private var illegalReports: [DeckBuilderStore.LegalityReport] {
        report.filter { !$0.legal }
    }

    var body: some View {
        if wrapInNavStack {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            summarySection
            legalSection
            illegalSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
        .navigationTitle("Legality Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if wrapInNavStack {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { if report.isEmpty { report = store.computeLegalityReport() } }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(store.deckName)
                    .font(Design.Fonts.display(22))
                    .foregroundStyle(Design.Colors.textPrimary)

                HStack(spacing: Design.Spacing.md) {
                    statLine(label: "Heroes", value: "\(store.heroes.count)")
                    if store.format.needsPlaybook {
                        statLine(label: "Plays", value: "\(store.plays.count)")
                    }
                    if store.format.needsHotDogs {
                        statLine(label: "Hot Dogs", value: "\(store.hotDogs.count)")
                    }
                    if store.format.needsPlaybook {
                        statLine(label: "DBS", value: "\(store.totalDBS)")
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 8) {
                    Image(systemName: legalReports.isEmpty ? "xmark.circle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(legalReports.isEmpty ? Color(hex: "C0392B") : Color(hex: "4CAF50"))
                    Text(legalReports.isEmpty
                         ? "Not yet legal for any preset"
                         : "Legal for \(legalReports.count) of \(report.count) events")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
            .listRowBackground(Design.Colors.surface)
        }
    }

    private var legalSection: some View {
        Section {
            if legalReports.isEmpty {
                Text("Your deck isn't legal for any of the 2026 Nationals or casual presets yet. Check the illegal events below to see what's missing.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .listRowBackground(Design.Colors.surface)
            } else {
                ForEach(legalReports) { r in
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "4CAF50"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.preset.name)
                                .font(Design.Fonts.mono(13, weight: .bold))
                                .foregroundStyle(Design.Colors.textPrimary)
                            if let div = r.preset.division {
                                Text("\(div) Division\(r.preset.divisionPurse.map { " · $\($0/1000)k" } ?? "")")
                                    .font(Design.Fonts.mono(10))
                                    .foregroundStyle(Design.Colors.textMuted)
                            }
                        }
                        Spacer()
                        Button("Apply") {
                            store.applyPreset(r.preset)
                            dismiss()
                        }
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                    }
                    .listRowBackground(Design.Colors.surface)
                }
            }
        } header: {
            Text("Legal Events (\(legalReports.count))")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Color(hex: "4CAF50"))
        }
    }

    private var illegalSection: some View {
        Section {
            ForEach(illegalReports) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Design.Colors.textMuted)
                        Text(r.preset.name)
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    ForEach(Array(r.errors.prefix(2).enumerated()), id: \.offset) { _, err in
                        Text("• \(err)")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if r.errors.count > 2 {
                        Text("+\(r.errors.count - 2) more issue(s)")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .padding(.leading, 10)
                    }
                }
                .padding(.vertical, 3)
                .listRowBackground(Design.Colors.surface)
            }
        } header: {
            Text("Not Legal For (\(illegalReports.count))")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
        } footer: {
            Text("Tap Apply on any legal event to switch the deck to that preset's rules. Toggle individual rules in Deck Rules to iterate toward compliance.")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Design.Colors.textMuted)
                .padding(.top, 6)
        }
    }

    private func statLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
            Text(value)
                .font(Design.Fonts.mono(14, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
        }
    }
}
