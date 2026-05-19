package com.bobaplaybook.app.feature.scan

import androidx.lifecycle.ViewModel
import com.bobaplaybook.core.data.catalog.CardRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Thin ViewModel wrapper that exposes [CardRepository] to the
 * BOBAApp scope so the scan-coordinator can synchronously look up
 * the matched card by bobaId without threading repos through the
 * Composable signature.
 */
@HiltViewModel
class ScanCoordinatorViewModel @Inject constructor(
    val cardRepository: CardRepository,
) : ViewModel()
