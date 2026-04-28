import Foundation

// MARK: - YouTubeFeedService
//
// Thin client around `boba-youtube-feed` (workers/youtube-feed/).
// All three feeds are pre-categorized + sorted server-side; the
// service just deserializes and hands the bundles to the Watch
// view. Single source of URL truth lives in `WorkerConfig`.
@MainActor
@Observable
final class YouTubeFeedService {
    var upcoming:   [YouTubeVideo] = []
    var vertical:   [YouTubeVideo] = []
    var horizontal: [YouTubeVideo] = []
    var writtenAt: String?      = nil
    var isLoading: Bool         = false
    var loadError: String?      = nil

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch all three feeds in one call. Worker returns the combined
    /// payload at the root path, which is the cheapest way to hydrate
    /// the Watch view on first appearance — three single-feed calls
    /// would mean three KV reads + three round-trips for the same
    /// data the cron job pre-staged.
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        guard let url = URL(string: WorkerConfig.youtubeFeedURL + "/") else {
            loadError = "Invalid feed URL"
            return
        }
        do {
            let (data, _) = try await session.data(from: url)
            let bundle = try JSONDecoder().decode(YouTubeFeedBundle.self, from: data)
            self.upcoming   = bundle.upcoming
            self.vertical   = bundle.vertical
            self.horizontal = bundle.horizontal
            self.writtenAt  = bundle.writtenAt
        } catch {
            loadError = error.localizedDescription
        }
    }
}
