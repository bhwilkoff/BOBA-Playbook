package com.bobaplaybook.app.feature.scan

import androidx.compose.runtime.Composable
import androidx.hilt.navigation.compose.hiltViewModel
import com.bobaplaybook.app.feature.decks.DecksViewModel
import com.bobaplaybook.core.data.catalog.CardRepository

/**
 * Routes scan matches by invocation context (ANDROID-DESIGN.md §6.5).
 *
 *  - From Find: navigate to the card detail
 *  - From Decks: add the card to the active draft
 *  - From Collection: BOBAApp shows ScanDesignationSheet, then the
 *    user picks which designation to file the scan under;
 *    CollectionViewModel.add does the Supabase write
 *
 * Single coordinator — never fork the scan UI per tab. Anti-pattern
 * called out in §6.5.
 */
enum class ScanDestination {
    CARD_DETAIL,   // Find (and any other context that just identifies)
    CURRENT_DECK,  // Decks
    COLLECTION,    // Collection (designation chosen separately)
}

@Composable
fun rememberScanCoordinator(): ScanCoordinator {
    val decksViewModel: DecksViewModel = hiltViewModel()
    return ScanCoordinator(decksViewModel = decksViewModel)
}

class ScanCoordinator(
    private val decksViewModel: DecksViewModel,
) {
    /**
     * Handle a scan match. Returns the bobaId iff the caller should
     * additionally navigate to card detail (e.g. Find context).
     * Returns null when the match was consumed in place (added to
     * deck / collection) and no nav is needed.
     */
    fun onMatch(
        bobaId: String,
        destination: ScanDestination,
        cardRepository: CardRepository,
    ): String? {
        return when (destination) {
            ScanDestination.CARD_DETAIL -> bobaId
            ScanDestination.CURRENT_DECK -> {
                // Synchronous catalog lookup — `cards` is a StateFlow that
                // always holds the current value (loaded by scan time), so
                // read `.value` directly instead of blocking the main thread.
                val card = cardRepository.cards.value.firstOrNull { it.bobaId == bobaId }
                card?.let { decksViewModel.add(it) }
                null
            }
            ScanDestination.COLLECTION -> {
                // Collection-context scans are intercepted at BOBAApp
                // level — ScanDesignationSheet handles the write. The
                // coordinator never reaches this branch from the
                // Collection tab today (BOBAApp short-circuits) but we
                // keep the case so misuse from other entry points
                // still falls back to detail.
                bobaId
            }
        }
    }
}
