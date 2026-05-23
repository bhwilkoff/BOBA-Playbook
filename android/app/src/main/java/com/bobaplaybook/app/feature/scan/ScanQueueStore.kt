package com.bobaplaybook.app.feature.scan

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Session-scoped log of cards matched during the current scan session
 * — parity with iOS `ScanStore.queue` (DESIGN.md §6.5 cross-cutting
 * scan capability). Capped at 25 entries so a long stack-scanning
 * session doesn't grow unbounded.
 *
 * Lifecycle:
 *  - [append] is called from ScanScreen on every successful match.
 *  - [clear] is called when the user explicitly clears the queue
 *    from the review sheet, or could be called on app cold start
 *    (not done today — surviving across cold-launch is harmless and
 *    occasionally useful).
 *
 * NOT persisted across process death. The queue is a working set; if
 * the user backgrounds the app and returns hours later, an empty
 * "Recent (0)" reads cleaner than stale matches from yesterday.
 */
@Singleton
class ScanQueueStore @Inject constructor() {

    data class Entry(
        val bobaId: String,
        val quantity: Int = 1,
        val matchedAt: Long = System.currentTimeMillis(),
    )

    private val _entries = MutableStateFlow<List<Entry>>(emptyList())
    val entries: StateFlow<List<Entry>> = _entries.asStateFlow()

    /**
     * Append a scanned card to the queue. iOS-parity (ScanStore.addToQueue):
     * if a row with the same bobaId already exists, bump its quantity
     * (clamped 1–99) instead of pruning + re-inserting. This is the
     * Whatnot box-break workflow — scan 3 physical copies of Maverick
     * in a row → queue shows "Maverick ×3", not just one row. The
     * prior "prune + re-insert" semantics lost the count entirely.
     */
    fun append(bobaId: String) {
        if (bobaId.isBlank()) return
        val current = _entries.value
        val existingIdx = current.indexOfFirst { it.bobaId == bobaId }
        if (existingIdx >= 0) {
            val existing = current[existingIdx]
            val bumped = existing.copy(
                quantity = (existing.quantity + 1).coerceAtMost(MAX_QUANTITY),
                matchedAt = System.currentTimeMillis(),
            )
            _entries.value = current.toMutableList().apply { set(existingIdx, bumped) }
        } else {
            _entries.value = (listOf(Entry(bobaId = bobaId)) + current).take(CAP)
        }
    }

    /**
     * Manually set the quantity for a queued card (review-sheet stepper
     * parity with iOS ScanStore.setQuantity). Clamped 1…99; 0 has no
     * effect — use [remove] to drop the entry.
     */
    fun setQuantity(bobaId: String, quantity: Int) {
        val clamped = quantity.coerceIn(1, MAX_QUANTITY)
        _entries.value = _entries.value.map { entry ->
            if (entry.bobaId == bobaId) entry.copy(quantity = clamped) else entry
        }
    }

    fun remove(bobaId: String) {
        _entries.value = _entries.value.filter { it.bobaId != bobaId }
    }

    fun clear() {
        _entries.value = emptyList()
    }

    private companion object {
        const val CAP = 25
        const val MAX_QUANTITY = 99
    }
}
