//
//  RulePresets.swift
//  BOBAPlaybook
//
//  Loads `rule_presets.json` and exposes the 2026 Nationals event presets
//  + casual rule sets to the Deck Builder. Coaches pick a preset (or start
//  from one and customize). The validator applies the preset's format +
//  overrides + specialRules when scoring legality + DBS.
//
//  Data source: assets/data/rule_presets.json (authored from the 2026 BoBA
//  National Events DRAFT PDF; casual presets authored in-app).
//

import Foundation

// ════════════════════════════════════════════════════════════════
// MARK: - Model
// ════════════════════════════════════════════════════════════════

/// A preset rule set. Bundles a base DeckFormat + DeckRuleOverrides +
/// optional special rules (weapon/treatment/set restrictions, etc.).
struct RulePreset: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let division: String?
    let divisionPurse: Int?
    let pps: Int?                // Prize Pool Shares per entry
    let format: String           // "rookie"/"substitution"/"playmaker"/"spec"/"elite"/"specPlus"
    let description: String
    let overrides: PresetOverrides
    let specialRules: [SpecialRule]

    /// Resolve the `format` string to a DeckFormat case.
    var deckFormat: DeckFormat {
        switch format {
        case "rookie":        return .rookie
        case "substitution":  return .substitution
        case "playmaker":     return .playmaker
        case "spec":          return .spec
        case "elite":         return .elite
        case "specPlus":      return .specPlus
        case "limited":       return .limited
        default:              return .playmaker
        }
    }

    /// Turn the preset's override fields into a `DeckRuleOverrides` applied on top of the format.
    var ruleOverrides: DeckRuleOverrides {
        var out = DeckRuleOverrides()
        out.perHeroNameLimit    = overrides.perHeroNameLimit
        out.perPowerLimit       = overrides.perPowerLimit
        out.disablePerPowerLimit = overrides.disablePerPowerLimit ?? false
        out.enforceDBS          = overrides.enforceDBS
        out.dbsBudgetOverride   = overrides.dbsBudget
        out.bonusPlaysEnabled   = overrides.bonusPlaysEnabled ?? true
        out.htdPlaysEnabled     = overrides.htdPlaysEnabled ?? true
        return out
    }
}

/// JSON-shaped overrides (uses optionals so missing fields stay at format defaults).
struct PresetOverrides: Codable, Hashable {
    var perHeroNameLimit: Int?
    var perPowerLimit: Int?
    var disablePerPowerLimit: Bool?
    var enforceDBS: Bool?
    var dbsBudget: Int?
    var bonusPlaysEnabled: Bool?
    var htdPlaysEnabled: Bool?
}

/// One "extra" rule that doesn't fit in PresetOverrides — weapon restriction,
/// set filter, ownership proof, etc. Each rule declares whether it can be
/// auto-enforced or needs coach self-verification.
struct SpecialRule: Codable, Hashable, Identifiable {
    let kind: String             // discriminated-union tag
    let allowed: [String]?       // weaponRestriction / setRestriction
    let token: String?           // treatmentContains
    let scope: String?           // "heroes" / "all"
    let name: String?            // hotDogHero
    let type: String?            // bannedCardType
    let value: Int?              // overrideHeroCount / overridePerPowerLimit
    let count: Int?              // ownershipProof.count
    let description: String?     // ownershipProof / bannedCardType
    let note: String?            // human-readable caveat
    let selfVerify: Bool?

    // Identifiable — synthesize a stable id from the discriminant tag plus its payload.
    var id: String {
        var parts: [String] = [kind]
        if let v = value { parts.append(String(v)) }
        if let t = token { parts.append(t) }
        if let n = name { parts.append(n) }
        if let a = allowed { parts.append(a.joined(separator: "|")) }
        if let t = type { parts.append(t) }
        return parts.joined(separator: ":")
    }

    /// One-line label for the active-rules chip list.
    var label: String {
        switch kind {
        case "weaponRestriction":
            return "Weapons: \((allowed ?? []).joined(separator: ", "))"
        case "treatmentContains":
            let where_: String = (scope == "heroes") ? "Heroes" : "All cards"
            return "\(where_) must be \(token ?? "?") treatment"
        case "hotDogHero":
            return "All Hot Dogs must be '\(name ?? "?")'"
        case "setRestriction":
            return "Set: \((allowed ?? []).joined(separator: ", "))"
        case "ownershipProof":
            return "Ownership: \(description ?? "\(count ?? 0) unique")"
        case "bannedCardType":
            return "No \(type ?? "?") cards"
        case "overrideHeroCount":
            return "Hero count: \(value ?? 0)"
        case "overridePerPowerLimit":
            return "Max \(value ?? 0) per power"
        default:
            return kind
        }
    }

    /// True when this rule can't be machine-enforced and the coach must self-verify.
    var isSelfVerify: Bool { selfVerify == true }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Loader
// ════════════════════════════════════════════════════════════════

struct RulePresetCatalog: Codable {
    let schemaVersion: Int
    let source: String?
    let presets: [RulePreset]
    let casualPresets: [RulePreset]
}

enum RulePresets {
    private static var cached: RulePresetCatalog?

    /// Loads + caches `rule_presets.json` from the app bundle. Returns an empty
    /// catalog if the file is missing or malformed (app continues to work with
    /// the legacy format picker).
    static func load() -> RulePresetCatalog {
        if let cached = cached { return cached }
        guard let url = Bundle.main.url(forResource: "rule_presets", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            let empty = RulePresetCatalog(schemaVersion: 0, source: nil, presets: [], casualPresets: [])
            cached = empty
            return empty
        }
        let decoded = (try? JSONDecoder().decode(RulePresetCatalog.self, from: data))
            ?? RulePresetCatalog(schemaVersion: 0, source: nil, presets: [], casualPresets: [])
        cached = decoded
        return decoded
    }

    static var nationalsPresets: [RulePreset] { load().presets }
    static var casualPresets: [RulePreset]   { load().casualPresets }
    static var allPresets: [RulePreset]      { nationalsPresets + casualPresets }

    static func find(id: String) -> RulePreset? {
        allPresets.first { $0.id == id }
    }
}
