import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// `nonisolated` overrides the project's default-MainActor isolation
/// so this Sendable value type can be read from background actors
/// (notably the grid-scan TaskGroup, which calls into ScanMatching
/// off MainActor for parallelism). The struct is Sendable; mutation
/// is by-value-copy so the lone `var` (imageFile — updated by
/// CardStore.applyRuntimeImageOverrides from card_image_overrides
/// applied rows) is safe across actors.
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
    /// Per-card searchable aliases — e.g. ["Skeeball"] on Skeee cards
    /// so users typing the printed-on-card name (which differs from
    /// the catalog hero name) still find the card. Word-split and
    /// merged into the haystack at match time by CardSearch.
    let searchAliases: [String]?
    let isInspiredInk: Bool
    /// True when the hero's inspiration athlete was in their rookie season
    /// at print time. Non-Hero rows decode as false.
    let rookieInspired: Bool
    var imageFile: String?
    let imageSource: String?
    let imageAvailable: Bool
    /// Frozen legacy field — populated for cards in the catalog before
    /// 2026-05-23. Used SOLELY as the destination of the per-card
    /// "View on Radish" external-link button per Radish's email-stated
    /// allowance for "ordinary user-facing linking." Nil for new
    /// cards; the button falls back to the Radish homepage. NEVER
    /// passed to any Worker / matcher / pricing lookup — that
    /// automation is prohibited.
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

    /// Tick 197 — Discord backlog #7 (Android tick 189 parity).
    /// Optional print-run label for at-a-glance scarcity. Returns nil
    /// for the typical 99% card. Source of truth: DECISIONS.md #028
    /// "Inspired Ink = Serialized with weapon-tied print numbers:
    /// Hex /5, Glow /10, Fire /25, Ice /50."  Superfoil is the
    /// next-rarest non-numbered treatment.
    var printRunLabel: String? {
        if isInspiredInk {
            switch element.uppercased() {
            case "HEX":  return "/5"
            case "GLOW": return "/10"
            case "FIRE": return "/25"
            case "ICE":  return "/50"
            default:     return "Serial"   // Steel/Gum/Brawl/Super Inspired Ink — print run not public
            }
        }
        if treatment?.lowercased().contains("superfoil") == true { return "SSP" }
        return nil
    }

    // Stable unique id — v3 formula matches boba_id.py:
    // "{cardNumber}-{hero or name}-{treatment??''}-{variation??''}-{element}".
    // 5th field is the weapon (DECISIONS.md #057 / 2026-05-25).
    // For Sealed Products (no hero) the `name` field stands in so
    // the id matches the catalog's canonical bobaId field + the
    // `Card.bobaId` getter below. Without the name fallback,
    // `card.id` for sealed produced an "old form" string
    // ("SEALED-foo---Bundle") that DIDN'T match the canonical
    // bobaId stored in cards.json — which is what the catalog
    // index `cardsById` is keyed on. User_cards rows written
    // with the canonical bobaId then failed to resolve, and
    // sealed products rendered as their raw bobaId in Collection
    // (Ben 2026-05-22).
    /// Hashable / Identifiable key. Must match the stored `bobaId`
    /// field (v3 5-field formula per DECISIONS.md #057) so the iOS
    /// catalog index `cardsById` agrees with Supabase user_cards rows
    /// + shared-URL targets. The v2 4-field formula collided on
    /// FIRE/GLOW weapon-variant pairs (101 collisions across GLBF +
    /// RAD), which crashed `Dictionary(uniqueKeysWithValues:)` in
    /// DeckBuilderStore.loadTemplate and elsewhere.
    ///
    /// `nonisolated` because the project default isolation is MainActor
    /// (per memory feedback_project_default_mainactor_isolation) but
    /// pure value-derived computed properties are safe across actors
    /// and Hashable conformance in Sets / Dictionary keys requires it.
    nonisolated var id: String { bobaId }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
    nonisolated static func == (lhs: Card, rhs: Card) -> Bool { lhs.id == rhs.id }

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
        // Default to empty string (NOT "NONE") for null element so the
        // v3 bobaId formula matches the canonical Python/Android source:
        // Python uses `card.get("element") or ""` → empty; Android uses
        // `val element: String = ""`. Sealed products in the catalog
        // store empty element; iOS defaulting to "NONE" caused the
        // computed bobaId to end in "-NONE" while stored ended in "-",
        // producing a Card.id mismatch that hid sealed-product art +
        // metadata in Collection / Find.
        element            = try c.decodeIfPresent(String.self,    forKey: .element)   ?? ""
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
        searchAliases      = try c.decodeIfPresent([String].self,  forKey: .searchAliases)
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

/// Inlined into Card.swift rather than a standalone file because
/// Xcode's PBXFileSystemSynchronizedRootGroup intermittently fails
/// to pick up new files (per memory feedback_xcode_synchronized_groups).
/// CodableRepresentation works because Card is already Codable+Sendable.
///
/// contentType is .json (built-in UTType) — that's what
/// CodableRepresentation actually emits via the default JSONEncoder.
/// An earlier custom UTType (exportedAs a bundle-namespaced string)
/// tripped Xcode's "exported type not declared in Info.plist"
/// warning; for in-app-only drag-drop (pool → editor) we don't need
/// or want a custom UTI announcing that BOBA Playbook can receive
/// cards. NOTE: don't put the literal old UTI string anywhere in
/// this file — Xcode's grep-based UTI scan will flag it again.
///
/// `nonisolated` matches the protocol's nonisolated requirement —
/// without it, Card's default MainActor isolation creates the
/// "Conformance crosses into main actor-isolated code" data-race
/// error in Swift 6 mode.
extension Card: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

extension Card {
    /// Destination for the per-card "View on Radish" external-link
    /// button. Prefers the legacy frozen `radishUrl` field (acquired
    /// before 2026-05-23 from Radish's sitemap, treated as static
    /// reference data); falls back to the Radish homepage when the
    /// field is null. This is the ONE permitted use of Radish-derived
    /// data per the email — no probing, no validation, no lookups,
    /// no pricing impact, no Worker call.
    var radishDisplayURL: URL {
        if let raw = radishUrl, let url = URL(string: raw) { return url }
        return URL(string: "https://radishpriceguide.com")!
    }
}

extension Card {
    /// Canonical card identifier matching `scripts/boba_id.py`'s
    /// 5-field v3 formula:
    ///   `cardNumber-(hero or name)-(treatment or "")-(variation or "")-(element or "")`
    /// The 5th field is the card's WEAPON (catalog stores it under the
    /// legacy field name `element` per DECISIONS.md #027). Added
    /// 2026-05-25 to disambiguate FIRE-weapon vs GLOW-weapon variant
    /// siblings that share otherwise-identical (cardNumber, hero,
    /// treatment, variation). Without weapon in the bobaId, the
    /// catalog needed to use distinct cardNumbers as a workaround for
    /// those pairs.
    /// Sealed products use `name` when `hero` is empty. Trailing
    /// dashes are intentional and stable. CLAUDE.md "One ID per
    /// Card" — this is the primary key for the catalog.
    ///
    /// Computed at runtime rather than decoded — the formula is
    /// deterministic so the value matches the `bobaId` stored in
    /// the JSON bundles. `nonisolated` because `id` (Hashable key)
    /// returns this value and must be callable from any actor.
    nonisolated var bobaId: String {
        let identifier = hero.isEmpty ? name : hero
        return "\(cardNumber)-\(identifier)-\(treatment ?? "")-\(variation ?? "")-\(element)"
    }
}
