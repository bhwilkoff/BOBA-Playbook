package com.bobaplaybook.app.feature.carddetail

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
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
    val isLoadingPricing: Boolean = false,
    val ebayActive: ImmutableList<PricingListing> = persistentListOf(),
    val ebaySold: ImmutableList<PricingListing> = persistentListOf(),
    /** Worker-resolved Radish landing URL (when present); used for tap-through. */
    val radishUrl: String? = null,
    val otherVersions: ImmutableList<Card> = persistentListOf(),
) {
    /**
     * Median of eBay-sold prices when available; falls back to median of
     * active asking prices so the user always sees a number when there's
     * any market signal at all. iOS DECISIONS.md #013 + #034 keep COMC
     * asking out of the sold waterfall — same posture here.
     */
    val marketEstimateUsd: Double?
        get() {
            val sales = if (ebaySold.isNotEmpty()) ebaySold else ebayActive
            if (sales.isEmpty()) return null
            return sales.map { it.priceUsd }.sorted().let { sorted ->
                val n = sorted.size
                if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            }
        }

    val marketEstimateBasis: String?
        get() = when {
            ebaySold.isNotEmpty() -> "based on ${ebaySold.size} recent eBay sold comps"
            ebayActive.isNotEmpty() -> "based on ${ebayActive.size} active listings (no sold comps yet)"
            else -> null
        }
}

/**
 * Card detail ViewModel.
 *
 * Reactive lookup from the live catalog plus on-demand pricing fetch
 * when the screen opens. ONE Worker round-trip per bobaId; Worker
 * aggregates eBay active + sold + Radish into the same response.
 * Pricing soft-fails — a Worker outage shows "no data" rather than
 * crashing the detail view.
 */
@HiltViewModel
class CardDetailViewModel @Inject constructor(
    private val cardRepository: CardRepository,
    private val pricingService: PricingService,
) : ViewModel() {

    private val pricingState = MutableStateFlow(PricingState())

    fun uiStateFor(bobaId: String): StateFlow<CardDetailUiState> {
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
            pricingState,
        ) { cards, pricing ->
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
                isLoadingPricing = pricing.isLoading,
                ebayActive = pricing.ebayActive[bobaId].orEmpty().toPersistentList(),
                ebaySold = pricing.ebaySold[bobaId].orEmpty().toPersistentList(),
                radishUrl = pricing.radishUrl[bobaId],
                otherVersions = otherVersions.toPersistentList(),
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = CardDetailUiState(),
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
            pricingState.value = pricingState.value.copy(
                isLoading = false,
                ebayActive = pricingState.value.ebayActive + (bobaId to bundle.ebayActive),
                ebaySold = pricingState.value.ebaySold + (bobaId to bundle.ebaySold),
                radishUrl = pricingState.value.radishUrl + (bobaId to bundle.radishResolvedUrl),
            )
        }
    }
}

private data class PricingState(
    val isLoading: Boolean = false,
    val startedForBobaId: Set<String> = emptySet(),
    val ebayActive: Map<String, List<PricingListing>> = emptyMap(),
    val ebaySold: Map<String, List<PricingListing>> = emptyMap(),
    val radishUrl: Map<String, String?> = emptyMap(),
)
