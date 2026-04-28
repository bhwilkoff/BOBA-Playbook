//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    @Binding var selectedTab: Int
    @Environment(AuthManager.self) private var auth

    var body: some View {
        // Native TabView clamps every .tabItem to a uniform size — there
        // is no API to make one item larger than the rest. We hide the
        // system tab bar with .toolbar(.hidden, for: .tabBar) and render
        // our own via .safeAreaInset so Find can sit higher and bigger
        // than its siblings (matches the web sidebar's "primary" treatment).
        TabView(selection: $selectedTab) {
            LearnView()
                .tag(1)
                .toolbar(.hidden, for: .tabBar)

            DecksView()
                .tag(3)
                .toolbar(.hidden, for: .tabBar)

            SearchView()
                .tag(0)
                .toolbar(.hidden, for: .tabBar)

            CollectionView()
                .tag(4)
                .toolbar(.hidden, for: .tabBar)

            PurchaseView()
                .tag(5)
                .toolbar(.hidden, for: .tabBar)
        }
        .tint(Design.Colors.bobaOrange)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BOBATabBar(selectedTab: $selectedTab)
        }
    }
}

private struct BOBATabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tag: 1, icon: "book.pages.fill",            label: "Learn")
            tabButton(tag: 3, icon: "rectangle.stack.badge.plus", label: "Decks")
            findButton()
            tabButton(tag: 4, icon: "square.grid.2x2",            label: "Collection")
            tabButton(tag: 5, icon: "cart.fill",                  label: "Purchase")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(
            ZStack {
                Color.black.opacity(0.85)
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func tabButton(tag: Int, icon: String, label: String) -> some View {
        Button {
            if selectedTab != tag {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(label)
                    .font(Design.Fonts.mono(10, weight: .bold))
            }
            .foregroundStyle(selectedTab == tag
                             ? Design.Colors.bobaOrange
                             : Design.Colors.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func findButton() -> some View {
        let active = (selectedTab == 0)
        return Button {
            if !active { selectedTab = 0 }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(active
                              ? Design.Colors.bobaOrange.opacity(0.28)
                              : Design.Colors.bobaOrange.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Circle()
                        .strokeBorder(Design.Colors.bobaOrange.opacity(active ? 0.7 : 0.35),
                                      lineWidth: 1.5)
                        .frame(width: 52, height: 52)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                Text("Find")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .offset(y: -10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
