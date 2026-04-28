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
    let publishedAt: String?       // ISO 8601 — when the YouTube
                                   //   placeholder was created. NOT
                                   //   the actual broadcast time.
    /// Effective broadcast time — actualStartTime if the stream is
    /// running or has run, otherwise scheduledStartTime. Surface this
    /// in the UI for upcoming/live cards instead of `publishedAt`,
    /// since `publishedAt` reflects when the streamer set up the
    /// event placeholder, not when the show actually airs.
    let streamTime: String?
    let scheduledStartTime: String?
    let actualStartTime:    String?
    let actualEndTime:      String?
    let channelId: String?
    let channelTitle: String?
    let thumbnail: String?
    let thumbnailWidth:  Int?
    let thumbnailHeight: Int?
    /// Worker-side classification — true when the source video was
    /// shot vertically (Shorts and explicitly-tagged vertical
    /// uploads). See `isVerticalVideo` in worker.js for the heuristic
    /// stack (📱 emoji, #shorts marker, ≤65s duration, vertical
    /// thumbnail).
    let isVertical: Bool
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
    var isUpcoming: Bool { liveBroadcastContent == "upcoming" }

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
        Self.relativeDateLabel(from: publishedAt)
    }

    /// Future-leaning broadcast time label for upcoming streams.
    /// "Tomorrow at 1:00 PM", "Wed at 1:00 PM", "Apr 30 at 1:00 PM".
    /// Uses `streamTime` (actualStartTime || scheduledStartTime) so
    /// the display reflects when the show actually airs, not when
    /// the streamer created the YouTube event placeholder.
    var streamTimeLabel: String? {
        guard let iso = streamTime,
              let date = Self.iso8601.date(from: iso)
              ?? Self.iso8601Fractional.date(from: iso)
        else { return nil }
        let cal = Calendar.current
        let now = Date()
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        if cal.isDateInToday(date) {
            return "Today at \(timeFmt.string(from: date))"
        }
        if cal.isDateInTomorrow(date) {
            return "Tomorrow at \(timeFmt.string(from: date))"
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at \(timeFmt.string(from: date))"
        }
        let secondsAhead = date.timeIntervalSince(now)
        if secondsAhead > 0, secondsAhead < 6 * 24 * 3600 {
            // Less than a week out → use weekday name.
            let dow = DateFormatter()
            dow.dateFormat = "EEE"
            return "\(dow.string(from: date)) at \(timeFmt.string(from: date))"
        }
        let date_fmt = DateFormatter()
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            date_fmt.dateFormat = "MMM d"
        } else {
            date_fmt.dateFormat = "MMM d, yyyy"
        }
        return "\(date_fmt.string(from: date)) at \(timeFmt.string(from: date))"
    }

    private static func relativeDateLabel(from iso: String?) -> String? {
        guard let iso = iso,
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
    let upcoming:   [YouTubeVideo]
    let vertical:   [YouTubeVideo]
    let horizontal: [YouTubeVideo]
    let writtenAt: String?
}
