package com.bobaplaybook.app.feature.learn

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.navigation.AppDestination
import com.bobaplaybook.app.navigation.TabRefreshBus
import com.bobaplaybook.core.network.YouTubeFeedBundle
import com.bobaplaybook.core.network.YouTubeFeedService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
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
    private val tabRefreshBus: TabRefreshBus,
) : ViewModel() {

    private val _state = MutableStateFlow(WatchUiState(isLoading = true))
    val state: StateFlow<WatchUiState> = _state.asStateFlow()

    init {
        refresh()
        // Tab-tap refresh recovery (Ben's punch-list #6). Re-fetch
        // whenever the user taps the Learn tab — covers stuck-blank
        // screens after a Worker failure when the user comes back.
        viewModelScope.launch {
            tabRefreshBus.events
                .filter { it == AppDestination.LEARN }
                .collect { refresh() }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            // Wrap the network call. Without the try/catch, an
            // unhandled exception (Worker offline, parse error) left
            // the state stuck on isLoading = true forever — the user
            // saw the loading spinner with no recovery path.
            val result = runCatching { service.loadAll() }
            result.fold(
                onSuccess = { bundle ->
                    val empty = bundle.upcoming.isEmpty() &&
                        bundle.vertical.isEmpty() &&
                        bundle.horizontal.isEmpty()
                    _state.value = WatchUiState(
                        isLoading = false,
                        bundle = bundle,
                        // Empty-but-loaded is NOT a fetch error — the
                        // channel just doesn't have any current
                        // content. Show nothing rather than a
                        // misleading "couldn't load" message.
                        error = null,
                        isEmpty = empty,
                    )
                },
                onFailure = {
                    _state.value = WatchUiState(
                        isLoading = false,
                        bundle = YouTubeFeedService.EMPTY,
                        error = "Couldn't load the YouTube feed. Pull to retry.",
                    )
                },
            )
        }
    }
}

data class WatchUiState(
    val isLoading: Boolean = false,
    val bundle: YouTubeFeedBundle = YouTubeFeedService.EMPTY,
    val error: String? = null,
    /** True when the fetch succeeded but every category was empty. */
    val isEmpty: Boolean = false,
)
