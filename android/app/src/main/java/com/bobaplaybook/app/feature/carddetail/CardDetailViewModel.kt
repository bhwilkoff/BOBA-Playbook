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
import kotlinx.coroutines.async
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
    val radishSales: ImmutableList<PricingListing> = persistentListOf(),
    val otherVersions: ImmutableList<Card> = persistentListOf(),
) {
    val marketEstimateUsd: Double?
        get() {
            // Radish first (preferred TCG comps), eBay sold as fallback
            val sales = if (radishSales.isNotEmpty()) radishSales else ebaySold
            if (sales.isEmpty()) return null
            return sales.map { it.priceUsd }.sorted().let { sorted ->
                // Median — robust to outliers in small samples
                val n = sorted.size
                if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            }
        }

    val marketEstimateBasis: String?
        get() {
            val n = (radishSales.size + ebaySold.size).takeIf { it > 0 } ?: return null
            return when {
                radishSales.isNotEmpty() && ebaySold.isNotEmpty() -> "based on $n recent sales (Radish + eBay)"
                radishSales.isNotEmpty()                          -> "based on ${radishSales.size} Radish sales"
                else                                              -> "based on ${ebaySold.size} eBay sold"
            }
        }
}

/**
 * Card detail ViewModel.
 *
 * Reactive lookup from the live catalog (so admin overrides on art
 * propagate instantly) plus on-demand pricing fetches when the screen
 * opens. Pricing soft-fails — a Worker outage shows "no data" rather
 * than crashing the detail view.
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
                radishSales = pricing.radish[bobaId].orEmpty().toPersistentList(),
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
            // Three parallel fetches via coroutineScope for structured concurrency
            kotlinx.coroutines.coroutineScope {
                val active = async { pricingService.ebayActive(card.cardNumber, card.hero) }
                val sold = async { pricingService.ebaySold(card.cardNumber, card.hero) }
                val radish = async { pricingService.radish(card.cardNumber) }
                val r1 = active.await()
                val r2 = sold.await()
                val r3 = radish.await()
                pricingState.value = pricingState.value.copy(
                    isLoading = false,
                    ebayActive = pricingState.value.ebayActive + (bobaId to r1),
                    ebaySold = pricingState.value.ebaySold + (bobaId to r2),
                    radish = pricingState.value.radish + (bobaId to r3),
                )
            }
        }
    }
}

private data class PricingState(
    val isLoading: Boolean = false,
    val startedForBobaId: Set<String> = emptySet(),
    val ebayActive: Map<String, List<PricingListing>> = emptyMap(),
    val ebaySold: Map<String, List<PricingListing>> = emptyMap(),
    val radish: Map<String, List<PricingListing>> = emptyMap(),
)
