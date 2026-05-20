package com.bobaplaybook.app.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Compose-friendly adapter around [CollectionPrefsStore]. Keeps the
 * Composable free of DataStore details and viewModelScope launches.
 */
@HiltViewModel
class CollectionPrefsViewModel @Inject constructor(
    private val store: CollectionPrefsStore,
) : ViewModel() {

    val displayMode: Flow<String?> = store.displayMode
    val sortOrder: Flow<String?>   = store.sortOrder

    fun setDisplayMode(mode: String) {
        viewModelScope.launch { store.setDisplayMode(mode) }
    }

    fun setSortOrder(order: String) {
        viewModelScope.launch { store.setSortOrder(order) }
    }
}
