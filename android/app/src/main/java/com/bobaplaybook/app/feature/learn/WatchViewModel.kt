package com.bobaplaybook.app.feature.learn

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.network.YouTubeFeedBundle
import com.bobaplaybook.core.network.YouTubeFeedService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Watch tab ViewModel — fetches the Worker-aggregated YouTube feed
 * (upcoming live · vertical Shorts · horizontal videos) and exposes
 * a [WatchUiState] for the Composable to render.
 *
 * Mirrors iOS `YouTubeFeedService.loadAll()` shape.
 */
@HiltViewModel
class WatchViewModel @Inject constructor(
    private val service: YouTubeFeedService,
) : ViewModel() {

    private val _state = MutableStateFlow(WatchUiState(isLoading = true))
    val state: StateFlow<WatchUiState> = _state.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val bundle = service.loadAll()
            val empty = bundle.upcoming.isEmpty() &&
                bundle.vertical.isEmpty() &&
                bundle.horizontal.isEmpty()
            _state.value = WatchUiState(
                isLoading = false,
                bundle = bundle,
                error = if (empty) "Couldn't load the YouTube feed. Pull to retry." else null,
            )
        }
    }
}

data class WatchUiState(
    val isLoading: Boolean = false,
    val bundle: YouTubeFeedBundle = YouTubeFeedService.EMPTY,
    val error: String? = null,
)
