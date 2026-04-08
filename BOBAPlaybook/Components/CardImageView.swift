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
    @State private var failed = false

    private var url: URL? {
        size == .thumb ? CDN.thumbURL(for: card) : CDN.fullURL(for: card)
    }

    var body: some View {
        Group {
            if cardStore.isImageHidden(card.cardNumber) {
                placeholder
            } else if let image = loadedImage ?? cachedImage {
                // cachedImage is a synchronous NSCache lookup — no spinner flash
                // when returning to a grid after navigating away.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed || url == nil {
                placeholder
            } else {
                ZStack {
                    Design.Colors.surface2
                    ProgressView()
                        .tint(Design.Colors.textMuted)
                }
                .task(id: url!) {
                    await loadImage(from: url!)
                }
            }
        }
    }

    /// Synchronous NSCache hit — avoids showing the spinner when the image is
    /// already in the process-level cache from a previous load this session.
    private var cachedImage: UIImage? {
        guard let u = url else { return nil }
        return cardImageCache.object(forKey: u as NSURL)
    }

    private func loadImage(from url: URL) async {
        let key = url as NSURL
        if let cached = cardImageCache.object(forKey: key) {
            loadedImage = cached
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = UIImage(data: data) {
                cardImageCache.setObject(image, forKey: key)
                loadedImage = image
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }

    // MARK: - Branded placeholder
    private var placeholder: some View {
        ZStack {
            Design.Colors.surface2
            // Element-tinted gradient overlay
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
