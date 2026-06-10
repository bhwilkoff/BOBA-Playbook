//
//  CachedAsyncCardImage.swift
//  BOBAPlaybook
//
//  Lightweight cached image loader for card images in practice battle and
//  deck builder views. Uses the same shared NSCache as CardImageView.
//  Does NOT require CardStore in the environment.
//

import SwiftUI

struct CachedAsyncCardImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    @State private var image: UIImage? = nil
    @State private var loadedURL: URL? = nil
    @State private var failed = false

    /// The image to render right now. Two-stage resolution guarantees
    /// the displayed art always matches `url`:
    ///   1. If our @State image was loaded for THIS url, use it.
    ///   2. Otherwise consult NSCache for THIS url synchronously —
    ///      if found, render immediately (no spinner flicker).
    ///   3. Otherwise nil → caller shows placeholder/spinner.
    /// Nothing in this property ever returns an image whose URL
    /// doesn't equal the current `url`, which closes the "card art
    /// doesn't match name/weapon" bug at its source: a SwiftUI
    /// re-render with a new url parameter (e.g. active-hero swap,
    /// substitution, hero replace) used to leave stale art on
    /// screen because the @State image wasn't bound to the URL.
    private var displayImage: UIImage? {
        if let image, loadedURL == url { return image }
        return cardImageCache.object(forKey: url as NSURL)
    }

    var body: some View {
        // Always maintain card aspect ratio (5:7) so loading/failed states
        // don't cause layout shifts or squished frames
        Color.clear
            .aspectRatio(5.0/7.0, contentMode: .fit)
            .overlay {
                Group {
                    if let image = displayImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else if failed {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Design.Colors.glass.opacity(0.3))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Design.Colors.surface)
                            ProgressView()
                                .tint(Design.Colors.textMuted)
                        }
                    }
                }
            }
            .clipped()
            // Watch `url` directly. SwiftUI's view identity is
            // positional, not parameter-driven — the @State above
            // survives parameter changes, so without `id: url` a
            // parent re-render with a new URL would never trigger a
            // reload. Watching `url` guarantees the task fires every
            // time the URL actually changes.
            .task(id: url) {
                failed = false
                await loadImage(for: url)
            }
    }

    private func loadImage(for requestedURL: URL) async {
        let key = requestedURL as NSURL
        if let cached = cardImageCache.object(forKey: key) {
            // Defensively guard against the parameter being changed
            // during the synchronous gap — only commit our @State if
            // the URL we loaded for is still the current one.
            guard requestedURL == url else { return }
            image = cached
            loadedURL = requestedURL
            return
        }
        // Debounce: skip cells that scroll past quickly (matches CardImageView)
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled, requestedURL == url else { return }
        if let cached = cardImageCache.object(forKey: key) {
            image = cached
            loadedURL = requestedURL
            return
        }
        var request = URLRequest(url: requestedURL)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, _) = try await cardImageSession.data(for: request)
            guard !Task.isCancelled, requestedURL == url else { return }
            // Decode OFF the main actor (matches CardImageView).
            // UIImage(data:) defers bitmap decode to first render —
            // preparingForDisplay() forces it in the detached task so
            // the main thread never pays the decode cost.
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let raw = UIImage(data: data) else { return nil }
                return raw.preparingForDisplay() ?? raw
            }.value
            guard !Task.isCancelled, requestedURL == url else { return }
            if let loaded {
                cardImageCache.setObject(loaded, forKey: key, cost: data.count)
                image = loaded
                loadedURL = requestedURL
            } else {
                failed = true
            }
        } catch {
            let cancelled = Task.isCancelled
                || (error as? URLError)?.code == .cancelled
                || error is CancellationError
            if !cancelled, requestedURL == url { failed = true }
        }
    }
}
