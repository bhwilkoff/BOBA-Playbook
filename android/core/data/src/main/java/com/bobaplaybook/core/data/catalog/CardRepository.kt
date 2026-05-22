package com.bobaplaybook.core.data.catalog

import com.bobaplaybook.core.domain.model.Card
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Card catalog repository — Android analog of iOS `CardStore`.
 *
 * Two state flows:
 *  - [cards]       — the live catalog (`List<Card>`). Starts with Phase 1
 *                    head (~500 cards) and atomically swaps to Phase 2
 *                    full (~17,974 cards) when [primeAsync] completes.
 *  - [isLoading]   — true while Phase 2 is in flight.
 *
 * Image-override map mirrors iOS `appliedImageOverridesByBobaId`. When
 * a mod-approved upload lands (M7), `applyImageOverride` mutates the
 * cards list AND rebuilds any derived flows the UI reads from — the
 * v2.280 iOS lesson (`feedback_derived_arrays_must_rebuild.md`)
 * translates directly: every mutation re-emits.
 */
@Singleton
class CardRepository @Inject constructor(
    private val loader: CardCatalogLoader,
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _cards = MutableStateFlow<List<Card>>(emptyList())
    val cards: StateFlow<List<Card>> = _cards.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /**
     * Phase 1 — synchronous. Call once from `Application.onCreate` so
     * the Find shelf has the head bundle before the first Compose frame.
     * Idempotent — once the catalog has any rows, subsequent calls are
     * no-ops. Without this guard, opening a tab whose ViewModel calls
     * primeSync() in init demoted the in-memory catalog from 17,915
     * cards back to the 500-row head bundle until Phase 2 re-loaded,
     * which caused (a) the Decks pool to flash a wrong-then-correct
     * card set and (b) CardDetail tap → "Card not found" if the
     * tapped bobaId lived in the Phase-2 chunk.
     */
    fun primeSync() {
        if (_cards.value.isNotEmpty()) return
        val head = loader.loadHead()
        if (head.isNotEmpty()) {
            _cards.value = head
        }
    }

    /**
     * Phase 2 — background fan-out. Call after [primeSync]. Atomically
     * swaps the full catalog in once decoded. Idempotent — skips when
     * the catalog already has more than the head-bundle row count
     * (loadFull always returns >= 17k rows; the head bundle has 500).
     */
    fun primeAsync() {
        // Already at full size (Phase 2 ran in a prior caller); skip.
        if (_cards.value.size > 1_000) {
            _isLoading.value = false
            return
        }
        scope.launch {
            val full = loader.loadFull()
            if (full.isNotEmpty()) {
                _cards.value = full
            }
            _isLoading.value = false
        }
    }

    /**
     * Apply an admin/mod image override at runtime. Mirrors iOS
     * `CardStore.setAppliedOverride`. Critical: this MUST re-emit a new
     * `_cards.value` (not mutate in place) because Compose's
     * `collectAsStateWithLifecycle` only fires on reference change.
     */
    fun applyImageOverride(bobaId: String, imageFile: String) {
        _cards.update { current ->
            current.map { card ->
                if (card.bobaId == bobaId) card.copy(imageFile = imageFile) else card
            }
        }
    }
}
