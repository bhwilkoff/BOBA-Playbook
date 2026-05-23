@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.bobaplaybook.core.network.YouTubeVideo
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.DisplayFontFamily

/**
 * In-app YouTube video page. Tapping a Watch tile now opens this
 * full-height bottom sheet instead of kicking the user out to the
 * YouTube app / Custom Tab. Layout mirrors iOS WatchView's
 * `VideoPlayerSheet`:
 *
 *   • 16:9 IFrame embed at the top (autoplay + playsinline)
 *   • Title (display font, ~18sp)
 *   • Subtitle row — channel · relative published date · view count
 *   • Description text (selectable, multi-line, links coloured cyan)
 *   • Close button (top-leading) + Open in YouTube (top-trailing)
 *
 * Passing the full [YouTubeVideo] (not just the id) ensures we have
 * description / channelTitle / viewCount on-hand without re-fetching
 * — the feed Worker already hydrates every video with those fields
 * (YouTubeFeedService.kt).
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun YouTubePlayerSheet(
    video: YouTubeVideo,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top action bar — Close (left) + Open in YouTube (right).
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close",
                        tint = BobaBrand.Orange,
                    )
                }
                androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
                IconButton(onClick = {
                    // Prefer the YouTube app via the youtube:// scheme;
                    // fall back to Custom Tabs for the same video URL.
                    val youtubeAppUri = Uri.parse("vnd.youtube:${video.videoId}")
                    val intent = Intent(Intent.ACTION_VIEW, youtubeAppUri)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    runCatching { context.startActivity(intent) }
                        .onFailure {
                            val web = "https://www.youtube.com/watch?v=${video.videoId}"
                            CustomTabsIntent.Builder().build()
                                .launchUrl(context, Uri.parse(web))
                        }
                }) {
                    Icon(
                        imageVector = Icons.Default.OpenInBrowser,
                        contentDescription = "Open in YouTube",
                        tint = BobaBrand.Cyan,
                    )
                }
            }

            // 16:9 player surface — black backdrop while the embed
            // boots so we don't see the framework default flash.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .background(Color.Black),
            ) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { ctx ->
                        WebView(ctx).apply {
                            layoutParams = android.view.ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                            // Settings parity with iOS WKWebView's config in
                            // YouTubePlayerView.swift. JS is required for the
                            // IFrame Player runtime, DOM storage + cookies for
                            // the cross-origin embed handshake, no user-gesture
                            // gate so playback starts inline.
                            settings.javaScriptEnabled = true
                            settings.mediaPlaybackRequiresUserGesture = false
                            settings.domStorageEnabled = true
                            settings.loadsImagesAutomatically = true
                            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                            // YouTube embed handshake needs to set + read
                            // cross-origin cookies. Without third-party cookie
                            // acceptance the player sometimes errors as
                            // "video unavailable" (152) intermittently.
                            CookieManager.getInstance().setAcceptCookie(true)
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                            webChromeClient = WebChromeClient()
                            webViewClient = WebViewClient()
                            setBackgroundColor(android.graphics.Color.BLACK)
                            // Mirror iOS WKWebView fix in
                            // BOBAPlaybook/Components/YouTubePlayerView.swift:
                            //   - host iframe at `youtube-nocookie.com` (not
                            //     `youtube.com`; the cookied host triggers
                            //     embedder-identity self-checks → error 152)
                            //   - meta + iframe referrerpolicy explicitly
                            //     `strict-origin-when-cross-origin`
                            //   - pass `origin` + `widget_referrer` query
                            //     params pointing at our public domain
                            //   - load with that same domain as the
                            //     `baseUrl` so the WebView sends the
                            //     correct Referer / Origin headers
                            // Reference:
                            //   simonwillison.net/2025/Dec/1/youtube-embed-153-error
                            val appPublicOrigin = "https://bobaplaybook.com"
                            val embedHtml = """
                                <!DOCTYPE html>
                                <html>
                                  <head>
                                    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
                                    <meta name="referrer" content="strict-origin-when-cross-origin">
                                    <style>
                                      html, body { margin: 0; padding: 0; background: #000; height: 100%; width: 100%; overflow: hidden; }
                                      .wrap { position: relative; width: 100%; height: 100%; }
                                      .wrap iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
                                    </style>
                                  </head>
                                  <body>
                                    <div class="wrap">
                                      <iframe
                                        src="https://www.youtube-nocookie.com/embed/${video.videoId}?playsinline=1&modestbranding=1&rel=0&fs=1&enablejsapi=1&origin=$appPublicOrigin&widget_referrer=$appPublicOrigin"
                                        referrerpolicy="strict-origin-when-cross-origin"
                                        allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
                                        allowfullscreen>
                                      </iframe>
                                    </div>
                                  </body>
                                </html>
                            """.trimIndent()
                            loadDataWithBaseURL(
                                appPublicOrigin,
                                embedHtml,
                                "text/html",
                                "utf-8",
                                null,
                            )
                        }
                    },
                )
            }

            // Title + metadata + description scroll panel below the
            // player. Vertical scroll so long descriptions don't push
            // the player off-screen.
            val descScroll = rememberScrollState()
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(descScroll)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    text = video.title,
                    fontSize = 18.sp,
                    fontFamily = DisplayFontFamily,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                VideoSubtitleRow(video)
                video.description?.takeIf { it.isNotBlank() }?.let { desc ->
                    androidx.compose.material3.HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                    )
                    // Selectable + multi-line description text — URLs
                    // aren't auto-linkified here (Compose's AnnotatedString
                    // would let us style them); for now plain text matches
                    // iOS-the-best-we-can-without-AttributedString plumbing.
                    androidx.compose.foundation.text.selection.SelectionContainer {
                        Text(
                            text = desc,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/**
 * Channel · relative date · view count subtitle. Mirrors iOS
 * WatchView.CardSubtitle (non-compact variant).
 */
