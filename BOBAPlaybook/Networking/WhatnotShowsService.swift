//
//  WhatnotShowsService.swift
//  BOBAPlaybook
//
//  Talks to the boba-whatnot-shows Cloudflare Worker for the
//  Purchase view's "Upcoming Breaks" section. The Worker scrapes
//  Whatnot's search page for "Bo Jackson Battle Arena" livestreams
//  and returns a normalized JSON list (see Cowork handoff).
//

import Foundation

struct WhatnotShow: Identifiable, Codable, Sendable, Hashable {
    let showId: String
    let showUrl: String
    let title: String
    let host: String
    let hostUrl: String
    let status: String?            // "PLAYING" | "CREATED"
    let isLive: Bool?
    let scheduledTimeText: String
    let scheduledTimeIso: String?
    let startTimeMs: Int64?
    let viewerCount: Int
    let categoryName: String
    let categorySlug: String
    let tags: [String]
    let thumbnailUrl: String

    var id: String { showId }
    var isLiveShow: Bool { isLive == true }

    var scheduledDate: Date? {
        if let ms = startTimeMs { return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0) }
        guard let iso = scheduledTimeIso, !iso.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}

// Decoded inside the WhatnotShowsService actor. Swift 6's default
// MainActor inference attaches to a synthesized Decodable
// conformance, which then can't be used from a non-MainActor
// context. An explicit `nonisolated init(from:)` opts the
// conformance out of that inference so the actor can decode it
// directly.
private struct WhatnotShowsResponse: Sendable {
    let shows: [WhatnotShow]
    let count: Int?
    let fetchedAtIso: String?
}

extension WhatnotShowsResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case shows, count, fetchedAtIso
    }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.shows = try c.decode([WhatnotShow].self, forKey: .shows)
        self.count = try c.decodeIfPresent(Int.self, forKey: .count)
        self.fetchedAtIso = try c.decodeIfPresent(String.self, forKey: .fetchedAtIso)
    }
}

actor WhatnotShowsService {
    static let shared = WhatnotShowsService()
    private init() {}

    /// 5 minutes — matches the Worker's edge cache; saves a round-trip
    /// when the user switches tabs back to Purchase quickly.
    private let cacheLifetime: TimeInterval = 300
    private var cached: (fetchedAt: Date, shows: [WhatnotShow])?

    func upcomingShows(query: String = "bo Jackson battle arena",
                       force: Bool = false) async throws -> [WhatnotShow] {
        if !force,
           let cached,
           Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached.shows
        }

        let base = await MainActor.run { WorkerConfig.ebayProxyURL }
        guard !base.isEmpty else { return [] }

        var components = URLComponents(string: base)
        components?.path = "/whatnot/upcoming"
        // No `status` param — let the Worker default to CREATED+PLAYING
        // so the Purchase view shows live streams alongside upcoming ones.
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder().decode(WhatnotShowsResponse.self, from: data)
        cached = (Date(), payload.shows)
        return payload.shows
    }
}
