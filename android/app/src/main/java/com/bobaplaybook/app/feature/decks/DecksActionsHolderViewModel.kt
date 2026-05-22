package com.bobaplaybook.app.feature.decks

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Hilt-injected ViewModel wrapper exposing the [DecksActions] singleton
 * to Composable scope (via `hiltViewModel()`). Pattern mirrors
 * `CardNavigationHolderViewModel` / `ScanQueueHolderViewModel`.
 */
@HiltViewModel
class DecksActionsHolderViewModel @Inject constructor(
    val bus: DecksActions,
) : ViewModel()
