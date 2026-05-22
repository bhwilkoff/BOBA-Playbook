package com.bobaplaybook.app.feature.scan

import androidx.lifecycle.ViewModel
import com.bobaplaybook.core.data.catalog.CardRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Compose-side accessor for the singleton [ScanQueueStore] + the
 * card repository (for rendering names in the review sheet). One VM
 * keeps the call sites tidy; reaching for `hiltViewModel<ScanQueueStore>`
 * isn't possible (it's not a ViewModel).
 */
@HiltViewModel
class ScanQueueHolderViewModel @Inject constructor(
    val queue: ScanQueueStore,
    val cardRepository: CardRepository,
) : ViewModel()
