package com.bobaplaybook.app.feature.carddetail

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.network.MarketEstimate
import com.bobaplaybook.core.network.PricingListing
import com.bobaplaybook.core.network.PricingService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class CardDetailUiState(
    val card: Card? = null,
    /**
     * Catalog is still streaming in. While true and `card` is null,
     * the screen should show a spinner instead of the "Card not
     * found" empty state — the requested bobaId may live in the
     * Phase-2 chunk that hasn't decoded yet.
     */
    val isCatalogLoading: Boolean = true,
    val isLoadingPricing: Boolean = false,
    val ebayActive: ImmutableList<PricingListing> = persistentListOf(),
    val ebaySold: ImmutableList<PricingListing> = persistentListOf(),
    /**
     * Comparability-derived Market Est. surfaced when ebaySold is empty.
     * Populated by `boba-price-estimator` Worker; null when the cron
     * hasn't computed an entry for this card yet (graceful "no data"
     * fallback in the UI). See workers/price-estimator/README.md.
     */
    val marketEstimate: MarketEstimate? = null,
    val otherVersions: ImmutableList<Card> = persistentListOf(),
    /**
     * Worker's pre-computed canonical market average — preferred over
     * a locally-recomputed median so iOS + Android stay in lockstep
     * for the same Worker response (DECISIONS.md #013 waterfall
     * lives in the Worker, not the client).
     */
    val workerMarketAverageUsd: Double? = null,
    val workerMarketSource: String? = null,
    val workerMarketCount: Int = 0,
) {
    /**
     * Prefer the Worker's pre-computed canonical average; fall back to
     * a local median over sold-then-active so the UI still shows a
     * number when the Worker hasn't filled the top-level field (legacy
     * response shape, or older cached entries).
     */
    val marketEstimateUsd: Double?
        get() {
            workerMarketAverageUsd?.let { return it }
            val sales = if (ebaySold.isNotEmpty()) ebaySold else ebayActive
            if (sales.isEmpty()) return null
            return sales.map { it.priceUsd }.sorted().let { sorted ->
                val n = sorted.size
                if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            }
        }

    val marketEstimateBasis: String?
        get() {
            // Worker-derived basis when available — names the source
            // the Worker actually used (eBay sold vs active fallback)
            // and the exact count it averaged over.
            if (workerMarketAverageUsd != null) {
                val srcLabel = if (workerMarketSource == "sold") "recent sold comps"
                               else "active listings"
                return "based on $workerMarketCount $srcLabel"
            }
            return when {
                ebaySold.isNotEmpty() -> "based on ${ebaySold.size} recent eBay sold comps"
                ebayActive.isNotEmpty() -> "based on ${ebayActive.size} active listings (no sold comps yet)"
                else -> null
            }
        }
}

/**
 * Card detail ViewModel.
 *
 * Reactive lookup from the live catalog plus on-demand pricing fetch
 * when the screen opens. ONE Worker round-trip per bobaId; Worker
 * aggregates eBay active + sold into the same response. Pricing
 * soft-fails — a Worker outage shows "no data" rather than crashing
 * the detail view.
 */
