package com.bobaplaybook.app.feature.find

import androidx.compose.runtime.Immutable
import com.bobaplaybook.core.domain.model.Card
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

/**
 * Immutable, Compose-stable UI state for the Find tab.
 *
 * One data class per screen — single source of truth, single re-emit
 * point. `ImmutableList` instead of `List` so Compose treats it as
 * stable (ANDROID-DEV.md §11.3).
 */
@Immutable
data class FindUiState(
    val query: String = "",
    val activeWeapon: String? = null,
    val isLoading: Boolean = true,
    val results: ImmutableList<Card> = persistentListOf(),
    val totalCatalogSize: Int = 0,
) {
    val isSearching: Boolean get() = query.isNotBlank() || activeWeapon != null
    val isEmpty: Boolean
        get() = !isLoading && isSearching && results.isEmpty()
}

/** Events the screen emits up to the ViewModel. Exhaustive sealed interface. */
sealed interface FindEvent {
    data class QueryChanged(val query: String)    : FindEvent
    data class WeaponToggled(val weapon: String?) : FindEvent
    data object ClearFilters                       : FindEvent
}
