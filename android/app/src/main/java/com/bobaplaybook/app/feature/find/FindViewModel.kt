package com.bobaplaybook.app.feature.find

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

/**
 * Find tab ViewModel.
 *
 * Combines [CardRepository.cards] (the live catalog) with a local query
 * + filter Flow. Debounced 100ms so typing doesn't run the filter on
 * every keystroke. Emits an immutable [FindUiState].
 *
 * Filter algorithm is intentionally simple for M1: case-insensitive
 * substring match on `hero`, `cardNumber`, `name`. The iOS app has a
 * pre-built search index for fuzzier matching — M1 ships the simple
 * algorithm because the pre-built index isn't generated yet on
 * Android. The "search-index generation on first launch" task is
 * captured in SCRATCHPAD.md for post-M1.
 */
@OptIn(FlowPreview::class, kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@HiltViewModel
class FindViewModel @Inject constructor(
    private val cardRepository: CardRepository,
) : ViewModel() {

    private val query   = MutableStateFlow("")
    private val weapon  = MutableStateFlow<String?>(null)

    /**
     * Boot phase-1 head synchronously + phase-2 full async. Mirrors
     * iOS DECISIONS.md #014. Safe to call multiple times — repository
     * short-circuits when the catalog is already loaded.
     */
    init {
        cardRepository.primeSync()
        cardRepository.primeAsync()
    }

    val uiState: StateFlow<FindUiState> =
        combine(
            cardRepository.cards,
            cardRepository.isLoading,
            query.debounce(100L).distinctUntilChanged(),
            weapon,
        ) { cards, isLoading, q, w ->
            val filtered = filter(cards, q, w)
            FindUiState(
                query = q,
                activeWeapon = w,
                isLoading = isLoading,
                results = filtered.toPersistentList(),
                totalCatalogSize = cards.size,
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = FindUiState(),
        )

    fun onEvent(event: FindEvent) {
        when (event) {
            is FindEvent.QueryChanged   -> query.value = event.query
            is FindEvent.WeaponToggled  -> weapon.update { current -> if (current == event.weapon) null else event.weapon }
            FindEvent.ClearFilters      -> { query.value = ""; weapon.value = null }
        }
    }

    /**
     * Local filter. Returns the catalog as-is when both filters are
     * blank — the no-search state shows the full grid below the
     * featured shelves, so feeding the LazyVerticalGrid every card
     * keeps it scrolling smoothly (Compose LazyGrid lazily composes
     * only the visible window).
     *
     * Cap at 500 results when the user has typed nothing — the grid
     * doesn't need 17k items materialized as composables. (Cells
     * themselves are lazy but the LazyListState is happier with a
     * bounded `items` count.)
     */
    private fun filter(cards: List<Card>, q: String, w: String?): List<Card> {
        if (q.isBlank() && w == null) {
            return cards.take(500)
        }
        val needle = q.trim().lowercase()
        return cards.asSequence()
            .filter { card ->
                (w == null || card.element.equals(w, ignoreCase = true)) &&
                (needle.isEmpty() ||
                    card.hero.lowercase().contains(needle) ||
                    card.name.lowercase().contains(needle) ||
                    card.cardNumber.lowercase().contains(needle))
            }
            .take(500)
            .toList()
    }
}
