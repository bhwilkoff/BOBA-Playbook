import Foundation

/// A recently sold BOBA card on eBay, fetched from the `recent_sales` Supabase table.
/// The Worker cron populates this table every 30 minutes.
struct RecentSale: Decodable, Identifiable {
    let id:          UUID
    let ebayItemId:  String
    let title:       String
    let price:       Decimal
    let soldDate:    Date
    let imageUrl:    String?
    let ebayUrl:     String
    // Card matching fields (nullable — not every sale matches a catalog card)
    let cardNumber:  String?
    let hero:        String?
    let treatment:   String?
    let power:       Int?
    let fetchedAt:   Date?
    let createdAt:   Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ebayItemId  = "ebay_item_id"
        case title
        case price
        case soldDate    = "sold_date"
        case imageUrl    = "image_url"
        case ebayUrl     = "ebay_url"
        case cardNumber  = "card_number"
        case hero
        case treatment
        case power
        case fetchedAt   = "fetched_at"
        case createdAt   = "created_at"
    }
}
