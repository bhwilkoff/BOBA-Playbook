package com.bobaplaybook.app.hints

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Thin ViewModel adapter around [HintsStore] so screens can use
 * `hiltViewModel<HintsViewModel>()` to bind dismissal state into the
 * Composable lifecycle.
 */
@HiltViewModel
class HintsViewModel @Inject constructor(
    private val store: HintsStore,
) : ViewModel() {

    fun isDismissed(id: String): Flow<Boolean> = store.isDismissed(id)

    val globalEnabled: Flow<Boolean> = store.globalEnabled

    fun dismiss(id: String) {
        viewModelScope.launch { store.dismiss(id) }
    }

    fun setGlobalEnabled(enabled: Boolean) {
        viewModelScope.launch { store.setGlobalEnabled(enabled) }
    }

    fun resetAll() {
        viewModelScope.launch { store.resetAll() }
    }
}
