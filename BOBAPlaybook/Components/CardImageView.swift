import SwiftUI

/// In-memory image cache shared across all CardImageView instances.
private let cardImageCache = NSCache<NSURL, UIImage>()

/// Async card image with a branded placeholder for cards without images.
/// Uses NSCache + returnCacheDataElseLoad to survive view recreation and tab switches.
/// Use `size: .thumb` for grids, `size: .full` for detail views.
struct CardImageView: View {
    let card: Card
    var size: ImageSize = .thumb

    enum ImageSize { case thumb, full }

    @Environment(CardStore.self) private var cardStore
    @State private var loadedImage: UIImage? = nil
    @State private var loadFailed  = false
    /// Incrementing this forces the `.task` to restart even when `url` is unchanged.
    /// Used to retry after a transient failure or task cancellation.
    @State private var loadID = 0

    private var url: URL? {
        size == .thumb ? CDN.thumbURL(for: card) : CDN.fullURL(for: card)
    }

    /// When loading the full image, check if the thumb is already in NSCache.
    /// Showing it immediately eliminates the loading spinner for cards seen in the grid.
    private var thumbImage: UIImage? {
        guard size == .full,
              let thumbURL = CDN.thumbURL(for: card) else { return nil }
        return cardImageCache.object(forKey: thumbURL as NSURL)
    }

    var body: some View {
        Group {
            if cardStore.isImageHidden(card.cardNumber) {
                placeholder
            } else if url == nil {
                placeholder
            } else {
                let resolved = loadedImage ?? cachedImage
                // Unified ZStack: thumb underlies the full image so the full res
                // can crossfade in rather than snapping. The task modifier stays
                // in scope regardless of load state so retries work correctly.
                ZStack {
                    Design.Colors.surface2
                    // Thumb from NSCache — shown immediately while full image loads.
                    // Hidden once the full image is ready (resolved != nil).
                    if let thumb = thumbImage, resolved == nil {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                    }
                    // Full image fades in over the thumb.
                    if let image = resolved {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .transition(.opacity)
                    }
                    // Spinner only when no thumb is available and nothing loaded yet.
                    if resolved == nil && thumbImage == nil && !loadFailed {
                        ProgressView()
                            .tint(Design.Colors.textMuted)
                    }
                    // Failed state — only when nothing else to show.
                    if loadFailed && resolved == nil {
                        placeholderContent
                    }
                }
                .task(id: loadID) {
                    await loadImage(from: url!)
                }
            }
        }
        .onAppear {
            // Retry every time the view enters the viewport.
            // - After a failure: resets the failed flag and triggers a fresh download.
            // - After a cancelled load (e.g. scrolled away mid-flight): restarts the task.
            // NSCache makes re-hits instant so this is safe to call unconditionally
            // when no image is in memory yet.
            if loadFailed || (loadedImage == nil && cachedImage == nil) {
                loadFailed = false
                loadID    += 1
            }
        }
        .onChange(of: url) { _, _ in
            // Card changed on the same view instance (e.g. scan detection chip).
            // Clear stale image immediately so the old card's image is never shown.
            loadedImage = nil
            loadFailed  = false
            loadID     += 1
        }
    }

    /// Synchronous NSCache hit — avoids showing the spinner when the image is
    /// already in the process-level cache from a previous load this session.
    private var cachedImage: UIImage? {
        guard let u = url else { return nil }
        return cardImageCache.object(forKey: u as NSURL)
    }

    private func loadImage(from url: URL) async {
        // Check in-memory cache first (synchronous, no network needed).
        let key = url as NSURL
        if let cached = cardImageCache.object(forKey: key) {
            loadedImage = cached
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            if let image = UIImage(data: data) {
                cardImageCache.setObject(image, forKey: key)
                withAnimation(.easeInOut(duration: 0.25)) {
                    loadedImage = image
                }
            } else {
                loadFailed = true
            }
        } catch {
            // Do NOT mark as failed for task cancellation. Cancellation happens when
            // the card scrolls out of view or a filter change reorders the grid.
            // The view will retry via loadID when it next appears.
            let cancelled = Task.isCancelled
                || (error as? URLError)?.code == .cancelled
                || error is CancellationError
            if !cancelled {
                loadFailed = true
            }
        }
    }

    // MARK: - Branded placeholder

    private var placeholder: some View {
        ZStack { placeholderContent }
    }

    private var placeholderContent: some View {
        ZStack {
            Design.Colors.surface2
            LinearGradient(
                colors: [Design.Colors.element(card.element).opacity(0.18), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: Design.Spacing.xs) {
                Text("BOBA PB")
                    .font(Design.Fonts.arena(22))
                    .foregroundStyle(Design.Colors.element(card.element).opacity(0.7))
                Text("Image Pending")
                    .font(Design.Fonts.mono(9, weight: .regular))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
        }
    }
}
