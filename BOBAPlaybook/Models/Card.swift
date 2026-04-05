import Foundation

struct Card: Codable, Identifiable, Hashable, Sendable {
    let bvId: Int?          // nullable in source data for some promo/variant cards
    let cardNumber: String
    let name: String
    let hero: String
    let cardType: String
    let set: String
    let subSet: String?
    let variation: String?
    let treatment: String?
    let element: String
    let power: Int?
    let playCost: Int?
    let playAbility: String?
    let athleteInspiration: String?
    let isInspiredInk: Bool
    let imageFile: String?
    let imageSource: String?
    let imageAvailable: Bool

    // Stable unique id: cardNumber + hero + treatment uniquely identifies each variant.
    // bvId is NOT unique — multiple hero variants share the same bvId.
    var id: String {
        "\(cardNumber)-\(hero)-\(treatment ?? "")"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Card, rhs: Card) -> Bool { lhs.id == rhs.id }
}
