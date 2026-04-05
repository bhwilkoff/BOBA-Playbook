import SwiftUI

/// Async card image with a branded placeholder for cards without images.
/// Use `size: .thumb` for grids, `size: .full` for detail views.
struct CardImageView: View {
    let card: Card
    var size: ImageSize = .thumb

    enum ImageSize { case thumb, full }

    var body: some View {
        if let url = size == .thumb ? CDN.thumbURL(for: card) : CDN.fullURL(for: card) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    placeholder
                case .empty:
                    ZStack {
                        Design.Colors.surface2
                        ProgressView()
                            .tint(Design.Colors.textMuted)
                    }
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
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
