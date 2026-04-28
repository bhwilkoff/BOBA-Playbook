import SwiftUI

// MARK: - WatchView
//
// Renders the three YouTube feeds the `boba-youtube-feed` Worker
// hands us, organized around a creator's two real distribution
// orientations (landscape for desktop / portrait for phone) plus a
// dedicated upcoming-live tab so coaches can find the next show:
//
//   - Upcoming Live → currently-live + scheduled streams + recent
//     replays (within 7 days). Sorted chronologically by the
//     ACTUAL stream time (actualStartTime || scheduledStartTime),
//     not the publishedAt timestamp YouTube stamps when the event
//     placeholder was first created. Big 16:9 cards.
//   - Vertical → previously-recorded vertical content. Catches both
//     YouTube Shorts AND longer phone-edition cuts (e.g. Radish's
//     daily show 📱 variant). 9:16 grid.
//   - Horizontal → previously-recorded landscape content. 16:9 grid.
//
// Tapping any tile presents a sheet hosting `YouTubePlayerView` so
// playback stays in-app via the YouTube IFrame Player API.

enum WatchTab: String, CaseIterable, Identifiable {
    case upcoming   = "Upcoming Live"
    case vertical   = "Vertical"
    case horizontal = "Horizontal"
    var id: String { rawValue }
}

struct WatchView: View {
    @State private var feed = YouTubeFeedService()
    @State private var tab: WatchTab = .upcoming
    @State private var playing: YouTubeVideo? = nil

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.sm)
                .padding(.bottom, Design.Spacing.xs)

            Group {
                if feed.isLoading && currentItems.isEmpty {
                    loadingView
                } else if let error = feed.loadError, currentItems.isEmpty {
                    errorView(error)
                } else if currentItems.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }
        }
        .task {
            if feed.upcoming.isEmpty && feed.vertical.isEmpty && feed.horizontal.isEmpty {
                await feed.loadAll()
            }
        }
        .sheet(item: $playing) { video in
            VideoPlayerSheet(video: video)
        }
    }

    private var currentItems: [YouTubeVideo] {
        switch tab {
        case .upcoming:   return feed.upcoming
        case .vertical:   return feed.vertical
        case .horizontal: return feed.horizontal
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(WatchTab.allCases) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                } label: {
                    HStack(spacing: 6) {
                        Text(t.rawValue)
                            .font(Design.Fonts.mono(13, weight: tab == t ? .bold : .regular))
                        Text("\(count(for: t))")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(tab == t ? Design.Colors.nearBlack.opacity(0.7) : Design.Colors.textMuted)
                    }
                    .foregroundStyle(tab == t ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                    .padding(.horizontal, Design.Spacing.md)
                    .frame(height: 32)
                    .background(Capsule().fill(tab == t ? Design.Colors.bobaCyan : Design.Colors.glass))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func count(for t: WatchTab) -> Int {
        switch t {
        case .upcoming:   return feed.upcoming.count
        case .vertical:   return feed.vertical.count
        case .horizontal: return feed.horizontal.count
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch tab {
        case .upcoming:   upcomingList
        case .vertical:   verticalGrid
        case .horizontal: horizontalGrid
        }
    }

    /// Upcoming/live feed — single-column, larger 16:9 cards.
    /// LIVE NOW broadcasts and the next-soonest scheduled streams
    /// surface at the top; recent replays follow.
    private var upcomingList: some View {
        ScrollView {
            LazyVStack(spacing: Design.Spacing.md) {
                ForEach(currentItems) { video in
                    UpcomingCard(video: video)
                        .onTapGesture { playing = video }
                }
            }
            .padding(Design.Spacing.lg)
        }
        .refreshable { await feed.loadAll() }
    }

    /// Vertical-recorded — 9:16 grid. Catches both Shorts and
    /// phone-edition cuts of longer shows.
    private var verticalGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: Design.Spacing.sm)],
                spacing: Design.Spacing.md
            ) {
                ForEach(currentItems) { video in
                    VerticalCard(video: video)
                        .onTapGesture { playing = video }
                }
            }
            .padding(Design.Spacing.lg)
        }
        .refreshable { await feed.loadAll() }
    }

    /// Horizontal-recorded — 16:9 grid, two columns on phones.
    private var horizontalGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 400), spacing: Design.Spacing.md)],
                spacing: Design.Spacing.md
            ) {
                ForEach(currentItems) { video in
                    HorizontalCard(video: video)
                        .onTapGesture { playing = video }
                }
            }
            .padding(Design.Spacing.lg)
        }
        .refreshable { await feed.loadAll() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: Design.Spacing.md) {
            ProgressView().tint(Design.Colors.bobaOrange).scaleEffect(1.2)
            Text("Loading videos…")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32)).foregroundStyle(Design.Colors.bobaOrange)
            Text("Couldn't load videos")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(message)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xl)
            Button("Try Again") { Task { await feed.loadAll() } }
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: tab == .upcoming ? "dot.radiowaves.left.and.right" :
                              tab == .vertical ? "rectangle.portrait" : "play.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(Design.Colors.textMuted)
            Text(tab == .upcoming   ? "No upcoming or live shows right now" :
                 tab == .vertical   ? "No vertical videos yet" :
                                      "No horizontal videos yet")
                .font(Design.Fonts.display(15))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Refreshes every 4 hours. Pull down to refresh now.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Card variants
