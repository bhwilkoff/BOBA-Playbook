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
    /** Card identified by full v3 bobaId — legacy path-style URL or in-app push. */
    data class CardDetail(val bobaId: String) : DeepLinkRoute

    /** Card identified by query-params (the canonical share-URL shape since
     *  bobaId v3 / DECISIONS.md #057). element disambiguates weapon-variant
     *  pairs (FIRE/GLOW etc.) that share cardNumber+hero+treatment. */
    data class CardDetailByFields(
        val cardNumber: String,
        val hero: String?,
        val treatment: String?,
        val element: String?,
    ) : DeepLinkRoute

    data class SearchQuery(val query: String) : DeepLinkRoute
    data class LearnCategory(val categoryId: String) : DeepLinkRoute
    data class PublicCollection(val username: String) : DeepLinkRoute
    data class DeckShare(val deckId: String) : DeepLinkRoute
    data object Scan : DeepLinkRoute

    companion object {
        /**
         * Parse a `bobaplaybook://...` URI or
         * `https://bobaplaybook.com/...` URI into a route.
         *
         * Card URLs come in two shapes:
         *  - Query-param (canonical since bobaId v3):
         *    `https://bobaplaybook.com/?card=GLBF-43&hero=BoJax&treatment=...&element=FIRE`
         *  - Legacy path (still accepted for backwards-compat with
         *    Android share URLs already in the wild):
         *    `https://bobaplaybook.com/card/{full v3 bobaId}`
         */
        fun parse(uri: android.net.Uri): DeepLinkRoute? {
            val segments = uri.pathSegments
            val cardQuery = uri.getQueryParameter("card")
            return when {
                // Query-param card URL — checked FIRST so root-path
                // `/?card=…` doesn't fall through to scheme-only logic.
                !cardQuery.isNullOrEmpty() ->
                    CardDetailByFields(
                        cardNumber = cardQuery.uppercase(),
                        hero       = uri.getQueryParameter("hero"),
                        treatment  = uri.getQueryParameter("treatment"),
                        element    = uri.getQueryParameter("element")?.uppercase(),
                    )
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
