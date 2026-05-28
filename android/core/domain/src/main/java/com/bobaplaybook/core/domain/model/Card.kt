package com.bobaplaybook.core.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * BOBA card catalog model. Mirrors `BOBAPlaybook/Models/Card.swift`
 * field-for-field; deviations are CALLED OUT in comments.
 *
 * The catalog is bundled in `app/src/main/assets/data/cards.json` via
 * the Gradle copy task in [ANDROID-DEV.md §13.3]. ~17,974 entries
 * decode at app start in a two-phase pipeline (DECISIONS.md #014).
 *
 * `ignoreUnknownKeys = true` is set on the decoder so the catalog can
 * grow new fields without breaking the Android client (mirrors iOS
 * Codable's "extra keys are silently dropped" semantics).
 *
 * `bobaId` is computed at runtime — same 4-field formula as `scripts/
 * boba_id.py` and `Card.swift::bobaId`. Sealed Products use `name` when
 * `hero` is empty. Trailing dashes are intentional and stable. Verified
 * 17,739 unique values across the bundle on iOS.
 *
 * Don't add an Android-only field here without first proposing it for
 * the canonical schema (`docs/CARD_SCHEMA.md`). Cross-platform drift is
 * the bug.
 */
@Serializable
data class Card(
    val bvId: Int? = null,
    val cardNumber: String,
    val name: String,
    val hero: String = "",
    val cardType: String,
    // Sealed Products (Booster Box, Blaster Box, Case, etc.) have
    // `element: null` in cards.json — they're not playable cards
    // with a weapon. Without the empty-string default + the
    // `coerceInputValues = true` Json config, kotlinx.serialization
    // would fail the FIRST null-element row and abort the full
    // catalog decode — leaving the in-memory catalog stuck at the
    // 506 cards from cards-head.json. That silently dropped EVERY
    // user_cards row in the Collection JOIN because almost all real
    // cards live past the head-bundle window. Default-to-"" keeps
    // every downstream `card.element.uppercase()` / `.lowercase()`
    // call site working without a sweep; sealed-product call sites
    // already guard via `card.isSealed`.
    val element: String = "",           // UPPERCASE in JSON when present, "" for Sealed Products, mixed-case in UI
    val set: String,
    @SerialName("subSet") val subSet: String? = null,
    val treatment: String? = null,
    val variation: String? = null,
    val release: String? = null,

    // Stats
    val power: Int? = null,
    val cost: Int? = null,
    val dbs: Int? = null,                // Damage Bonus / Score (Plays only)
    val hitPoints: Int? = null,
    val hd: Int? = null,                 // Heroic Damage

    // Catalog flags
    val rarityLabel: String? = null,
    val rarityTier: String? = null,
    val rookieInspired: Boolean = false,

    // Image fields — mirrors iOS Card.imageFile being mutable for runtime
    // override (admin upload → `setAppliedOverride` → in-place mutation).
    // Kotlin data classes don't have `var` properties as ergonomic as
    // Swift; the override path is handled in the CardRepository instead
    // of mutating the model. See ANDROID-DEV.md §11.4 for the swap
    // pattern.
    val imageFile: String? = null,
    val imageSource: String? = null,
    val imageAvailable: Boolean = false,
    /**
     * Frozen legacy field — populated for cards added to the catalog
     * before 2026-05-23. Used SOLELY as the destination of the per-card
     * "View on Radish" external-link button per Radish's email-stated
     * allowance for "ordinary user-facing linking." Null for new cards;
     * the button falls back to the Radish homepage. NEVER passed to any
     * Worker / matcher / pricing lookup — that automation is prohibited.
     */
    val radishUrl: String? = null,
    val bvUrl: String? = null,
    /**
     * Card-art-OCR'd print run, populated for 464 of 17,974 catalog
     * cards (PRICING_PLAYBOOK §6.4 Feature 0). `5`, `10`, `25`, or
     * `50` typically — observed serialization, the hardest scarcity
     * signal we have. Null for the un-numbered majority. DECISIONS.md
     * #061 makes this the ONLY source of [printRunLabel] — the prior
     * weapon→count switch (#028 assumption) shipped wrong values on
     * 174+ FIRE cards because FIRE + ICE each appear at BOTH /5 AND
     * /50 in the real OCR data.
     */
    val printRun: Int? = null,

    /** The real-world athlete this card's hero is inspired by. */
    val athleteInspiration: String? = null,

    /**
     * Per-card searchable aliases — e.g. `["Skeeball"]` on Skeee cards
     * so users typing the printed-on-card name (which differs from the
     * catalog hero) still find them. Merged into the haystack at
     * search time by CardSearch.
     */
    val searchAliases: List<String>? = null,

    // Play-only fields
    val persistent: List<PersistentEffectSpec> = emptyList(),
    val abilityText: String? = null,
    val bonusText: String? = null,
    @SerialName("bobaId") val bobaIdField: String? = null,     // when present in JSON, prefer this over computed

    // Play subtype flags. iOS Card.swift lines 31-32. Used by
    // CardFormatEligibility to surface "Bonus Play" / "HTD Play" badges
    // that are toggled OFF in certain event formats (Spec Playmaker,
    // Brawl Playmaker, Tecmo Bowl).
    @SerialName("isBonusPlay") val isBonusPlay: Boolean? = null,
    @SerialName("isHTD")       val isHTD: Boolean? = null,

    /**
     * Tick 189 — Discord backlog #7. Catalog has `isInspiredInk` on
     * every card; iOS Card.swift mirrors it as a non-optional Bool.
     * Inspired Ink = Serialized variant with weapon-tied print runs
     * (Hex /5, Glow /10, Fire /25, Ice /50 per DECISIONS.md #028).
     */
    @SerialName("isInspiredInk") val isInspiredInk: Boolean = false,
) {
    /**
     * Canonical card identifier — matches `scripts/boba_id.py` v3
     * formula and iOS `Card.bobaId`. CLAUDE.md "One ID per Card" — this
     * is the primary key.
     *
     * 5-field formula:
     *   cardNumber-(hero|name)-treatment-variation-element
     *
     * The 5th field is the card's WEAPON (catalog stores it under the
     * legacy field name `element` per DECISIONS.md #027). Added
     * 2026-05-25 to disambiguate FIRE-weapon vs GLOW-weapon variant
     * siblings that share otherwise-identical (cardNumber, hero,
     * treatment, variation).
     *
     * Sealed products fall back to `name` when `hero` is empty.
     * Trailing dashes are intentional and stable.
     */
    val bobaId: String
        get() = bobaIdField ?: run {
            val identifier = hero.ifEmpty { name }
            "$cardNumber-$identifier-${treatment.orEmpty()}-${variation.orEmpty()}-$element"
        }

    /** True for sealed-product entries (no hero, has a name like "Booster Box"). */
    val isSealed: Boolean
        get() = cardType.equals("Sealed Product", ignoreCase = true) || hero.isEmpty()

    /** Card-type classifiers (mirrors iOS Card.swift). */
    val isHero: Boolean   get() = cardType.equals("Hero", ignoreCase = true)
    val isPlay: Boolean   get() = cardType.equals("Play", ignoreCase = true)
    val isHotDog: Boolean get() = cardType.equals("HotDog", ignoreCase = true) ||
                                  cardType.contains("Hot Dog", ignoreCase = true)

    /** User-facing display name. Heroes show their hero name; sealed shows product name. */
    val displayName: String
        get() = if (hero.isNotEmpty()) hero else name

    /**
     * Print-run label for cards — reads the catalog's real [printRun]
     * field (populated for 464 cards via card-art OCR; PRICING_PLAYBOOK
     * §6.4 Feature 0). Returns null when there's no OCR'd value, which
     * is most cards. The prior weapon→count switch (DECISIONS.md #028
     * assumption — FIRE→/25, ICE→/50, etc.) is retired by #061: the
     * OCR data shows FIRE + ICE each appear at BOTH /5 AND /50, so
     * the weapon→count mapping shipped wrong values on 174+ FIRE
     * cards alone. Anything not on the card art itself is a guess,
     * and we ship the truth or nothing.
     */
    val printRunLabel: String?
        get() = printRun?.takeIf { it > 0 }?.let { "/$it" }
}

/**
 * Persistent-effect spec (Play cards). Mirrors the iOS `PersistentEffect`
 * struct that DECISIONS.md #030 documents.
 *
 * Lean placeholder for now — the Practice executor (M5.5) ports the
 * full state-machine engine and will expand this.
 */
@Serializable
data class PersistentEffectSpec(
    val trigger: String,
    val scope: String? = null,
    val n: Int? = null,
    val effect: String? = null,
)
