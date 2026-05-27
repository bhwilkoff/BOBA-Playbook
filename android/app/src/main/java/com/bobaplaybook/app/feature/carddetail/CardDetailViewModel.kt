package com.bobaplaybook.app.feature.carddetail

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.network.CommunityCompResult
import com.bobaplaybook.core.network.CompsResult
import com.bobaplaybook.core.network.MarketEstimate
import com.bobaplaybook.core.network.PricingListing
import com.bobaplaybook.core.network.PricingService
import com.bobaplaybook.core.network.ProfileService
import com.bobaplaybook.core.network.ResolvedPricing
import com.bobaplaybook.core.network.WhatnotListing
import com.bobaplaybook.core.network.marketValue
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
    /**
     * Whatnot active listings (Tier 2 — asking signal, Buy Now only;
     * never folded into the sold/value number, #034). matchesCard flags
     * the ones the Worker bound to this card; UI shows those first.
     */
    val whatnotListings: ImmutableList<WhatnotListing> = persistentListOf(),
    /**
     * Real transacted comps (Tier 1+3 — vanish-inferred eBay/Whatnot sales +
     * mod-approved community comps) from boba-pricing-tracker /comps. The REAL
     * "Recent Sales" signal; the resolver ranks it above Listed Range (#058).
     */
    val marketComps: CompsResult? = null,
) {
    /**
     * Provenance-honest resolution (DECISIONS.md #058) — the ONE place the
     * four-signal hierarchy is applied for the render. Recent Sales (comps +
     * real eBay sold) → Listed Range (eBay active + Whatnot matched asks).
     */
    val resolved: ResolvedPricing
        get() = marketValue(
            ebayActive = ebayActive,
            ebaySold = ebaySold,
            comps = marketComps,
            whatnotMatched = whatnotListings.filter { it.matchesCard },
        )

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
    private val profileService: ProfileService,
) : ViewModel() {

    /**
     * Tier 3 community-comp submission (PRICING_PLAYBOOK §5). Suspends
     * for the RPC round-trip and returns a typed result so the sheet can
     * show specific copy (rate-limited vs already-this-week vs generic).
     * The RPC is auth-gated + rate-limited server-side; the sheet only
     * opens its form for signed-in users.
     */
    suspend fun submitCommunityComp(
        bobaId: String,
        priceUsd: Double,
        soldAtIso: String,
        platform: String,
        notes: String?,
    ): CommunityCompResult =
        profileService.submitCommunityComp(bobaId, priceUsd, soldAtIso, platform, notes)

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
                whatnotListings = pricing.whatnot[bobaId].orEmpty().toPersistentList(),
                marketComps = pricing.comps[bobaId],
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
            // Persistence-layer fast path — query Supabase's
            // card_prices_latest view first. When a fresh row (< 24h)
            // exists, skip the live ebay-proxy round-trip; significant
            // latency win + saves eBay API quota. Falls through to the
            // live path when no row or stale.
            val cached = pricingService.fetchCachedBundle(bobaId)
            val bundle = cached ?: pricingService.fetchAll(
                cardNumber = card.cardNumber,
                hero = card.hero,
                set = card.set,
                element = card.element.takeIf { !card.isSealed },
                bobaId = bobaId,
            )
            // Market Est. fallback — query boba-price-estimator when
            // the eBay-proxy returned no sold history. Surfaces as a
            // "MARKET EST." section in the UI. Best-effort; null
            // result is fine (graceful "no data" path). When `cached`
            // hit, the snapshot Worker already folded the estimator
            // into its result so we skip the per-card call here.
            val estimate = if (cached == null && bundle.ebaySold.isEmpty()) {
                pricingService.fetchMarketEstimate(bobaId)
            } else null
            // Whatnot active asks — additive Buy Now source, runs on both
            // cached + live paths (not in card_prices_latest). Soft-fails
            // to []. Query by the hero token; Worker binds via cardNumber
            // + weapon and flags matchesCard.
            val whatnot = pricingService.fetchWhatnotProducts(
                query = card.hero,
                cardNumber = card.cardNumber,
                weapon = if (card.isSealed) "" else card.element,
                treatment = card.treatment.orEmpty(),
                power = card.power,
                bobaId = bobaId,
            )
            // Real transacted comps (Recent Sales) — vanish-inferred eBay/
            // Whatnot sales + community comps. The resolver ranks these above
            // the Listed Range (#058). Runs on both cached + live paths.
            val comps = pricingService.fetchComps(bobaId)
            pricingState.value = pricingState.value.copy(
                isLoading = false,
                ebayActive = pricingState.value.ebayActive + (bobaId to bundle.ebayActive),
                ebaySold = pricingState.value.ebaySold + (bobaId to bundle.ebaySold),
                marketEstimate = pricingState.value.marketEstimate + (bobaId to estimate),
                marketAverage = pricingState.value.marketAverage + (bobaId to bundle.marketAverageUsd),
                marketSource = pricingState.value.marketSource + (bobaId to bundle.marketSource),
                marketCount = pricingState.value.marketCount + (bobaId to bundle.marketCount),
                whatnot = pricingState.value.whatnot + (bobaId to whatnot),
                comps = pricingState.value.comps + (bobaId to comps),
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
    /** Whatnot active listings — per-bobaId (asking signal, Buy Now only). */
    val whatnot: Map<String, List<WhatnotListing>> = emptyMap(),
    /** Transacted comps (Recent Sales) — per-bobaId; null when none yet. */
    val comps: Map<String, CompsResult?> = emptyMap(),
)
