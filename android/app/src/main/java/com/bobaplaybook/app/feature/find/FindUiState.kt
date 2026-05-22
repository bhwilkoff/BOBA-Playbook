package com.bobaplaybook.app.feature.find

import androidx.compose.runtime.Immutable
import com.bobaplaybook.core.domain.model.Card
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.ImmutableSet
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.persistentSetOf

/**
 * Find tab UI state — mirrors iOS `CardStore` filter surface
 * verbatim. ANDROID-DESIGN.md §8.1.
 *
 * Every dimension matches the iOS SearchView + FilterSheetView so the
 * cross-platform behavior is identical:
 *   - 8 filter dimensions (purpose, showcase, elements, set, treatment,
 *     release, power range, has-image)
 *   - 9 sort orders (default → variation)
 *   - Catalog-wide search w/ alias expansion
 */
@Immutable
data class FindUiState(
    // Search
    val query: String = "",

    // Filters (mirrors CardStore — iOS field names preserved as
    // comments where Kotlin names differ for idiom).
    val activeWeapons: ImmutableSet<String> = persistentSetOf(),  // CardStore.selectedElements
    val activeTreatment: String? = null,
    val activeSet: String? = null,
    val activeRelease: String? = null,
    val powerMin: Int? = null,
    val powerMax: Int? = null,
    val hasImageOnly: Boolean = false,
    val cardPurpose: CardPurpose = CardPurpose.ALL,
    val showcaseId: String? = null,

    // Sort
    val sortOrder: SortOrder = SortOrder.DEFAULT,

    // Derived state
    val isLoading: Boolean = true,
    val results: ImmutableList<Card> = persistentListOf(),
    val suggestions: ImmutableList<SearchSuggestion> = persistentListOf(),

    // Featured shelves (no-search state when showcaseMode is on)
    val recentlyAdded: ImmutableList<Card> = persistentListOf(),
    val heroesByWeapon: ImmutableList<WeaponShelf> = persistentListOf(),
    val coachingStaff: ImmutableList<Card> = persistentListOf(),
    /** Per-showcase carousel rows — WoBA, Rookie Inspired, plus the named sports. */
    val showcaseShelves: ImmutableList<ShowcaseShelf> = persistentListOf(),

    // Available filter values from the catalog (populated by VM)
    val availableSets: ImmutableList<String> = persistentListOf(),
    val availableTreatments: ImmutableList<String> = persistentListOf(),
    val availableReleases: ImmutableList<String> = persistentListOf(),
    val availableElements: ImmutableList<String> = persistentListOf(),

    val totalCatalogSize: Int = 0,
) {
    val isSearching: Boolean
        get() = query.isNotBlank() || activeFilterCount > 0

    val isEmpty: Boolean
        get() = !isLoading && isSearching && results.isEmpty()

    val hasFeatured: Boolean
        get() = !isLoading && recentlyAdded.isNotEmpty()

    /** Active filter count for the toolbar badge. Mirrors iOS CardStore.activeFilterCount. */
    val activeFilterCount: Int
        get() = listOf(
            activeWeapons.isNotEmpty(),
            activeTreatment != null,
            activeSet != null,
            activeRelease != null,
            powerMin != null,
            powerMax != null,
            hasImageOnly,
            cardPurpose != CardPurpose.ALL,
            showcaseId != null,
        ).count { it }
}

/** Featured shelf — one weapon's representative cards. */
@Immutable
data class WeaponShelf(
    val weapon: String,
    val cards: ImmutableList<Card>,
)

/** Featured shelf — one named Showcase (WoBA, Rookie Inspired, or a sport). */
@Immutable
data class ShowcaseShelf(
    val showcaseId: String,
    val name: String,
    val cards: ImmutableList<Card>,
)

/**
 * Live suggestion inside the expanded SearchBar content area.
 *
 *  - [CardHit] — tap navigates to the card's detail
 *  - [Token]   — tap commits a filter as an InputChip
 */
@Immutable
sealed interface SearchSuggestion {
    @Immutable
    data class CardHit(val card: Card) : SearchSuggestion
    @Immutable
    data class Token(val kind: TokenKind, val value: String) : SearchSuggestion
}

enum class TokenKind { WEAPON, TREATMENT, SET }

/**
 * Card-purpose chip-row filter (iOS CardPurpose enum).
 *
 * Each value is a single-select chip in the FilterSheet.
 */
enum class CardPurpose(val label: String) {
    ALL("All"),
    HEROES("Heroes"),
    PLAYS("Plays"),
    HOT_DOGS("Hot Dogs"),
    SEALED("Sealed");
}

/**
 * Sort orders (iOS CardSortOrder).
 *
 * Defaults to has-image-first (DEFAULT). Catalog sorts that work
 * without user-collection state — Collection adds its own dimensions
 * (date added, market value, paid).
 */
enum class SortOrder(val label: String) {
    DEFAULT         ("Default (has image first)"),
    // Tick 354 — iOS v2.328 + web tick 283 parity. Reverse catalog
    // order — newer sets append, so recently-added cards bubble up.
    RECENTLY_ADDED  ("Recently Added"),
    NAME_ASC        ("Name A → Z"),
    NAME_DESC       ("Name Z → A"),
    POWER_DESC      ("Power: High → Low"),
    POWER_ASC       ("Power: Low → High"),
    NUMBER_ASC      ("Card # Ascending"),
    NUMBER_DESC     ("Card # Descending"),
    COST_ASC        ("Hot Dog Cost: Low → High"),
    COST_DESC       ("Hot Dog Cost: High → Low"),
    VARIATION       ("Variation");
}

/** Power-range presets (iOS FilterSheetView.presetRow). */
data class PowerPreset(val label: String, val min: Int?, val max: Int?) {
    companion object {
        val ANY   = PowerPreset("Any",   null, null)
        val LOW   = PowerPreset("Low",   null, 114)
        val MID   = PowerPreset("Mid",   115, 139)
        val HIGH  = PowerPreset("High",  140, 164)
        val ELITE = PowerPreset("Elite", 165, null)
        val all = listOf(ANY, LOW, MID, HIGH, ELITE)
    }
}

/** Events the screen emits up to the ViewModel. */
sealed interface FindEvent {
    data class QueryChanged       (val query: String)            : FindEvent
    data class WeaponToggled      (val weapon: String)           : FindEvent
    data class TreatmentChanged   (val treatment: String?)       : FindEvent
    data class SetChanged         (val set: String?)             : FindEvent
    data class ReleaseChanged     (val release: String?)         : FindEvent
    data class PowerMinChanged    (val min: Int?)                : FindEvent
    data class PowerMaxChanged    (val max: Int?)                : FindEvent
    data class PowerPresetApplied (val preset: PowerPreset)      : FindEvent
    data class HasImageToggled    (val enabled: Boolean)         : FindEvent
    data class CardPurposeChanged (val purpose: CardPurpose)     : FindEvent
    data class ShowcaseChanged    (val showcaseId: String?)      : FindEvent
    data class SortChanged        (val sort: SortOrder)          : FindEvent
    data class SuggestionTapped   (val suggestion: SearchSuggestion) : FindEvent
    data object ClearAllFilters                                   : FindEvent
}
