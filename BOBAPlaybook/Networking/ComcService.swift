import Foundation

/// COMC.com asking-price listings, surfaced alongside eBay active
/// listings in the BUY NOW panel. NOT mixed into the sold-comp /
/// market-value waterfall (asking > sold; would inflate estimates).
///
/// Soft-fail by design: every method returns an empty array on any
/// error. The COMC integration is additive — when COMC's
/// Cloudflare-Turnstile WAF blocks the worker (current state per
/// 2026-04-29) we just don't render any COMC items, and eBay active
/// continues to populate the BUY NOW panel.
actor ComcService {
    static let shared = ComcService()
    private init() {}

    struct Listing: Decodable, Sendable, Identifiable {
        var id: String { itemId }
        let itemId: String
        let comcUrl: String
        let year: String
        let set: String
        let cardNumber: String
        let hero: String
        let grading: String
        let condition: String
        let askingPriceUsd: Decimal?

        enum CodingKeys: String, CodingKey {
            case itemId         = "item_id"
            case comcUrl        = "comc_url"
            case year, set, cardNumber, hero, grading, condition
            case askingPriceUsd = "asking_price_usd"
        }
    }

    struct Response: Decodable, Sendable {
        let count:      Int
        let cardNumber: String
        let listings:   [Listing]
        /// True when COMC's WAF served a Cloudflare Turnstile JS
        /// challenge instead of search results. Lets the UI tell
        /// the difference between "no inventory" (count=0,
        /// challenged=nil/false) and "blocked" (count=0,
        /// challenged=true) so we don't flash a misleading "no
        /// COMC listings" label when the data is just unreachable.
        let challenged: Bool?
    }

    // 30-min in-memory cache keyed on cardNumber. The Worker's KV
    // already enforces a 30-min TTL, so this is mostly to avoid the
    // round-trip when the user pages back to the same card.
    private var cache: [String: (resp: Response, fetchedAt: Date)] = [:]
    private let cacheLifetime: TimeInterval = 1800

    /// Returns COMC listings for a card (cheapest first), or [] on
    /// any failure. Never throws — additive feature, never blocks
    /// the BUY NOW panel from rendering eBay-active alongside.
    func listings(cardNumber: String, forceRefresh: Bool = false) async -> Response {
        let key = cardNumber
        if !forceRefresh,
           let entry = cache[key],
           Date().timeIntervalSince(entry.fetchedAt) < cacheLifetime {
            return entry.resp
        }

        let base = WorkerConfig.comcProxyURL
        guard !base.isEmpty,
              var components = URLComponents(string: "\(base)/listings") else {
            return Response(count: 0, cardNumber: cardNumber, listings: [], challenged: nil)
        }
        components.queryItems = [URLQueryItem(name: "cardNumber", value: cardNumber)]
        guard let url = components.url else {
            return Response(count: 0, cardNumber: cardNumber, listings: [], challenged: nil)
        }

        var req = URLRequest(url: url)
        // Tight timeout — the worker is ~200ms cache-hit / ~1s cache
        // miss. 5s is plenty and aborts when COMC's WAF challenges
        // the worker's outbound (we'll show "no COMC items" rather
        // than wait the full 60s).
        req.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            cache[key] = (decoded, Date())
            return decoded
        } catch {
            // Soft-fail with an empty response — caller will render
            // nothing in the COMC strip. We do NOT cache the empty
            // result so a transient failure (timeout) doesn't lock
            // out a real success on next view re-entry.
            return Response(count: 0, cardNumber: cardNumber, listings: [], challenged: nil)
        }
    }
}
