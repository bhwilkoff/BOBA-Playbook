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

    private let gridColumns = [
        GridItem(.flexible(), spacing: Design.Spacing.sm),
        GridItem(.flexible(), spacing: Design.Spacing.sm),
    ]

    var body: some View {
        Group {
            if isLoading && shows.isEmpty {
                placeholder
            } else if let loadError, shows.isEmpty {
                errorState(loadError)
            } else if shows.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: gridColumns, spacing: Design.Spacing.sm) {
                    ForEach(shows) { show in
                        showCard(show)
                    }
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
                // Card-shape thumbnail (5:7 portrait — matches Whatnot's
                // trading-card-shaped images so we don't aggressively
                // crop the show art).
                ZStack(alignment: .topLeading) {
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
                    .aspectRatio(5.0/7.0, contentMode: .fill)
                    .clipped()

                    // LIVE pill — pulsing red badge for currently-streaming shows.
                    if show.isLiveShow {
                        HStack(spacing: 4) {
                            Circle().fill(.white).frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(Design.Fonts.mono(9, weight: .bold))
                                .foregroundStyle(.white)
                                .tracking(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "C0392B")))
                        .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("@\(show.host)")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !show.isLiveShow, !show.scheduledTimeText.isEmpty {
                            Text(show.scheduledTimeText)
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
                    Text(show.title)
                        .font(Design.Fonts.display(13))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        if !show.categoryName.isEmpty {
                            Text(show.categoryName.uppercased())
                                .font(Design.Fonts.mono(8, weight: .bold))
                                .foregroundStyle(Design.Colors.textMuted)
                                .tracking(1)
                        }
                        if show.viewerCount > 0 {
                            Text("\(show.viewerCount) \(show.isLiveShow ? "watching" : "interested")")
                                .font(Design.Fonts.mono(8))
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(Design.Spacing.sm)
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
