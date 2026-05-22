package com.bobaplaybook.app.feature.purchase

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.network.StoreLocatorService
import com.bobaplaybook.core.network.StoreLocation
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

    val isLoadingStores: Boolean = false,
    val stores: ImmutableList<StoreLocation> = persistentListOf(),
    val indieOnly: Boolean = false,
    val storeQuery: String = "",
    // Tick 431 — scraped_at ISO from stores-manifest.json so the UI
    // can render "Updated 5d ago" (web tick 428 + iOS parity).
    val storesScrapedAt: String? = null,
) {
    val filteredStores: ImmutableList<StoreLocation>
        get() {
            val needle = storeQuery.lowercase().trim()
            val pool = if (indieOnly) stores.filter { it.isIndie } else stores
            val filtered = if (needle.isEmpty()) pool else pool.filter { store ->
                listOf(store.name, store.city, store.state, store.stateShort)
                    .joinToString(" ").lowercase().contains(needle)
            }
            return filtered.toPersistentList()
        }
}

@HiltViewModel
class PurchaseViewModel @Inject constructor(
    private val whatnotService: WhatnotService,
    private val storeLocatorService: StoreLocatorService,
) : ViewModel() {

    private val _state = MutableStateFlow(PurchaseUiState())
    val state: StateFlow<PurchaseUiState> = _state.asStateFlow()

    init {
        refreshBreaks()
        refreshStores()
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

    fun refreshStores() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingStores = true)
            val stores = storeLocatorService.fetchStores()
            // Tick 431 — fetch manifest in parallel-ish (sequential but
            // fast) so the "Updated" stamp populates on first render.
            val scrapedAt = storeLocatorService.fetchScrapedAt()
            _state.value = _state.value.copy(
                isLoadingStores = false,
                stores = stores.toPersistentList(),
                storesScrapedAt = scrapedAt,
            )
        }
    }

    fun setIndieOnly(enabled: Boolean) { _state.value = _state.value.copy(indieOnly = enabled) }
    fun setStoreQuery(query: String) { _state.value = _state.value.copy(storeQuery = query) }
}
