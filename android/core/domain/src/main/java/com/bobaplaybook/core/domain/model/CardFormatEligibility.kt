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

/**
 * Tick 179 — positive legality answer (Discord-mined backlog #4).
 * Restrictions tell you what's BANNED; this tells you what's LEGAL.
 * Discord §11 finding: ~30-35% of rules Qs are "is this legal in Spec
 * / Spec+ / Brawl / Checklist?" — we surface a 4-chip at-a-glance strip.
 */
enum class FormatStatus { LEGAL, CONSTRAINED, ILLEGAL }

data class FormatLegality(
    val format: String,
    val status: FormatStatus,
    /** Tooltip detail explaining why constrained / illegal. Null for legal. */
    val reason: String? = null,
)

object CardFormatEligibility {

    /**
     * 4-chip strip for the card-detail header. Order matches user mental
     * model (Spec → Spec+ → Brawl → Checklist). Sealed products return
     * empty (no format meaning).
     */
    fun legalFormats(card: Card): List<FormatLegality> {
        if (card.cardType.equals("sealed_product", ignoreCase = true)) return emptyList()
        return listOf(
            specLegality(card),
            specPlusLegality(card),
            brawlLegality(card),
            checklistLegality(card),
        )
    }

    /**
     * Tick 464 — Discord backlog #4 carry-forward (per-cell badge half).
     * Returns a compact abbreviation of formats where the card is LEGAL
     * for use as a corner overlay on card cells (e.g., `"S+ C"` for a
     * card playable in Spec+ and Checklist only). Returns null when the
     * card is legal in all 4 formats — most cards — so the badge only
     * surfaces unusual cards. CONSTRAINED treated as legal (the card is
     * still playable; tiered-slot detail belongs on Card Detail).
     */
    fun restrictedLegalAbbrev(card: Card): String? {
        val chips = legalFormats(card)
        if (chips.isEmpty()) return null
        val abbrev = chips.mapNotNull { chip ->
            if (chip.status == FormatStatus.ILLEGAL) return@mapNotNull null
            when (chip.format) {
                "Spec" -> "S"
                "Spec+" -> "S+"
                "Brawl" -> "B"
                "Checklist" -> "C"
                else -> null
            }
        }
        // All 4 legal → no badge (typical 99% case).
        if (abbrev.size == 4) return null
        // No formats legal → defensive null (no useful info).
        if (abbrev.isEmpty()) return null
        return abbrev.joinToString(" ")
    }

    private fun specLegality(card: Card): FormatLegality {
        // Spec: Power ≤ 160 for Heroes. Plays / BP / HTD allowed.
        val p = if (card.isHero) card.power else null
        return when {
            p != null && p > 160 -> FormatLegality(
                "Spec", FormatStatus.ILLEGAL,
                "Power $p exceeds Spec's 160 cap."
            )
            else -> FormatLegality("Spec", FormatStatus.LEGAL)
        }
    }

    private fun specPlusLegality(card: Card): FormatLegality {
        val p = if (card.isHero) card.power else null
        return when {
            p != null && p > 200 -> FormatLegality(
                "Spec+", FormatStatus.ILLEGAL,
                "Power $p exceeds the SPEC+ 200 ceiling."
            )
            p != null && p > 160 -> FormatLegality(
                "Spec+", FormatStatus.CONSTRAINED,
                "Power $p fits SPEC+'s 165-200 tiered slots (max 1-2 per deck by power)."
            )
            else -> FormatLegality("Spec+", FormatStatus.LEGAL)
        }
    }

    private fun brawlLegality(card: Card): FormatLegality {
        val p = if (card.isHero) card.power else null
        return when {
            p != null && p > 160 -> FormatLegality(
                "Brawl", FormatStatus.ILLEGAL,
                "Power $p exceeds Brawl's 160 cap."
            )
            else -> FormatLegality("Brawl", FormatStatus.LEGAL)
        }
    }

    private fun checklistLegality(card: Card): FormatLegality {
        // Checklist accepts the broadest set; Trainer is the only known
        // restriction (banned in Elite Playmaker, not in Checklist itself).
        return FormatLegality("Checklist", FormatStatus.LEGAL)
    }

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
