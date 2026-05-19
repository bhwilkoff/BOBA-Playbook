package com.bobaplaybook.app.feature.scan

import androidx.compose.runtime.Composable
import androidx.hilt.navigation.compose.hiltViewModel
import com.bobaplaybook.app.feature.decks.DecksViewModel
import com.bobaplaybook.core.data.catalog.CardRepository
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/**
 * Routes scan matches by invocation context (ANDROID-DESIGN.md §6.5).
 *
 *  - From Find: navigate to the card detail
 *  - From Decks: add the card to the active draft
 *  - From Collection: add to the user's collection at the chosen
 *    designation (M7 polish — designation prompt)
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
                // Synchronous catalog lookup — already in memory by scan time.
                val card = runBlocking { cardRepository.cards.first().firstOrNull { it.bobaId == bobaId } }
                card?.let { decksViewModel.add(it) }
                null
            }
            ScanDestination.COLLECTION -> {
                // M7 polish — prompt for designation; for now fall through to
                // card detail so the user can pick from the detail screen.
                bobaId
            }
        }
    }
}
