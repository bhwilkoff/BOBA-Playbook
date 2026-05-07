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
    enum PurchaseMode: String, CaseIterable, Identifiable, Hashable {
        case breaks = "Live Breaks"
        case stores = "Find a Store"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .breaks: return "tv.fill"
            case .stores: return "mappin.and.ellipse"
            }
        }
    }

    @State private var mode: PurchaseMode = .breaks
    @State private var walkthrough: BOBAWalkthrough.Script? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// `List(selection:)` on iOS only accepts Binding<T?>? — not the
    /// non-optional state above. Wrapper lets the iPad sidebar drive
    /// selection while keeping the rest of the body / Picker using
    /// the non-optional value.
    private var modeBinding: Binding<PurchaseMode?> {
        Binding(
            get: { mode },
            set: { if let v = $0 { mode = v } }
        )
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadBody
            } else {
                compactBody
            }
        }
        // .walkthroughOverlay must sit OUTSIDE NavigationStack so the
        // overlay's GeometryReader measures the full screen, not the
        // collapsed-VStack inner content (the bug that reported
        // container 79.7×47 — the modePicker's intrinsic size).
        .walkthroughOverlay($walkthrough)
        .onAppear {
            if WalkthroughsManager.shared.shouldShow(.purchaseTab) {
                // Defer so the segmented Picker lays out before the
                // walkthrough captures its anchor — without the
                // deferral the Picker's pre-layout rect was bizarre
                // (e.g., (-39.7, -23.3, 79.3, 47)).
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    walkthrough = .purchaseTab
                }
            }
        }
    }

    // MARK: - Compact (iPhone) body — segmented picker + content

    @ViewBuilder
    private var compactBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .walkthroughAnchor("purchase.picker")

                modeContent
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { purchaseToolbar }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - iPad body — sidebar mode picker + detail

    @ViewBuilder
    private var iPadBody: some View {
        NavigationSplitView {
            List(selection: modeBinding) {
                ForEach(PurchaseMode.allCases) { m in
                    Label(m.rawValue, systemImage: m.icon)
                        .tag(m)
                        .walkthroughAnchor(m == .breaks ? "purchase.picker" : "")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Purchase")
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        } detail: {
            NavigationStack {
                modeContent
                    .background(Design.Colors.nearBlack)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { purchaseToolbar }
                    .toolbarBackground(.regularMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .breaks: UpcomingBreaksList()
        case .stores: StoreLocatorView()
        }
    }

    @ToolbarContentBuilder
    private var purchaseToolbar: some ToolbarContent {
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

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(PurchaseMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}
