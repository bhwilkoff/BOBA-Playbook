//
//  PurchaseView.swift
//  BOBAPlaybook
//
//  Per DESIGN.md §8.5 — segmented picker (≤4 segments) at top, two
//  destinations: Live Breaks + Find a Store. Each owns its own scroll
//  context (refreshable, etc.). Walkthrough fires on first visit and
//  re-launches from the overflow Menu.
//

import SwiftUI

struct PurchaseView: View {
    enum PurchaseMode: String, CaseIterable, Identifiable {
        case breaks = "Live Breaks"
        case stores = "Find a Store"
        var id: String { rawValue }
    }

    @State private var mode: PurchaseMode = .breaks
    @State private var walkthrough: BOBAWalkthrough.Script? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .walkthroughAnchor("purchase.picker")

                switch mode {
                case .breaks:
                    UpcomingBreaksList()
                case .stores:
                    StoreLocatorView()
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            WalkthroughsManager.shared.relaunch(.purchaseTab)
                            walkthrough = .purchaseTab
                        } label: {
                            Label("Show walkthrough", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    .accessibilityLabel("Purchase options")
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .walkthroughOverlay($walkthrough)
        }
        .onAppear {
            if WalkthroughsManager.shared.shouldShow(.purchaseTab) {
                walkthrough = .purchaseTab
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(PurchaseMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}
