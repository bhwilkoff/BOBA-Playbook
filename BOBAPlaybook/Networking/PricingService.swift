import Foundation

actor PricingService {
    static let shared = PricingService()
    private init() {}

    struct ListingItem: Decodable, Sendable {
        let title: String
        let price: Decimal
        let url: String
    }

    struct PricingResult: Sendable {
        let low: Decimal
        let average: Decimal
        let high: Decimal
        let listingCount: Int
        let recentListings: [ListingItem]
        let fetchedAt: Date
    }

    enum PricingError: LocalizedError {
        case notConfigured
        case noListings
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Pricing worker not configured."
            case .noListings:    return "No active eBay listings found."
            }
        }
    }

    // In-memory cache: key = "hero_cardNumber_days"
    // Keyed on hero+cardNumber so two cards sharing a card number (e.g. RAD-352
    // Brockness vs Spider) each get their own search results.
    private var cache: [String: PricingResult] = [:]
    private let cacheLifetime: TimeInterval = 3600  // 1 hour

    func pricing(for cardNumber: String,
                 hero: String,
                 set: String,
                 element: String,
                 days: Int) async throws -> PricingResult {
        let key = "\(hero)_\(cardNumber)_\(days)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
        }

        let base = await MainActor.run { WorkerConfig.ebayProxyURL }
        guard !base.isEmpty else { throw PricingError.notConfigured }

        var components = URLComponents(string: base)
        components?.queryItems = [
            URLQueryItem(name: "cardNumber", value: cardNumber),
            URLQueryItem(name: "hero",       value: hero),
            URLQueryItem(name: "set",        value: set),
            URLQueryItem(name: "element",    value: element),
            URLQueryItem(name: "days",       value: "\(days)"),
        ]
        guard let url = components?.url else { throw PricingError.notConfigured }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(PricingResponse.self, from: data)

        guard response.listingCount > 0 else { throw PricingError.noListings }

        let result = PricingResult(
            low:             response.low,
            average:         response.average,
            high:            response.high,
            listingCount:    response.listingCount,
            recentListings:  response.recentListings,
            fetchedAt:       Date()
        )
        cache[key] = result
        return result
    }

    // MARK: - Private response model

    private struct PricingResponse: Decodable {
        let low: Decimal
        let average: Decimal
        let high: Decimal
        let listingCount: Int
        let recentListings: [ListingItem]
    }
}
