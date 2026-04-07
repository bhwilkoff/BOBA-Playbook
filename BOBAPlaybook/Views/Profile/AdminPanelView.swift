import SwiftUI

// MARK: - AdminPanelView
// Only visible to users with role == "admin".
// Shows user list with role promotion/demotion and aggregate metrics.

struct AdminPanelView: View {
    @Environment(AuthManager.self) private var auth
    @State private var users: [AdminUserProfile] = []
    @State private var metrics: AdminMetrics? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var roleUpdateTarget: AdminUserProfile? = nil
    @State private var showRolePicker = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView().tint(Design.Colors.bobaOrange)
                        Spacer()
                    }
                }
                .listRowBackground(Design.Colors.surface)
            } else {
                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Design.Colors.surface)
                }

                // Metrics
                if let m = metrics {
                    Section("METRICS") {
                        metricRow(icon: "person.3.fill",        label: "Total Users",              value: "\(m.totalUsers)",         color: Design.Colors.bobaCyan)
                        metricRow(icon: "pencil.circle.fill",   label: "Card Corrections",         value: "\(m.pendingCorrections)",  color: Design.Colors.bobaOrange)
                        metricRow(icon: "photo.badge.plus.fill",label: "Image Overrides",          value: "\(m.pendingImageOverrides)", color: Color(hex: "8B00FF"))
                    }
                    .listRowBackground(Design.Colors.surface)
                }

                // User list
                Section("USERS (\(users.count))") {
                    ForEach(users) { user in
                        UserRoleRow(
                            user: user,
                            isCurrentUser: user.userId == auth.userId,
                            onRoleChange: { newRole in
                                Task { await updateRole(user: user, newRole: newRole) }
                            }
                        )
                    }
                }
                .listRowBackground(Design.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
        .navigationTitle("Admin Panel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let usersResult  = SupabaseClient.shared.fetchAllUserProfiles()
            async let metricsResult = SupabaseClient.shared.fetchAdminMetrics()
            users   = try await usersResult
            metrics = try await metricsResult
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func updateRole(user: AdminUserProfile, newRole: String) async {
        do {
            try await SupabaseClient.shared.updateUserRole(userId: user.userId, role: newRole)
            // Refresh list after update
            await loadData()
        } catch {
            errorMessage = "Role update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Row builders

    private func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Design.Fonts.mono(16, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - UserRoleRow

private struct UserRoleRow: View {
    let user: AdminUserProfile
    let isCurrentUser: Bool
    let onRoleChange: (String) -> Void

    @State private var showPicker = false

    private let allRoles = ["user", "moderator", "admin"]

    private func badgeColor(_ role: String) -> Color {
        switch role {
        case "admin":     return Design.Colors.bobaOrange
        case "moderator": return Design.Colors.bobaCyan
        default:          return Design.Colors.textMuted
        }
    }

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(user.email ?? "Unknown")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(isCurrentUser ? Design.Colors.bobaOrange : Design.Colors.textPrimary)
                    .lineLimit(1)
                Text(user.userId.uuidString.prefix(12) + "…")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                Text(user.createdAt, style: .date)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            Spacer()

            if isCurrentUser {
                // Can't demote yourself
                roleBadge(user.role)
            } else {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 4) {
                        roleBadge(user.role)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .confirmationDialog("Change role for \(user.email ?? "this user")",
                                    isPresented: $showPicker, titleVisibility: .visible) {
                    ForEach(allRoles.filter { $0 != user.role }, id: \.self) { role in
                        Button(role.capitalized) { onRoleChange(role) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    private func roleBadge(_ role: String) -> some View {
        Text(role.uppercased())
            .font(Design.Fonts.mono(9, weight: .bold))
            .foregroundStyle(Design.Colors.nearBlack)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor(role))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
