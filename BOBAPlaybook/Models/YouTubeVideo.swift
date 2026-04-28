import Foundation

// MARK: - YouTubeVideo
//
// One video row coming back from `boba-youtube-feed`. The Worker
// hydrates each video with `videos.list` so the UI has duration,
// statistics, live state, and the categorized priority signal
// without making any network calls of its own.
//
// Worker source-of-truth: workers/youtube-feed/worker.js
struct YouTubeVideo: Codable, Identifiable, Hashable {
    let videoId: String
    let title: String
    let description: String?
    let publishedAt: String?       // ISO 8601
    let channelId: String?
    let channelTitle: String?
    let thumbnail: String?
    let durationSec: Int?
    let viewCount: Int?
    let likeCount: Int?
    let commentCount: Int?
    let embeddable: Bool?
    let liveBroadcastContent: String?  // "live" | "upcoming" | "none"
    let liveStreamingDetails: LiveDetails?
    let priority: Int                  // 0 = top-pinned, 5 = channel, 9 = search
    let sourceChannel: String?
    let url: String
    let embedUrl: String

    var id: String { videoId }

    var isLiveNow: Bool { liveBroadcastContent == "live" }

    /// Pretty duration ("1:23" / "12:34" / "1:02:03"). Returns nil for
    /// items without a known duration (live streams in progress).
    var durationLabel: String? {
        guard let s = durationSec else { return nil }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// Best-effort relative date ("today", "2d ago", "Mar 14"). Same
    /// shape as the collection-row formatter so the two surfaces feel
    /// consistent.
    var publishedRelative: String? {
        guard let iso = publishedAt,
              let date = Self.iso8601.date(from: iso)
              ?? Self.iso8601Fractional.date(from: iso)
        else { return nil }
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date)     { return "today" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let f = DateFormatter()
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            f.dateFormat = "MMM d"
        } else {
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: date)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    struct LiveDetails: Codable, Hashable {
        let actualStartTime: String?
        let actualEndTime:   String?
        let scheduledStartTime: String?
        let concurrentViewers: String?
    }
}

// MARK: - Combined feed payload
//
// Worker `/` returns all three feeds in one payload — handy for the
// initial WatchView load so the user can flip between rails without
// triggering three separate requests.
struct YouTubeFeedBundle: Codable {
    let live:    [YouTubeVideo]
    let short:   [YouTubeVideo]
    let regular: [YouTubeVideo]
    let writtenAt: String?
}
