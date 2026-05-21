package com.bobaplaybook.app.feature.collection

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.data.rainbows.CustomRainbow
import com.bobaplaybook.core.data.rainbows.CustomRainbowRepository
import com.bobaplaybook.core.data.rainbows.RainbowCriteria
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Custom rainbows view-model — read-side State + create/delete events.
 */
@HiltViewModel
class CustomRainbowsViewModel @Inject constructor(
    private val repo: CustomRainbowRepository,
    private val authManager: AuthManager,
) : ViewModel() {

    val rainbows: StateFlow<List<CustomRainbow>> = repo.rainbows
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun create(name: String, criteria: RainbowCriteria, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val userId = (authManager.authState.first() as? AuthState.SignedIn)?.userId
            if (userId == null) { onResult(false); return@launch }
            val id = repo.save(userId, name, criteria)
            onResult(id != null)
        }
    }

    /** Rename + criteria edit of an existing rainbow. Parity with
     *  web `API.updateCustomRainbow` (tick 15) and iOS
     *  `CustomRainbowStore.update`. */
    fun update(id: String, name: String, criteria: RainbowCriteria, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val ok = repo.update(id, name, criteria)
            onResult(ok)
        }
    }

    fun delete(id: String) {
        viewModelScope.launch { repo.delete(id) }
    }
}
