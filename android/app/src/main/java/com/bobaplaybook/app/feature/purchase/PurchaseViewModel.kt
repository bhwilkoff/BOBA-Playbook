package com.bobaplaybook.app.feature.purchase

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.network.WhatnotService
import com.bobaplaybook.core.network.WhatnotShow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@Immutable
data class PurchaseUiState(
    val isLoadingBreaks: Boolean = false,
    val upcomingBreaks: ImmutableList<WhatnotShow> = persistentListOf(),
    val breaksError: String? = null,
)

@HiltViewModel
class PurchaseViewModel @Inject constructor(
    private val whatnotService: WhatnotService,
) : ViewModel() {

    private val _state = MutableStateFlow(PurchaseUiState())
    val state: StateFlow<PurchaseUiState> = _state.asStateFlow()

    init {
        refreshBreaks()
    }

    fun refreshBreaks() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingBreaks = true, breaksError = null)
            val shows = whatnotService.upcomingBreaks()
            _state.value = _state.value.copy(
                isLoadingBreaks = false,
                upcomingBreaks = shows.toPersistentList(),
                breaksError = if (shows.isEmpty()) "No upcoming breaks at the moment." else null,
            )
        }
    }
}
