package com.bobaplaybook.app.feature.find

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Tick 279 — singleton bus for Find-tab actions dispatched from outside
 * the Find composable hierarchy (e.g. root-level hardware-keyboard
 * handlers in BOBAApp). FindScreen collects [surpriseRequested] in a
 * LaunchedEffect and fires its existing onSurpriseMe pick logic.
 *
 * Mirrors iOS v2.311 + web tick 273 keyboard parity. iPhone has no
 * keyboard so iOS handles this with .keyboardShortcut on a hidden
 * Button at SearchView root; web uses a document.addEventListener.
 * Android needs a singleton because the root focusable Box that owns
 * the keyboard event lives in BOBAApp.kt, well above FindScreen's
 * composition.
 */
@Singleton
class FindActions @Inject constructor() {
    private val _surpriseRequested = MutableSharedFlow<Unit>(
        replay = 0,
        extraBufferCapacity = 1,
    )
    val surpriseRequested: SharedFlow<Unit> = _surpriseRequested.asSharedFlow()

    fun requestSurprise() {
        _surpriseRequested.tryEmit(Unit)
    }
}
