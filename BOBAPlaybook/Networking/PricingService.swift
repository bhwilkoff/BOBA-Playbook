import Foundation

actor PricingService {
    static let shared = PricingService()
    private init() {}

    struct PricingResult: Sendable {
        let low: Decimal
        let average: Decimal
        let high: Decimal
        let saleCount: Int
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

    // In-memory cache: key = "cardNumber_days"
    private var cache: [String: PricingResult] = [:]
    private let cacheLifetime: TimeInterval = 3600  // 1 hour

    func pricing(for cardNumber: String, days: Int) async throws -> PricingResult {
        let key = "\(cardNumber)_\(days)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
        }

        let base = await MainActor.run { WorkerConfig.ebayProxyURL }
        guard !base.isEmpty else { throw PricingError.notConfigured }

        var components = URLComponents(string: base)
        components?.queryItems = [
            URLQueryItem(name: "cardNumber", value: cardNumber),
            URLQueryItem(name: "days",       value: "\(days)")
        ]
        guard let url = components?.url else { throw PricingError.notConfigured }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(PricingResponse.self, from: data)

        guard response.saleCount > 0 else { throw PricingError.noSales }

        let result = PricingResult(
            low:       response.low,
            average:   response.average,
            high:      response.high,
            saleCount: response.saleCount,
            fetchedAt: Date()
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
    }
}
