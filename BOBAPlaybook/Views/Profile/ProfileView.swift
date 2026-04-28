import SwiftUI

// MARK: - ProfileView
// Auth state, account info, and sign out.

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingSignIn = false
    @State private var showingSignOutConfirm = false
    @State private var isRecalculating = false
    @State private var recalculateProgress: (current: Int, total: Int)? = nil
    @State private var showingModRequestSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAuthenticated {
                    signedInView
                } else {
                    signedOutView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
                // Presented as a sheet from the Find tab since the nav
                // refactor — surface a Done button so coaches can close it.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showingModRequestSheet) {
            ModRequestSheet()
        }
        .overlay(alignment: .top) {
            if auth.confirmationEmailSent {
                confirmationBanner
            }
        }
    }

    private var confirmationBanner: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "envelope.badge.fill")
                .foregroundStyle(Design.Colors.bobaCyan)
            Text("Check your email to confirm your account.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.surface.opacity(0.97))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Design.Colors.bobaCyan.opacity(0.4)), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Signed out

    private var signedOutView: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()
            Image(systemName: "person.circle")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Not signed in")
                .font(Design.Fonts.display(20))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Sign in to sync your collection\nand access it on any device.")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
            Button {
                showingSignIn = true
            } label: {
                Text("Sign In / Create Account")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .frame(maxWidth: 280)
                    .frame(height: 50)
                    .background(Design.Colors.bobaOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Signed in

    private var signedInView: some View {
        List {
            // Account section
            Section {
                HStack(spacing: Design.Spacing.md) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Design.Colors.bobaOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.email ?? "BOBA Player")
                            .font(Design.Fonts.display(16))
                            .foregroundStyle(Design.Colors.textPrimary)
                        HStack(spacing: Design.Spacing.xs) {
                            Text(auth.isMod ? (auth.isAdmin ? "Admin" : "Moderator") : "Member")
                                .font(Design.Fonts.mono(12))
                                .foregroundStyle(Design.Colors.textMuted)
                            if auth.isMod {
                                Text(auth.isAdmin ? "ADMIN" : "MOD")
                                    .font(Design.Fonts.mono(9, weight: .bold))
                                    .foregroundStyle(Design.Colors.nearBlack)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(auth.isAdmin ? Design.Colors.bobaOrange : Design.Colors.bobaCyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            // Admin-only practice access. The historical
                            // bottom-nav Play tab was removed pending an
                            // IP review with BoBA; this icon keeps the
                            // surface available for testing without
                            // exposing it to other roles.
                            if auth.isAdmin {
                                NavigationLink(destination: PlayView()) {
                                    Image(systemName: "bolt.square.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Design.Colors.bobaOrange)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Practice (admin only)")
                            }
                        }
                    }
                }
                .padding(.vertical, Design.Spacing.xs)
            }
            .listRowBackground(Design.Colors.surface)

            // Collection stats
            Section("COLLECTION") {
                statRow(
                    icon: "person.fill",
                    label: "Personal",
                    value: "\(collection.uniqueBobaIds(for: .personal).count)"
                )
                statRow(
                    icon: "tag.fill",
                    label: "For Sale",
                    value: "\(collection.uniqueBobaIds(for: .for_sale).count)"
                )
                statRow(
                    icon: "arrow.left.arrow.right",
                    label: "For Trade",
                    value: "\(collection.uniqueBobaIds(for: .for_trade).count)"
                )
                statRow(
                    icon: "star.fill",
                    label: "Wanted",
                    value: "\(collection.uniqueBobaIds(for: .wanted).count)"
                )
                statRow(
                    icon: "crown.fill",
                    label: "Grails",
                    value: "\(collection.uniqueBobaIds(for: .grails).count)"
                )
                statRow(
                    icon: "dollarsign.circle",
                    label: "Total Paid",
                    value: formatCurrency(collection.totalPurchaseValue)
                )
                // Estimated market value row
                HStack {
                    Label("Est. Market Value", systemImage: "chart.line.uptrend.xyaxis")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Spacer()
                    if collection.totalEstimatedValue > 0 {
                        Text(formatCurrency(collection.totalEstimatedValue))
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    } else {
                        Text("—")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
            }
            .listRowBackground(Design.Colors.surface)

            // Collection value recalculate
            Section {
                if isRecalculating, let progress = recalculateProgress {
                    HStack(spacing: Design.Spacing.sm) {
                        ProgressView()
                            .tint(Design.Colors.bobaOrange)
                            .scaleEffect(0.85)
                        Text("Updating \(progress.current) of \(progress.total) cards…")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                } else {
                    Button {
                        isRecalculating = true
                        recalculateProgress = (0, 0)
                        Task {
                            await collection.recalculateAllValues(cardStore: cardStore) { current, total in
                                recalculateProgress = (current, total)
                            }
                            isRecalculating = false
                            recalculateProgress = nil
                        }
                    } label: {
                        Label("Recalculate Collection Value", systemImage: "arrow.clockwise")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                    .disabled(isRecalculating)
                }
            }
            .listRowBackground(Design.Colors.surface)

            // Settings
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
            }
            .listRowBackground(Design.Colors.surface)

            // Mod access request — shown to non-mods only
            if !auth.isMod {
                Section("MODERATOR ACCESS") {
                    if auth.hasPendingModRequest {
                        HStack(spacing: Design.Spacing.sm) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(Design.Colors.bobaCyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Request pending")
                                    .font(Design.Fonts.mono(14, weight: .bold))
                                    .foregroundStyle(Design.Colors.textPrimary)
                                Text("An admin will review your request soon.")
                                    .font(Design.Fonts.mono(11))
                                    .foregroundStyle(Design.Colors.textMuted)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                            Text("Become a moderator to help improve the catalog: upload images of cards from your own collection, fix wrong card data, and flag issues with existing images.")
                                .font(Design.Fonts.mono(12))
                                .foregroundStyle(Design.Colors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                            Button {
                                showingModRequestSheet = true
                            } label: {
                                Label("Request Mod Access", systemImage: "shield.lefthalf.filled.badge.checkmark")
                                    .font(Design.Fonts.mono(14, weight: .bold))
                                    .foregroundStyle(Design.Colors.bobaCyan)
                            }
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)
            }

            // Mod tools
            if auth.isMod {
                Section("MODERATION") {
                    NavigationLink {
                        ModPanelView()
                    } label: {
                        Label("Mod Panel", systemImage: "shield.lefthalf.filled")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    if auth.isAdmin {
                        NavigationLink {
                            AdminPanelView()
                        } label: {
                            Label("Admin Panel", systemImage: "person.badge.key.fill")
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)
            }

            // Sign out — .confirmationDialog is on the Section (not the Button) to anchor
            // the iPad popover to this row without the dialog re-triggering the button tap.
            Section {
                Button {
                    showingSignOutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                            .font(Design.Fonts.mono(15))
                    }
                    .foregroundStyle(.red)
                }
            }
            .listRowBackground(Design.Colors.surface)
            .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your collection data is saved in the cloud and will sync back when you sign in again.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Design.Fonts.mono(14, weight: .bold))
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        guard value > 0 else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
