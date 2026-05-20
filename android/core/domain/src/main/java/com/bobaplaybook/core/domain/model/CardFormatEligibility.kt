package com.bobaplaybook.core.domain.model

/**
 * Per-card format restrictions. Mirrors iOS
 * `BOBAPlaybook/Models/CardFormatEligibility.swift` field-for-field.
 *
 * Most cards are legal in every BoBA format — showing a row of green ✓
 * pills for the 99% case was noise. This type returns *only* the
 * exceptions: cards whose per-card properties limit where they can be
 * played. When the returned list is empty, the card-detail surface
 * renders nothing in this slot.
 *
 * Deck-level rules (DBS budget, count limits, per-power caps) remain
 * the Decks tab's legality audit — this file is strictly card-by-card.
 */
data class CardRestriction(
    val label: String,
    val detail: String,
)

object CardFormatEligibility {

    /**
     * Returns all per-card format restrictions that apply. Empty list
     * means no badge row — the default outcome for the typical Hero
     * under Power 160 or a base Play.
     */
    fun restrictions(card: Card): List<CardRestriction> {
        val out = mutableListOf<CardRestriction>()

        // Hero Power caps — the most common real restriction.
        if (card.isHero) {
            val p = card.power
            if (p != null && p > 160) {
                if (p > 200) {
                    // Covers 1/1 Supers that overshoot even the SPEC+ ceiling.
                    out += CardRestriction(
                        label = "Spec & SPEC+ ineligible",
                        detail = "Power $p exceeds the SPEC+ 200 ceiling. Apex Playmaker, Elite, and Limited still allow it.",
                    )
                } else {
                    // 161-200 — Spec-illegal, SPEC+-constrained (tiered slots).
                    out += CardRestriction(
                        label = "Spec-ineligible",
                        detail = "Power $p exceeds Spec's 160 cap. Legal in Apex Playmaker; in SPEC+ this sits in the tiered 165-200 slots (max 1-2 per deck by power).",
                    )
                }
            }
        }

        // Bonus Plays — several events toggle BP off entirely.
        if (card.isBonusPlay == true) {
            out += CardRestriction(
                label = "Bonus Play",
                detail = "Events with Bonus Plays OFF (Spec Playmaker, Brawl Playmaker) don't permit this card. Apex / AlphaTrilogy Playmaker allow it.",
            )
        }

        // Home Team Discount Plays — same shape as BP.
        if (card.isHTD == true) {
            out += CardRestriction(
                label = "HTD Play",
                detail = "Events with HTD Plays OFF (Spec Playmaker, Brawl Playmaker) don't permit this card. Tecmo Bowl omits HTDs by construction. Apex / AlphaTrilogy Playmaker allow it.",
            )
        }

        // Elite Playmaker bans Trainer cards. Forward-looking — catalog
        // doesn't tag Trainer yet, so this only fires if/when it does.
        if (card.cardType.equals("Trainer", ignoreCase = true)) {
            out += CardRestriction(
                label = "Trainer",
                detail = "Trainer cards are banned in Elite Playmaker. Other Playmaker-lineage formats accept them.",
            )
        }

        return out
    }
}
