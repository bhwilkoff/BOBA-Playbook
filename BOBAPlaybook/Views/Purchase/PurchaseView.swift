//
//  PurchaseView.swift
//  BOBAPlaybook
//
//  Two sections:
//    1. Upcoming Breaks — Whatnot upcoming-shows feed for "Bo Jackson
//       Battle Arena", served by the boba-whatnot-shows Worker. Each
//       show renders as a large card (image + host + scheduled time +
//       title + viewer count) and taps through to whatnot.com.
//    2. Find a Store — moved here from inside Collection. Embeds the
//       existing StoreLocatorView.
//

import SwiftUI

struct PurchaseView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                    upcomingBreaksSection
                    findStoreSection
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Purchase")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var upcomingBreaksSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            sectionHeader(title: "UPCOMING BREAKS",
                          subtitle: "Live community streams featuring Bo Jackson Battle Arena")
            UpcomingBreaksList()
        }
    }

    private var findStoreSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            sectionHeader(title: "FIND A STORE",
                          subtitle: "Local card shops carrying BoBA")
            NavigationLink {
                StoreLocatorView()
            } label: {
                HStack(spacing: Design.Spacing.md) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Design.Colors.bobaOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open the store map")
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("Independent retailers + big-box (filterable)")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .padding(Design.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.surface)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .tracking(2)
            Text(subtitle)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }
}
