import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// `nonisolated` overrides the project's default-MainActor isolation
/// so this Sendable value type can be read from background actors
/// (notably the grid-scan TaskGroup, which calls into ScanMatching
/// off MainActor for parallelism). The struct is already Sendable
/// and all properties are immutable `let`s — there's no concurrency
/// hazard, just a default-isolation correction.
nonisolated struct Card: Codable, Identifiable, Hashable, Sendable {
    let bvId: Int?
    let cardNumber: String
    let name: String
    let hero: String          // "" for sealed products
    let cardType: String
    let set: String
    let subSet: String?
    let variation: String?
    let treatment: String?
    /// Canonical release label, normalized from `set` (drops the
    /// "Edition" suffix where applicable). Matches the names used in
    /// BoBA's published DBS update and the bobaleagues CSV format
    /// (Alpha / Alpha Update / Griffey / Alpha Blast / Promo / etc.).
    /// Empty string for legacy records that haven't been re-bundled.
    let release: String
    let element: String       // "NONE" for sealed products
    let power: Int?
    let playCost: Int?
    let isBonusPlay: Bool?
    let isHTD: Bool?                  // Play cards only — marks "Home Team Discount" HTD variants
    let playAbility: String?
    let dbs: Int?                     // Deck Balancing System score (Plays only, nil for Heroes/HotDogs/Sealed)
    let dbsTier: String?              // "Low" | "Medium" | "High" | "Very High" (Plays only)
    let athleteInspiration: String?
    let isInspiredInk: Bool
    /// True when the hero's inspiration athlete was in their rookie season
    /// at print time. Non-Hero rows decode as false.
    let rookieInspired: Bool
    let imageFile: String?
    let imageSource: String?
    let imageAvailable: Bool
    let radishUrl: String?

    // Sealed product fields (nil for regular cards)
    let sealedProductId: String?
    let productType: String?
    let packsPerBox: Int?
    let cardsPerPack: Int?
    let totalCards: Int?
    let msrp: Double?
    let upc: String?
    let highlights: [String]?
    let caseQuantity: Int?
    let ebaySearchQuery: String?

    var isSealed:  Bool { cardType == "Sealed Product" }
    var isHero:    Bool { cardType == "Hero" }
    var isPlay:    Bool { cardType == "Play" }
    var isHotDog:  Bool { cardType == "HotDog" }

    /// Display name: for non-Hero cards whose name/hero is non-ASCII (e.g. Japanese "怪獣焼き"),
    /// fall back to the variation field which holds the readable English name.
    var displayName: String {
        guard !isHero else { return name }
        let raw = name
        let hasNonASCII = raw.unicodeScalars.contains { $0.value > 127 }
        if hasNonASCII, let v = variation, v.unicodeScalars.allSatisfy({ $0.value <= 127 }) {
            return v
        }
        return raw
    }

    var playCostLabel: String? {
        guard let cost = playCost else { return nil }
        return cost == 0 ? "FREE" : "\(cost) HD"
    }

    // Rarity derived from treatment field
    var rarityTier: Int {
        guard let t = treatment?.lowercased() else { return 0 }
        if t.contains("kanji")        { return 5 }
        if t.contains("superfoil") || isInspiredInk { return 4 }
        if t.contains("blizzard")     { return 3 }
        if t.contains("battlefoil") || t.contains("logofoil") { return 2 }
        if t.contains("blast") || t.contains("paper") { return 1 }
        return 0
    }

    var rarityLabel: String {
        switch rarityTier {
        case 5: return "Kanjifoil"
        case 4: return isInspiredInk ? "Inspired Ink" : "Superfoil"
        case 3: return "Blizzard"
        case 2: return treatment?.lowercased().contains("logofoil") == true ? "Logofoil" : "Battlefoil"
        case 1: return treatment?.lowercased().contains("blast") == true ? "Blast" : "Paper"
        default: return "Base Set"
        }
    }

    // Stable unique id — v2 formula matches boba_id.py: "{cardNumber}-{hero}-{treatment??''}-{variation??''}"
    var id: String { "\(cardNumber)-\(hero)-\(treatment ?? "")-\(variation ?? "")" }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Card, rhs: Card) -> Bool { lhs.id == rhs.id }

    // Custom decoder handles nullable hero/element/imageAvailable for sealed products
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bvId               = try c.decodeIfPresent(Int.self,      forKey: .bvId)
        cardNumber         = try c.decode(String.self,             forKey: .cardNumber)
        name               = try c.decode(String.self,             forKey: .name)
        hero               = try c.decodeIfPresent(String.self,    forKey: .hero)      ?? ""
        cardType           = try c.decode(String.self,             forKey: .cardType)
        set                = try c.decode(String.self,             forKey: .set)
        subSet             = try c.decodeIfPresent(String.self,    forKey: .subSet)
        variation          = try c.decodeIfPresent(String.self,    forKey: .variation)
        treatment          = try c.decodeIfPresent(String.self,    forKey: .treatment)
        release            = try c.decodeIfPresent(String.self,    forKey: .release) ?? ""
        element            = try c.decodeIfPresent(String.self,    forKey: .element)   ?? "NONE"
        power              = try c.decodeIfPresent(Int.self,       forKey: .power)
        // playCost is an Int for Play cards (0–6 Hot Dogs) but sealed products
        // incorrectly store their MSRP price here as a Double. Decode flexibly.
        if let intVal = try? c.decodeIfPresent(Int.self, forKey: .playCost) {
            playCost = intVal
        } else if let dblVal = try? c.decodeIfPresent(Double.self, forKey: .playCost) {
            playCost = Int(dblVal)
        } else {
            playCost = nil
        }
        isBonusPlay        = try c.decodeIfPresent(Bool.self,       forKey: .isBonusPlay)
        isHTD              = try c.decodeIfPresent(Bool.self,       forKey: .isHTD)
        playAbility        = try c.decodeIfPresent(String.self,    forKey: .playAbility)
        dbs                = try c.decodeIfPresent(Int.self,       forKey: .dbs)
        dbsTier            = try c.decodeIfPresent(String.self,    forKey: .dbsTier)
        athleteInspiration = try c.decodeIfPresent(String.self,    forKey: .athleteInspiration)
        isInspiredInk      = try c.decodeIfPresent(Bool.self,      forKey: .isInspiredInk) ?? false
        rookieInspired     = try c.decodeIfPresent(Bool.self,      forKey: .rookieInspired) ?? false
        let file           = try c.decodeIfPresent(String.self,    forKey: .imageFile)
        imageFile          = file
        imageSource        = try c.decodeIfPresent(String.self,    forKey: .imageSource)
        // imageAvailable may be null (sealed); derive from imageFile presence as fallback
        imageAvailable     = try c.decodeIfPresent(Bool.self,      forKey: .imageAvailable)
                             ?? !(file?.isEmpty ?? true)
        radishUrl          = try c.decodeIfPresent(String.self,    forKey: .radishUrl)
        sealedProductId    = try c.decodeIfPresent(String.self,    forKey: .sealedProductId)
        productType        = try c.decodeIfPresent(String.self,    forKey: .productType)
        packsPerBox        = try c.decodeIfPresent(Int.self,       forKey: .packsPerBox)
        cardsPerPack       = try c.decodeIfPresent(Int.self,       forKey: .cardsPerPack)
        totalCards         = try c.decodeIfPresent(Int.self,       forKey: .totalCards)
        msrp               = try c.decodeIfPresent(Double.self,    forKey: .msrp)
        upc                = try c.decodeIfPresent(String.self,    forKey: .upc)
        highlights         = try c.decodeIfPresent([String].self,  forKey: .highlights)
        caseQuantity       = try c.decodeIfPresent(Int.self,       forKey: .caseQuantity)
        ebaySearchQuery    = try c.decodeIfPresent(String.self,    forKey: .ebaySearchQuery)
    }
}

// MARK: - Transferable (drag-and-drop, DESIGN.md §6.6)

/// Custom UTType for in-app card drag-drop. Namespaced under the
/// bundle ID and intentionally NOT declared in Info.plist — we
/// don't want third-party apps announcing they can receive BOBA
/// cards. Internal use only. `nonisolated` so it doesn't pick up
/// the project's default MainActor isolation
/// (SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor) — the Transferable
/// machinery reads it from arbitrary actors during drag-drop.
extension UTType {
    nonisolated static let bobaCard = UTType(exportedAs: "com.bhwilkoff.bobaplaybook.card")
}

/// Inlined into Card.swift rather than a standalone file because
/// Xcode's PBXFileSystemSynchronizedRootGroup intermittently fails
/// to pick up new files (per memory feedback_xcode_synchronized_groups).
/// CodableRepresentation works because Card is already Codable+Sendable.
/// `nonisolated` on transferRepresentation matches the protocol's
/// nonisolated requirement — without it, Card's default MainActor
/// isolation would create the "Conformance crosses into main actor-
/// isolated code" data-race error in Swift 6 mode.
extension Card: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bobaCard)
    }
}
