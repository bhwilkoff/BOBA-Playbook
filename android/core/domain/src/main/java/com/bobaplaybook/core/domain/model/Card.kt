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
    val element: String,                // UPPERCASE in JSON, mixed-case in UI
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
    val radishUrl: String? = null,
    val bvUrl: String? = null,

    /** The real-world athlete this card's hero is inspired by. */
    val athleteInspiration: String? = null,

    // Play-only fields
    val persistent: List<PersistentEffectSpec> = emptyList(),
    val abilityText: String? = null,
    val bonusText: String? = null,
    val bobaIdField: String? = null,     // when present in JSON, prefer this over computed
) {
    /**
     * Canonical card identifier — matches `scripts/boba_id.py` v2 formula
     * and iOS `Card.bobaId`. CLAUDE.md "One ID per Card" — this is the
     * primary key.
     *
     * Sealed products fall back to `name` when `hero` is empty. Trailing
     * dashes are intentional and stable.
     */
    val bobaId: String
        get() = bobaIdField ?: run {
            val identifier = hero.ifEmpty { name }
            "$cardNumber-$identifier-${treatment.orEmpty()}-${variation.orEmpty()}"
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
