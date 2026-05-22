package com.bobaplaybook.app.navigation

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Tab-tap refresh bus.
 *
 * Ben's punch-list #6: "When a new view is tapped, it should force a
 * refresh of that view so that we don't have any situations where
 * the screen for that view stays blank (has happened on the find
 * view a few times)."
 *
 * BOBAApp emits a [AppDestination] every time the user taps a
 * NavigationBarItem — whether or not the destination changes. Per-
 * tab ViewModels (WatchViewModel, PurchaseViewModel, FindViewModel,
 * CollectionViewModel, DecksViewModel) collect this flow and force
 * a fresh fetch of their backing data when the bus emits their own
 * destination. Stuck-blank screens recover with a single tab tap.
 *
 * Singleton SharedFlow with `replay = 0` + `extraBufferCapacity = 1`
 * so a tap fired while no collector is active doesn't queue a
 * phantom refresh — only currently-observing VMs see the event.
 */
@Singleton
class TabRefreshBus @Inject constructor() {
    private val _events = MutableSharedFlow<AppDestination>(
        replay = 0,
        extraBufferCapacity = 1,
    )
    val events: SharedFlow<AppDestination> = _events.asSharedFlow()

    fun signalTap(destination: AppDestination) {
        _events.tryEmit(destination)
    }
}
