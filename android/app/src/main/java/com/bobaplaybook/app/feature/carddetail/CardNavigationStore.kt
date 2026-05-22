package com.bobaplaybook.app.feature.carddetail

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Shared list of sibling cards for in-detail swipe navigation —
 * parity with iOS `navigationCards: [Card]` (CardDetailView.swift).
 *
 * Find / Decks / Collection each populate this store with the
 * currently-visible result set BEFORE navigating to the detail screen.
 * The detail screen reads the list + uses the incoming `bobaId`
 * as the starting index. Horizontal swipe advances the index in-place
 * (no navigation push); the detail view re-renders for the new bobaId.
 *
 * Why a shared store rather than route arguments: a Find search can
 * easily push 100+ matching cards through; serializing that list of
 * bobaIds into a navigation argument is fragile (URL-encoded JSON
 * blob, ~2 KB Android arg ceiling). A process-scoped singleton is
 * the cheap solution.
 *
 * When the source list churns (filter change, navigation pop), call
 * [set] from the source screen with the fresh list. [clear] when
 * the detail screen is no longer on screen.
 */
@Singleton
class CardNavigationStore @Inject constructor() {
    private val _bobaIds = MutableStateFlow<List<String>>(emptyList())
    val bobaIds: StateFlow<List<String>> = _bobaIds.asStateFlow()

    // Tick 329 — Ctrl+→ / Ctrl+← keyboard shortcut bus. BOBAApp root
    // emits a delta (+1 / -1) and the CardDetailScreen LaunchedEffect
    // collects + applies via the existing wrap-around index math. If no
    // CardDetailScreen is composed (user isn't on card detail), the
    // collect never runs — the keystroke is a no-op.
    private val _requestAdvance = kotlinx.coroutines.flow.MutableSharedFlow<Int>(
        replay = 0,
        extraBufferCapacity = 1,
    )
    val requestAdvance: kotlinx.coroutines.flow.SharedFlow<Int> =
        _requestAdvance.asSharedFlow()

    fun set(ids: List<String>) {
        _bobaIds.value = ids
    }

    fun clear() {
        _bobaIds.value = emptyList()
    }

    fun advance(delta: Int) {
        _requestAdvance.tryEmit(delta)
    }
}
