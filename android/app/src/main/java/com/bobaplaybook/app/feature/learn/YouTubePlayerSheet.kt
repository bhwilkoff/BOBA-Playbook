@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import android.annotation.SuppressLint
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView

/**
 * In-app YouTube player. Tapping a video tile on the Watch tab now
 * opens this full-height bottom sheet instead of bouncing the user
 * out to the YouTube app / Custom Tab. iOS WatchView.swift loads
 * the embed in a sheet for the same reason — keeps the user in
 * BOBA's context and lets us tile a "Back" action without losing
 * the surrounding article copy.
 *
 * Uses YouTube's IFrame embed URL with `autoplay=1` and
 * `playsinline=1` so it plays inline (no involuntary full-screen
 * takeover) but Chrome's full-screen button still works for users
 * who want it. JavaScript is required by the embed; the WebView's
 * settings opt in.
 *
 * `videoId` is the YouTube ID extracted from the feed URL by
 * [extractYouTubeId].
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun YouTubePlayerSheet(
    videoId: String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.Black,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
        ) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    WebView(ctx).apply {
                        layoutParams = android.view.ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                        settings.javaScriptEnabled = true
                        // Required for the IFrame embed's inline + autoplay
                        // behavior; otherwise the player insists on a
                        // user-gesture-triggered fullscreen.
                        settings.mediaPlaybackRequiresUserGesture = false
                        settings.domStorageEnabled = true
                        // Chrome / fullscreen buttons in the embed only
                        // work with a chrome client wired in. Without
                        // this, tapping the FS button is a no-op.
                        webChromeClient = WebChromeClient()
                        webViewClient = WebViewClient()
                        // Solid-black background while the embed boots
                        // so the white framework default doesn't flash.
                        setBackgroundColor(android.graphics.Color.BLACK)
                        val embedHtml = """
                            <!DOCTYPE html>
                            <html><head>
                              <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
                              <style>
                                html,body{margin:0;padding:0;background:#000;height:100%;}
                                iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0;}
                              </style>
                            </head><body>
                              <iframe
                                src="https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1&rel=0&modestbranding=1"
                                allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
                                allowfullscreen></iframe>
                            </body></html>
                        """.trimIndent()
                        loadDataWithBaseURL(
                            "https://www.youtube.com",
                            embedHtml,
                            "text/html",
                            "utf-8",
                            null,
                        )
                    }
                },
            )
        }
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
    // youtu.be/ID and youtube.com/shorts/ID — last path segment is the ID.
    Regex("""(?:youtu\.be/|youtube\.com/shorts/|youtube\.com/embed/|youtube\.com/live/)([A-Za-z0-9_-]{11})""")
        .find(url)
        ?.groupValues?.getOrNull(1)
        ?.let { return it }
    // youtube.com/watch?v=ID
    Regex("""[?&]v=([A-Za-z0-9_-]{11})""")
        .find(url)
        ?.groupValues?.getOrNull(1)
        ?.let { return it }
    return null
}
