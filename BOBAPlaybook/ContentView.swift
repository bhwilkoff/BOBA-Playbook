//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    @Binding var selectedTab: Int
    @Environment(AuthManager.self) private var auth

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
