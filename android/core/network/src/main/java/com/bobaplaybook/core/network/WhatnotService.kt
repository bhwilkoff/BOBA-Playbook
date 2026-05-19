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
)

@Serializable
private data class WhatnotResponse(
    val shows: List<WhatnotRow> = emptyList(),
)

@Serializable
private data class WhatnotRow(
    val id: String? = null,
    val title: String? = null,
    @SerialName("host_username") val host: String? = null,
    @SerialName("host_avatar") val hostAvatarUrl: String? = null,
    @SerialName("scheduled_at") val scheduledAt: Long? = null,
    @SerialName("viewer_count") val viewerCount: Int? = null,
    @SerialName("thumbnail") val thumbnailUrl: String? = null,
    val url: String? = null,
) {
    fun toDomain() = WhatnotShow(
        id = id.orEmpty(),
        title = title.orEmpty(),
        host = host.orEmpty(),
        hostAvatarUrl = hostAvatarUrl,
        scheduledAt = scheduledAt,
        viewerCount = viewerCount ?: 0,
        thumbnailUrl = thumbnailUrl,
        showUrl = url.orEmpty(),
    )
}
