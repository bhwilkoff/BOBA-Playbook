//
//  ContentView.swift
//  BOBAPlaybook
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }

            PlaceholderView(
                title: "Play",
                icon: "bolt.square.fill",
                message: "Rulebook, strategy tips, and deck builder — coming in M4."
            )
            .tabItem {
                Label("Play", systemImage: "bolt.square.fill")
            }

            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "square.grid.2x2")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
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
