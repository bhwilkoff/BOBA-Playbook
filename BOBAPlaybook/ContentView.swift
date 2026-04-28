//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    @Binding var selectedTab: Int
    @Environment(AuthManager.self) private var auth

    var body: some View {
        // Nav order: Learn · Decks · Find · Collection · Purchase. Find is
        // the default landing surface and sits centered in the rail; the
        // SF Symbol "magnifyingglass.circle.fill" is rendered larger via
        // .symbolRenderingMode(.hierarchical) + the orange tint to read
        // as the primary entry point.
        TabView(selection: $selectedTab) {
            LearnView()
                .tabItem { Label("Learn", systemImage: "book.pages.fill") }
                .tag(1)

            DecksView()
                .tabItem { Label("Decks", systemImage: "rectangle.stack.badge.plus") }
                .tag(3)

            SearchView()
                .tabItem {
                    Label("Find", systemImage: "magnifyingglass.circle.fill")
                }
                .tag(0)

            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
                .tag(4)

            PurchaseView()
                .tabItem { Label("Purchase", systemImage: "cart.fill") }
                .tag(5)
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
