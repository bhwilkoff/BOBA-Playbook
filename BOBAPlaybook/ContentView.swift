//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    @Binding var selectedTab: Int
    @Environment(AuthManager.self) private var auth

    var body: some View {
        // Nav: Find, Learn, Decks, Collection. The historical Play tab is
        // gated to admins only and reachable through the Profile screen
        // (an icon next to the role badge). Non-admin builds never see
        // the practice surface from here.
        TabView(selection: $selectedTab) {
            SearchView()
                .tabItem { Label("Find", systemImage: "magnifyingglass") }
                .tag(0)

            LearnView()
                .tabItem { Label("Learn", systemImage: "book.pages.fill") }
                .tag(1)

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
