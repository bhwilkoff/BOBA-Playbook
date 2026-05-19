package com.bobaplaybook.app.feature.find

import androidx.compose.runtime.Immutable
import com.bobaplaybook.core.domain.model.Card
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

/**
 * Immutable, Compose-stable UI state for the Find tab.
 *
 * Single source of truth, single re-emit point. `ImmutableList` instead
 * of `List` so Compose treats it as stable (ANDROID-DEV.md §11.3).
 *
 * Search-active state vs no-search state is encoded by [isSearching];
 * the screen renders [results] when searching and the featured shelves
 * ([recentlyAdded], [heroesByWeapon], [coachingStaff]) when not.
 */
@Immutable
data class FindUiState(
    val query: String = "",
    val activeWeapon: String? = null,
    val activeTreatment: String? = null,
    val isLoading: Boolean = true,
    val results: ImmutableList<Card> = persistentListOf(),
    val suggestions: ImmutableList<SearchSuggestion> = persistentListOf(),
    val recentlyAdded: ImmutableList<Card> = persistentListOf(),
    val heroesByWeapon: ImmutableList<WeaponShelf> = persistentListOf(),
    val coachingStaff: ImmutableList<Card> = persistentListOf(),
    val totalCatalogSize: Int = 0,
) {
    val isSearching: Boolean
        get() = query.isNotBlank() || activeWeapon != null || activeTreatment != null

    val isEmpty: Boolean
        get() = !isLoading && isSearching && results.isEmpty()

    val hasFeatured: Boolean
        get() = !isLoading && recentlyAdded.isNotEmpty()
}

/**
 * Featured shelf — one weapon's representative cards. Rendered as a
 * horizontal carousel row on the no-search state.
 */
@Immutable
data class WeaponShelf(
    val weapon: String,
    val cards: ImmutableList<Card>,
)

/**
 * Live suggestion inside the expanded SearchBar content area.
 *
 *  - [Card]  — tap navigates to the card's detail
 *  - [Token] — tap commits a filter (weapon, treatment, etc.) as an
 *              InputChip inside the search field
 *
 * Matches M3 SearchBar suggestion pattern (ANDROID-DESIGN.md §7).
 */
@Immutable
sealed interface SearchSuggestion {
    @Immutable
    data class CardHit(val card: Card) : SearchSuggestion
    @Immutable
    data class Token(val kind: TokenKind, val value: String) : SearchSuggestion
}

enum class TokenKind { WEAPON, TREATMENT, SET }

/** Events the screen emits up to the ViewModel. Exhaustive sealed interface. */
sealed interface FindEvent {
    data class QueryChanged(val query: String)        : FindEvent
    data class WeaponToggled(val weapon: String?)     : FindEvent
    data class TreatmentToggled(val treatment: String?) : FindEvent
    data class SuggestionTapped(val suggestion: SearchSuggestion) : FindEvent
    data object ClearFilters                          : FindEvent
}
