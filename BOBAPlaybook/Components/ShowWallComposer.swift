import SwiftUI
import UIKit

// MARK: - ShowWallComposer
//
// Renders a grid of card thumbnails into a single UIImage for sharing.
// Streamers drop this into Whatnot chat / Discord / screenshots to
// advertise what's coming up in the show. Uses ImageRenderer (iOS 17+)
// against a SwiftUI layout so the output inherits the app's styling
// automatically — no separate Core Graphics composition.

enum ShowWallComposer {

    /// Choose a column count that keeps each thumbnail readable without
    /// making the wall ridiculously tall. The Whatnot / Discord message
    /// preview generally displays ≈1:1 → 4:3, so biasing to a near-
    /// square grid keeps thumbnails reasonably sized.
    private static func columnCount(for count: Int) -> Int {
        switch count {
        case 0...1:  return 1
        case 2...4:  return 2
        case 5...9:  return 3
        case 10...16: return 4
        case 17...36: return 6
        default:      return 8
        }
    }

    /// Produce a UIImage from the cards' CDN thumbnails. Runs on the
    /// main actor because ImageRenderer requires it. Returns nil if
    /// all image fetches fail (unlikely — thumbs are on R2).
    @MainActor
    static func compose(cards: [Card], title: String) async -> UIImage? {
        guard !cards.isEmpty else { return nil }

        let images = await fetchThumbs(for: cards)
        let cols = columnCount(for: cards.count)

        let content = WallGrid(title: title, columns: cols, pairs: zip(cards, images).map { ($0, $1) })
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Fetch every card's thumbnail as a UIImage. Missing images fall
    /// back to a placeholder tile so the grid stays visually aligned.
    @MainActor
    private static func fetchThumbs(for cards: [Card]) async -> [UIImage?] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, card) in cards.enumerated() {
                group.addTask {
                    guard let url = CDN.thumbURL(for: card) else { return (i, nil) }
                    if let cached = cardImageCache.object(forKey: url as NSURL) {
                        return (i, cached)
                    }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let img = UIImage(data: data) {
                            cardImageCache.setObject(img, forKey: url as NSURL)
                            return (i, img)
                        }
                    } catch { /* fall through to nil */ }
                    return (i, nil)
                }
            }
            var out = Array<UIImage?>(repeating: nil, count: cards.count)
            for await (i, img) in group { out[i] = img }
            return out
        }
    }
}

// MARK: - Grid layout
//
// Plain SwiftUI layout fed to ImageRenderer. Kept separate so the
// renderer sees a deterministic tree (no async work, no environment
// lookups).

private struct WallGrid: View {
    let title: String
    let columns: Int
    let pairs: [(Card, UIImage?)]

    /// Tile edge. Larger tiles look better shared at native phone
    /// resolution (ImageRenderer scale=3 multiplies this).
    private let tileWidth: CGFloat = 170

    var body: some View {
        let gridCols = Array(repeating: GridItem(.fixed(tileWidth), spacing: 10), count: columns)
        VStack(spacing: 14) {
            header
            LazyVGrid(columns: gridCols, spacing: 10) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    tile(for: pair.0, image: pair.1)
                }
            }
            .padding(.horizontal, 18)
            footer
        }
        .padding(.vertical, 22)
        .frame(width: CGFloat(columns) * (tileWidth + 10) + 36)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "0D0D1A"),
                    Color(hex: "080810"),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("BOBA PLAYBOOK")
                .font(Design.Fonts.mono(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color(hex: "FF4D00"))
            Text(title)
                .font(Design.Fonts.display(22))
                .foregroundStyle(.white)
            Text("\(pairs.count) card\(pairs.count == 1 ? "" : "s")")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Color(hex: "A0A0C0"))
        }
    }

    private var footer: some View {
        Text("bobaplaybook.com")
            .font(Design.Fonts.mono(9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color(hex: "606088"))
    }

    private func tile(for card: Card, image: UIImage?) -> some View {
        ZStack {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "1A1A28"))
                    .overlay(
                        Text(String((card.hero.isEmpty ? card.name : card.hero).prefix(2)).uppercased())
                            .font(Design.Fonts.display(22))
                            .foregroundStyle(Color(hex: "FF4D00"))
                    )
            }
        }
        .frame(width: tileWidth, height: tileWidth * 7 / 5)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}
