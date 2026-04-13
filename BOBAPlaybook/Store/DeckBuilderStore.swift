//
//  DeckBuilderStore.swift
//  BOBAPlaybook
//
//  @Observable store for the Deck Builder feature.
//  Manages deck contents, validation, format selection, and Supabase persistence.
//

import Foundation

// ════════════════════════════════════════════════════════════════
// MARK: - Deck Format
// ════════════════════════════════════════════════════════════════

enum DeckFormat: String, CaseIterable, Identifiable, Codable {
    case rookie        = "Rookie"
    case substitution  = "Substitution"
    case playmaker     = "Playmaker"
    case spec          = "SPEC Playmaker"
    case limited       = "Limited"

    var id: String { rawValue }

    var heroTarget: Int { self == .limited ? 40 : 60 }
    var heroMinimum: Int { self == .limited ? 40 : 60 }
    var needsHotDogs: Bool { self != .rookie }
    var needsPlaybook: Bool { self != .rookie && self != .substitution }
    var enforcesPowerCap: Bool { self == .spec }
    var enforcesDBS: Bool { self == .spec }
    var hasSideboard: Bool { self == .spec }
    var powerCap: Int { 160 }

    var supabaseValue: String {
        switch self {
        case .rookie:       return "rookie"
        case .substitution: return "substitution"
        case .playmaker:    return "playmaker"
        case .spec:         return "spec"
        case .limited:      return "limited"
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Deck Card Role
// ════════════════════════════════════════════════════════════════

enum DeckCardRole: String, Codable {
    case hero, play, bonusPlay = "bonus_play", hotDog = "hot_dog", sideboard
}

// ════════════════════════════════════════════════════════════════
// MARK: - Validation Error
// ════════════════════════════════════════════════════════════════

struct DeckValidationError: Identifiable, Equatable {
    let id = UUID()
    let section: DeckCardRole
    let message: String
}

// ════════════════════════════════════════════════════════════════
// MARK: - Saved Deck (Supabase)
// ════════════════════════════════════════════════════════════════

struct SavedDeck: Identifiable, Codable {
    let id: UUID
    var name: String
    var format: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, format
        case createdAt = "created_at"
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - DeckBuilderStore
// ════════════════════════════════════════════════════════════════

@Observable
@MainActor
final class DeckBuilderStore {

    // MARK: - Deck Identity
    var deckName: String = "New Deck"
    var format: DeckFormat = .playmaker
    var currentDeckId: UUID?            // non-nil when editing a saved deck

    // MARK: - Deck Contents (ordered arrays of bobaIds)
    var heroes: [Card] = []
    var plays: [Card] = []
    var bonusPlays: [Card] = []
    var hotDogs: [Card] = []
    var sideboard: [Card] = []          // SPEC format only

    // MARK: - Card Browser State
    var browserTab: DeckCardRole = .hero
    var browserSearch: String = ""
    var browserElement: String = "ALL"
    var browserPowerMin: Int = 0
    var browserPowerMax: Int = 999

    // MARK: - Saved Decks List
    var savedDecks: [SavedDeck] = []
    var isLoadingSaved = false

    // MARK: - Save State
    var isSaving = false
    var saveError: String?

    // MARK: - Computed Stats

    var heroPowerValues: [Int: Int] {
        var counts: [Int: Int] = [:]
        for card in heroes { counts[(card.power ?? 0), default: 0] += 1 }
        return counts
    }

    var heroPowerMin: Int? { heroes.compactMap { $0.power }.min() }
    var heroPowerMax: Int? { heroes.compactMap { $0.power }.max() }

    // Note: dbs field not yet in Card model; returns 0 until field is added.
    var totalDBS: Int { 0 }

    var isHeroSectionComplete: Bool {
        heroes.count == format.heroTarget
    }

    var isPlaybookComplete: Bool {
        !format.needsPlaybook || plays.count == 30
    }

    var isHotDogComplete: Bool {
        !format.needsHotDogs || hotDogs.count == 10
    }

    // MARK: - Validation

    var validationErrors: [DeckValidationError] {
        var errors: [DeckValidationError] = []

        // Hero count
        if heroes.count < format.heroMinimum {
            errors.append(.init(section: .hero, message: "Need \(format.heroTarget - heroes.count) more heroes (\(heroes.count)/\(format.heroTarget))"))
        } else if heroes.count > format.heroTarget {
            errors.append(.init(section: .hero, message: "Too many heroes (\(heroes.count)/\(format.heroTarget))"))
        }

        // Power cap (SPEC only)
        if format.enforcesPowerCap {
            let overCap = heroes.filter { ($0.power ?? 0) > format.powerCap }
            if !overCap.isEmpty {
                errors.append(.init(section: .hero, message: "\(overCap.count) hero(es) over power cap \(format.powerCap)"))
            }
        }

        // Per-power-value limit (max 6)
        for (power, count) in heroPowerValues where count > 6 {
            errors.append(.init(section: .hero, message: "Power \(power): \(count)/6 — remove \(count - 6) card(s)"))
        }

        // 4-attribute uniqueness (no two cards share hero+treatment+element+power)
        var seen: Set<String> = []
        for card in heroes {
            let key = "\(card.hero)|\(card.treatment ?? "")|\(card.element)|\(card.power ?? 0)"
            if seen.contains(key) {
                errors.append(.init(section: .hero, message: "Duplicate variation: \(card.hero) (\(card.treatment ?? "Base"), \(card.element), \(card.power ?? 0))"))
            }
            seen.insert(key)
        }

        // Per-hero cap (max 6 of same hero name — official rules)
        var heroCounts: [String: Int] = [:]
        for card in heroes { heroCounts[card.hero, default: 0] += 1 }
        for (hero, count) in heroCounts where count > 6 {
            errors.append(.init(section: .hero, message: "\(hero): \(count)/6 max — remove \(count - 6)"))
        }

        // Plays
        if format.needsPlaybook {
            if plays.count < 30 {
                errors.append(.init(section: .play, message: "Need \(30 - plays.count) more plays (\(plays.count)/30)"))
            } else if plays.count > 30 {
                errors.append(.init(section: .play, message: "Too many plays (\(plays.count)/30)"))
            }
            // Play name uniqueness
            var playNames: Set<String> = []
            for card in plays + bonusPlays {
                let name = card.name
                if playNames.contains(name) {
                    errors.append(.init(section: .play, message: "Duplicate play name: \(name)"))
                }
                playNames.insert(name)
            }
        }

        // Hot Dogs
        if format.needsHotDogs && hotDogs.count != 10 {
            let diff = 10 - hotDogs.count
            if diff > 0 {
                errors.append(.init(section: .hotDog, message: "Need \(diff) more hot dogs (\(hotDogs.count)/10)"))
            } else {
                errors.append(.init(section: .hotDog, message: "Too many hot dogs (\(hotDogs.count)/10)"))
            }
        }

        return errors
    }

    var isLegal: Bool { validationErrors.isEmpty && isHeroSectionComplete }

    // MARK: - Card Queries

    /// True if this card is already in the deck (any role).
    func isInDeck(_ card: Card) -> Bool {
        heroes.contains(card) || plays.contains(card) || bonusPlays.contains(card) || hotDogs.contains(card) || sideboard.contains(card)
    }

    /// Count of a card already in the hero deck (for repeat-check).
    func heroCount(for card: Card) -> Int {
        heroes.filter { $0 == card }.count
    }

    /// True if adding this hero would violate a rule immediately.
    func heroWouldViolate(_ card: Card) -> Bool {
        guard let power = card.power else { return true }
        // Power cap
        if format.enforcesPowerCap && power > format.powerCap { return true }
        // Variation already present
        if heroes.contains(card) { return true }
        // Per-power limit
        if (heroPowerValues[power] ?? 0) >= 6 { return true }
        // Per-hero limit
        let heroTotal = heroes.filter { $0.hero == card.hero }.count
        if heroTotal >= 6 { return true }
        return false
    }

    // MARK: - Add / Remove

    func addCard(_ card: Card, role: DeckCardRole) {
        switch role {
        case .hero:
            guard !heroes.contains(card) else { return }
            heroes.append(card)
        case .play:
            guard !plays.contains(card) && !bonusPlays.contains(card) else { return }
            if card.cardNumber.hasPrefix("BPL") || card.treatment == "Bonus Plays" {
                bonusPlays.append(card)
            } else {
                plays.append(card)
            }
        case .bonusPlay:
            guard !bonusPlays.contains(card) && !plays.contains(card) else { return }
            bonusPlays.append(card)
        case .hotDog:
            if hotDogs.count < 10 { hotDogs.append(card) }
        case .sideboard:
            sideboard.append(card)
        }
    }

    func removeCard(_ card: Card, role: DeckCardRole) {
        switch role {
        case .hero:      heroes.removeFirst(card)
        case .play:      plays.removeFirst(card)
        case .bonusPlay: bonusPlays.removeFirst(card)
        case .hotDog:    hotDogs.removeFirst(card)
        case .sideboard: sideboard.removeFirst(card)
        }
    }

    // MARK: - Clear

    func clearDeck() {
        heroes = []; plays = []; bonusPlays = []; hotDogs = []; sideboard = []
        deckName = "New Deck"; currentDeckId = nil
    }

    // MARK: - Load Template

    func loadTemplate(_ template: DeckTemplate, allCards: [Card]) {
        clearDeck()
        deckName = template.name
        format = template.format
        let byId = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
        heroes = template.heroIds.compactMap { byId[$0] }
        plays = template.playIds.compactMap { byId[$0] }
        bonusPlays = template.bonusPlayIds.compactMap { byId[$0] }
        hotDogs = template.hotDogIds.compactMap { byId[$0] }
    }

    // MARK: - Supabase Save

    func saveDeck() async {
        guard SupabaseClient.shared.isAuthenticated else { return }
        isSaving = true
        saveError = nil
        do {
            try await SupabaseClient.shared.saveDeck(self)
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    func loadSavedDecks() async {
        guard SupabaseClient.shared.isAuthenticated else { return }
        isLoadingSaved = true
        do {
            savedDecks = try await SupabaseClient.shared.fetchDecks()
        } catch {}
        isLoadingSaved = false
    }

    // MARK: - Text Export

    var deckListText: String {
        var lines: [String] = ["# \(deckName) (\(format.rawValue))"]
        lines.append("")
        lines.append("## Heroes (\(heroes.count))")
        let grouped = Dictionary(grouping: heroes) { $0.power ?? 0 }
        for power in grouped.keys.sorted(by: >) {
            let cards = grouped[power]!
            for card in cards {
                let t = card.treatment ?? "Base"
                lines.append("\(card.hero) \(power) \(card.element) (\(t))")
            }
        }
        if format.needsPlaybook {
            lines.append("")
            lines.append("## Plays (\(plays.count)/30)")
            for card in plays {
                let cost = card.playCost.map { "\($0) HD" } ?? "0 HD"
                lines.append("\(card.name) (\(cost))")
            }
            if !bonusPlays.isEmpty {
                lines.append("")
                lines.append("## Bonus Plays (\(bonusPlays.count))")
                for card in bonusPlays {
                    let cost = card.playCost.map { "\($0) HD" } ?? "0 HD"
                    lines.append("\(card.name) (\(cost))")
                }
            }
        }
        if format.needsHotDogs && !hotDogs.isEmpty {
            lines.append("")
            lines.append("## Hot Dogs (\(hotDogs.count)/10)")
            for card in hotDogs { lines.append(card.name) }
        }
        return lines.joined(separator: "\n")
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Deck Template
// ════════════════════════════════════════════════════════════════

struct DeckTemplate: Identifiable {
    let id: String
    let name: String
    let format: DeckFormat
    let description: String
    let heroIds: [String]
    let playIds: [String]
    let bonusPlayIds: [String]
    let hotDogIds: [String]

    // Metadata for the 5 archetypes — IDs loaded from TemplateDeck.json bundle file
    private static let metadata: [(id: String, name: String, description: String)] = [
        ("fire-aggro",        "Fire Aggro",          "Aggressive tempo deck focused on Fire weapon synergies. Play fast, burn resources, win battles before your opponent can set up."),
        ("ice-control",       "Ice Control",         "Defensive control deck using Ice plays to deny your opponent's strategies and outlast them over 7 battles."),
        ("steel-wall",        "Steel Wall",           "Durable defense focused on Steel weapon cards. Build consistent power advantages with protective plays."),
        ("mixed-toolbox",     "Mixed Toolbox",        "Flexible all-elements deck with answers for every situation. Adapt to your opponent's strategy."),
        ("economy-attrition", "Economy / Attrition",  "Resource denial archetype. Starve your opponent of Hot Dogs while conserving your own."),
    ]

    // Loaded once from TemplateDeck.json bundled resource
    static let all: [DeckTemplate] = {
        guard let url = Bundle.main.url(forResource: "TemplateDeck", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: TemplateJSON].self, from: data)
        else {
            // Fallback: empty templates if bundle file is missing
            return metadata.map { meta in
                DeckTemplate(id: meta.id, name: meta.name, format: .playmaker,
                             description: meta.description, heroIds: [], playIds: [], bonusPlayIds: [], hotDogIds: [])
            }
        }
        return metadata.compactMap { meta in
            guard let t = raw[meta.id] else { return nil }
            return DeckTemplate(id: meta.id, name: meta.name, format: .playmaker,
                                description: meta.description,
                                heroIds: t.heroIds, playIds: t.playIds,
                                bonusPlayIds: t.bonusPlayIds, hotDogIds: t.hotDogIds)
        }
    }()

    private struct TemplateJSON: Decodable {
        let heroIds: [String]
        let playIds: [String]
        let bonusPlayIds: [String]
        let hotDogIds: [String]
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Array helper
// ════════════════════════════════════════════════════════════════

private extension Array where Element: Equatable {
    mutating func removeFirst(_ element: Element) {
        if let idx = firstIndex(of: element) { remove(at: idx) }
    }
}
