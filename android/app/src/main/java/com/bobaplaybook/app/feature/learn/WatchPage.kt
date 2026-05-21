@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.network.YouTubeVideo
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * Watch tab — three feed sections (live+upcoming · videos · shorts)
 * with M3 tap-to-open via Custom Tab. iOS YouTubeFeedService parity.
 *
 * Worker: `boba-youtube-feed.benwilkoff.workers.dev`
 *  - Live broadcasts surface a brand-orange LIVE pill in the thumb
 *  - Duration label badge bottom-right (omitted when live)
 *  - Channel + view count subtitle
 *  - Vertical Shorts use a portrait 80×142 thumbnail; horizontal
 *    videos use a 16:9 140×80 landscape thumbnail
 */
@Composable
internal fun WatchPageContent() {
    val vm: WatchViewModel = hiltViewModel()
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current

    val openVideo: (String) -> Unit = { url ->
        CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url))
    }

    val emptyBundle = state.bundle.upcoming.isEmpty() &&
        state.bundle.vertical.isEmpty() &&
        state.bundle.horizontal.isEmpty()

    when {
        state.isLoading && emptyBundle -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        emptyBundle -> {
            // Distinguish "fetch failed" from "loaded but the channel
            // has no current content." Prior copy ("Couldn't load
            // videos") fired on both cases — misleading when the
            // YouTube channel just temporarily has nothing new.
            val isFetchError = state.error != null
            BOBAEmptyState(
                icon = Icons.Default.PlayArrow,
                headline = if (isFetchError) "Couldn't load videos" else "No videos right now",
                body = state.error ?: "Check back soon — the BoBA channel updates frequently.",
                actionLabel = "Retry",
                onAction = { vm.refresh() },
                modifier = Modifier.fillMaxSize(),
            )
        }
        else -> {
            val scope = androidx.compose.runtime.rememberCoroutineScope()
            var isRefreshing by androidx.compose.runtime.remember {
                androidx.compose.runtime.mutableStateOf(false)
            }
            // Tab picker — iOS WatchView parity. The previous stacked-
            // section layout buried Live+Upcoming under Videos as the
            // user scrolled. A segmented tab makes the three feeds
            // explicit and surfaces the count per tab.
            var tab by androidx.compose.runtime.saveable.rememberSaveable {
                androidx.compose.runtime.mutableStateOf("upcoming")
            }
            val items = when (tab) {
                "upcoming"   -> state.bundle.upcoming
                "horizontal" -> state.bundle.horizontal
                "vertical"   -> state.bundle.vertical
                else         -> emptyList()
            }
            Column(modifier = Modifier.fillMaxSize()) {
                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    val tabs = listOf(
                        "upcoming"   to "Upcoming Live (${state.bundle.upcoming.size})",
                        "horizontal" to "Horizontal (${state.bundle.horizontal.size})",
                        "vertical"   to "Vertical (${state.bundle.vertical.size})",
                    )
                    tabs.forEachIndexed { index, pair ->
                        val key = pair.first
                        val label = pair.second
                        SegmentedButton(
                            selected = tab == key,
                            onClick = { tab = key },
                            shape = SegmentedButtonDefaults.itemShape(index, tabs.size),
                            icon = {},
                        ) {
                            Text(label, style = MaterialTheme.typography.labelSmall, maxLines = 1)
                        }
                    }
                }
                androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        vm.refresh()
                        scope.launch {
                            kotlinx.coroutines.delay(800)
                            isRefreshing = false
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    if (items.isEmpty()) {
                        BOBAEmptyState(
                            icon = Icons.Default.PlayArrow,
                            headline = when (tab) {
                                "upcoming"   -> "No upcoming streams"
                                "horizontal" -> "No horizontal videos yet"
                                else         -> "No vertical videos yet"
                            },
                            body = "Pull down to refresh. New uploads appear every few minutes.",
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(items, key = { "${tab}-${it.videoId}" }) { v ->
                                VideoRow(
                                    video = v,
                                    onClick = { openVideo(v.url) },
                                    vertical = (tab == "vertical"),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VideoRow(
    video: YouTubeVideo,
    onClick: () -> Unit,
    vertical: Boolean = false,
) {
    Surface(
        onClick = onClick,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Row(
            modifier = Modifier.padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val thumbWidth = if (vertical) 80.dp else 140.dp
            val thumbHeight = if (vertical) 142.dp else 80.dp
            Box(
                modifier = Modifier
                    .size(thumbWidth, thumbHeight)
                    .clip(MaterialTheme.shapes.small)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh),
            ) {
                video.thumbnail?.let { url ->
                    AsyncImage(
                        model = ImageRequest.Builder(LocalContext.current)
                            .data(url).crossfade(150).build(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                if (video.isLiveNow) {
                    Surface(
                        color = Color(0xFFFF4D00),
                        shape = RoundedCornerShape(4.dp),
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(4.dp),
                    ) {
                        Text(
                            "LIVE",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                }
                if (!video.isLiveNow) {
                    video.durationLabel?.let { label ->
                        Surface(
                            color = Color.Black.copy(alpha = 0.75f),
                            shape = RoundedCornerShape(4.dp),
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(4.dp),
                        ) {
                            Text(
                                label,
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.White,
                                modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                            )
                        }
                    }
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    video.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 2,
                )
                val subtitle = buildList {
                    video.channelTitle?.let { add(it) }
                    video.viewCountLabel?.let { add(it) }
                }.joinToString(" · ")
                if (subtitle.isNotBlank()) {
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
                // Upcoming / live streams surface the stream-time label
                // ("Tomorrow at 1:00 PM" / "Live now") so users can
                // decide whether to tune in. Skips for VOD videos.
                if (video.isLiveNow || video.isUpcoming) {
                    video.streamTimeLabel?.let { label ->
                        Text(
                            label,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (video.isLiveNow) Color(0xFFFF4D00)
                                    else MaterialTheme.colorScheme.primary,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}
