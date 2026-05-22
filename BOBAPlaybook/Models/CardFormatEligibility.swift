import Foundation

// MARK: - Per-Card Format Restrictions
//
// Most cards are legal in every format the app surfaces — showing a row
// of green ✓ pills for that 99% case was noise. This type instead
// returns *only* the exceptions: the narrow set of per-card rules where
// something about the card itself (not the deck it's going in) limits
// where it can be played. When the returned list is empty, the card
// detail view renders nothing in this slot.
//
// Deck-level rules (DBS budget, count limits, per-power caps) remain
// the Decks tab's legality audit — this file is strictly card-by-card.

struct CardRestriction: Identifiable {
    let id = UUID()
    let label: String   // Short badge text, e.g. "Spec-ineligible"
    let detail: String  // One-sentence explanation rendered beneath
}

// Tick 207 — Discord backlog #4 (positive legality answer). Restrictions
// tell you what's BANNED; this tells you what's LEGAL. Discord §11
// finding: ~30-35% of rules Qs are "is this legal in Spec / Spec+ /
// Brawl / Checklist?" — we surface a 4-chip at-a-glance strip. Closes
// the iOS half of the trio (Android tick 179, web tick 203).
enum FormatStatus {
    case legal, constrained, illegal
}

struct FormatLegality: Identifiable {
    let id = UUID()
    let format: String       // "Spec" / "Spec+" / "Brawl" / "Checklist"
    let status: FormatStatus
    let reason: String?      // Detail tooltip for constrained/illegal. nil when legal.
}

enum CardFormatEligibility {

    /// 4-chip strip for the card-detail header. Order matches the user
    /// mental model (Spec → Spec+ → Brawl → Checklist). Sealed products
    /// return empty (no format meaning).
    static func legalFormats(for card: Card) -> [FormatLegality] {
        if card.cardType.lowercased() == "sealed product" { return [] }
        return [
            specLegality(for: card),
            specPlusLegality(for: card),
            brawlLegality(for: card),
            checklistLegality(for: card),
        ]
    }

    /// Compact abbreviation of the formats where the card is LEGAL —
    /// used as a per-cell corner overlay (Android tick 464 parity /
    /// Discord backlog #4 carry-forward). Returns nil when the card is
    /// legal in all 4 formats (typical 99% case → no badge). CONSTRAINED
    /// treated as legal (the card is still playable; tier detail lives
    /// on Card Detail).
    static func restrictedLegalAbbrev(for card: Card) -> String? {
        let chips = legalFormats(for: card)
        if chips.isEmpty { return nil }
        let abbrev: [String] = chips.compactMap { chip in
            if chip.status == .illegal { return nil }
            switch chip.format {
            case "Spec":      return "S"
            case "Spec+":     return "S+"
            case "Brawl":     return "B"
            case "Checklist": return "C"
            default:          return nil
            }
        }
        if abbrev.count == 4 { return nil }   // legal everywhere → no badge
        if abbrev.isEmpty    { return nil }   // legal nowhere → defensive nil
        return abbrev.joined(separator: " ")
    }

    private static func specLegality(for card: Card) -> FormatLegality {
        let p: Int? = card.isHero ? card.power : nil
        if let p = p, p > 160 {
            return .init(format: "Spec", status: .illegal, reason: "Power \(p) exceeds Spec's 160 cap.")
        }
        return .init(format: "Spec", status: .legal, reason: nil)
    }

    private static func specPlusLegality(for card: Card) -> FormatLegality {
        let p: Int? = card.isHero ? card.power : nil
        if let p = p, p > 200 {
            return .init(format: "Spec+", status: .illegal, reason: "Power \(p) exceeds the SPEC+ 200 ceiling.")
        }
        if let p = p, p > 160 {
            return .init(format: "Spec+", status: .constrained, reason: "Power \(p) fits SPEC+'s 165-200 tiered slots (max 1-2 per deck by power).")
        }
        return .init(format: "Spec+", status: .legal, reason: nil)
    }

    private static func brawlLegality(for card: Card) -> FormatLegality {
        let p: Int? = card.isHero ? card.power : nil
        if let p = p, p > 160 {
            return .init(format: "Brawl", status: .illegal, reason: "Power \(p) exceeds Brawl's 160 cap.")
        }
        return .init(format: "Brawl", status: .legal, reason: nil)
    }

    private static func checklistLegality(for card: Card) -> FormatLegality {
        // Checklist accepts the broadest set; Trainer is the only known
        // restriction (banned in Elite Playmaker, not Checklist itself).
        return .init(format: "Checklist", status: .legal, reason: nil)
    }

    /// Returns all per-card format restrictions that apply. Empty list
    /// means no badge row — the default outcome for the typical hero
    /// under Power 160 or a base Play.
    static func restrictions(for card: Card) -> [CardRestriction] {
        var out: [CardRestriction] = []

        // Hero Power caps — the most common real restriction.
        if card.isHero, let p = card.power, p > 160 {
            if p > 200 {
                // Covers 1/1 Supers that overshoot even the SPEC+ ceiling.
                out.append(.init(
                    label: "Spec & SPEC+ ineligible",
                    detail: "Power \(p) exceeds the SPEC+ 200 ceiling. Apex Playmaker, Elite, and Limited still allow it."
                ))
            } else {
                // 161–200 — Spec-illegal, SPEC+-constrained (tiered slots).
                out.append(.init(
                    label: "Spec-ineligible",
                    detail: "Power \(p) exceeds Spec's 160 cap. Legal in Apex Playmaker; in SPEC+ this sits in the tiered 165–200 slots (max 1–2 per deck by power)."
                ))
            }
        }

        // Bonus Plays — several events toggle BP off entirely.
        if card.isBonusPlay == true {
            out.append(.init(
                label: "Bonus Play",
                detail: "Events with Bonus Plays OFF (Spec Playmaker, Brawl Playmaker) don't permit this card. Apex / AlphaTrilogy Playmaker allow it."
            ))
        }

        // Home Team Discount Plays — same shape as BP.
        if card.isHTD == true {
            out.append(.init(
                label: "HTD Play",
                detail: "Events with HTD Plays OFF (Spec Playmaker, Brawl Playmaker) don't permit this card. Tecmo Bowl omits HTDs by construction. Apex / AlphaTrilogy Playmaker allow it."
            ))
        }

        // Elite Playmaker bans Trainer cards. Forward-looking — catalog
        // doesn't tag Trainer yet, so this only fires if/when it does.
        if card.cardType == "Trainer" {
            out.append(.init(
                label: "Trainer",
                detail: "Trainer cards are banned in Elite Playmaker. Other Playmaker-lineage formats accept them."
            ))
        }

        return out
    }
}
