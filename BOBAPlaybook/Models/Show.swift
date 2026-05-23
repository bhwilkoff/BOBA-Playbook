import Foundation

// MARK: - Show Models
//
// A Show is a streamer's pre-curated list of cards assembled for a
// single live broadcast (Whatnot / YouTube / etc.). Shows are distinct
// from the user's Collection — a card in a show need not be in the
// collection, and cards in a show don't contribute to collection value.
// Persisted in Supabase tables `shows` + `show_cards`.

struct Show: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ShowCard: Identifiable, Codable, Sendable {
    let id: UUID
    let showId: UUID
    var bobaId: String
    var sortOrder: Int
    var excludedFromTotal: Bool
    /// Streamer-flagged "big hit" — promoted to a hero-row tile in the
    /// wall image at much larger size than the standard grid. Default
    /// false so existing rows decode cleanly. See ShowWallComposer for
    /// the responsive layout (1, 2–3, or 4+ big hits each lay out
    /// differently).
    var isBigHit: Bool
    let addedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case showId            = "show_id"
        case bobaId            = "boba_id"
        case sortOrder         = "sort_order"
        case excludedFromTotal = "excluded_from_total"
        case isBigHit          = "is_big_hit"
        case addedAt           = "added_at"
    }

    /// Custom init so legacy rows decoded before `is_big_hit` shipped
    /// (or rows from an older app build cached locally) default to
    /// false instead of throwing a missing-key error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,    forKey: .id)
        showId            = try c.decode(UUID.self,    forKey: .showId)
        bobaId            = try c.decode(String.self,  forKey: .bobaId)
        sortOrder         = try c.decode(Int.self,     forKey: .sortOrder)
        excludedFromTotal = try c.decode(Bool.self,    forKey: .excludedFromTotal)
        isBigHit          = try c.decodeIfPresent(Bool.self, forKey: .isBigHit) ?? false
        addedAt           = try c.decodeIfPresent(Date.self, forKey: .addedAt)
    }
}

// MARK: - Time horizons for Show totals
//
// Streamers want to look at the totals across different windows — a
// 7-day market reading looks different from a 6-month one. The picker
// on the Show detail view is driven by this enum. `days` maps to the
// `days` query param the pricing Worker already supports.

enum ShowHorizon: String, CaseIterable, Identifiable, Codable {
    case d7       = "7d"
    case d30      = "30d"
    case d90      = "90d"
    case m3       = "3mo"
    case m6       = "6mo"
    case m9       = "9mo"

    var id: String { rawValue }

    /// Days value to send to the pricing Worker. The Worker caps at 90,
    /// so longer windows still clamp server-side — acceptable since
    /// eBay Marketplace Insights data rarely contains reliable history
    /// beyond ~90 days anyway.
    var days: Int {
        switch self {
        case .d7:  return 7
        case .d30: return 30
        case .d90: return 90
        case .m3:  return 90
        case .m6:  return 180
        case .m9:  return 270
        }
    }

    var shortLabel: String { rawValue.uppercased() }
}
