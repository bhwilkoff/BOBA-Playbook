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
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

/**
 * Find tab ViewModel.
 *
 * Combines [CardRepository.cards] (the live catalog) with local query +
 * filter Flows. Debounced 100ms so typing doesn't run the filter on
 * every keystroke. Emits an immutable [FindUiState].
 *
 * Featured shelves (no-search state) are precomputed once the catalog
 * lands and re-emit only when the catalog itself changes (mod override
 * etc.). Search results, suggestions, and counts re-emit on every
 * query/filter change.
 */
@OptIn(FlowPreview::class, kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@HiltViewModel
class FindViewModel @Inject constructor(
    private val cardRepository: CardRepository,
) : ViewModel() {

    private val query      = MutableStateFlow("")
    private val weapon     = MutableStateFlow<String?>(null)
    private val treatment  = MutableStateFlow<String?>(null)

    private val canonicalWeapons = listOf(
        "FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER",
    )

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
            combine(weapon, treatment) { w, t -> w to t },
        ) { cards, isLoading, q, (w, t) ->
            val needle = q.trim()
            val filtered = filter(cards, needle, w, t)
            val featured = if (cards.isEmpty()) FeaturedShelves.EMPTY
                           else FeaturedShelves.build(cards)
            FindUiState(
                query = q,
                activeWeapon = w,
                activeTreatment = t,
                isLoading = isLoading,
                results = filtered.toPersistentList(),
                suggestions = buildSuggestions(cards, needle).toPersistentList(),
                recentlyAdded = featured.recentlyAdded,
                heroesByWeapon = featured.heroesByWeapon,
                coachingStaff = featured.coachingStaff,
                totalCatalogSize = cards.size,
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = FindUiState(),
        )

    fun onEvent(event: FindEvent) {
        when (event) {
            is FindEvent.QueryChanged       -> query.value = event.query
            is FindEvent.WeaponToggled      -> weapon.update { c -> if (c == event.weapon) null else event.weapon }
            is FindEvent.TreatmentToggled   -> treatment.update { c -> if (c == event.treatment) null else event.treatment }
            is FindEvent.SuggestionTapped   -> handleSuggestion(event.suggestion)
            FindEvent.ClearFilters          -> {
                query.value = ""
                weapon.value = null
                treatment.value = null
            }
        }
    }

    private fun handleSuggestion(suggestion: SearchSuggestion) {
        when (suggestion) {
            is SearchSuggestion.CardHit -> {
                // Screen handles navigation; ViewModel just clears the query
                // so we return to the no-search state when the user comes back.
                query.value = ""
            }
            is SearchSuggestion.Token -> {
                when (suggestion.kind) {
                    TokenKind.WEAPON    -> weapon.value = suggestion.value
                    TokenKind.TREATMENT -> treatment.value = suggestion.value
                    TokenKind.SET       -> { /* future: set filter */ }
                }
                query.value = ""
            }
        }
    }

    /**
     * Local filter. Returns the catalog as-is (capped 500) when no
     * filters are active.
     */
    private fun filter(cards: List<Card>, q: String, w: String?, t: String?): List<Card> {
        if (q.isBlank() && w == null && t == null) {
            return cards.take(500)
        }
        val needle = q.lowercase()
        return cards.asSequence()
            .filter { card ->
                (w == null || card.element.equals(w, ignoreCase = true)) &&
                (t == null || card.treatment.equals(t, ignoreCase = true)) &&
                (needle.isEmpty() ||
                    card.hero.lowercase().contains(needle) ||
                    card.name.lowercase().contains(needle) ||
                    card.cardNumber.lowercase().contains(needle))
            }
            .take(500)
            .toList()
    }

    /**
     * Build live suggestions inside the expanded SearchBar. Up to 8
     * mixed token + card suggestions ranked by:
     *  1. Exact weapon-name match → Token
     *  2. Exact treatment-name match → Token
     *  3. Card hits (hero / name / cardNumber prefix)
     */
    private fun buildSuggestions(cards: List<Card>, needle: String): List<SearchSuggestion> {
        if (needle.isBlank() || needle.length < 2) return emptyList()
        val n = needle.lowercase()
        val out = mutableListOf<SearchSuggestion>()

        canonicalWeapons.firstOrNull { it.lowercase().startsWith(n) }?.let {
            out += SearchSuggestion.Token(TokenKind.WEAPON, it)
        }

        val treatments = cards.asSequence()
            .mapNotNull { it.treatment }
            .distinct()
            .filter { it.lowercase().startsWith(n) }
            .take(2)
            .toList()
        treatments.forEach { out += SearchSuggestion.Token(TokenKind.TREATMENT, it) }

        cards.asSequence()
            .filter { card ->
                card.hero.lowercase().startsWith(n) ||
                card.name.lowercase().startsWith(n) ||
                card.cardNumber.lowercase().startsWith(n)
            }
            .take(8 - out.size)
            .forEach { out += SearchSuggestion.CardHit(it) }

        return out
    }
}

/**
 * Featured-shelf precomputation. Stable across query changes; only
 * recomputes when the catalog itself swaps (head → full, or override).
 *
 * Currently builds three shelves:
 *  - Recently Added — last 24 cards in catalog order (catalog is
 *    insertion-ordered by release date in the reconciliation pipeline,
 *    so "last N" is a reasonable proxy until we have a real
 *    `releaseDate` field)
 *  - Heroes by Weapon — one carousel row per weapon (8 weapons), each
 *    with up to 12 cards
 *  - Coaching Staff — cards with cardType containing "Coach"
 */
private data class FeaturedShelves(
    val recentlyAdded: kotlinx.collections.immutable.ImmutableList<Card>,
    val heroesByWeapon: kotlinx.collections.immutable.ImmutableList<WeaponShelf>,
    val coachingStaff: kotlinx.collections.immutable.ImmutableList<Card>,
) {
    companion object {
        val EMPTY = FeaturedShelves(
            recentlyAdded = persistentListOf(),
            heroesByWeapon = persistentListOf(),
            coachingStaff = persistentListOf(),
        )

        fun build(cards: List<Card>): FeaturedShelves {
            val withArt = cards.filter { !it.imageFile.isNullOrEmpty() }
            val canonicalWeapons = listOf("FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER")
            return FeaturedShelves(
                recentlyAdded = withArt.takeLast(24).reversed().toPersistentList(),
                heroesByWeapon = canonicalWeapons.map { w ->
                    WeaponShelf(
                        weapon = w,
                        cards = withArt.asSequence()
                            .filter { it.element.equals(w, ignoreCase = true) }
                            .take(12)
                            .toList()
                            .toPersistentList(),
                    )
                }.filter { it.cards.isNotEmpty() }
                  .toPersistentList(),
                coachingStaff = withArt.asSequence()
                    .filter { it.cardType.contains("Coach", ignoreCase = true) }
                    .take(20)
                    .toList()
                    .toPersistentList(),
            )
        }
    }
}
