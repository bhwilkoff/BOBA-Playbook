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
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

    /// Vertical-recorded — 2-column 9:16 grid with the thumbnail on
    /// top of each card and the info block underneath. Confirmed-
    /// working approach: compute the column width ONCE at the grid
    /// level via GeometryReader, then pass it as an explicit Int
    /// down to the card so AsyncImage's load state has no chance
    /// to leak intrinsic-size signals into the grid math. (Same
    /// principle that made the single-column rev work — fixed
    /// pixel widths, not flex-column inference.)
    private var verticalGrid: some View {
        GeometryReader { proxy in
            let outerPad: CGFloat = Design.Spacing.lg
            let gap: CGFloat      = Design.Spacing.md
            let columnWidth = max(120, (proxy.size.width - outerPad * 2 - gap) / 2)
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(columnWidth), spacing: gap, alignment: .top),
                        GridItem(.fixed(columnWidth), spacing: gap, alignment: .top),
                    ],
                    alignment: .leading,
                    spacing: Design.Spacing.lg
                ) {
                    ForEach(currentItems) { video in
                        VerticalCard(video: video, width: columnWidth)
                            .onTapGesture { playing = video }
                    }
                }
                .padding(outerPad)
            }
            .refreshable { await feed.loadAll() }
        }
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

                // Upcoming feed only carries live + scheduled streams
                // (replays now route to Vertical/Horizontal). LIVE NOW
                // is red, UPCOMING is cyan to differentiate at a glance.
                if video.isLiveNow {
                    Text("LIVE NOW")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "C0392B")))
                        .padding(8)
                } else {
                    Text("UPCOMING")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.85)))
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
    /// Explicit pixel width handed down from the grid. Pinning this
    /// instead of relying on LazyVGrid to size flexibly was what
    /// made the single-column rev work — same principle here.
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            // Thumbnail on top — 9:16, fixed pixel size from grid.
            // Tries the original-aspect-ratio URL first (vertical
            // for true Shorts / phone-edition uploads); falls back
            // to the worker-supplied thumb if that 404s.
            VerticalThumbnail(video: video)
                .frame(width: width, height: width * 16 / 9)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if let dur = video.durationLabel {
                        durationBadge(dur).padding(6)
                    }
                }

            // Info block UNDERNEATH the thumbnail.
            Text(video.title)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            CardSubtitle(video: video, compact: true)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Thumbnail used in the vertical feed. Originally tried to fetch
/// YouTube's `oardefault.jpg` (the original-aspect-ratio variant)
/// to get a true portrait first-frame for vertical content — but
/// that URL only reliably exists for genuine Shorts. Most of the
/// videos in our vertical bucket are regular 16:9 uploads tagged
/// with the 📱 emoji (Radish's phone-edition daily show), so
/// YouTube serves a generic gray placeholder for the OAR variant
/// instead of returning 404, and AsyncImage's .failure phase
/// never fires.
///
/// Pragmatic resolution: just use the worker-supplied thumbnail
/// (always populated, always real) and let `.scaledToFill` center-
/// crop it into the 9:16 frame. The cropped slice shows the
/// vertical center of the 16:9 art — for Radish's daily show
/// that's the player figure, which reads cleanly.
private struct VerticalThumbnail: View {
    let video: YouTubeVideo

    var body: some View {
        ZStack {
            Color.black
            if let urlString = video.thumbnail,
               let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .clipped()
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Design.Colors.textMuted)
            }
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

/// Aspect-ratio-agnostic thumbnail. Fills whatever frame its parent
/// gives it; the parent (a card) is responsible for the aspect
/// ratio via its own `.aspectRatio` modifier. AsyncImage is
/// `.clipped()` so its pre-load placeholder intrinsic size can't
/// leak up to the parent and break LazyVGrid's column sizing.
private struct ThumbnailImage: View {
    let url: String?

    var body: some View {
        ZStack {
            Color.black
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .clipped()
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
    }
}

/// Backwards-compatible shim — the existing UpcomingCard /
/// HorizontalCard call sites still construct ThumbnailView with an
/// explicit aspect. They get the same flexible body but the
/// aspect modifier is reapplied here for those sites; vertical
/// cards now route through ThumbnailImage directly so they don't
/// double-apply aspect.
private struct ThumbnailView: View {
    let url: String?
    let aspect: CGFloat

    var body: some View {
        ThumbnailImage(url: url)
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

/// Wrap every URL in a description with an AttributedString `.link`
/// attribute so SwiftUI's Text renders it as a tappable link. Uses
/// NSDataDetector for URL identification — covers http/https/etc.,
/// trailing punctuation, and unicode without us reinventing the
/// regex. `.tint` on the Text view colors the links, and the system
/// handles tap → SFSafariViewController routing.
private func linkify(_ source: String) -> AttributedString {
    var attributed = AttributedString(source)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return attributed
    }
    let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
    detector.enumerateMatches(in: source, options: [], range: nsRange) { match, _, _ in
        guard let match = match, let url = match.url,
              let range = Range(match.range, in: source),
              let attrRange = Range(range, in: attributed)
        else { return }
        attributed[attrRange].link = url
        attributed[attrRange].underlineStyle = .single
    }
    return attributed
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
                            // Linkified description — every URL in
                            // the string becomes a tappable link.
                            // SwiftUI's Text renders an
                            // AttributedString natively when the
                            // attribute set includes `.link`.
                            Text(linkify(desc))
                                .font(Design.Fonts.mono(13))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .tint(Design.Colors.bobaCyan)
                                .textSelection(.enabled)
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
                ToolbarItem(placement: .topBarTrailing) {
                    OpenInYouTubeButton(videoId: video.videoId)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Open-in-YouTube fallback
//
// The IFrame embed works for ~95% of videos, but a small fraction
// (creator-disabled, age-gated, region-locked, music rights) error
// out with code 152/153 and surface YouTube's "Watch video on
// YouTube" CTA inside the iframe. A user-visible escape hatch in
// the player sheet header gives the same CTA the same prominence
// without forcing the user to tap into the broken iframe first.
//
// Routing prefers the YouTube app via the `youtube://` URL scheme
// when installed (zero-friction continuation); falls back to
// SFSafariViewController otherwise. SFSafariViewController shares
// cookies with mobile Safari so any creator-required age/region
// gates handle naturally.
private struct OpenInYouTubeButton: View {
    let videoId: String
    @State private var safariURL: URL? = nil

    var body: some View {
        Button {
            openOnYouTube()
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.Colors.bobaCyan)
        }
        .accessibilityLabel("Open in YouTube")
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    private func openOnYouTube() {
        let appURL = URL(string: "youtube://watch?v=\(videoId)")!
        let webURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            // SFSafariViewController as the in-app fallback per
            // Apple HIG; shares cookies with Safari so any auth
            // gating works.
            safariURL = webURL
        }
    }
}

// Identifiable conformance so the .sheet(item:) presenter accepts
// a URL directly. Local-scoped to keep the helper close to the
// only view that uses it; if Safari sheets become a pattern we
// can promote this into Components.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
