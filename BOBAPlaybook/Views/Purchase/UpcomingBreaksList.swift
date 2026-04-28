//
//  UpcomingBreaksList.swift
//  BOBAPlaybook
//
//  Renders the Whatnot upcoming-shows feed as a vertical stack of
//  large card tiles (image + host + scheduled time + title +
//  viewer count). Tap → open whatnot.com/live/{id} in the system
//  browser.
//

import SwiftUI

struct UpcomingBreaksList: View {
    @State private var shows: [WhatnotShow] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            if isLoading && shows.isEmpty {
                placeholder
            } else if let loadError, shows.isEmpty {
                errorState(loadError)
            } else if shows.isEmpty {
                emptyState
            } else {
                ForEach(shows) { show in
                    showCard(show)
                }
            }
        }
        .task {
            await load(force: false)
        }
        .refreshable {
            await load(force: true)
        }
    }

    private func showCard(_ show: WhatnotShow) -> some View {
        Link(destination: URL(string: show.showUrl) ?? URL(string: "https://whatnot.com")!) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                AsyncImage(url: URL(string: show.thumbnailUrl)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Design.Colors.surface)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(Design.Colors.surface)
                            .overlay(Image(systemName: "tv")
                                .font(.system(size: 36))
                                .foregroundStyle(Design.Colors.textMuted))
                    @unknown default:
                        Rectangle().fill(Design.Colors.surface)
                    }
                }
                .frame(height: 180)
                .clipped()

                // Footer
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Design.Colors.bobaCyan)
                        Text(show.host)
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !show.scheduledTimeText.isEmpty {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Design.Colors.bobaOrange)
                            Text(show.scheduledTimeText)
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }

                    Text(show.title)
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        if !show.categoryName.isEmpty {
                            Text(show.categoryName.uppercased())
                                .font(Design.Fonts.mono(9, weight: .bold))
                                .foregroundStyle(Design.Colors.textMuted)
                                .tracking(1)
                        }
                        if show.viewerCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 9))
                                Text("\(show.viewerCount) interested")
                                    .font(Design.Fonts.mono(10))
                            }
                            .foregroundStyle(Design.Colors.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(Design.Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var placeholder: some View {
        VStack(spacing: Design.Spacing.md) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.surface)
                    .frame(height: 240)
                    .overlay(ProgressView().tint(Design.Colors.bobaOrange))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: "tv.slash")
                .font(.system(size: 32))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No upcoming shows right now")
                .font(Design.Fonts.display(14))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Pull to refresh, or check back soon")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Design.Spacing.xl)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "C0392B"))
            Text("Couldn't load shows")
                .font(Design.Fonts.display(14))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(msg)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Design.Spacing.lg)
    }

    private func load(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            shows = try await WhatnotShowsService.shared.upcomingShows(force: force)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
