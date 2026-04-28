import SwiftUI
import UIKit
import WebKit

// MARK: - YouTubePlayerView
//
// Embeds the YouTube IFrame Player API inside a WKWebView so videos
// play inside the app without bouncing out to Safari. This is
// YouTube's officially-supported embed path (per
// developers.google.com/youtube/iframe_api_reference) — the WKWebView
// is just a thin native shell around the same iframe a webpage would
// host. Apple's archived `youtube-ios-player-helper` did the exact
// same thing.
//
// `playsinline` keeps the video confined to the host view rather than
// auto-presenting full-screen on first play; users get a full-screen
// button on the player controls when they want it.
//
// The web view loads a self-contained HTML doc (no remote page) so we
// don't pay a navigation roundtrip on every present, and so the
// YouTube cookie surface stays minimal. The `baseURL` we hand
// loadHTMLString is `https://www.youtube.com` so the embedded iframe
// passes referrer checks correctly.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    /// When true, the player starts playing as soon as the view loads.
    /// Defaults to false because muted-autoplay on a launch is the kind
    /// of "did the app just take over my speakers" surprise we want to
    /// avoid.
    var autoplay: Bool = false

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Inline playback: stay inside our frame instead of auto-
        // presenting AVPlayerViewController full-screen the moment
        // the user taps play.
        config.allowsInlineMediaPlayback = true
        // Skip the "tap to play" gate — the user already tapped a
        // tile to open the player sheet, requiring a second tap to
        // start playback feels broken.
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces         = false
        webView.isOpaque                   = false
        webView.backgroundColor            = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload when the video id actually changes — re-running
        // loadHTMLString with the same id resets playback.
        if context.coordinator.lastVideoId == videoId { return }
        context.coordinator.lastVideoId = videoId

        let html = Self.makeEmbedHTML(videoId: videoId, autoplay: autoplay)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastVideoId: String? = nil
    }

    /// Single-page HTML doc that boots the IFrame API. Keeping it
    /// inline (as opposed to a remote page) means: zero extra network
    /// hop, no caching weirdness, and easy iteration when we want to
    /// expose more player controls (next/prev, currentTime bridge,
    /// etc.) later.
    private static func makeEmbedHTML(videoId: String, autoplay: Bool) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body { width: 100%; height: 100%; background: black; overflow: hidden; }
            #player-wrap { width: 100%; height: 100%; position: relative; }
            #player { position: absolute; inset: 0; width: 100%; height: 100%; }
          </style>
        </head>
        <body>
          <div id="player-wrap"><div id="player"></div></div>
          <script>
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            document.head.appendChild(tag);
            function onYouTubeIframeAPIReady() {
              new YT.Player('player', {
                videoId: '\(videoId)',
                playerVars: {
                  playsinline:    1,
                  modestbranding: 1,
                  rel:            0,
                  autoplay:       \(autoplay ? 1 : 0)
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }
}
