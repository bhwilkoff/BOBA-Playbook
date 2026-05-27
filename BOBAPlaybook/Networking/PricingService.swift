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
        /// just a comparability-function range (low/avg/high) computed
        /// from comparable cards. UI surfaces it as "MARKET EST."
        /// instead of "RECENT SALES" so users know the figure is a
        /// model estimate, not a transaction.
        let estimated: Bool?
        /// Free-form provenance string — only meaningful when estimated=true.
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
                 days: Int,
                 treatment: String? = nil,
                 variation: String? = nil,
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

        // Persistence-layer fast path. boba-pricing-snapshot's nightly
        // cron writes the latest market data to Supabase's
        // card_prices_history table; the `card_prices_latest` view
        // returns the most-recent row per (boba_id, source). When a
        // fresh row (< 24h) exists, render it immediately and skip
        // the live eBay-proxy roundtrip — significant latency win on
        // re-opened cards + saves eBay API quota. Refresh button
        // bypasses this path by setting forceRefresh=true.
        if !forceRefresh,
           let bobaId = bobaIdHint(cardNumber: cardNumber, hero: hero, treatment: treatment, variation: variation, element: element),
           let cachedResult = await fetchCachedPricingResult(bobaId: bobaId) {
            cache[key] = cachedResult
            return cachedResult
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
            // The Worker's parallel sold + active fetch keeps cold-path
            // latency around 0.9-1.5s, so a 7s timeout is now a genuine
            // network/server hiccup worth retrying immediately, not
            // caching as no-data.
            // Per-card retries already happen on next view appearance.
            throw PricingError.noData
        }
        let response = try JSONDecoder().decode(PricingResponse.self, from: data)

        // Provenance-honest pricing (PRICING_PLAYBOOK.md §7 · DESIGN.md
        // §8.7): when the Worker returns no real sold comps we do NOT
        // fabricate a "MARKET EST." from the starved `boba-price-
        // estimator`. PricingSection instead surfaces the active eBay
        // listings honestly as "LISTED RANGE". `fetchEstimatorBucket`
        // is retained (DECISIONS.md #025 keep-code-hide-entry-point)
        // for the Tier 4 overhaul, which reintroduces a clearly-labeled
        // estimate ONLY when fed real comp data.
        let soldSection = response.sold

        // Accept the response if any section has data
        let hasDualData = soldSection != nil || response.active != nil
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
            sold:      soldSection,
            active:    response.active
        )
        cache[key] = result
        return result
    }

    // MARK: - Estimator Worker fallback

    /// Reconstruct the v2 bobaId from the call params. Mirrors
    /// `scripts/boba_id.py` (CLAUDE.md "One ID per Card"):
    /// `{cardNumber}-{hero or name}-{treatment or ""}-{variation or ""}-{element}`
    /// — v3 5-field formula per DECISIONS.md #057. Element is the 5th
    /// field and disambiguates FIRE/GLOW weapon-variant pairs that
    /// otherwise share cardNumber + hero + treatment + variation.
    /// Must match the stored `bobaId` field used as `boba_id` in
    /// Supabase's card_prices_latest view; pre-v3 (4-field) hints
    /// silently missed the cache for variant-pair cards.
    private func bobaIdHint(cardNumber: String, hero: String, treatment: String?, variation: String?, element: String) -> String? {
        guard !cardNumber.isEmpty else { return nil }
        let id = hero.isEmpty ? "" : hero
        return "\(cardNumber)-\(id)-\(treatment ?? "")-\(variation ?? "")-\(element)"
    }

    private struct EstimatorResponse: Decodable {
        let low:               Double
        let mid:               Double
        let high:              Double
        let comparableCount:   Int?
        let comparableSources: [String]?
    }

    private struct CardPricesLatestRow: Decodable {
        let source:      String
        let snapshotAt:  String
        let lowUsd:      Decimal?
        let avgUsd:      Decimal?
        let highUsd:     Decimal?
        let itemCount:   Int?

        enum CodingKeys: String, CodingKey {
            case source
            case snapshotAt = "snapshot_at"
            case lowUsd     = "low_usd"
            case avgUsd     = "avg_usd"
            case highUsd    = "high_usd"
            case itemCount  = "item_count"
        }
    }

    /// Returns a PricingResult assembled from the latest snapshot rows
    /// for `bobaId` in Supabase's `card_prices_latest` view. nil when
    /// no fresh row (< 24h) exists; the caller falls through to the
    /// live ebay-proxy path.
    private func fetchCachedPricingResult(bobaId: String) async -> PricingResult? {
        // Anon-key Supabase REST read. The card_prices_history table
        // RLS allows public read; service-role write only.
        // Project default isolation is MainActor (per .pbxproj
        // SWIFT_DEFAULT_ACTOR_ISOLATION setting), so SupabaseConfig
        // is implicitly MainActor-isolated. PricingService is its own
        // actor — hop through MainActor.run to read the constant.
        let supabaseURL = "https://pazkimtkwwwekuguxkff.supabase.co/rest/v1"
        let anonKey = await MainActor.run { SupabaseConfig.anonKey }
        let encoded = bobaId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bobaId
        let urlString = "\(supabaseURL)/card_prices_latest?boba_id=eq.\(encoded)&select=source,snapshot_at,low_usd,avg_usd,high_usd,item_count"
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let rows = try JSONDecoder().decode([CardPricesLatestRow].self, from: data)
            if rows.isEmpty { return nil }
            let freshThreshold: TimeInterval = 24 * 3600
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var sold: PricingBucket?
            var active: PricingBucket?
            for row in rows {
                let parsed = isoFormatter.date(from: row.snapshotAt)
                    ?? ISO8601DateFormatter().date(from: row.snapshotAt)
                guard let snapshot = parsed,
                      Date().timeIntervalSince(snapshot) < freshThreshold else { continue }
                let bucket = PricingBucket(
                    low:             row.lowUsd ?? 0,
                    average:         row.avgUsd ?? 0,
                    high:            row.highUsd ?? 0,
                    count:           row.itemCount ?? 0,
                    items:           [],
                    countProbable:   nil,
                    stale:           nil,
                    estimated:       row.source == "estimator" ? true : nil,
                    estimatedSource: row.source == "estimator" ? "comps" : nil
                )
                switch row.source {
                case "ebay_sold":   sold = bucket
                case "ebay_active": active = bucket
                case "estimator":   if sold == nil { sold = bucket }
                default: break
                }
            }
            guard let primary = sold ?? active else { return nil }
            return PricingResult(
                low:       primary.low,
                average:   primary.average,
                high:      primary.high,
                count:     primary.count,
                priceType: sold != nil ? "sold" : "listed",
                items:     [],
                fetchedAt: Date(),
                sold:      sold,
                active:    active
            )
        } catch {
            return nil
        }
    }

    private func fetchEstimatorBucket(bobaId: String) async -> PricingBucket? {
        let base = await MainActor.run { WorkerConfig.priceEstimatorURL }
        guard !base.isEmpty,
              var comps = URLComponents(string: "\(base)/estimate") else { return nil }
        comps.queryItems = [URLQueryItem(name: "bobaId", value: bobaId)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let est = try JSONDecoder().decode(EstimatorResponse.self, from: data)
            return PricingBucket(
                low:             Decimal(est.low),
                average:         Decimal(est.mid),
                high:            Decimal(est.high),
                count:           0,
                items:           [],
                countProbable:   nil,
                stale:           nil,
                estimated:       true,
                estimatedSource: "comparability"
            )
        } catch {
            return nil
        }
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
    }
}

