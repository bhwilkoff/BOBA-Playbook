//
//  ModRequestSheet.swift
//  BOBAPlaybook
//
//  Form presented from ProfileView for users to request moderator access.
//  Lists what mod access unlocks and collects a short reason. Submitting
//  writes mod_request_reason + mod_request_at to the user's own profile.
//

import SwiftUI

struct ModRequestSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String = ""
    @State private var isSubmitting = false

    private let minReasonLength = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    header
                    featureList
                    reasonField
                    submitButton
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Request Mod Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 32))
                .foregroundStyle(Design.Colors.bobaCyan)
            Text("Help improve the catalog")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Moderator access lets trusted collectors contribute directly to BOBA Playbook's card data and images.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("WHAT YOU CAN DO AS A MOD")
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
            featureRow(icon: "camera.fill", title: "Upload card images", detail: "Submit photos of cards from your own collection, especially for the ~1,500 cards still missing art.")
            featureRow(icon: "pencil.and.list.clipboard", title: "Fix wrong card data", detail: "Correct hero names, power values, abilities, or any field that's printed wrong in the app.")
            featureRow(icon: "flag.fill", title: "Flag image issues", detail: "Request removal or replacement of card images that show the wrong art.")
            featureRow(icon: "checkmark.seal.fill", title: "Review before shipping", detail: "All changes go through admin review before they hit the catalog — no risk of accidental damage.")
        }
        .padding(Design.Spacing.md)
        .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.surface))
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.bobaOrange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(detail)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("TELL ME A BIT ABOUT YOURSELF")
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
            Text("How long have you collected BOBA? Do you focus on specific athletes, sets, or treatments? What's motivating you to help?")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $reason)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Design.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 120)
            HStack {
                Spacer()
                Text("\(reason.count)/\(minReasonLength) minimum")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(reason.count >= minReasonLength ? Design.Colors.bobaCyan : Design.Colors.textMuted)
            }
        }
    }

    private var canSubmit: Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= minReasonLength && !isSubmitting
    }

    private var submitButton: some View {
        Button {
            Task {
                isSubmitting = true
                await auth.requestRole("moderator", reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
                isSubmitting = false
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView().tint(Design.Colors.nearBlack).scaleEffect(0.8) }
                Text(isSubmitting ? "SUBMITTING…" : "SUBMIT REQUEST")
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(Design.Colors.nearBlack)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 10).fill(canSubmit ? Design.Colors.bobaOrange : Design.Colors.textMuted))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }
}
