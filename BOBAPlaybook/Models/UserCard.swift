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

    var id: UUID { userId }

    /// Best available label: display name → email prefix → UUID prefix
    var label: String {
        if let name = displayName, !name.isEmpty { return name }
        if let e = email { return e }
        return userId.uuidString.prefix(8) + "…"
    }

    enum CodingKeys: String, CodingKey {
        case userId               = "user_id"
        case email
        case role
        case createdAt            = "created_at"
        case lastSignInAt         = "last_sign_in_at"
        case displayName          = "display_name"
        case collectionCount      = "collection_count"
        case totalCollectionValue = "total_collection_value"
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
    /// Composite identifier matching Card.id: "{cardNumber}-{hero}-{treatment??''}-{variation??''}".
    /// Used for exact card matching so two cards with the same card number but
    /// different treatments/editions are never confused.
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
    /// Composite identifier matching Card.id ("{cardNumber}-{hero}-{treatment??''}-{variation??''}"). Stored server-side for exact card matching.
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
