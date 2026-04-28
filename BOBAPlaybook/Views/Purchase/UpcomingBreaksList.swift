//
//  UpcomingBreaksList.swift
//  BOBAPlaybook
//
//  Renders the Whatnot live + upcoming feed as a 2-column grid of
//  card-shape (5:7 portrait) tiles. Each tile links out to
//  whatnot.com/live/{id}. Live shows display a pulsing red LIVE
//  pill in the top-left of the thumbnail.
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
        .task { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    private func showCard(_ show: WhatnotShow) -> some View {
        Link(destination: URL(string: show.showUrl) ?? URL(string: "https://whatnot.com")!) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail(show)
                cardFooter(show)
            }
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(_ show: WhatnotShow) -> some View {
        // 5:7 portrait container; image fills via overlay so it can
        // never overflow the cell. Using `.aspectRatio(.fill)` directly
        // on AsyncImage caused the intrinsic image dimensions (~414×640)
        // to dictate the layout and the cards overlapped each other.
        Color.clear
            .aspectRatio(5.0/7.0, contentMode: .fit)
            .overlay(
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
            )
            .clipped()
            .overlay(alignment: .topLeading) {
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
    }

    @ViewBuilder
    private func cardFooter(_ show: WhatnotShow) -> some View {
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

    private var placeholder: some View {
        LazyVGrid(columns: gridColumns, spacing: Design.Spacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
                Color.clear
                    .aspectRatio(5.0/7.0, contentMode: .fit)
                    .overlay(ProgressView().tint(Design.Colors.bobaOrange))
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.md)
                            .fill(Design.Colors.surface)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
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
