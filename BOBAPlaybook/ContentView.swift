//
//  ContentView.swift
//  BOBAPlaybook
//
//  IA shape (v2.040+): NavigationSplitView with `.prominentDetail`
//  style. Sidebar (leading) lists the five destinations + Profile.
//  Detail (trailing) hosts the selected destination's existing
//  NavigationStack in full-screen.
//
//  Sidebar trigger lives as a leading toolbar item in each
//  destination — its icon is the CURRENT destination's icon
//  (magnifying glass on Find, cart on Purchase, etc.) per user
//  direction. Tap → sidebar slides over the detail with a dim
//  backdrop on iPhone; docks alongside on iPad.
//
//  This replaces the iOS-26 TabView shape we shipped through v2.039.
//  The drag-to-resize Decks drawer that prompted the IA change is
//  expected to migrate to a native `.sheet + .presentationDetents`
//  in a follow-up commit (the tab bar that was hiding it is now gone).
//

import SwiftUI

// =============================================================
// MARK: - Destination model
// =============================================================

enum Destination: String, Hashable, Identifiable, CaseIterable {
    case find, learn, decks, collection, purchase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .find:       return "Find"
        case .learn:      return "Learn"
        case .decks:      return "Decks"
        case .collection: return "Collection"
        case .purchase:   return "Purchase"
        }
    }

    /// SF Symbol used as the sidebar-trigger icon in the destination's
    /// leading toolbar slot AND as the leading icon in the sidebar row.
    var icon: String {
        switch self {
        case .find:       return "magnifyingglass"
        case .learn:      return "book.pages.fill"
        case .decks:      return "rectangle.stack.badge.plus"
        case .collection: return "square.grid.2x2"
        case .purchase:   return "cart.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .find:       return "Search · scan · explore"
        case .learn:      return "Rules · strategy · glossary"
        case .decks:      return "Build · save · share"
        case .collection: return "Personal · sale · trade · grails"
        case .purchase:   return "Breaks · stores · acquire"
        }
    }
}

// =============================================================
// MARK: - Sidebar trigger plumbing
// =============================================================

private struct OpenSidebarKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Action that opens the sidebar from a destination's toolbar.
    /// Set by ContentView; consumed by `BOBASidebarTriggerButton`.
    var openSidebar: () -> Void {
        get { self[OpenSidebarKey.self] }
        set { self[OpenSidebarKey.self] = newValue }
    }
}

struct BOBASidebarTriggerButton: View {
    let destination: Destination
    @Environment(\.openSidebar) private var openSidebar

    var body: some View {
        Button {
            openSidebar()
        } label: {
            Image(systemName: destination.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.Colors.textPrimary)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Open navigation")
        .accessibilityHint("Switch between Find, Learn, Decks, Collection, and Purchase")
    }
}

extension View {
    /// Adds the leading sidebar-trigger toolbar item to the destination's
    /// existing toolbar. Apply inside the destination's NavigationStack
    /// so the item lands in that stack's nav bar.
    func bobaSidebarTrigger(_ destination: Destination) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BOBASidebarTriggerButton(destination: destination)
            }
        }
    }
}

// =============================================================
// MARK: - Sidebar
// =============================================================

private struct BOBASidebar: View {
    @Binding var selectedDestination: Destination
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var profileSheetPresented: Bool

    @Environment(AuthManager.self) private var auth

    var body: some View {
        List {
            Section {
                ForEach(Destination.allCases) { dest in
                    Button {
                        selectedDestination = dest
                        columnVisibility = .detailOnly
                    } label: {
                        DestinationRow(
                            destination: dest,
                            isSelected: dest == selectedDestination
                        )
                    }
                    .listRowBackground(rowBackground(for: dest))
                }
            } header: {
                Text("Destinations")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }

            Section {
                Button {
                    columnVisibility = .detailOnly
                    profileSheetPresented = true
                } label: {
                    ProfileRow(isAuthenticated: auth.isAuthenticated)
                }
                .listRowBackground(Color.clear)
            } header: {
                Text("Account")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
        .navigationTitle("BOBA")
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func rowBackground(for dest: Destination) -> Color {
        dest == selectedDestination
            ? Design.Colors.bobaOrange.opacity(0.15)
            : Color.clear
    }
}

private struct DestinationRow: View {
    let destination: Destination
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: destination.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected
                                 ? Design.Colors.bobaOrange
                                 : Design.Colors.textPrimary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.title)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(destination.subtitle)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct ProfileRow: View {
    let isAuthenticated: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Design.Colors.textPrimary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(isAuthenticated ? "Profile" : "Sign in")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(isAuthenticated ? "Account · settings" : "Save decks, sync collection")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// =============================================================
// MARK: - ContentView
// =============================================================

struct ContentView: View {
    @Binding var selectedDestination: Destination
    @Environment(AuthManager.self) private var auth
    @Environment(ScanStore.self) private var scanStore
    @Environment(ScanCoordinator.self) private var scanCoordinator

    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var profileSheetPresented = false

    var body: some View {
        @Bindable var coord = scanCoordinator

        NavigationSplitView(columnVisibility: $columnVisibility) {
            BOBASidebar(
                selectedDestination: $selectedDestination,
                columnVisibility: $columnVisibility,
                profileSheetPresented: $profileSheetPresented
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            destinationView
                .environment(\.openSidebar) {
                    withAnimation(.snappy(duration: 0.25)) {
                        columnVisibility = .all
                    }
                }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .tint(Design.Colors.bobaOrange)
        .sheet(isPresented: $profileSheetPresented) {
            ProfileView()
        }
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

    @ViewBuilder
    private var destinationView: some View {
        switch selectedDestination {
        case .find:       SearchView()
        case .learn:      LearnView()
        case .decks:      DecksView()
        case .collection: CollectionView()
        case .purchase:   PurchaseView()
        }
    }
}

// =============================================================
// MARK: - Placeholder for unbuilt destinations
// =============================================================

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
