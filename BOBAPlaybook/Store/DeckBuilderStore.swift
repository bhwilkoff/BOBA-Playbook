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

/// Hero deck rules for a game mode (per 2026 BoBA Nationals PDF).
///
/// Four "hero deck formats" from the PDF (Apex / Spec / Elite / SPEC+) compose
/// with three game modes (Rookie / Substitution / Playmaker) to produce the
/// division-specific rules used in the app. The raw values keep their legacy
/// spellings so saved-deck rows in Supabase continue to decode.
enum DeckFormat: String, CaseIterable, Identifiable, Codable {
    case rookie        = "Rookie"
    case substitution  = "Substitution"
    case playmaker     = "Playmaker"          // = "Apex Playmaker" (Apex hero rules)
    case spec          = "SPEC Playmaker"      // Spec hero rules
    case elite         = "Elite Playmaker"     // 8,250 total power cap, Trainer-banned
    case specPlus      = "SPEC+ Playmaker"     // Up to 70 heroes with tiered 175-200 limits
    case limited       = "Limited"

    var id: String { rawValue }

    /// What shows in the UI picker and stat bars.
    var displayName: String {
        switch self {
        case .rookie:       return "Rookie"
        case .substitution: return "Substitution"
        case .playmaker:    return "Apex Playmaker"
        case .spec:         return "Spec Playmaker"
        case .elite:        return "Elite Playmaker"
        case .specPlus:     return "SPEC+ Playmaker"
        case .limited:      return "Limited"
        }
    }

    // MARK: - Hero-deck shape

    /// Minimum number of heroes required for a legal deck.
    var heroMinimum: Int {
        switch self {
        case .limited:  return 40
        case .specPlus: return 60  // 60 ≤160 floor; +10 optional higher slots
        default:        return 60
        }
    }

    /// Maximum heroes allowed. SPEC+ is the only format that goes above 60.
    var heroMaximum: Int {
        switch self {
        case .limited:  return 40
        case .specPlus: return 70
        default:        return 60
        }
    }

    /// Target count shown in the UI (same as minimum for most formats; SPEC+
    /// shows minimum since the extra 10 are optional).
    var heroTarget: Int { heroMinimum }

    // MARK: - Game-mode shape

    var needsHotDogs: Bool { self != .rookie }
    var needsPlaybook: Bool { self != .rookie && self != .substitution }

    // MARK: - Power rules

    /// Per-hero power ceiling. Spec = 160. SPEC+ base 60 heroes are 160; the
    /// optional extras can be 165–200. Apex/Elite/Playmaker/Rookie/Sub: nil.
    var heroPowerCap: Int? {
        self == .spec ? 160 : nil
    }

    /// Only Elite enforces a total-power budget across all heroes (8,250).
    var totalPowerCap: Int? {
        self == .elite ? 8_250 : nil
    }

    /// Ceiling above which no hero is allowed, even in SPEC+. 200 for SPEC+, nil elsewhere.
    var absoluteHeroPowerMax: Int? {
        self == .specPlus ? 200 : nil
    }

    /// Default per-power-value limit. Standard is 6 across all formats (the
    /// 2026 PDF only overrides this for the Blast division at 3; that
    /// override lives on DeckDivision, not DeckFormat).
    var perPowerDefaultLimit: Int { 6 }

    /// SPEC+ "higher-power" tiered limits: max N of each power value in the
    /// optional 10-slot overflow above 160. Empty for other formats.
    var specPlusTieredLimits: [Int: Int] {
        guard self == .specPlus else { return [:] }
        return [
            165: 2, 170: 2,
            175: 1, 180: 1, 185: 1, 190: 1, 195: 1, 200: 1,
        ]
    }

    // MARK: - Playbook rules

    /// Apex/Spec/Elite/SPEC+/Limited all enforce 1,000 DBS. Rookie/Sub don't have Plays.
    var enforcesDBS: Bool { needsPlaybook }
    var dbsBudget: Int { 1_000 }