@HiltViewModel
class CardDetailViewModel @Inject constructor(
    private val cardRepository: CardRepository,
    private val pricingService: PricingService,
) : ViewModel() {

    private val pricingState = MutableStateFlow(PricingState())

    fun uiStateFor(bobaId: String): StateFlow<CardDetailUiState> {
        // Synchronous catalog lookup so the StateFlow's initialValue
        // already carries the resolved card. Without this, opening
        // card detail from Decks (or anywhere downstream of a fresh
        // CardDetailViewModel) rendered "Card not found" for one
        // frame while `combine` made its async emission, then snapped
        // to the real card ~1s later (Ben 2026-05-22). The card
        // is always present in the singleton catalog by the time
        // any tap can fire — Phase 1 head bundle ran in
        // BOBAApp init.
        val seededCard = cardRepository.cards.value.firstOrNull { it.bobaId == bobaId }
        // Kick off pricing on first observation
        viewModelScope.launch {
            cardRepository.cards
                .map { it.firstOrNull { c -> c.bobaId == bobaId } }
                .collect { card ->
                    if (card != null && !pricingState.value.startedForBobaId.contains(bobaId)) {
                        pricingState.value = pricingState.value.copy(
                            startedForBobaId = pricingState.value.startedForBobaId + bobaId,
                            isLoading = true,
                        )
                        loadPricing(bobaId, card)
                    }
                }
        }
        return combine(
            cardRepository.cards,
            cardRepository.isLoading,
            pricingState,
        ) { cards, catalogLoading, pricing ->
            val card = cards.firstOrNull { c -> c.bobaId == bobaId }
            val otherVersions = card?.let { c ->
                cards.asSequence()
                    .filter { it.bobaId != bobaId && it.hero.equals(c.hero, ignoreCase = true) && c.hero.isNotEmpty() }
                    .filter { !it.imageFile.isNullOrEmpty() }
                    .take(12)
                    .toList()
            } ?: emptyList()
            CardDetailUiState(
                card = card,
                // Catalog priming is a two-phase load — the head bundle
                // ships before Phase 2 brings in the full 17k. If the
                // requested card is in the second phase, UI rendered
                // "Card not found" for ~1s while Phase 2 finished, then
                // snapped to the real card. Surface a "still loading"
                // signal so the screen can show a spinner instead.
                isCatalogLoading = catalogLoading && card == null,
                isLoadingPricing = pricing.isLoading,
                ebayActive = pricing.ebayActive[bobaId].orEmpty().toPersistentList(),
                ebaySold = pricing.ebaySold[bobaId].orEmpty().toPersistentList(),
                marketEstimate = pricing.marketEstimate[bobaId],
                otherVersions = otherVersions.toPersistentList(),
                workerMarketAverageUsd = pricing.marketAverage[bobaId],
                workerMarketSource = pricing.marketSource[bobaId],
                workerMarketCount = pricing.marketCount[bobaId] ?: 0,
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = CardDetailUiState(
                card = seededCard,
                isCatalogLoading = seededCard == null && cardRepository.isLoading.value,
            ),
        )
    }

    private fun loadPricing(bobaId: String, card: Card) {
        viewModelScope.launch {
            val bundle = pricingService.fetchAll(
                cardNumber = card.cardNumber,
                hero = card.hero,
                set = card.set,
                element = card.element.takeIf { !card.isSealed },
            )
            // Market Est. fallback — query boba-price-estimator when
            // the eBay-proxy returned no sold history. Surfaces as a
            // "MARKET EST." section in the UI. Best-effort; null
            // result is fine (graceful "no data" path).
            val estimate = if (bundle.ebaySold.isEmpty()) {
                pricingService.fetchMarketEstimate(bobaId)
            } else null
            pricingState.value = pricingState.value.copy(
                isLoading = false,
                ebayActive = pricingState.value.ebayActive + (bobaId to bundle.ebayActive),
                ebaySold = pricingState.value.ebaySold + (bobaId to bundle.ebaySold),
                marketEstimate = pricingState.value.marketEstimate + (bobaId to estimate),
                marketAverage = pricingState.value.marketAverage + (bobaId to bundle.marketAverageUsd),
                marketSource = pricingState.value.marketSource + (bobaId to bundle.marketSource),
                marketCount = pricingState.value.marketCount + (bobaId to bundle.marketCount),
            )
        }
    }

    /**
     * Force a fresh pricing fetch for [bobaId] — used by the manual
     * refresh button on the pricing panels. Bypasses the
     * startedForBobaId guard since the caller explicitly asked for
     * a re-fetch.
     */
    fun refreshPricing(bobaId: String) {
        val card = cardRepository.cards.value.firstOrNull { it.bobaId == bobaId } ?: return
        pricingState.value = pricingState.value.copy(isLoading = true)
        loadPricing(bobaId, card)
    }
}

private data class PricingState(
    val isLoading: Boolean = false,
    val startedForBobaId: Set<String> = emptySet(),
    val ebayActive: Map<String, List<PricingListing>> = emptyMap(),
    val ebaySold: Map<String, List<PricingListing>> = emptyMap(),
    /** Comparability-derived Market Est. — per-bobaId; null when none. */
    val marketEstimate: Map<String, MarketEstimate?> = emptyMap(),
    /** Worker pre-computed average — per-bobaId. */
    val marketAverage: Map<String, Double?> = emptyMap(),
    /** "sold" / "listed" — per-bobaId. */
    val marketSource: Map<String, String?> = emptyMap(),
    val marketCount: Map<String, Int> = emptyMap(),
)
