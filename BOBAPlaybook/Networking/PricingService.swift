import Foundation

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

        enum CodingKeys: String, CodingKey {
            case low, average, high, count, items
            case countProbable = "count_probable"
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

    func pricing(for cardNumber: String,
                 hero: String,
                 set: String,
                 element: String,
                 power: Int?,
                 radishUrl: String?,
                 days: Int,
                 treatment: String? = nil) async throws -> PricingResult {
        let key = "\(hero)_\(cardNumber)_\(days)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
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

        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(PricingResponse.self, from: data)

        // Accept the response if any section has data
        let hasDualData = response.sold != nil || response.active != nil
        guard response.count > 0 || hasDualData else { throw PricingError.noData }

        let result = PricingResult(
            low:       response.low,
            average:   response.average,
            high:      response.high,
            count:     response.count,
            priceType: response.priceType,
            items:     response.items,
            fetchedAt: Date(),
            sold:      response.sold,
            active:    response.active
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
    }
}