    // MARK: - Banned types

    /// Elite bans Trainer cards (the pre-built Battle Trainer Kit decks).
    /// Catalog doesn't currently tag Trainer cards, so this is forward-looking.
    var bannedCardTypes: Set<String> {
        self == .elite ? ["Trainer"] : []
    }

    // MARK: - Back-compat convenience

    /// True when any hero power cap applies (existing callers expect this).
    var enforcesPowerCap: Bool { heroPowerCap != nil || absoluteHeroPowerMax != nil }
    var powerCap: Int { heroPowerCap ?? absoluteHeroPowerMax ?? .max }
    var hasSideboard: Bool { self == .spec || self == .specPlus }

    var supabaseValue: String {
        switch self {
        case .rookie:       return "rookie"
        case .substitution: return "substitution"
        case .playmaker:    return "playmaker"
        case .spec:         return "spec"
        case .elite:        return "elite"
        case .specPlus:     return "spec_plus"
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
// MARK: - Optional Rule Overrides
// ════════════════════════════════════════════════════════════════

/// User-toggleable rules that overlay on top of a `DeckFormat`'s defaults.
/// Lets a Coach build under a custom rule set — e.g. turn the retired
/// "max 6 of same hero name" rule back on for casual play, or flip Bonus
/// Plays / HTD Plays off to match a specific event configuration.
///
/// Every property here corresponds to one "rule chip" surfaced in the UI,
/// so coaches can see at a glance exactly what they're building under.
struct DeckRuleOverrides: Equatable, Codable {
    /// Max copies of the same hero NAME (across variations). The 2026 BoBA
    /// Nationals PDF retired this rule — "Unlimited Versions of a Hero Per
    /// Deck" — but it remains available as an optional casual-play rule.
    /// `nil` means no enforcement (current PDF default).
    var perHeroNameLimit: Int? = nil

    /// Override the default 6-per-power-value. Blast division uses 3.
    /// `nil` defers to `DeckFormat.perPowerDefaultLimit`.
    var perPowerLimit: Int? = nil

    /// If true, validator flags the 6-per-power rule as disabled. Edge case
    /// for casual "no rules" decks; mostly here for completeness.
    var disablePerPowerLimit: Bool = false

    /// Turn the Playmaker-division DBS budget (1,000) on/off. `nil` defers
    /// to `DeckFormat.enforcesDBS`. Note: Rookie/Sub formats have no plays
    /// so DBS is N/A regardless.
    var enforceDBS: Bool? = nil
    var dbsBudgetOverride: Int? = nil

    /// Per-event toggles that materially affect deck-building. Per the 2026
    /// PDF, some events turn these off (Spec Playmaker: Bonus OFF, HTD OFF;
    /// Brawl Playmaker: Bonus OFF, HTD OFF; Tecmo Bowl: HTD N/A).
    var bonusPlaysEnabled: Bool = true
    var htdPlaysEnabled: Bool = true

    /// Whether the validator was manually configured by the user vs. left
    /// at the format's defaults. Purely informational for the UI chip list.
    var hasAnyUserOverride: Bool {
        perHeroNameLimit != nil
            || perPowerLimit != nil
            || disablePerPowerLimit
            || enforceDBS != nil
            || dbsBudgetOverride != nil
            || !bonusPlaysEnabled
            || !htdPlaysEnabled
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

    /// Toggleable rules stacked on top of the format's defaults. Lets coaches
    /// opt in to retired rules (e.g. legacy 6-per-hero) or flip off divisions'
    /// default toggles (Bonus Plays, HTD Plays) while staying inside the same
    /// hero-deck format.
    var ruleOverrides: DeckRuleOverrides = DeckRuleOverrides()

    /// Currently-selected rule preset. nil means the coach is building under
    /// the raw `format` defaults without a named preset attached.
    var activePresetID: String?
    var activePreset: RulePreset? {
        guard let id = activePresetID else { return nil }
        return RulePresets.find(id: id)
    }

    /// Load a preset: overrides + format get pushed to the store so every
    /// subsequent validation runs against the preset's rules. SpecialRules
    /// flow through `activePreset?.specialRules` and are evaluated by the
    /// validator (see extension below).
    func applyPreset(_ preset: RulePreset) {
        activePresetID = preset.id
        format = preset.deckFormat
        ruleOverrides = preset.ruleOverrides
    }

    /// Clear the active preset. Keeps the current format + overrides intact —
    /// the coach has effectively turned the preset into a "custom" rule set.
    func unlinkFromPreset() {
        activePresetID = nil
    }

    /// True when the coach has modified the rule overrides so they diverge
    /// from the active preset's baseline (or if no preset is attached and
    /// any non-default override is set). Drives the "Custom Rule Set"
    /// indicator in the UI.
    var isCustomRuleSet: Bool {
        if let preset = activePreset {
            return ruleOverrides != preset.ruleOverrides
        }
        return ruleOverrides.hasAnyUserOverride
    }

    /// Effective per-power limit after merging format default + user override.
    var effectivePerPowerLimit: Int? {
        if ruleOverrides.disablePerPowerLimit { return nil }
        return ruleOverrides.perPowerLimit ?? format.perPowerDefaultLimit
    }

    /// Effective DBS enforcement flag.
    var effectiveEnforceDBS: Bool {
        ruleOverrides.enforceDBS ?? format.enforcesDBS
    }

    /// Effective DBS budget (only used when enforcement is on).
    var effectiveDBSBudget: Int {
        ruleOverrides.dbsBudgetOverride ?? format.dbsBudget
    }

    /// A human-readable description of every rule active for the current
    /// deck. Shown in the UI so coaches see exactly what constraints they're
    /// building under. Rules carry an `isOverride` flag so the UI can mark
    /// which come from user toggles vs. the format's defaults.
    struct RuleDescriptor: Identifiable {
        let id = UUID()
        let label: String
        let isOverride: Bool  // true when the rule differs from the format default
    }
    var activeRules: [RuleDescriptor] {
        var out: [RuleDescriptor] = []

        // Hero count
        if format.heroMinimum == format.heroMaximum {
            out.append(.init(label: "\(format.heroMinimum) Heroes", isOverride: false))
        } else {
            out.append(.init(label: "\(format.heroMinimum)–\(format.heroMaximum) Heroes", isOverride: false))
        }

        // Per-power limit (default vs override)
        if let limit = effectivePerPowerLimit {
            let isOverride = ruleOverrides.perPowerLimit != nil && ruleOverrides.perPowerLimit != format.perPowerDefaultLimit
            out.append(.init(label: "Max \(limit) per power value", isOverride: isOverride))
        } else if ruleOverrides.disablePerPowerLimit {
            out.append(.init(label: "No per-power limit", isOverride: true))
        }

        // Power caps
        if let cap = format.heroPowerCap {
            out.append(.init(label: "Heroes ≤ \(cap) power", isOverride: false))
        }
        if let total = format.totalPowerCap {
            out.append(.init(label: "Total power ≤ \(total)", isOverride: false))
        }
        if let absMax = format.absoluteHeroPowerMax {
            out.append(.init(label: "No heroes above \(absMax) power", isOverride: false))
        }
        if !format.specPlusTieredLimits.isEmpty {
            out.append(.init(label: "SPEC+ tiered slots (1×175-200, 2×165/170)", isOverride: false))
        }

        // Optional 6-per-hero rule
        if let limit = ruleOverrides.perHeroNameLimit {
            out.append(.init(label: "Max \(limit) of same hero (optional)", isOverride: true))
        }

        // Banned types
        if !format.bannedCardTypes.isEmpty {
            out.append(.init(label: "No \(format.bannedCardTypes.sorted().joined(separator: ", ")) cards", isOverride: false))
        }

        // Playbook + DBS
        if format.needsPlaybook {
            if effectiveEnforceDBS {
                let isOverride = ruleOverrides.enforceDBS == true && !format.enforcesDBS
                    || ruleOverrides.dbsBudgetOverride != nil
                out.append(.init(label: "\(effectiveDBSBudget) DBS budget", isOverride: isOverride))
            } else if format.enforcesDBS && ruleOverrides.enforceDBS == false {
                out.append(.init(label: "DBS enforcement OFF", isOverride: true))
            }
            out.append(.init(label: ruleOverrides.bonusPlaysEnabled ? "Bonus Plays ON" : "Bonus Plays OFF",
                             isOverride: !ruleOverrides.bonusPlaysEnabled))
            out.append(.init(label: ruleOverrides.htdPlaysEnabled ? "HTD Plays ON" : "HTD Plays OFF",
                             isOverride: !ruleOverrides.htdPlaysEnabled))
        }

        // Unique-variation rule is always on (didn't get retired in 2026)
        out.append(.init(label: "One-of per exact card", isOverride: false))

        return out
    }

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

    /// Total DBS across the Playbook (main + bonus plays). Budget is 1,000
    /// for all Playmaker divisions per the 2026 Nationals ruleset.
    var totalDBS: Int {
        var total = 0
        for card in plays { total += (card.dbs ?? 0) }
        for card in bonusPlays { total += (card.dbs ?? 0) }
        return total
    }

    /// DBS-per-tier breakdown for the Playbook (main + bonus). Nil values skipped.
    var dbsTierCounts: [String: Int] {
        var buckets: [String: Int] = [:]
        for c in plays + bonusPlays {
            guard let t = c.dbsTier else { continue }
            buckets[t, default: 0] += 1
        }
        return buckets
    }

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

        // Hero count: must fall within [minimum, maximum] for the chosen format.
        // For SPEC+ the range is [60, 70] (60 ≤160 base + up to 10 higher-power).
        if heroes.count < format.heroMinimum {
            errors.append(.init(section: .hero, message: "Need \(format.heroMinimum - heroes.count) more heroes (\(heroes.count)/\(format.heroMinimum))"))
        } else if heroes.count > format.heroMaximum {
            let over = heroes.count - format.heroMaximum
            errors.append(.init(section: .hero, message: "Too many heroes (\(heroes.count)/\(format.heroMaximum)) — remove \(over)"))
        }

        // Per-hero power cap (Spec: 160; SPEC+: the 60-hero base must be ≤160)
        if let cap = format.heroPowerCap {
            let overBase: Int
            if format == .specPlus {
                // In SPEC+ the FIRST 60 heroes form the Spec base and must be ≤160;
                // the remaining up-to-10 can go higher (subject to tiered limits below).
                let sorted = heroes.sorted { ($0.power ?? 0) < ($1.power ?? 0) }
                let base = sorted.prefix(60)
                overBase = base.filter { ($0.power ?? 0) > cap }.count
            } else {
                overBase = heroes.filter { ($0.power ?? 0) > cap }.count
            }
            if overBase > 0 {
                errors.append(.init(section: .hero, message: "\(overBase) hero(es) over power cap \(cap)"))
            }
        }

        // Absolute hero power ceiling (SPEC+: no heroes above 200)
        if let absMax = format.absoluteHeroPowerMax {
            let over = heroes.filter { ($0.power ?? 0) > absMax }.count
            if over > 0 {
                errors.append(.init(section: .hero, message: "\(over) hero(es) above the \(absMax) ceiling"))
            }
        }

        // Elite: total-power budget across the whole hero deck
        if let totalCap = format.totalPowerCap {
            let total = heroes.reduce(0) { $0 + ($1.power ?? 0) }
            if total > totalCap {
                errors.append(.init(section: .hero, message: "Total power \(total)/\(totalCap) — over budget by \(total - totalCap)"))
            }
        }

        // SPEC+ tiered per-power limits for the optional 10 higher-power slots
        if !format.specPlusTieredLimits.isEmpty {
            for (power, limit) in format.specPlusTieredLimits {
                let count = heroPowerValues[power] ?? 0
                if count > limit {
                    errors.append(.init(section: .hero, message: "SPEC+ allows \(limit) hero(es) at power \(power); have \(count)"))
                }
            }
        }

        // Per-power-value limit. Default 6; Blast division uses 3. Users can
        // also disable the rule entirely via ruleOverrides.disablePerPowerLimit.
        let tieredPowers = Set(format.specPlusTieredLimits.keys)
        if let perPowerLimit = effectivePerPowerLimit {
            // Skip standard limit at SPEC+ tiered powers — stricter caps already applied.
            for (power, count) in heroPowerValues where !tieredPowers.contains(power) && count > perPowerLimit {
                errors.append(.init(section: .hero, message: "Power \(power): \(count)/\(perPowerLimit) — remove \(count - perPowerLimit) card(s)"))
            }
        }

        // 4-attribute uniqueness: no two cards share hero+treatment+element+power
        // (the "one of" exact-card rule that survived the 2026 PDF update).
        var seen: Set<String> = []
        for card in heroes {
            let key = "\(card.hero)|\(card.treatment ?? "")|\(card.element)|\(card.power ?? 0)"
            if seen.contains(key) {
                errors.append(.init(section: .hero, message: "Duplicate variation: \(card.hero) (\(card.treatment ?? "Base"), \(card.element), \(card.power ?? 0))"))
            }
            seen.insert(key)
        }
        // The 2026 PDF retired the mandatory "max 6 of same hero name" rule
        // ("Unlimited Versions of a Hero Per Deck"). It's still available as
        // an opt-in rule via ruleOverrides.perHeroNameLimit for casual play
        // or legacy-format decks.
        if let limit = ruleOverrides.perHeroNameLimit {
            var heroCounts: [String: Int] = [:]
            for card in heroes { heroCounts[card.hero, default: 0] += 1 }
            for (hero, count) in heroCounts where count > limit {
                errors.append(.init(section: .hero, message: "\(hero): \(count)/\(limit) max (optional rule) — remove \(count - limit)"))
            }
        }

        // Banned card types (Elite: Trainer cards not legal)
        if !format.bannedCardTypes.isEmpty {
            let banned = heroes.filter { format.bannedCardTypes.contains($0.cardType) }
            if !banned.isEmpty {
                let typeList = Array(format.bannedCardTypes).joined(separator: ", ")
                errors.append(.init(section: .hero, message: "\(banned.count) banned card(s): \(typeList) not legal in this format"))
            }
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

        // DBS budget (Playmaker divisions only). Enforcement + budget honor
        // per-deck overrides so e.g. Spec Playmaker at 1,000 DBS can turn into
        // a "Spec Unlimited" casual build by flipping enforceDBS off.
        if effectiveEnforceDBS && format.needsPlaybook && !plays.isEmpty {
            let budget = effectiveDBSBudget
            let over = totalDBS - budget
            if over > 0 {
                errors.append(.init(section: .play, message: "Playbook over DBS budget: \(totalDBS)/\(budget) — reduce by \(over)"))
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

        // Preset-driven special rules (weapon restriction, treatment filter, etc.)
        errors.append(contentsOf: specialRuleErrors)

        return errors
    }

    /// Evaluate the current active preset's specialRules (if any) against the
    /// deck. Self-verify rules surface as informational — the validator
    /// doesn't block on them, but they still render in the rule-set UI.
    private var specialRuleErrors: [DeckValidationError] {
        guard let preset = activePreset else { return [] }
        var errors: [DeckValidationError] = []
        for rule in preset.specialRules {
            if rule.isSelfVerify { continue }  // skip — handled in UI as informational
            switch rule.kind {
            case "weaponRestriction":
                let allowed = Set(rule.allowed ?? [])
                let bad = heroes.filter { !allowed.contains($0.element) }
                if !bad.isEmpty {
                    errors.append(.init(section: .hero, message: "\(bad.count) hero(es) outside allowed weapons: \(allowed.sorted().joined(separator: ", "))"))
                }
            case "treatmentContains":
                let token = rule.token ?? ""
                let scope = rule.scope ?? "heroes"
                let offenders: [Card]
                if scope == "all" {
                    offenders = (heroes + hotDogs).filter { !( ($0.treatment ?? "").contains(token) ) }
                } else {
                    offenders = heroes.filter { !( ($0.treatment ?? "").contains(token) ) }
                }
                if !offenders.isEmpty {
                    errors.append(.init(section: .hero, message: "\(offenders.count) card(s) missing '\(token)' treatment"))
                }
            case "hotDogHero":
                let required = rule.name ?? ""
                let bad = hotDogs.filter { $0.hero != required }
                if !bad.isEmpty {
                    errors.append(.init(section: .hotDog, message: "\(bad.count) hot dog(s) not '\(required)'"))
                }
            case "setRestriction":
                let allowed = Set(rule.allowed ?? [])
                let bad = (heroes + plays + bonusPlays + hotDogs).filter { !allowed.contains($0.set) }
                if !bad.isEmpty {
                    errors.append(.init(section: .hero, message: "\(bad.count) card(s) outside allowed set(s): \(allowed.sorted().joined(separator: ", "))"))
                }
            case "overrideHeroCount":
                // Reported as "right count" via format.heroMinimum override;
                // here we just check the deck actually matches this target.
                if let target = rule.value, heroes.count != target {
                    let diff = target - heroes.count
                    if diff > 0 {
                        errors.append(.init(section: .hero, message: "Division requires \(target) heroes (need \(diff) more)"))
                    } else {
                        errors.append(.init(section: .hero, message: "Division requires \(target) heroes (remove \(-diff))"))
                    }
                }
            default:
                break  // Other rule kinds are informational-only for now
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
    ///
    /// Checks per-hero power cap, absolute power ceiling, per-power limit
    /// (including SPEC+ tiered 175-200/165-170 slots), exact-variation
    /// uniqueness, and banned card types. The 2026 PDF retired the old
    /// "max 6 of same hero name" rule — only the exact-card uniqueness
    /// constraint survives.
    func heroWouldViolate(_ card: Card) -> Bool {
        guard let power = card.power else { return true }

        // Exact-variation uniqueness (the "one of" rule)
        if heroes.contains(card) { return true }

        // Banned card types
        if format.bannedCardTypes.contains(card.cardType) { return true }

        // Per-hero power cap (Spec: 160; SPEC+: only if adding into the base 60)
        if let cap = format.heroPowerCap, power > cap {
            if format == .specPlus {
                // In SPEC+ the ≤160 heroes fill the base 60; over-160 goes to the
                // tiered overflow slots. Only block if power > cap AND the tiered
                // limit at this power is already exhausted (or power > absoluteMax).
                let tieredLimit = format.specPlusTieredLimits[power]
                if tieredLimit == nil { return true }            // e.g. power 162 — not on the ladder
                if (heroPowerValues[power] ?? 0) >= (tieredLimit ?? 0) { return true }
            } else {
                return true
            }
        }

        // Absolute ceiling
        if let absMax = format.absoluteHeroPowerMax, power > absMax { return true }

        // Elite: total-power budget would be exceeded by adding this card
        if let totalCap = format.totalPowerCap {
            let newTotal = heroes.reduce(0) { $0 + ($1.power ?? 0) } + power
            if newTotal > totalCap { return true }
        }

        // Per-power-value limit (tiered powers already checked above for SPEC+)
        let tieredPowers = Set(format.specPlusTieredLimits.keys)
        if !tieredPowers.contains(power), let perPowerLimit = effectivePerPowerLimit {
            if (heroPowerValues[power] ?? 0) >= perPowerLimit { return true }
        }

        // Optional 6-per-hero-name rule (retired by default; opt-in via ruleOverrides).
        if let limit = ruleOverrides.perHeroNameLimit {
            let sameName = heroes.filter { $0.hero == card.hero }.count
            if sameName >= limit { return true }
        }

        // Hero-max check (Limited: 40, others: 60 or 70 for SPEC+)
        if heroes.count >= format.heroMaximum { return true }

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

    // MARK: - Draft persistence (local)
    //
    // Every time the deck builder disappears we snapshot the in-progress deck
    // to UserDefaults. When the builder reappears we auto-restore silently,
    // so coaches can wander off and come back without losing work. The draft
    // is separate from Supabase saved decks — saving to cloud doesn't clear
    // it, and loading a saved deck overwrites it.

    struct DraftSnapshot: Codable {
        let deckName: String
        let format: String               // supabaseValue (slug)
        let activePresetID: String?
        let ruleOverrides: DeckRuleOverrides
        let heroBobaIds: [String]
        let playBobaIds: [String]
        let bonusPlayBobaIds: [String]
        let hotDogBobaIds: [String]
        let sideboardBobaIds: [String]
        let currentDeckId: UUID?
        let savedAt: Date
    }

    private static let draftKey = "bp_deckDraft_v1"

    /// True when a non-empty draft exists on disk — used to decide whether
    /// the splash "Build Custom Deck" screen should show.
    static func hasSavedDraft() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: draftKey),
              let snap = try? JSONDecoder().decode(DraftSnapshot.self, from: data) else { return false }
        return !snap.heroBobaIds.isEmpty || !snap.playBobaIds.isEmpty
            || !snap.bonusPlayBobaIds.isEmpty || !snap.hotDogBobaIds.isEmpty
    }

    /// Serialize the current deck to UserDefaults. No-op for empty decks
    /// (avoids "resuming" an empty deck on the next open).
    func saveDraft() {
        let empty = heroes.isEmpty && plays.isEmpty && bonusPlays.isEmpty && hotDogs.isEmpty
        if empty {
            discardDraft()
            return
        }
        let snap = DraftSnapshot(
            deckName: deckName,
            format: format.supabaseValue,
            activePresetID: activePresetID,
            ruleOverrides: ruleOverrides,
            heroBobaIds: heroes.map(\.id),
            playBobaIds: plays.map(\.id),
            bonusPlayBobaIds: bonusPlays.map(\.id),
            hotDogBobaIds: hotDogs.map(\.id),
            sideboardBobaIds: sideboard.map(\.id),
            currentDeckId: currentDeckId,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.draftKey)
        }
    }

    /// Restore the last draft (if any). Returns true when a draft was
    /// applied, so callers can decide whether to skip the splash screen.
    @discardableResult
    func restoreDraft(allCards: [Card]) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let snap = try? JSONDecoder().decode(DraftSnapshot.self, from: data) else { return false }
        let byId = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
        deckName = snap.deckName
        if let f = DeckFormat.allCases.first(where: { $0.supabaseValue == snap.format }) {
            format = f
        }
        activePresetID = snap.activePresetID
        ruleOverrides = snap.ruleOverrides
        heroes = snap.heroBobaIds.compactMap { byId[$0] }
        plays = snap.playBobaIds.compactMap { byId[$0] }
        bonusPlays = snap.bonusPlayBobaIds.compactMap { byId[$0] }
        hotDogs = snap.hotDogBobaIds.compactMap { byId[$0] }
        sideboard = snap.sideboardBobaIds.compactMap { byId[$0] }
        currentDeckId = snap.currentDeckId
        return !heroes.isEmpty || !plays.isEmpty || !bonusPlays.isEmpty || !hotDogs.isEmpty
    }

    func discardDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
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
