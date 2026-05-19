package com.bobaplaybook.app.connectivity

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob

/**
 * Connectivity tracker (ANDROID-DESIGN.md §6.7 — universal "offline"
 * state).
 *
 * Exposes a hot StateFlow<Boolean> that emits `true` when the device
 * is online (any non-cellular default route counts as well as cell). UI
 * surfaces a [BOBAOfflinePill] when `false`.
 *
 * Uses ConnectivityManager.NetworkCallback rather than the deprecated
 * activeNetworkInfo polling pattern. NetworkCallback fires immediately
 * on registration with the current state.
 */
@Singleton
class ConnectivityState @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    val isOnline: Flow<Boolean> = callbackFlow {
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { trySend(true) }
            override fun onLost(network: Network)       { trySend(false) }
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                trySend(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        cm.registerNetworkCallback(request, callback)

        // Seed with current state — onCapabilitiesChanged fires after registration
        // but emit immediately so UI doesn't blink the offline pill.
        val active = cm.activeNetwork
        val caps = active?.let { cm.getNetworkCapabilities(it) }
        trySend(caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true)

        awaitClose { cm.unregisterNetworkCallback(callback) }
    }.distinctUntilChanged()
        .stateIn(
            scope = CoroutineScope(SupervisorJob()),
            started = SharingStarted.Eagerly,
            initialValue = true,
        )
}
