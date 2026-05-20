package com.bobaplaybook.app.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/** Compose adapter around [FindPrefsStore]. */
@HiltViewModel
class FindPrefsViewModel @Inject constructor(
    private val store: FindPrefsStore,
) : ViewModel() {

    val showcaseMode: Flow<Boolean> = store.showcaseMode
    val quickAdd: Flow<Boolean>     = store.quickAdd

    fun setShowcaseMode(enabled: Boolean) {
        viewModelScope.launch { store.setShowcaseMode(enabled) }
    }

    fun setQuickAdd(enabled: Boolean) {
        viewModelScope.launch { store.setQuickAdd(enabled) }
    }
}
