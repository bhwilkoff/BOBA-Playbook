package com.bobaplaybook.app.feature.collection

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.core.data.shows.Show
import com.bobaplaybook.core.data.shows.ShowRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Tick 201 — ShowsViewModel exposes the user's streamer Shows for
 * `ShowsListScreen` to render. Wraps `ShowRepository.shows` and
 * surfaces a one-shot `refresh()` action for pull-to-refresh.
 */
@HiltViewModel
class ShowsViewModel @Inject constructor(
    private val repo: ShowRepository,
) : ViewModel() {

    val shows: StateFlow<List<Show>> = repo.shows
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            _refreshing.value = true
            repo.refresh()
            _refreshing.value = false
        }
    }
}
