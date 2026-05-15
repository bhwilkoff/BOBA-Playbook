import Foundation

// MARK: - RainbowCriteria
//
// Filter expression for a custom rainbow. Each non-empty list
// narrows the matching cards by ONE dimension; dimensions
// AND-combine while values within a dimension OR-combine.
//
// Examples
//   • "Cupid in Griffey only"   → heroes=["Cupid"] + sets=["Griffey Edition"]
//   • "All Glows"               → elements=["GLOW"]
//   • "Every Hot Dog"           → cardTypes=["HotDog"]
//   • "Alpha-only Maverick"     → heroes=["Maverick"] + releases=["Alpha"]
//   • "Inspired Ink Cupid"      → heroes=["Cupid"] + inspiredInkOnly=true
//
// A card matches if EVERY non-empty dimension's check passes. An
// empty dimension means "any value is fine for this dimension."

struct RainbowCriteria: Codable, Hashable {
    var heroes:          [String] = []
    var sets:            [String] = []
    var subSets:         [String] = []
    var elements:        [String] = []
    var treatments:      [String] = []
    var cardTypes:       [String] = []
    var releases:        [String] = []
    var inspiredInkOnly: Bool     = false

    /// True if the criteria is effectively empty (would match every
    /// card in the catalog). Used as a guard in the editor to keep
    /// the user from saving a degenerate rainbow.
    var isEmpty: Bool {
        heroes.isEmpty
            && sets.isEmpty
            && subSets.isEmpty
            && elements.isEmpty
            && treatments.isEmpty
            && cardTypes.isEmpty
            && releases.isEmpty
            && !inspiredInkOnly
    }

    /// Per-card match test. Cheap; called per-card in lists.
    func matches(_ card: Card) -> Bool {
        if !heroes.isEmpty,
           !heroes.contains(where: { $0.caseInsensitiveCompare(card.hero) == .orderedSame }) {
            return false
        }
        if !sets.isEmpty,
           !sets.contains(where: { $0.caseInsensitiveCompare(card.set) == .orderedSame }) {
            return false
        }
        if !subSets.isEmpty {
            let cardSub = card.subSet ?? ""
            if !subSets.contains(where: { $0.caseInsensitiveCompare(cardSub) == .orderedSame }) {
                return false
            }
        }
        if !elements.isEmpty,
           !elements.contains(where: { $0.caseInsensitiveCompare(card.element) == .orderedSame }) {
            return false
        }
        if !treatments.isEmpty {
            let cardTreat = card.treatment ?? ""
            if !treatments.contains(where: { $0.caseInsensitiveCompare(cardTreat) == .orderedSame }) {
                return false
            }
        }
        if !cardTypes.isEmpty,
           !cardTypes.contains(where: { $0.caseInsensitiveCompare(card.cardType) == .orderedSame }) {
            return false
        }
        if !releases.isEmpty,
           !releases.contains(where: { $0.caseInsensitiveCompare(card.release) == .orderedSame }) {
            return false
        }
        if inspiredInkOnly, !card.isInspiredInk {
            return false
        }
        return true
    }

    /// One-line plain-English summary used as the row subtitle in
    /// the rainbow list. Skips empty dimensions; tweaks plurals
    /// and the special inspired-ink toggle.
    var summary: String {
        var parts: [String] = []
        if !heroes.isEmpty     { parts.append(heroes.joined(separator: " · ")) }
        if !sets.isEmpty       { parts.append(sets.joined(separator: " · ")) }
        if !subSets.isEmpty    { parts.append(subSets.joined(separator: " · ")) }
        if !elements.isEmpty   { parts.append(elements.joined(separator: " · ")) }
        if !treatments.isEmpty { parts.append(treatments.joined(separator: " · ")) }
        if !cardTypes.isEmpty  { parts.append(cardTypes.joined(separator: " · ")) }
        if !releases.isEmpty   { parts.append(releases.joined(separator: " · ")) }
        if inspiredInkOnly     { parts.append("Inspired Ink") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - CustomRainbow

struct CustomRainbow: Identifiable, Codable, Hashable {
    let id:        UUID
    var name:      String
    var criteria:  RainbowCriteria
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        criteria: RainbowCriteria = RainbowCriteria(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id        = id
        self.name      = name
        self.criteria  = criteria
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
