package com.bobaplaybook.app.feature.find

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.showcase.Showcase
import com.bobaplaybook.core.domain.showcase.Showcases
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.persistentSetOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.collections.immutable.toPersistentSet
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

/**
 * Find tab ViewModel — full parity with iOS `CardStore`.
 *
 * State machine:
 *  - 8 filter dimensions combine via AND
 *  - Showcase smart-match (typing "WoBA" → narrows to that showcase
 *    automatically; no need to open the filter sheet)
 *  - 9 sort orders applied after filter
 *  - Featured shelves precomputed once the catalog lands
 *  - Live suggestions inside the SearchBar expanded content
 */
@OptIn(FlowPreview::class, kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@HiltViewModel
class FindViewModel @Inject constructor(
    private val cardRepository: CardRepository,
) : ViewModel() {

    private val query           = MutableStateFlow("")
    private val activeWeapons   = MutableStateFlow<Set<String>>(emptySet())
    private val activeTreatment = MutableStateFlow<String?>(null)
    private val activeSet       = MutableStateFlow<String?>(null)
    private val activeRelease   = MutableStateFlow<String?>(null)
    private val powerMin        = MutableStateFlow<Int?>(null)
    private val powerMax        = MutableStateFlow<Int?>(null)
    private val hasImageOnly    = MutableStateFlow(false)
    private val cardPurpose     = MutableStateFlow(CardPurpose.ALL)
    private val showcaseId      = MutableStateFlow<String?>(null)
    private val sortOrder       = MutableStateFlow(SortOrder.DEFAULT)

    private val canonicalWeapons = listOf(
        "FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER",
    )

    init {
        cardRepository.primeSync()
        cardRepository.primeAsync()
    }

    /** Combined filter parameters — single Flow to keep `combine` arity sane. */
    private data class Filters(
        val query: String,
        val weapons: Set<String>,
        val treatment: String?,
        val set: String?,
        val release: String?,
        val powerMin: Int?,
        val powerMax: Int?,
        val hasImageOnly: Boolean,
        val purpose: CardPurpose,
        val showcaseId: String?,
        val sort: SortOrder,
    )

    private val filtersFlow = combine(
        query.debounce(100L).distinctUntilChanged(),
        combine(activeWeapons, activeTreatment, activeSet, activeRelease) { w, t, s, r ->
            arrayOf(w, t, s, r)
        },
        combine(powerMin, powerMax, hasImageOnly) { mn, mx, img -> Triple(mn, mx, img) },
        combine(cardPurpose, showcaseId, sortOrder) { p, sc, sortRule -> Triple(p, sc, sortRule) },
    ) { q, group1, group2, group3 ->
        @Suppress("UNCHECKED_CAST")
        Filters(
            query = q,
            weapons    = group1[0] as Set<String>,
            treatment  = group1[1] as String?,
            set        = group1[2] as String?,
            release    = group1[3] as String?,
            powerMin   = group2.first,
            powerMax   = group2.second,
            hasImageOnly = group2.third,
            purpose    = group3.first,
            showcaseId = group3.second,
            sort       = group3.third,
        )
    }

    val uiState: StateFlow<FindUiState> =
        combine(
            cardRepository.cards,
            cardRepository.isLoading,
            filtersFlow,
        ) { cards, isLoading, f ->
            val filtered  = applyFilters(cards, f)
            val sorted    = applySort(filtered, f.sort)
            val suggestions = buildSuggestions(cards, f.query)
            val featured  = if (cards.isEmpty()) FeaturedShelves.EMPTY
                            else FeaturedShelves.build(cards)
            val available = AvailableValues.from(cards)
            FindUiState(
                query              = f.query,
                activeWeapons      = f.weapons.toPersistentSet(),
                activeTreatment    = f.treatment,
                activeSet          = f.set,
                activeRelease      = f.release,
                powerMin           = f.powerMin,
                powerMax           = f.powerMax,
                hasImageOnly       = f.hasImageOnly,
                cardPurpose        = f.purpose,
                showcaseId         = f.showcaseId,
                sortOrder          = f.sort,
                isLoading          = isLoading,
                results            = sorted.toPersistentList(),
                suggestions        = suggestions.toPersistentList(),
                recentlyAdded      = featured.recentlyAdded,
                heroesByWeapon     = featured.heroesByWeapon,
                coachingStaff      = featured.coachingStaff,
                showcaseShelves    = featured.showcaseShelves,
                availableSets      = available.sets.toPersistentList(),
                availableTreatments= available.treatments.toPersistentList(),
                availableReleases  = available.releases.toPersistentList(),
                availableElements  = available.elements.toPersistentList(),
                totalCatalogSize   = cards.size,
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = FindUiState(),
        )

    fun onEvent(event: FindEvent) {
        when (event) {
            is FindEvent.QueryChanged       -> query.value = event.query
            is FindEvent.WeaponToggled      -> activeWeapons.update { c -> if (event.weapon in c) c - event.weapon else c + event.weapon }
            is FindEvent.TreatmentChanged   -> activeTreatment.value = event.treatment
            is FindEvent.SetChanged         -> activeSet.value = event.set
            is FindEvent.ReleaseChanged     -> activeRelease.value = event.release
            is FindEvent.PowerMinChanged    -> powerMin.value = event.min
            is FindEvent.PowerMaxChanged    -> powerMax.value = event.max
            is FindEvent.PowerPresetApplied -> { powerMin.value = event.preset.min; powerMax.value = event.preset.max }
            is FindEvent.HasImageToggled    -> hasImageOnly.value = event.enabled
            is FindEvent.CardPurposeChanged -> cardPurpose.value = event.purpose
            is FindEvent.ShowcaseChanged    -> showcaseId.value = event.showcaseId
            is FindEvent.SortChanged        -> sortOrder.value = event.sort
            is FindEvent.SuggestionTapped   -> handleSuggestion(event.suggestion)
            FindEvent.ClearAllFilters       -> clearAll()
        }
    }

    private fun handleSuggestion(suggestion: SearchSuggestion) {
        when (suggestion) {
            is SearchSuggestion.CardHit -> query.value = ""
            is SearchSuggestion.Token -> {
                when (suggestion.kind) {
                    TokenKind.WEAPON    -> activeWeapons.update { it + suggestion.value }
                    TokenKind.TREATMENT -> activeTreatment.value = suggestion.value
                    TokenKind.SET       -> activeSet.value = suggestion.value
                }
                query.value = ""
            }
        }
    }

    fun clearAll() {
        query.value = ""
        activeWeapons.value = emptySet()
        activeTreatment.value = null
        activeSet.value = null
        activeRelease.value = null
        powerMin.value = null
        powerMax.value = null
        hasImageOnly.value = false
        cardPurpose.value = CardPurpose.ALL
        showcaseId.value = null
        sortOrder.value = SortOrder.DEFAULT
    }

    /** Filter pipeline. Mirrors iOS CardStore.applyFilters. */
    private fun applyFilters(cards: List<Card>, f: Filters): List<Card> {
        val needle = f.query.trim().lowercase()
        // Smart-match: typing a showcase token auto-narrows.
        val typedShowcase: Showcase? = if (needle.isEmpty()) null else Showcases.matching(needle)
        val pickedShowcase: Showcase? = f.showcaseId?.let { Showcases.byId(it) }
        val activeShowcase = typedShowcase ?: pickedShowcase
        val isShowcaseSearch = typedShowcase != nil()

        if (cards.isEmpty()) return emptyList()
        if (f.query.isBlank() && f.weapons.isEmpty() && f.treatment == null && f.set == null &&
            f.release == null && f.powerMin == null && f.powerMax == null && !f.hasImageOnly &&
            f.purpose == CardPurpose.ALL && activeShowcase == null) {
            // No filters active — return the full catalog. LazyVerticalGrid
            // composes lazily with stable keys; 17k items materialize only as
            // they scroll into view.
            return cards
        }

        return cards.asSequence().filter { card ->
            // Card purpose
            when (f.purpose) {
                CardPurpose.ALL      -> {}
                CardPurpose.HEROES   -> if (!card.isHero)    return@filter false
                CardPurpose.PLAYS    -> if (!card.isPlay)    return@filter false
                CardPurpose.HOT_DOGS -> if (!card.isHotDog)  return@filter false
                CardPurpose.SEALED   -> if (!card.isSealed)  return@filter false
            }
            // Showcase
            if (activeShowcase != null && !activeShowcase.match(card)) return@filter false
            // Has image
            if (f.hasImageOnly && card.imageFile.isNullOrEmpty()) return@filter false
            // Element (weapons multi-select)
            if (f.weapons.isNotEmpty() && card.element.uppercase() !in f.weapons.map { it.uppercase() }) return@filter false
            // Treatment
            if (f.treatment != null && !card.treatment.equals(f.treatment, ignoreCase = true)) return@filter false
            // Set
            if (f.set != null && !card.set.equals(f.set, ignoreCase = true)) return@filter false
            // Release
            if (f.release != null && !card.release.equals(f.release, ignoreCase = true)) return@filter false
            // Power range
            val p = card.power
            if (f.powerMin != null && (p == null || p < f.powerMin)) return@filter false
            if (f.powerMax != null && (p == null || p > f.powerMax)) return@filter false
            // Text search — skip when typed-showcase consumes the query.
            // Use word-prefix matching (CardSearch.matches) NOT raw
            // String.contains() so "amon" finds Amon-Ra but never Johnny
            // Damon — memory feedback_search_word_prefix.
            if (!isShowcaseSearch && needle.isNotEmpty()) {
                if (!com.bobaplaybook.core.domain.search.CardSearch.matches(needle, card)) return@filter false
            }
            true
        }.toList()
    }

    /**
     * Sort pipeline. Mirrors iOS CardStore sortOrder switch.
     *
     * Every sort uses image-first as its PRIMARY key — memory
     * `feedback_card_art_sort_priority`: "every card list/grid must
     * sort cards with imageFile ahead of image-pending placeholders".
     * Cards without art at the top of any sort feels broken; the
     * user's chosen criterion becomes the tiebreaker WITHIN each
     * art-status group.
     */
    private fun applySort(cards: List<Card>, order: SortOrder): List<Card> {
        val artFirst = compareByDescending<Card> { !it.imageFile.isNullOrEmpty() }
        return when (order) {
            SortOrder.DEFAULT     -> cards.sortedWith(artFirst.thenBy { it.cardNumber })
            SortOrder.NAME_ASC    -> cards.sortedWith(artFirst.thenBy { it.displayName.lowercase() })
            SortOrder.NAME_DESC   -> cards.sortedWith(artFirst.thenByDescending { it.displayName.lowercase() })
            SortOrder.POWER_DESC  -> cards.sortedWith(artFirst.thenByDescending { it.power ?: 0 })
            SortOrder.POWER_ASC   -> cards.sortedWith(artFirst.thenBy { it.power ?: Int.MAX_VALUE })
            SortOrder.NUMBER_ASC  -> cards.sortedWith(artFirst.thenBy { it.cardNumber })
            SortOrder.NUMBER_DESC -> cards.sortedWith(artFirst.thenByDescending { it.cardNumber })
            SortOrder.COST_ASC    -> cards.sortedWith(artFirst.thenBy { it.cost ?: Int.MAX_VALUE })
            SortOrder.COST_DESC   -> cards.sortedWith(artFirst.thenByDescending { it.cost ?: 0 })
            SortOrder.VARIATION   -> cards.sortedWith(artFirst.thenBy { it.variation ?: "" })
        }
    }

    /** Live suggestions for the expanded SearchBar (max 8). */
    private fun buildSuggestions(cards: List<Card>, query: String): List<SearchSuggestion> {
        val needle = query.lowercase().trim()
        if (needle.length < 2) return emptyList()
        val out = mutableListOf<SearchSuggestion>()

        canonicalWeapons.firstOrNull { it.lowercase().startsWith(needle) }?.let {
            out += SearchSuggestion.Token(TokenKind.WEAPON, it)
        }
        cards.asSequence()
            .mapNotNull { it.treatment }
            .distinct()
            .filter { it.lowercase().startsWith(needle) }
            .take(2)
            .forEach { out += SearchSuggestion.Token(TokenKind.TREATMENT, it) }
        cards.asSequence()
            .filter { c ->
                c.hero.lowercase().startsWith(needle) ||
                c.name.lowercase().startsWith(needle) ||
                c.cardNumber.lowercase().startsWith(needle)
            }
            .take(8 - out.size)
            .forEach { out += SearchSuggestion.CardHit(it) }
        return out
    }

    private fun nil(): Showcase? = null
}

/** Featured-shelf precomputation. Recomputes only on catalog swap. */
private data class FeaturedShelves(
    val recentlyAdded: kotlinx.collections.immutable.ImmutableList<Card>,
    val heroesByWeapon: kotlinx.collections.immutable.ImmutableList<WeaponShelf>,
    val coachingStaff: kotlinx.collections.immutable.ImmutableList<Card>,
    val showcaseShelves: kotlinx.collections.immutable.ImmutableList<ShowcaseShelf>,
) {
    companion object {
        val EMPTY = FeaturedShelves(persistentListOf(), persistentListOf(), persistentListOf(), persistentListOf())

        fun build(cards: List<Card>): FeaturedShelves {
            val withArt = cards.filter { !it.imageFile.isNullOrEmpty() }
            val canonicalWeapons = listOf("FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER")
            // Pre-compute showcase carousels — iOS DECISIONS.md / Showcase.swift
            // parity. WoBA + Rookie Inspired + every named sport. Cap each at
            // 20 cards (visible on first carousel scroll without overwhelming).
            val showcaseShelves = com.bobaplaybook.core.domain.showcase.Showcases.all.map { showcase ->
                ShowcaseShelf(
                    showcaseId = showcase.id,
                    name = showcase.name,
                    cards = withArt.asSequence()
                        .filter { showcase.match(it) }
                        .take(20)
                        .toList()
                        .toPersistentList(),
                )
            }.filter { it.cards.isNotEmpty() }.toPersistentList()
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
                }.filter { it.cards.isNotEmpty() }.toPersistentList(),
                coachingStaff = withArt.asSequence()
                    .filter { it.cardType.contains("Coach", ignoreCase = true) }
                    .take(20)
                    .toList()
                    .toPersistentList(),
                showcaseShelves = showcaseShelves,
            )
        }
    }
}

/** Distinct filter values pulled from the catalog. */
private data class AvailableValues(
    val sets: List<String>,
    val treatments: List<String>,
    val releases: List<String>,
    val elements: List<String>,
) {
    companion object {
        fun from(cards: List<Card>): AvailableValues = AvailableValues(
            sets = cards.mapNotNull { it.set.takeIf { s -> s.isNotBlank() } }.distinct().sorted(),
            treatments = cards.mapNotNull { it.treatment?.takeIf { t -> t.isNotBlank() } }.distinct().sorted(),
            releases = cards.mapNotNull { it.release?.takeIf { r -> r.isNotBlank() } }.distinct().sorted(),
            elements = cards.map { it.element.uppercase() }.distinct().sorted(),
        )
    }
}