/// Whatnot active product listings (Tier 2 — an ASKING signal surfaced in
/// the BUY NOW panel only; NEVER mixed into the sold-comp / market-value
/// waterfall — asks run above sold and would inflate, per DECISIONS.md
/// #034 + PRICING_PLAYBOOK §4). Calls `boba-ebay-proxy /whatnot/products`,
/// which binds listings to the specific card via cardNumber + weapon and
/// flags `matchesCard` (best-first). Soft-fails to empty on any error or a
/// Cloudflare challenge, so a Whatnot hiccup never blocks eBay pricing.
///
/// Inlined here rather than its own file per the Xcode synchronized-group
/// reliability note (memory `feedback_xcode_synchronized_groups`).
actor WhatnotProductsService {
    static let shared = WhatnotProductsService()
    private init() {}

    struct Listing: Decodable, Sendable, Identifiable {
        var id: String { listingId.isEmpty ? "\(title)-\(priceCents)" : listingId }
        let title: String
        let price: Decimal
        let priceCents: Int
        let currency: String?
        let condition: String?
        let listingId: String
        let listingUrl: String
        let seller: String?
        let sellerUrl: String?
        let imageUrl: String?
        let format: String?        // "buy_now" | "auction"
        let matchesCard: Bool?
    }

    struct Response: Decodable, Sendable {
        let count: Int
        let bestMatchCount: Int?
        let listings: [Listing]
        let challenged: Bool?
    }

    private var cache: [String: (resp: Response, at: Date)] = [:]
    private let lifetime: TimeInterval = 720  // 12 min — matches the Worker edge cache

    /// Returns Whatnot listings for a card (matched-first), or an empty
    /// response on any failure. Never throws — additive BUY NOW source.
    func products(query: String, cardNumber: String, weapon: String,
                  treatment: String = "", power: String = "",
                  forceRefresh: Bool = false) async -> Response {
        let empty = Response(count: 0, bestMatchCount: 0, listings: [], challenged: nil)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return empty }

        let key = "\(q.lowercased())|\(cardNumber.lowercased())|\(weapon.lowercased())|\(treatment.lowercased())|\(power)"
        if !forceRefresh, let e = cache[key],
           Date().timeIntervalSince(e.at) < lifetime {
            return e.resp
        }

        let base = await MainActor.run { WorkerConfig.ebayProxyURL }
        guard !base.isEmpty,
              var comp = URLComponents(string: "\(base)/whatnot/products") else { return empty }
        // BoBA sellers title by card number OR power — send both so the
        // Worker can match on whichever the listing used.
        comp.queryItems = [
            URLQueryItem(name: "query",      value: q),
            URLQueryItem(name: "cardNumber", value: cardNumber),
            URLQueryItem(name: "weapon",     value: weapon),
            URLQueryItem(name: "treatment",  value: treatment),
            URLQueryItem(name: "power",      value: power),
        ]
        guard let url = comp.url else { return empty }

        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            cache[key] = (decoded, Date())
            return decoded
        } catch {
            // Soft-fail; don't cache so a transient failure doesn't lock
            // out a real success on the next view re-entry.
            return empty
        }
    }
}
