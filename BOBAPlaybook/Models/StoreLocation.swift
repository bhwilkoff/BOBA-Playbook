import Foundation
import CoreLocation

struct StoreLocation: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let slug: String
    let phone: String
    let email: String
    let website: String
    let address: Address
    let location: Coordinate
    let placeId: String
    let officialUrl: String
    let modifiedAt: String

    struct Address: Codable, Hashable, Sendable {
        let full: String
        let street: String
        let city: String
        let state: String
        let stateShort: String
        let postCode: String
        let country: String
        let countryShort: String
    }

    struct Coordinate: Codable, Hashable, Sendable {
        let lat: Double
        let lng: Double
    }
}

extension StoreLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }

    /// Known national / big-box retailers. Ben's intent: surface the
    /// small hobby shops that actually champion BOBA, rather than bury
    /// them under ~1,800 Target + DICK'S rows. Off-default filter.
    ///
    /// Keep this list mirrored in `js/store-locator.js` (BIG_BOX_KEYWORDS)
    /// so iOS + web classify identically.
    static let bigBoxKeywords: [String] = [
        "dick's sporting", "dicks sporting", "dsg ", "dsg house of sport",
        "dick's house of sport", "dick's sporting goods combo store",
        "target",
        "walmart", "wal-mart",
        "costco",
        "meijer",
        "fred meyer",
        "scheels",
        "academy sports",
        "gamestop",
        "five below",
        "best buy",
        "barnes & noble", "barnes and noble",
        "books-a-million", "books a million",
        "hobby lobby",
        "kohl's", "kohls",
    ]

    /// True when the store's name matches a known big-box chain. The
    /// name field is authoritative (ACF-populated) so substring matching
    /// is reliable — the data doesn't mix chain + franchisee in one row.
    var isBigBox: Bool {
        let n = name.lowercased()
        return StoreLocation.bigBoxKeywords.contains { n.contains($0) }
    }

    /// Apple Maps deeplink. Opens the native Maps app on iOS; falls back
    /// to maps.apple.com in any browser.
    var appleMapsURL: URL? {
        var c = URLComponents(string: "https://maps.apple.com/")!
        var q = [URLQueryItem(name: "ll", value: "\(location.lat),\(location.lng)")]
        if !name.isEmpty { q.append(.init(name: "q", value: name)) }
        c.queryItems = q
        return c.url
    }

    var googleMapsURL: URL? {
        if !placeId.isEmpty {
            return URL(string: "https://www.google.com/maps/place/?q=place_id:\(placeId)")
        }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(location.lat),\(location.lng)")
    }

    var telURL: URL? {
        let digits = phone.filter { "0123456789+".contains($0) }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    var websiteURL: URL? {
        let trimmed = website.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    /// Relative "Last verified X ago" based on `modifiedAt`. Returns a
    /// best-effort human string; falls back to the raw timestamp when
    /// parsing fails.
    var lastVerifiedLabel: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = iso.date(from: modifiedAt)
            ?? ISO8601DateFormatter().date(from: modifiedAt)
        guard let date = parsed else { return modifiedAt }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Last verified \(f.localizedString(for: date, relativeTo: Date()))"
    }
}
