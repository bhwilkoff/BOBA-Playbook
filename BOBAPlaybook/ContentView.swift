//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    @Binding var selectedTab: Int
    @Environment(AuthManager.self) private var auth
    @Environment(ScanStore.self) private var scanStore
    @Environment(ScanCoordinator.self) private var scanCoordinator

    var body: some View {
        // iOS 26 Tab API. Using `Tab(value:)` (instead of the deprecated
        // .tabItem modifier) opts the tab bar into the system's
        // floating "Liquid Glass" appearance — larger icons, pill-shaped
        // active state, the look the old build had before the .tabItem
        // refactor regressed it.
        //
        // Find tab uses `role: .search` per DESIGN.md §6.1 — the iOS 26
        // dedicated search pattern. The tab bar minimizes during search
        // and search results take the canvas. SearchView still owns its
        // own .searchable field; the role tells iOS how to render the
        // tab bar slot.
        @Bindable var coord = scanCoordinator
        TabView(selection: $selectedTab) {
            Tab("Learn", systemImage: "book.pages.fill", value: 1) {
                LearnView()
            }

            Tab("Decks", systemImage: "rectangle.stack.badge.plus", value: 3) {
                DecksView()
            }

            Tab(value: 0, role: .search) {
                SearchView()
            }

            Tab("Collection", systemImage: "square.grid.2x2", value: 4) {
                CollectionView()
            }

            Tab("Purchase", systemImage: "cart.fill", value: 5) {
                PurchaseView()
            }
        }
        // .tabViewStyle(.sidebarAdaptable) intentionally omitted —
        // when the user picks "sidebar mode" on iPadOS 26, the system
        // tab bar morphs to a left sidebar. Our per-tab
        // NavigationSplitView (saved decks in Decks; lens picker in
        // Collection; mode picker in Purchase; category list in
        // Learn) then adds a SECOND sidebar to the right of the
        // system one — visually competing.
        //
        // Floating tab pill is the right anchor: TabView stays a
        // bottom pill on every device, and each tab owns its own
        // sidebar/detail layout via NavigationSplitView. iPad users
        // get a richer in-tab navigation than the system tab sidebar
        // would provide (which is just the 5 tab names).
        .tint(Design.Colors.bobaOrange)
        // iPad hardware-keyboard shortcuts — Cmd+1..5 jump to tabs in
        // sidebar order (Find / Learn / Decks / Collection / Purchase).
        // Hidden Button overlay is the standard SwiftUI pattern for
        // attaching .keyboardShortcut to a binding-driven selection.
        // No-op on iPhone (no keyboard) — costs only an invisible
        // 0×0 view, no layout impact.
        .background(TabSwitchShortcuts(selectedTab: $selectedTab))
        // Centralized scan presentation per DESIGN.md §6.5 — single
        // ScanView modal regardless of which tab invoked it. Tabs call
        // ScanCoordinator.start(...) with the right destination; the
        // coordinator drives this fullScreenCover.
        .fullScreenCover(isPresented: $coord.isPresenting, onDismiss: {
            scanCoordinator.dismiss(scanStore: scanStore)
        }) {
            ZStack(alignment: .topLeading) {
                ScanView()
                Button {
                    coord.isPresenting = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .padding(Design.Spacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scanner")
            }
        }
    }
}

// MARK: - Hardware-keyboard tab shortcuts (iPad)

/// Cmd+1..5 jump to tabs in sidebar order. Renders as 0×0 hidden
/// buttons — present in the responder chain so .keyboardShortcut
/// fires, but not visible or interactive via touch. iPhone with no
/// keyboard simply ignores them.
///
/// Cmd+/ also jumps to Find — matches the canonical GitHub / YouTube
/// "go to search" pattern + Android tick 131's `/` shortcut. iPad-only
/// affordance; iPhone w/o keyboard ignores it.
private struct TabSwitchShortcuts: View {
    @Binding var selectedTab: Int
    var body: some View {
        Group {
            Button { selectedTab = 0 } label: { EmptyView() }
                .keyboardShortcut("1", modifiers: .command)
            Button { selectedTab = 1 } label: { EmptyView() }
                .keyboardShortcut("2", modifiers: .command)
            Button { selectedTab = 3 } label: { EmptyView() }
                .keyboardShortcut("3", modifiers: .command)
            Button { selectedTab = 4 } label: { EmptyView() }
                .keyboardShortcut("4", modifiers: .command)
            Button { selectedTab = 5 } label: { EmptyView() }
                .keyboardShortcut("5", modifiers: .command)
            // Cmd+/ → Find. Same "go to search" idiom Chromebooks +
            // GitHub use. Routes to tab 0 (Find).
            Button { selectedTab = 0 } label: { EmptyView() }
                .keyboardShortcut("/", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Placeholder for unbuilt tabs
struct PlaceholderView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: Design.Spacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Design.Colors.textMuted)
                Text(title)
                    .font(Design.Fonts.display(20))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(message)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Design.Colors.nearBlack)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
