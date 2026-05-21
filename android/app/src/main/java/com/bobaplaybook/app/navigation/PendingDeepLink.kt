package com.bobaplaybook.app.navigation

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * App-scoped deep-link queue. MainActivity parses the incoming Intent
 * and writes the resolved route here; BOBAApp consumes via Flow and
 * dispatches to the right NavController.
 *
 * Mirrors iOS CardStore.pendingScan / pendingSearchQuery pattern.
 */
@Singleton
class PendingDeepLink @Inject constructor() {
    private val _route = MutableStateFlow<DeepLinkRoute?>(null)
    val route: StateFlow<DeepLinkRoute?> = _route.asStateFlow()

    fun set(route: DeepLinkRoute) {
        _route.value = route
    }

    fun consume(): DeepLinkRoute? {
        val current = _route.value
        _route.value = null
        return current
    }
}

/**
 * Parsed deep-link route. Resolved from either:
 *  - Universal App Link: https://bobaplaybook.com/{type}/{id}
 *  - Custom scheme:      bobaplaybook://{type}/{id}
 */
sealed interface DeepLinkRoute {
    data class CardDetail(val bobaId: String) : DeepLinkRoute
    data class SearchQuery(val query: String) : DeepLinkRoute
    data class LearnCategory(val categoryId: String) : DeepLinkRoute
    data class PublicCollection(val username: String) : DeepLinkRoute
    data class DeckShare(val deckId: String) : DeepLinkRoute
    data object Scan : DeepLinkRoute

    companion object {
        /**
         * Parse a `bobaplaybook://...` URI or
         * `https://bobaplaybook.com/...` URI into a route.
         */
        fun parse(uri: android.net.Uri): DeepLinkRoute? {
            val segments = uri.pathSegments
            return when {
                segments.firstOrNull() == "card" && segments.size >= 2 ->
                    CardDetail(segments[1])
                segments.firstOrNull() == "scan" || uri.host == "scan" ->
                    Scan
                segments.firstOrNull() == "search" -> {
                    val q = uri.getQueryParameter("q").orEmpty()
                    if (q.isNotEmpty()) SearchQuery(q) else null
                }
                segments.firstOrNull() == "learn" && segments.size >= 2 ->
                    LearnCategory(segments[1])
                segments.firstOrNull() == "u" && segments.size >= 2 ->
                    PublicCollection(segments[1])
                segments.firstOrNull() == "deck" && segments.size >= 2 ->
                    DeckShare(segments[1])
                else -> null
            }
        }
    }
}
