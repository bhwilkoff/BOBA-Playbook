import Foundation

// MARK: - Admin models

struct AdminUserProfile: Codable, Identifiable {
    let userId: UUID
    let email: String?
    let role: String
    let createdAt: Date
    let lastSignInAt: Date?
    let displayName: String?
    let collectionCount: Int
    let totalCollectionValue: Decimal
    let username: String?
    let publicCollectionEnabled: Bool
    let avatarUrl: String?
    let discordAvatarUrl: String?

    var id: UUID { userId }

    /// Best available label: display name → @username → email →
    /// UUID prefix. @username takes precedence over email when
    /// display_name is missing because the handle is more meaningful
    /// to other admins reviewing the row.
    var label: String {
        if let name = displayName, !name.isEmpty { return name }
        if let u = username, !u.isEmpty { return "@\(u)" }
        if let e = email { return e }
        return userId.uuidString.prefix(8) + "…"
    }

    /// Public-collection URL when sharing is on; nil otherwise.
    /// Mirrors the bobaplaybook.com/u/{username} contract from
    /// DECISIONS.md #039.
    var publicCollectionURL: URL? {
        guard publicCollectionEnabled, let u = username, !u.isEmpty else { return nil }
        return URL(string: "https://bobaplaybook.com/u/\(u)")
    }

    /// Resolved avatar URL — custom (R2) takes precedence over
    /// Discord. Same resolver semantics as AuthManager.resolvedAvatarURL.
    var resolvedAvatarURL: URL? {
        if let s = avatarUrl,        let u = URL(string: s) { return u }
        if let s = discordAvatarUrl, let u = URL(string: s) { return u }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case userId                    = "user_id"
        case email
        case role
        case createdAt                 = "created_at"
        case lastSignInAt              = "last_sign_in_at"
        case displayName               = "display_name"
        case collectionCount           = "collection_count"
        case totalCollectionValue      = "total_collection_value"
        case username
        case publicCollectionEnabled   = "public_collection_enabled"
        case avatarUrl                 = "avatar_url"
        case discordAvatarUrl          = "discord_avatar_url"
    }
}

struct AdminMetrics {
    let totalUsers: Int
    let pendingCorrections: Int
    let pendingImageOverrides: Int
}

// MARK: - UserCard
// One row = one physical copy of a card in the user's collection.
// Multiple copies of the same card_number are grouped in the UI.
struct UserCard: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let cardNumber: String
    /// Composite identifier matching Card.id: v3 5-field formula
    /// "{cardNumber}-{hero}-{treatment??''}-{variation??''}-{element}"
    /// (DECISIONS.md #057). Used for exact card matching so weapon-
    /// variant pairs (FIRE/GLOW) at the same cardNumber/treatment are
    /// never confused.
    let bobaId: String?
    var designation: Designation
    var condition: String?
    var serialNumber: Int?
    var grade: String?
    var gradingCompany: String?
    var purchasePrice: Decimal?
    var askingPrice: Decimal?
    var estimatedValue: Decimal?
    var lastPriceCheck: Date?
    let acquiredAt: Date
    var notes: String?

    // MARK: Designation
    enum Designation: String, Codable, CaseIterable, Identifiable, Hashable {
        case personal
        case for_sale
        case for_trade
        case wanted
        case grails

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .personal:  return "Personal"
            case .for_sale:  return "For Sale"
            case .for_trade: return "For Trade"
            case .wanted:    return "Wanted"
            case .grails:    return "Grails"
            }
        }

        /// Compact label for tight UI surfaces (e.g. a 5-segment iOS
        /// segmented Picker that needs to fit on an iPhone Mini).
        /// Drops "For " from the For Sale / For Trade designations.
        var shortDisplayName: String {
            switch self {
            case .personal:  return "Personal"
            case .for_sale:  return "Sale"
            case .for_trade: return "Trade"
            case .wanted:    return "Wanted"
            case .grails:    return "Grails"
            }
        }

        var icon: String {
            switch self {
            case .personal:  return "person.fill"
            case .for_sale:  return "tag.fill"
            case .for_trade: return "arrow.left.arrow.right"
            case .wanted:    return "star.fill"
            case .grails:    return "crown.fill"
            }
        }

        /// Whether this designation represents ownership (vs. a wishlist)
        var isOwned: Bool {
            switch self {
            case .personal, .for_sale, .for_trade: return true
            case .wanted, .grails: return false
            }
        }
    }

    // MARK: Supabase snake_case mapping
    enum CodingKeys: String, CodingKey {
        case id
        case userId          = "user_id"
        case cardNumber      = "card_number"
        case bobaId          = "boba_id"
        case designation
        case condition
        case serialNumber    = "serial_number"
        case grade
        case gradingCompany  = "grading_company"
        case purchasePrice   = "purchase_price"
        case askingPrice     = "asking_price"
        case estimatedValue  = "estimated_value"
        case lastPriceCheck  = "last_price_check"
        case acquiredAt      = "acquired_at"
        case notes
    }
}

// MARK: - New card payload (for POST to Supabase)
struct NewUserCard: Encodable {
    let cardNumber: String
    /// Composite identifier matching Card.id — v3 5-field formula
    /// "{cardNumber}-{hero}-{treatment??''}-{variation??''}-{element}"
    /// (DECISIONS.md #057). Stored server-side for exact card matching.
    let bobaId: String
    let designation: UserCard.Designation
    var condition: String?
    var serialNumber: Int?
    var grade: String?
    var gradingCompany: String?
    var purchasePrice: Decimal?
    var askingPrice: Decimal?
    var estimatedValue: Decimal?
    var lastPriceCheck: Date?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case cardNumber     = "card_number"
        case bobaId         = "boba_id"
        case designation
        case condition
        case serialNumber   = "serial_number"
        case grade
        case gradingCompany = "grading_company"
        case purchasePrice  = "purchase_price"
        case askingPrice    = "asking_price"
        case estimatedValue = "estimated_value"
        case lastPriceCheck = "last_price_check"
        case notes
    }
}
