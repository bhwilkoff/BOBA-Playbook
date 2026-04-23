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

enum CardFormatEligibility {

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
