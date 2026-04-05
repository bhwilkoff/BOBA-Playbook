import Foundation

actor PricingService {
    static let shared = PricingService()
    private init() {}

    struct SaleItem: Decodable, Sendable {
        let title: String
        let price: Decimal
        let date: String   // ISO 8601 from eBay, e.g. "2026-03-15T12:00:00Z"
        let url: String
    }

    struct PricingResult: Sendable {
        let low: Decimal
        let average: Decimal
        let high: Decimal
        let saleCount: Int
        let recentSales: [SaleItem]
        let fetchedAt: Date
    }

    enum PricingError: LocalizedError {
        case notConfigured
        case noSales
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Pricing worker not configured."
            case .noSales:       return "No recent eBay sales found."
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

        guard response.saleCount > 0 else { throw PricingError.noSales }

        let result = PricingResult(
            low:         response.low,
            average:     response.average,
            high:        response.high,
            saleCount:   response.saleCount,
            recentSales: response.recentSales,
            fetchedAt:   Date()
        )
        cache[key] = result
        return result
    }

    // MARK: - Private response model

    private struct PricingResponse: Decodable {
        let low: Decimal
        let average: Decimal
        let high: Decimal
        let saleCount: Int
        let recentSales: [SaleItem]
    }
}
