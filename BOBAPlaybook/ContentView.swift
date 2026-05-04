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
        .tint(Design.Colors.bobaOrange)
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
