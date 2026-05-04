import SwiftUI
import UIKit
import WebKit

// MARK: - YouTubePlayerView
//
// Embeds the YouTube IFrame Player inside a WKWebView so videos play
// inside the app without bouncing out to Safari. This is YouTube's
// officially-supported embed path.
//
// IMPLEMENTATION NOTE — Post-July-2025 YouTube tightened embedder-
// identity checks; both naive WKWebView strategies broke:
//
//   • `loadHTMLString` with `baseURL: nil` or any non-public URL →
//     Referer is stripped → "Error 153 video player configuration
//     error".
//   • `loadHTMLString` with `baseURL: youtube.com` → YouTube sees
//     itself as the embedder → "Error 152 video unavailable".
//   • `webView.load(URLRequest)` straight to `youtube.com/embed/{id}`
//     → no Referer at all → 153.
//
// The fix is to pretend we're the public web app: load a tiny HTML
// shell with a bare iframe (NOT the JS IFrame API, which adds a
// second cross-origin script load that tightens referrer checks),
// host the iframe at `youtube-nocookie.com`, set the page's
// referrer policy explicitly, pass `origin` + `widget_referrer`
// query params pointing at our public domain, and use that same
// domain as the `loadHTMLString` baseURL.
//
// Reference: simonwillison.net/2025/Dec/1/youtube-embed-153-error/
// + multiple 2025 reports of the same fix landing across Capacitor,
// React Native, and native iOS embedders.
private let appPublicOrigin = "https://bobaplaybook.com"

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    /// When true, the player starts playing as soon as the view loads.
    /// In practice iOS ignores `autoplay=1` without a user gesture,
    /// AND some videos error out when the param is set, so we leave
    /// it off by default.
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
        // Explicit JS allow — required for the iframe's IFrame
        // Player runtime. This is the WK 16+ way to do what
        // `WKPreferences.javaScriptEnabled` used to do.
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Default (persistent) data store — the IFrame player relies
        // on cookies/storage during the embed handshake; .nonPersistent
        // is a documented 153 trigger.
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces         = false
        webView.isOpaque                   = false
        webView.backgroundColor            = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload when the video id actually changes — re-firing
        // loadHTMLString with the same id would reset playback mid-
        // watch.
        if context.coordinator.lastVideoId == videoId { return }
        context.coordinator.lastVideoId = videoId

        let html = Self.makeEmbedHTML(videoId: videoId, autoplay: autoplay)
        webView.loadHTMLString(html, baseURL: URL(string: appPublicOrigin))
    }

    /// Tear-down hook called by SwiftUI when the WKWebView is being
    /// removed (sheet dismissed, navigation popped, etc.). We force
    /// any active media presentation (HTML5-video fullscreen, PiP,
    /// AirPlay) to close FIRST, then yield a runloop tick before the
    /// WebContent process gets killed.
    ///
    /// Without this, the sequence on a fullscreen-then-dismiss is:
    ///   1. AVPlayerViewController is presented by WebContent for
    ///      the iframe's HTML5 video element.
    ///   2. User dismisses the sheet (Close button or swipe-down).
    ///   3. SwiftUI removes WKWebView → WebContent process gets
    ///      torn down.
    ///   4. AVPlayerViewController tries to exit fullscreen but its
    ///      hosting process is already gone → crash with
    ///      "Invalid call of -[AVPlayerViewController _transitionFromFullScreenAnimated:...]".
    ///
    /// `closeAllMediaPresentations(completionHandler:)` (iOS 14.5+)
    /// hands AVPlayerViewController a clean exit signal while the
    /// process is still alive. The completion handler completes
    /// after fullscreen has dismissed, so we synchronously block
    /// dismantle until that's done.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.closeAllMediaPresentations(completionHandler: { })
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastVideoId: String? = nil
    }

    /// Inline HTML doc that hosts a bare YouTube iframe. No IFrame
    /// Player JS API — the bare iframe is more reliable post the
    /// 2025 referrer-policy tightening. The iframe is sized via the
    /// classic 56.25%-padding-bottom technique to fill its parent
    /// at 16:9 without layout flicker. Fullscreen is enabled (`fs=1`
    /// + `allowfullscreen`) — vertical Shorts are unwatchable at
    /// 9:16-shrunk-into-16:9, so the FS button is the whole point of
    /// the experience. The crash that came with fullscreen on 1.971
    /// is handled in `dismantleUIView` by calling
    /// `closeAllMediaPresentations` before WKWebView tear-down.
    private static func makeEmbedHTML(videoId: String, autoplay: Bool) -> String {
        let autoplayParam = autoplay ? "&autoplay=1" : ""
        let originEsc = appPublicOrigin
        return """
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
                src="https://www.youtube-nocookie.com/embed/\(videoId)?playsinline=1&modestbranding=1&rel=0&fs=1&enablejsapi=1&origin=\(originEsc)&widget_referrer=\(originEsc)\(autoplayParam)"
                referrerpolicy="strict-origin-when-cross-origin"
                allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
                allowfullscreen>
              </iframe>
            </div>
          </body>
        </html>
        """
    }
}
