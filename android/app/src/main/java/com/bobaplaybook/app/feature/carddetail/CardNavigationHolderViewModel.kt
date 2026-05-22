package com.bobaplaybook.app.feature.carddetail

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Tiny pass-through so Composables can reach the app-singleton
 * [CardNavigationStore] via `hiltViewModel()`. Avoids passing the
 * store explicitly through every call site.
 *
 * Why a VM at all: Hilt's compose-integration prefers `hiltViewModel()`
 * over directly injecting a singleton into a Composable. The VM is the
 * idiomatic seam.
 */
@HiltViewModel
class CardNavigationHolderViewModel @Inject constructor(
    val store: CardNavigationStore,
) : ViewModel()
