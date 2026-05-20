package com.bobaplaybook.app.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Thin Compose-friendly adapter around [GridDensityStore]. Screens
 * collect `columnsFor(target)` into a StateFlow and call
 * `setColumns(target, n)` from picker callbacks.
 *
 * Lives in `app/settings` so Find / Decks / Collection all share one
 * injection point. Keeps the rememberSaveable + magic-number defaults
 * out of the Composables, mirroring iOS @AppStorage("bp_*GridColumns_v1").
 */
@HiltViewModel
class GridDensityViewModel @Inject constructor(
    private val store: GridDensityStore,
) : ViewModel() {

    fun columnsFor(target: GridDensityStore.Target): Flow<Int> =
        store.columnsFor(target)

    fun setColumns(target: GridDensityStore.Target, columns: Int) {
        viewModelScope.launch { store.setColumns(target, columns) }
    }
}
