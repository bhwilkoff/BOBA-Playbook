package com.bobaplaybook.app.feature.carddetail

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import androidx.lifecycle.viewModelScope

@Immutable
data class CardDetailUiState(
    val card: Card? = null,
)

/**
 * Card detail ViewModel.
 *
 * Single Flow that re-resolves the card from the live catalog whenever
 * the repository emits — this is the v2.280 lesson translated. If an
 * admin updates the card art elsewhere in the app, this screen
 * automatically picks up the new imageFile.
 */
@HiltViewModel
class CardDetailViewModel @Inject constructor(
    private val cardRepository: CardRepository,
) : ViewModel() {

    fun uiStateFor(bobaId: String): StateFlow<CardDetailUiState> =
        cardRepository.cards
            .map { all -> CardDetailUiState(card = all.firstOrNull { it.bobaId == bobaId }) }
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5_000),
                initialValue = CardDetailUiState(),
            )
}
