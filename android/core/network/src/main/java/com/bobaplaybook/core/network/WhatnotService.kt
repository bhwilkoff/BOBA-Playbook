package com.bobaplaybook.core.network

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Whatnot upcoming-breaks fetcher — hits the existing
 * `boba-ebay-proxy/whatnot/upcoming` Worker endpoint.
 *
 * Same shape iOS + web consume. Returns empty on failure (offline,
 * Whatnot rate-limit) so the UI degrades to "no upcoming breaks
 * found" rather than crashing.
 */
@Singleton
class WhatnotService @Inject constructor(
    private val httpClient: HttpClient,
) {

    suspend fun upcomingBreaks(): List<WhatnotShow> = withContext(Dispatchers.IO) {
        runCatching {
            val response: WhatnotResponse = httpClient.get(
                "${WorkerConfig.EBAY_PROXY}/whatnot/upcoming",
            ).body()
            response.shows.map { it.toDomain() }
        }.getOrDefault(emptyList())
    }
}

data class WhatnotShow(
    val id: String,
    val title: String,
    val host: String,
    val hostAvatarUrl: String?,
    val scheduledAt: Long?,
    val viewerCount: Int,
    val thumbnailUrl: String?,
    val showUrl: String,
    val isLive: Boolean,
    // Tick 516 — iOS WhatnotShowsService.swift:25 has this too.
    // Worker exposes `categoryName` at worker.js:2052; we just
    // weren't surfacing it. Rendered uppercase in WhatnotTile
    // bottom row for iOS parity.
    val categoryName: String = "",
)

@Serializable
private data class WhatnotResponse(
    val shows: List<WhatnotRow> = emptyList(),
)

/**
 * Worker `boba-ebay-proxy /whatnot/upcoming` returns camelCase fields,
 * not snake_case. The Worker shape lives in workers/ebay-proxy/worker.js
 * — keep this row in lockstep with it. Verified 2026-05-20 against
 * the live endpoint.
 */
@Serializable
private data class WhatnotRow(
    val showId: String? = null,
    val showUrl: String? = null,
    val title: String? = null,
    val host: String? = null,
    val hostUrl: String? = null,
    val status: String? = null,
    val isLive: Boolean? = null,
    val scheduledTimeIso: String? = null,
    val startTimeMs: Long? = null,
    val viewerCount: Int? = null,
    val thumbnailUrl: String? = null,
    val categoryName: String? = null,
) {
    fun toDomain(): WhatnotShow {
        // Synthesize a stable ID when the Worker doesn't send one —
        // otherwise multiple shows collapse to id="" and the
        // LazyColumn's stable-key contract crashes with
        // IllegalArgumentException("Key \"\" was already used").
        val resolvedId = showId?.takeIf { it.isNotBlank() }
            ?: listOfNotNull(host, title, startTimeMs?.toString(), showUrl)
                .joinToString("|")
                .ifBlank { "show-${System.identityHashCode(this)}" }
        return WhatnotShow(
            id = resolvedId,
            title = title.orEmpty(),
            host = host.orEmpty(),
            hostAvatarUrl = null,  // Worker doesn't surface a host avatar
            scheduledAt = startTimeMs,
            viewerCount = viewerCount ?: 0,
            thumbnailUrl = thumbnailUrl,
            showUrl = showUrl.orEmpty(),
            isLive = isLive ?: (status == "LIVE"),
            categoryName = categoryName.orEmpty(),
        )
    }
}
