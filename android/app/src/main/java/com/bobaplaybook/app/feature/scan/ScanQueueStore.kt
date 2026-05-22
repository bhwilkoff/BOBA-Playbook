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
        val matchedAt: Long = System.currentTimeMillis(),
    )

    private val _entries = MutableStateFlow<List<Entry>>(emptyList())
    val entries: StateFlow<List<Entry>> = _entries.asStateFlow()

    fun append(bobaId: String) {
        if (bobaId.isBlank()) return
        val current = _entries.value
        // De-dupe by bobaId — if the user scans the same card twice
        // in a row, surface it once at the top with a fresh timestamp.
        val pruned = current.filter { it.bobaId != bobaId }
        _entries.value = (listOf(Entry(bobaId)) + pruned).take(CAP)
    }

    fun remove(bobaId: String) {
        _entries.value = _entries.value.filter { it.bobaId != bobaId }
    }

    fun clear() {
        _entries.value = emptyList()
    }

    private companion object {
        const val CAP = 25
    }
}
