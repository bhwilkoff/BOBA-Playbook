import SwiftUI
import UIKit
import WebKit

// MARK: - YouTubePlayerView
//
// Embeds the YouTube IFrame Player inside a WKWebView so videos play
// inside the app without bouncing out to Safari. This is YouTube's
// officially-supported embed path; the WKWebView is just a thin
// native shell around the same iframe a webpage would host.
//
// IMPLEMENTATION NOTE — we load the embed URL directly
// (`https://www.youtube.com/embed/{id}?...`) rather than wrapping
// the IFrame Player JS API inside a `loadHTMLString` doc. The
// HTMLString approach trips a "Video unavailable / Error 152" page
// for some otherwise-embeddable videos because `window.location.
// origin` is `null` when WKWebView loads inline HTML, and YouTube's
// player rejects the embed under that origin. Loading the embed URL
// natively gives the iframe a real https://www.youtube.com origin
// so the player's referrer/origin checks pass.
//
// `playsinline=1` keeps the video confined to the host view rather
// than auto-presenting full-screen on first play; users still get a
// full-screen button on the player controls.
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
        // Only reload when the video id actually changes — re-firing
        // load() with the same id would reset playback mid-watch.
        if context.coordinator.lastVideoId == videoId { return }
        context.coordinator.lastVideoId = videoId

        guard let url = Self.makeEmbedURL(videoId: videoId, autoplay: autoplay) else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastVideoId: String? = nil
    }

    /// Build the canonical YouTube embed URL with the player tuned
    /// for in-app playback (inline, no related videos, low-chrome
    /// branding). Adopting the embed URL directly — instead of
    /// constructing a script-driven IFrame inside `loadHTMLString` —
    /// is the workaround for the "Video unavailable / Error 152"
    /// error that hits otherwise-embeddable videos when the
    /// origin is null.
    private static func makeEmbedURL(videoId: String, autoplay: Bool) -> URL? {
        var comps = URLComponents(string: "https://www.youtube.com/embed/\(videoId)")
        comps?.queryItems = [
            URLQueryItem(name: "playsinline",    value: "1"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "rel",            value: "0"),
            URLQueryItem(name: "autoplay",       value: autoplay ? "1" : "0"),
        ]
        return comps?.url
    }
}