// ════════════════════════════════════════════════════════════════

private struct UpcomingCard: View {
    let video: YouTubeVideo

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(url: video.thumbnail, aspect: 16.0/9.0)

                if video.isLiveNow {
                    Text("LIVE NOW")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "C0392B")))
                        .padding(8)
                } else if video.isUpcoming {
                    Text("UPCOMING")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.85)))
                        .padding(8)
                } else {
                    Text("REPLAY")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
                if let dur = video.durationLabel {
                    durationBadge(dur).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                // Stream-time line — surfaced ABOVE the channel/views
                // subtitle for upcoming and live cards. Uses
                // streamTime (actual || scheduled), not publishedAt.
                if let when = video.streamTimeLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(video.isLiveNow ? Color(hex: "C0392B") : Design.Colors.bobaCyan)
                        Text(when)
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(video.isLiveNow ? Color(hex: "C0392B") : Design.Colors.bobaCyan)
                    }
                }
                CardSubtitle(video: video)
            }
        }
    }
}

private struct VerticalCard: View {
    let video: YouTubeVideo

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(url: video.thumbnail, aspect: 9.0/16.0)
                if let dur = video.durationLabel {
                    durationBadge(dur).padding(6)
                }
            }
            Text(video.title)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(2)
            CardSubtitle(video: video, compact: true)
        }
    }
}

private struct HorizontalCard: View {
    let video: YouTubeVideo

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(url: video.thumbnail, aspect: 16.0/9.0)
                if let dur = video.durationLabel {
                    durationBadge(dur).padding(6)
                }
            }
            Text(video.title)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(2)
            CardSubtitle(video: video)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Shared card pieces
// ════════════════════════════════════════════════════════════════

private struct ThumbnailView: View {
    let url: String?
    let aspect: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface2)
            if let urlString = url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CardSubtitle: View {
    let video: YouTubeVideo
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if video.priority == 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Design.Colors.bobaCyan)
            }
            if let ch = video.channelTitle, !ch.isEmpty {
                Text(ch)
                    .font(Design.Fonts.mono(compact ? 9 : 10, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .lineLimit(1)
            }
            if let pub = video.publishedRelative {
                Text("·")
                    .font(Design.Fonts.mono(compact ? 9 : 10))
                    .foregroundStyle(Design.Colors.textMuted)
                Text(pub)
                    .font(Design.Fonts.mono(compact ? 9 : 10))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            if let v = video.viewCount, v > 0 {
                Text("·")
                    .font(Design.Fonts.mono(compact ? 9 : 10))
                    .foregroundStyle(Design.Colors.textMuted)
                Text("\(formatViews(v)) views")
                    .font(Design.Fonts.mono(compact ? 9 : 10))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
    }

    private func formatViews(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private func durationBadge(_ text: String) -> some View {
    Text(text)
        .font(Design.Fonts.mono(10, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.7)))
}

// ════════════════════════════════════════════════════════════════
// MARK: - Player sheet
// ════════════════════════════════════════════════════════════════

private struct VideoPlayerSheet: View {
    let video: YouTubeVideo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                YouTubePlayerView(videoId: video.videoId, autoplay: true)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .background(Color.black)

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.md) {
                        Text(video.title)
                            .font(Design.Fonts.display(18))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        CardSubtitle(video: video)
                        if let desc = video.description, !desc.isEmpty {
                            Divider().background(Design.Colors.glassBorder)
                            Text(desc)
                                .font(Design.Fonts.mono(13))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Design.Spacing.lg)
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
