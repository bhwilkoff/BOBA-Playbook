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

    // Convenience: resolves the correct URL based on card type.
    // CardStore overlays runtime `applied_image_file` overrides from
    // card_image_overrides on top of cards.json's imageFile — pass
    // the resolved filename via the `override` parameter when known.
    static func thumbURL(for card: Card, override: String? = nil) -> URL? {
        let file = override ?? card.imageFile
        guard let f = file, !f.isEmpty else { return nil }
        if card.isSealed { return sealedThumb(for: f) }
        // Some sets ship a single full-quality tier only (no separate thumb) —
        // serve the full image in grids too. Keeps one copy on the CDN; the
        // source art is already grid-sized.
        if fullOnly(card) { return full(for: f) }
        return thumb(for: f)
    }

    /// Sets whose art lives only under `full/` (no `thumbs/` tier). Grids serve
    /// the full image directly for these.
    static func fullOnly(_ card: Card) -> Bool {
        card.set == "Tecmo Bowl Edition"
    }
    static func fullURL(for card: Card, override: String? = nil) -> URL? {
        let file = override ?? card.imageFile
        guard let f = file, !f.isEmpty else { return nil }
        return card.isSealed ? sealedFull(for: f) : full(for: f)
    }
}
