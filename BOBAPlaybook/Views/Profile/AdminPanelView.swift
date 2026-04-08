import SwiftUI

// MARK: - AdminPanelView
// Only visible to users with role == "admin".
// Shows user list with role promotion/demotion and aggregate metrics.

struct AdminPanelView: View {
    @Environment(AuthManager.self) private var auth
    @State private var users: [AdminUserProfile] = []
    @State private var metrics: AdminMetrics? = nil
    @State private var pendingCorrections: [SupabaseClient.PendingCorrection] = []
    @State private var recentCorrections: [SupabaseClient.PendingCorrection] = []
    @State private var missingArt: [SupabaseClient.ImageOverride] = []
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

                // Missing art queue
                Section("MISSING ART (\(missingArt.count))") {
                    if missingArt.isEmpty {
                        Text("No missing art — all images accounted for.")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                    } else {
                        ForEach(missingArt) { override in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(override.cardNumber)
                                        .font(Design.Fonts.mono(13, weight: .bold))
                                        .foregroundStyle(Design.Colors.bobaCyan)
                                    Text(override.action.uppercased())
                                        .font(Design.Fonts.mono(9, weight: .bold))
                                        .foregroundStyle(Design.Colors.textMuted)
                                    Text(override.createdAt, style: .date)
                                        .font(Design.Fonts.mono(10))
                                        .foregroundStyle(Design.Colors.textMuted)
                                }
                                Spacer()
                                HStack(spacing: 12) {
                                    Button("Approve") {
                                        Task { await approveImageOverride(id: override.id) }
                                    }
                                    .font(Design.Fonts.mono(12, weight: .bold))
                                    .foregroundStyle(Color.green)
                                    .buttonStyle(.plain)
                                    Button("Reject") {
                                        Task { await rejectImageOverride(id: override.id) }
                                    }
                                    .font(Design.Fonts.mono(12, weight: .bold))
                                    .foregroundStyle(Design.Colors.bobaOrange)
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, Design.Spacing.xs)
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)

                // Pending corrections
                Section("PENDING CORRECTIONS (\(pendingCorrections.count))") {
                    if pendingCorrections.isEmpty {
                        Text("No pending corrections.")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                    } else {
                        ForEach(pendingCorrections) { correction in
                            CorrectionReviewRow(correction: correction) { approved in
                                Task { await handleCorrection(id: correction.id, approve: approved) }
                            }
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)

                // Recent activity — lets admins confirm their corrections saved
                if !recentCorrections.isEmpty {
                    Section("RECENT ACTIVITY (MY LAST \(recentCorrections.count))") {
                        ForEach(recentCorrections) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(c.cardNumber)
                                        .font(Design.Fonts.mono(12, weight: .bold))
                                        .foregroundStyle(Design.Colors.bobaCyan)
                                    Spacer()
                                    Text(c.status.uppercased())
                                        .font(Design.Fonts.mono(9, weight: .bold))
                                        .foregroundStyle(c.status == "approved" ? Color.green : c.status == "rejected" ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(c.status == "approved" ? Color.green : c.status == "rejected" ? Design.Colors.bobaOrange : Design.Colors.textMuted, lineWidth: 1))
                                }
                                ForEach(c.corrections.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                                    Text("\(key): \(val)")
                                        .font(Design.Fonts.mono(11))
                                        .foregroundStyle(Design.Colors.textSecondary)
                                }
                                Text(c.createdAt, style: .relative)
                                    .font(Design.Fonts.mono(10))
                                    .foregroundStyle(Design.Colors.textMuted)
                            }
                            .padding(.vertical, Design.Spacing.xs)
                        }
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
            async let usersResult       = SupabaseClient.shared.fetchAllUserProfiles()
            async let metricsResult     = SupabaseClient.shared.fetchAdminMetrics()
            async let correctionsResult = SupabaseClient.shared.fetchPendingCorrections()
            async let recentResult      = SupabaseClient.shared.fetchRecentCorrections()
            async let missingArtResult  = SupabaseClient.shared.fetchPendingImageOverrides()
            users               = try await usersResult
            metrics             = try await metricsResult
            pendingCorrections  = try await correctionsResult
            recentCorrections   = try await recentResult
            missingArt          = try await missingArtResult
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func updateRole(user: AdminUserProfile, newRole: String) async {
        do {
            try await SupabaseClient.shared.updateUserRole(userId: user.userId, role: newRole)
            await loadData()
        } catch {
            errorMessage = "Role update failed: \(error.localizedDescription)"
        }
    }

    private func approveImageOverride(id: Int) async {
        do {
            try await SupabaseClient.shared.approveImageOverride(id: id)
            missingArt.removeAll { $0.id == id }
        } catch {
            errorMessage = "Failed to approve: \(error.localizedDescription)"
        }
    }

    private func rejectImageOverride(id: Int) async {
        do {
            try await SupabaseClient.shared.rejectImageOverride(id: id)
            missingArt.removeAll { $0.id == id }
        } catch {
            errorMessage = "Failed to reject: \(error.localizedDescription)"
        }
    }

    private func handleCorrection(id: Int, approve: Bool) async {
        do {
            if approve {
                try await SupabaseClient.shared.approveCorrection(id: id)
            } else {
                try await SupabaseClient.shared.rejectCorrection(id: id)
            }
            pendingCorrections.removeAll { $0.id == id }
            recentCorrections = (try? await SupabaseClient.shared.fetchRecentCorrections()) ?? recentCorrections
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
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

// MARK: - CorrectionReviewRow

private struct CorrectionReviewRow: View {
    let correction: SupabaseClient.PendingCorrection
    let onDecision: (Bool) -> Void  // true = approve, false = reject

    @State private var isActing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                Text(correction.cardNumber)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Spacer()
                Text(correction.createdAt, style: .date)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
            }

            // Changed fields
            ForEach(correction.corrections.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                HStack(spacing: 4) {
                    Text(key + ":")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                    Text(val)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
            }

            if let note = correction.notes, !note.isEmpty {
                Text("\"\(note)\"")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .italic()
            }

            HStack(spacing: Design.Spacing.sm) {
                Spacer()
                Button {
                    isActing = true
                    onDecision(false)
                } label: {
                    Text("Reject")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Design.Colors.bobaOrange, lineWidth: 1))
                }
                .disabled(isActing)
                .buttonStyle(.plain)

                Button {
                    isActing = true
                    onDecision(true)
                } label: {
                    Text("Approve")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Color(hex: "4ade80"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "4ade80"), lineWidth: 1))
                }
                .disabled(isActing)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Design.Spacing.xs)
    }
}
