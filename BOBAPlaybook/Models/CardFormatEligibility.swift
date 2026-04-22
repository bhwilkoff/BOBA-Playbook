import Foundation

// MARK: - Per-Card Format Eligibility
//
// Coarse-grained "can this card legally appear in a deck of this format?"
// verdict. Powers the pill row on CardDetailView so coaches don't have to
// remember every format's hero-power cap. Designed as single-card checks
// only — deck-level rules (DBS budget, total-power cap, count limits)
// live on DeckBuilderStore and are enforced during deck validation.

enum CardFormatEligibility {
    enum Verdict {
        case legal                    // fits the format's per-card rules
        case warning(String)          // legal but constrained (e.g. single copy only)
        case banned(String)           // can never appear in this format
        case notApplicable            // card type has no place in this format (e.g. Play in Rookie)

        var symbol: String {
            switch self {
            case .legal:          return "checkmark"
            case .warning:        return "exclamationmark.triangle.fill"
            case .banned:         return "xmark"
            case .notApplicable:  return "minus"
            }
        }
    }

    /// The formats we want to surface on the card detail pill row. Ordered
    /// by how often the Discord corpus shows them in rules questions.
    static let surfaceFormats: [DeckFormat] = [
        .playmaker, .spec, .specPlus, .elite, .limited,
    ]

    /// Returns a verdict for a single card against a single format. Deck-
    /// level constraints (DBS budget, hero count, per-power limits) are
    /// intentionally out of scope here — this is a card-by-card answer.
    static func verdict(card: Card, format: DeckFormat) -> Verdict {
        // Sealed products + Hot Dogs — not deckable items per se.
        if card.isSealed {
            return .notApplicable
        }

        // Hero-deck checks
        if card.isHero {
            if let cap = format.heroPowerCap, let p = card.power, p > cap {
                return .banned("Hero Power \(p) exceeds \(format.displayName)'s \(cap) cap")
            }
            if let absMax = format.absoluteHeroPowerMax, let p = card.power, p > absMax {
                return .banned("Hero Power \(p) exceeds \(format.displayName)'s \(absMax) ceiling")
            }
            if format == .specPlus, let p = card.power, p > 160 {
                // Higher-power slots are capped per tier — warn, don't ban.
                if format.specPlusTieredLimits[p] != nil {
                    return .warning("Tiered-limit slot — max \(format.specPlusTieredLimits[p]!) per deck")
                }
            }
            return .legal
        }

        // Play checks
        if card.isPlay {
            if !format.needsPlaybook {
                return .notApplicable
            }
            if card.isBonusPlay == true {
                // Per current DeckFormat rules, Bonus Plays are allowed in
                // every playmaker-lineage format. If a future format bans
                // them, extend DeckFormat.bannedCardTypes accordingly.
                return .legal
            }
            // Elite bans Trainer card types (forward-looking — catalog doesn't tag yet).
            if format.bannedCardTypes.contains(card.cardType) {
                return .banned("\(card.cardType) cards are banned in \(format.displayName)")
            }
            return .legal
        }

        // Hot Dog
        if card.isHotDog {
            return format.needsHotDogs ? .legal : .notApplicable
        }

        return .legal
    }
}