@Composable
private fun VideoSubtitleRow(video: YouTubeVideo) {
    val parts = buildList<SubtitlePart> {
        video.channelTitle?.takeIf { it.isNotBlank() }?.let { add(ChannelPart(it)) }
        relativePublished(video.publishedAt)?.let { add(MutedPart(it)) }
        video.viewCount?.takeIf { it > 0 }?.let { add(MutedPart("${formatViews(it)} views")) }
    }
    if (parts.isEmpty()) return
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        parts.forEachIndexed { idx, part ->
            if (idx > 0) {
                Text(
                    text = "·",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            when (part) {
                is ChannelPart -> Text(
                    text = part.text,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = BobaBrand.Cyan,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                is MutedPart -> Text(
                    text = part.text,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private sealed interface SubtitlePart
private data class ChannelPart(val text: String) : SubtitlePart
private data class MutedPart(val text: String) : SubtitlePart

/** "1.2K", "356K", "4.5M" style formatter — iOS WatchView.formatViews parity. */
private fun formatViews(n: Int): String = when {
    n >= 1_000_000 -> "${"%.1f".format(n / 1_000_000.0)}M".replace(".0M", "M")
    n >= 1_000 -> "${"%.1f".format(n / 1_000.0)}K".replace(".0K", "K")
    else -> n.toString()
}

/** "5 min ago" / "2h ago" / "3d ago" / "May 22" — iOS publishedRelative parity. */
private fun relativePublished(iso: String?): String? {
    if (iso.isNullOrBlank()) return null
    val instant = runCatching { java.time.Instant.parse(iso) }.getOrNull() ?: return null
    val sec = java.time.Duration.between(instant, java.time.Instant.now()).seconds
    return when {
        sec < 60 -> "just now"
        sec < 3_600 -> "${sec / 60} min ago"
        sec < 86_400 -> "${sec / 3_600}h ago"
        sec < 86_400 * 7 -> "${sec / 86_400}d ago"
        sec < 86_400 * 30 -> "${sec / (86_400 * 7)}w ago"
        sec < 86_400 * 365 -> "${sec / (86_400 * 30)}mo ago"
        else -> "${sec / (86_400 * 365)}y ago"
    }
}

/**
 * Pull the 11-character YouTube video ID from any reasonable feed
 * URL shape — handles `https://www.youtube.com/watch?v=ID`,
 * `https://youtu.be/ID`, and `https://www.youtube.com/shorts/ID`.
 * Returns null when the URL doesn't look like YouTube; callers
 * should fall back to opening the raw URL in a Custom Tab.
 */
fun extractYouTubeId(url: String): String? {
    if (url.isBlank()) return null
    Regex("""(?:youtu\.be/|youtube\.com/shorts/|youtube\.com/embed/|youtube\.com/live/)([A-Za-z0-9_-]{11})""")
        .find(url)
        ?.groupValues?.getOrNull(1)
        ?.let { return it }
    Regex("""[?&]v=([A-Za-z0-9_-]{11})""")
        .find(url)
        ?.groupValues?.getOrNull(1)
        ?.let { return it }
    return null
}
