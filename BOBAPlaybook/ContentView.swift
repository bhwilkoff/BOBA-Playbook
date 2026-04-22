//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    @Binding var selectedTab: Int

    var body: some View {
        // Nav refactor: 5 tabs — Find, Learn, Play, Decks, Collection.
        // Scan moved into the Find tab's search bar (right-edge button).
        // Profile moved to a toolbar icon on the Find tab (left of wordmark).
        TabView(selection: $selectedTab) {
            SearchView()
                .tabItem { Label("Find", systemImage: "magnifyingglass") }
                .tag(0)

            LearnView()
                .tabItem { Label("Learn", systemImage: "book.pages.fill") }
                .tag(1)

            PlayView()
                .tabItem { Label("Play", systemImage: "bolt.square.fill") }
                .tag(2)

            DecksView()
                .tabItem { Label("Decks", systemImage: "rectangle.stack.badge.plus") }
                .tag(3)

            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
                .tag(4)
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
