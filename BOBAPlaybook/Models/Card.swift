import Foundation

struct Card: Codable, Identifiable, Hashable, Sendable {
    let bvId: Int?
    let cardNumber: String
    let name: String
    let hero: String          // "" for sealed products
    let cardType: String
    let set: String
    let subSet: String?
    let variation: String?
    let treatment: String?
    let element: String       // "NONE" for sealed products
    let power: Int?
    let playCost: Int?
    let isBonusPlay: Bool?
    let playAbility: String?
    let athleteInspiration: String?
    let isInspiredInk: Bool
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
        playAbility        = try c.decodeIfPresent(String.self,    forKey: .playAbility)
        athleteInspiration = try c.decodeIfPresent(String.self,    forKey: .athleteInspiration)
        isInspiredInk      = try c.decodeIfPresent(Bool.self,      forKey: .isInspiredInk) ?? false
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
