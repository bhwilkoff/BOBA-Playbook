import Foundation

/// Cross-surface pricing-cache pulse. SwiftUI views observe
/// `version` via `.task(id:)` so any cache invalidation (per-card
/// or wholesale) re-runs their pricing fetch automatically. The
/// actor below bumps this whenever it drops cache entries; views
/// don't need to know about each other.
@MainActor
@Observable
final class PricingPulse {
    static let shared = PricingPulse()
    var version: Int = 0
    private init() {}
    fileprivate func bump() { version &+= 1 }
}

actor PricingService {
    static let shared = PricingService()
    private init() {}

    struct PricingItem: Decodable, Sendable {
        let title: String
        let price: Decimal
        let date:  String   // ISO 8601 for sold items; empty string for active listings
        let url:   String
        /// 0–1 score from the Worker's enriched matcher. Nil when the
        /// Worker is running in legacy mode or on an older response
        /// shape. UI treats >= 0.70 as confirmed, 0.45–0.70 as probable.
        let matchConfidence: Double?
        /// Signal names that contributed positively to matchConfidence.
        /// e.g. ["card_number_exact", "hero", "trusted_seller"]. Used to
        /// render the "Probable match" tooltip reasons.
        let matchReasons: [String]?

        enum CodingKeys: String, CodingKey {
            case title, price, date, url, matchConfidence, matchReasons
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            price = try c.decode(Decimal.self, forKey: .price)
            date  = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
            url   = try c.decodeIfPresent(String.self, forKey: .url)   ?? ""
            matchConfidence = try c.decodeIfPresent(Double.self,   forKey: .matchConfidence)
            matchReasons    = try c.decodeIfPresent([String].self, forKey: .matchReasons)
        }

        var isProbableMatch: Bool {
            if let c = matchConfidence { return c < 0.70 }
            return false
        }
    }

    struct PricingBucket: Decodable, Sendable {
        let low:     Decimal
        let average: Decimal
        let high:    Decimal
        let count:   Int
        let items:   [PricingItem]
        /// Sold-only: count of probable (badge-only) matches returned
        /// alongside the confirmed ones. Nil for active listings and
        /// legacy responses.
        let countProbable: Int?
        /// Sold-only: true when the only available comp is a single
        /// sale older than the requested window. UI surfaces it as
        /// "Last sold {date}" instead of "{days}-day avg" since one
        /// stale sale isn't really a window-based aggregate.
        let stale: Bool?
        /// Sold-only: true when the bucket carries no real sales —
        /// just Radish's Market Est. range (low/avg/high) computed
        /// from comparable cards. UI surfaces it as "MARKET EST."
        /// instead of "RECENT SALES" so users know the figure is a
        /// model estimate, not a transaction.
        let estimated: Bool?
        /// "comps" or "own_sales" — only meaningful when estimated=true.
        let estimatedSource: String?

        enum CodingKeys: String, CodingKey {
            case low, average, high, count, items, stale, estimated
            case countProbable   = "count_probable"
            case estimatedSource = "estimatedSource"
        }
    }

    struct PricingResult: Sendable {
        // Legacy flat fields (always populated for backward compat)
        let low:       Decimal
        let average:   Decimal
        let high:      Decimal
        let count:     Int
        let priceType: String   // "sold" | "listed"
        let items:     [PricingItem]
        let fetchedAt: Date
        // New dual-section fields (nil when Worker returns legacy shape)
        let sold:      PricingBucket?
        let active:    PricingBucket?
        /// Worker-validated Radish URL — present when the Worker
        /// actually pulled sales data. Clients should prefer this
        /// for the user-facing "Radish Guide" button so the link
        /// lands on a page that has listings instead of a 200-OK
        /// shell with no comps.
        let radishResolvedUrl: String?

        var isSold: Bool { priceType == "sold" }
    }

    enum PricingError: LocalizedError {
        case notConfigured
        case noData
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Pricing worker not configured."
            case .noData:        return "No eBay listings found."
            }
        }
    }

    // In-memory cache keyed on "hero_cardNumber_days"
    private var cache: [String: PricingResult] = [:]
    private let cacheLifetime: TimeInterval = 3600  // 1 hour
    /// Negative cache for cards the Worker reported as having no data.
    /// Without this, re-opening a show with no-comp cards re-hits the
    /// slow Worker round-trip every time (the Worker exhausts every
    /// eBay search variant before giving up).
    private var emptyAt: [String: Date] = [:]
    /// Shortened from 600s (10min) → 120s (2min) on 2026-04-29.
    /// Worker is now sub-second on cache hits and ~1s on cold cache
    /// after the parallel namespace sweep, so a long backoff just
    /// traps users in a blank pricing pane when the worker recovers.
    private let emptyLifetime: TimeInterval = 120

    // ── Cross-surface invalidation broadcaster ────────────────────────────────
    //
    // PricingSection (and any other surface that displays pricing)
    // can observe `cacheVersion` via `.task(id:)`. Whenever any
    // refresh path drops cache entries (per-card or wholesale), it
    // bumps the version, and every observer re-runs its fetch.
    //
    // Without this, refreshes from one surface (e.g. Collection's
    // "Refresh Market Values" button) silently updated the
    // PricingService cache but the user's open card-detail view
    // kept showing whatever it loaded a moment earlier — they had
    // to dismiss and re-open to see the new number.
    private(set) var cacheVersion: Int = 0

    /// Drop the cached entry for one card and bump the version so
    /// observers re-fetch. Use this when an explicit per-card
    /// refresh happens (e.g. show queue scanner stepping past a
    /// card it just refreshed).
    func invalidate(cardNumber: String, hero: String) async {
        let prefix = "\(hero)_\(cardNumber)_"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        emptyAt = emptyAt.filter { !$0.key.hasPrefix(prefix) }
        cacheVersion &+= 1
        await MainActor.run { PricingPulse.shared.bump() }
    }

    /// Drop every cached entry and bump the version. Used by the
    /// Collection-level "Refresh market values" button after the
    /// recalc loop completes — every card surface in the app
    /// re-fetches on next render.
    func bumpAll() async {
        cache.removeAll()
        emptyAt.removeAll()
        cacheVersion &+= 1
        await MainActor.run { PricingPulse.shared.bump() }
    }

    func pricing(for cardNumber: String,
                 hero: String,
                 set: String,
                 element: String,
                 power: Int?,
                 radishUrl: String?,
                 days: Int,
                 treatment: String? = nil,
                 forceRefresh: Bool = false) async throws -> PricingResult {
        let key = "\(hero)_\(cardNumber)_\(days)"
        if !forceRefresh,
           let cached = cache[key],
           Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
        }
        if !forceRefresh,
           let stamped = emptyAt[key],
           Date().timeIntervalSince(stamped) < emptyLifetime {
            throw PricingError.noData
        }
        // Force-refresh path also drops any prior negative cache so a
        // card that previously returned no-data gets a real second
        // chance (e.g. once Market Est. fallback is wired up, a card
        // that had truly nothing now has an estimated price).
        if forceRefresh {
            cache.removeValue(forKey: key)
            emptyAt.removeValue(forKey: key)
            cacheVersion &+= 1
            await MainActor.run { PricingPulse.shared.bump() }
        }

        let base = await MainActor.run { WorkerConfig.ebayProxyURL }
        guard !base.isEmpty else { throw PricingError.notConfigured }

        var components = URLComponents(string: base)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "cardNumber", value: cardNumber),
            URLQueryItem(name: "hero",       value: hero),
            URLQueryItem(name: "set",        value: set),
            URLQueryItem(name: "element",    value: element),
            URLQueryItem(name: "days",       value: "\(days)"),
        ]
        if let power     { queryItems.append(URLQueryItem(name: "power",     value: "\(power)")) }
        if let radishUrl { queryItems.append(URLQueryItem(name: "radishUrl", value: radishUrl)) }
        if let treatment, !treatment.isEmpty {
            // Sent only so the Worker's enriched sold-comp scorer can
            // credit treatment matches. No effect on legacy mode.
            queryItems.append(URLQueryItem(name: "treatment", value: treatment))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw PricingError.notConfigured }

        // Tight per-request timeout — the Worker normally responds in
        // 100–500ms on the happy path. The slow path (no-comp cards
        // where it exhausts every eBay search variant) measured 30–40s,
        // which is much longer than any user should wait per card.
        // 7s is comfortably above the happy path and aborts the slow
        // tail; the caller catches and treats it as no-data.
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            // Timeout used to stamp emptyAt for 600s (later 120s),
            // which trapped users in a blank pricing pane any time
            // a single cold-cache request blew past 7s — even
            // though the Worker was returning real data on retry.
            // The parallel namespace sweep (worker.js fetchRadishSales)
            // dropped cold-path latency from 4-5s → 0.9-1.5s, so a
            // 7s timeout is now a genuine network/server hiccup
            // worth retrying immediately, not caching as no-data.
            // Per-card retries already happen on next view appearance.
            throw PricingError.noData
        }
        let response = try JSONDecoder().decode(PricingResponse.self, from: data)

        // Accept the response if any section has data
        let hasDualData = response.sold != nil || response.active != nil
        guard response.count > 0 || hasDualData else {
            emptyAt[key] = Date()
            throw PricingError.noData
        }

        let result = PricingResult(
            low:       response.low,
            average:   response.average,
            high:      response.high,
            count:     response.count,
            priceType: response.priceType,
            items:     response.items,
            fetchedAt: Date(),
            sold:      response.sold,
            active:    response.active,
            radishResolvedUrl: response.radishResolvedUrl
        )
        cache[key] = result
        return result
    }

    // MARK: - Private response model

    private struct PricingResponse: Decodable {
        // Legacy flat fields (always present for backward compat)
        let low:       Decimal
        let average:   Decimal
        let high:      Decimal
        let count:     Int
        let priceType: String
        let items:     [PricingItem]
        // New dual-section fields
        let sold:      PricingBucket?
        let active:    PricingBucket?
        // Worker-validated Radish URL (present when the Worker
        // actually scraped sales data, nil otherwise).
        let radishResolvedUrl: String?
    }
}
