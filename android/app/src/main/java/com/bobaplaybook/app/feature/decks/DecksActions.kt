package com.bobaplaybook.app.feature.decks

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Tick 309 — singleton bus for Decks-tab actions dispatched from
 * outside the Decks composable hierarchy (e.g. root-level hardware-
 * keyboard handlers in BOBAApp).
 *
 * Mirrors [com.bobaplaybook.app.feature.find.FindActions] from
 * tick 279.
 *
 * Carries:
 *  - [savePressed] — Ctrl+S keyboard shortcut → DecksScreen invokes
 *    save if the editor is open + auth + non-empty deck.
 *  - [clearPressed] — `n` keyboard shortcut → DecksScreen surfaces
 *    the clear-deck confirm dialog (or runs clear when draft empty).
 *    iOS Cmd+N (v2.322) + web 'n' (tick 323) parity.
 */
@Singleton
class DecksActions @Inject constructor() {
    private val _savePressed = MutableSharedFlow<Unit>(
        replay = 0,
        extraBufferCapacity = 1,
    )
    val savePressed: SharedFlow<Unit> = _savePressed.asSharedFlow()

    private val _clearPressed = MutableSharedFlow<Unit>(
        replay = 0,
        extraBufferCapacity = 1,
    )
    val clearPressed: SharedFlow<Unit> = _clearPressed.asSharedFlow()

    fun requestSave() {
        _savePressed.tryEmit(Unit)
    }

    fun requestClear() {
        _clearPressed.tryEmit(Unit)
    }
}
