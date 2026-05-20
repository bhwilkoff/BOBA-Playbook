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
 * YouTube feed fetcher — hits `boba-youtube-feed` Worker.
 *
 * Worker pre-categorizes into three feeds (upcoming live streams,
 * vertical Shorts, horizontal videos) and hydrates each video with
 * `videos.list` metadata (duration, view count, live state). The
 * Android client only deserializes + renders.
 *
 * Returns an empty bundle on failure so the Watch tab degrades to
 * "Couldn't load feed" rather than crashing.
 *
 * Worker source-of-truth: workers/youtube-feed/worker.js
 */
@Singleton
class YouTubeFeedService @Inject constructor(
    private val httpClient: HttpClient,
) {

    suspend fun loadAll(): YouTubeFeedBundle = withContext(Dispatchers.IO) {
        runCatching {
            httpClient.get("${WorkerConfig.YOUTUBE_FEED}/").body<YouTubeFeedBundle>()
        }.getOrDefault(EMPTY)
    }

    companion object {
        val EMPTY = YouTubeFeedBundle(
            upcoming = emptyList(),
            vertical = emptyList(),
            horizontal = emptyList(),
            writtenAt = null,
        )
    }
}

@Serializable
data class YouTubeFeedBundle(
    val upcoming: List<YouTubeVideo> = emptyList(),
    val vertical: List<YouTubeVideo> = emptyList(),
    val horizontal: List<YouTubeVideo> = emptyList(),
    @SerialName("writtenAt") val writtenAt: String? = null,
)

@Serializable
data class YouTubeVideo(
    val videoId: String,
    val title: String,
    val description: String? = null,
    val publishedAt: String? = null,
    val streamTime: String? = null,
    val scheduledStartTime: String? = null,
    val actualStartTime: String? = null,
    val actualEndTime: String? = null,
    val channelId: String? = null,
    val channelTitle: String? = null,
    val thumbnail: String? = null,
    val thumbnailWidth: Int? = null,
    val thumbnailHeight: Int? = null,
    val isVertical: Boolean = false,
    val durationSec: Int? = null,
    val viewCount: Int? = null,
    val likeCount: Int? = null,
    val commentCount: Int? = null,
    val embeddable: Boolean? = null,
    val liveBroadcastContent: String? = null,
    val priority: Int = 9,
    val sourceChannel: String? = null,
    val url: String,
    val embedUrl: String,
) {
    val isLiveNow: Boolean get() = liveBroadcastContent == "live"
    val isUpcoming: Boolean get() = liveBroadcastContent == "upcoming"

    /** "1:23" / "12:34" / "1:02:03"; null for unknown (live in progress). */
    val durationLabel: String?
        get() = durationSec?.let { s ->
            val h = s / 3600
            val m = (s % 3600) / 60
            val sec = s % 60
            if (h > 0) "%d:%02d:%02d".format(h, m, sec)
            else "%d:%02d".format(m, sec)
        }

    /** Short view-count label: "1.2K views" / "847K views" / "1.4M views". */
    val viewCountLabel: String?
        get() = viewCount?.let { n ->
            when {
                n >= 1_000_000 -> "%.1fM views".format(n / 1_000_000.0)
                n >= 1_000     -> "%.1fK views".format(n / 1_000.0)
                else           -> "$n views"
            }
        }
}
