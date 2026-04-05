import Foundation

enum CDN {
    static let base = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"

    // Regular card images
    static func thumb(for imageFile: String) -> URL {
        URL(string: "\(base)/thumbs/\(imageFile)")!
    }
    static func full(for imageFile: String) -> URL {
        URL(string: "\(base)/full/\(imageFile)")!
    }

    // Sealed product images (sealed/thumbs/ and sealed/optimized/)
    static func sealedThumb(for imageFile: String) -> URL {
        URL(string: "\(base)/sealed/thumbs/\(imageFile)")!
    }
    static func sealedFull(for imageFile: String) -> URL {
        URL(string: "\(base)/sealed/optimized/\(imageFile)")!
    }

    // Convenience: resolves the correct URL based on card type
    static func thumbURL(for card: Card) -> URL? {
        guard let file = card.imageFile, !file.isEmpty else { return nil }
        return card.isSealed ? sealedThumb(for: file) : thumb(for: file)
    }
    static func fullURL(for card: Card) -> URL? {
        guard let file = card.imageFile, !file.isEmpty else { return nil }
        return card.isSealed ? sealedFull(for: file) : full(for: file)
    }
}
