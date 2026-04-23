import SwiftUI
import UIKit

// MARK: - ShowWallComposer
//
// Renders a grid of card thumbnails into a single UIImage for sharing.
// Streamers drop this into Whatnot chat / Discord / screenshots to
// advertise what's coming up in the show. Uses ImageRenderer (iOS 17+)
// against a SwiftUI layout so the output inherits the app's styling
// automatically — no separate Core Graphics composition.

// MARK: - Wall options
//
// Options the streamer can toggle in the Wall Options sheet before
// generating. Defaults match the previous unconfigurable behavior
// so an "always tap Generate Wall" flow is unchanged.
//
// Sendable so its `static let default` can be referenced from any
// isolation context — without it, Swift 6 inferred MainActor isolation
// from the file's SwiftUI imports and rejected the access.
struct ShowWallOptions: Sendable {
    var includeBranding: Bool = true   // BOBA PLAYBOOK header tag
    var includeTitle:    Bool = true   // Show name as the big header
    var customText:      String = ""   // Replaces / adds to the title — see WallGrid
    var includePrices:   Bool = false  // Per-tile price overlay

    /// Computed (not stored) so the initializer expression isn't evaluated
    /// in the file's inferred MainActor context — Swift 6 was flagging
    /// `static let default = ShowWallOptions()` as MainActor-isolated even
    /// after the struct was marked Sendable.
    static var `default`: ShowWallOptions { ShowWallOptions() }
}

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
    ///
    /// `prices` is optional — only consulted when `options.includePrices`
    /// is true. Pass an empty dict if you don't have prices yet; the
    /// composer falls back to "—" per tile.
    /// Caller must always pass `options` explicitly. Default parameter
    /// values are evaluated at the call site's isolation, and Swift 6
    /// flagged `= .default` here as a MainActor crossing — the actual
    /// caller (ShowDetailView.generateWall) already supplies a value.
    @MainActor
    static func compose(
        cards: [Card],
        title: String,
        options: ShowWallOptions,
        prices: [String: Decimal]
    ) async -> UIImage? {
        guard !cards.isEmpty else { return nil }

        let images = await fetchThumbs(for: cards)
        let cols = columnCount(for: cards.count)

        let content = WallGrid(
            title: title,
            columns: cols,
            options: options,
            pairs: zip(cards, images).map { ($0, $1) },
            prices: prices
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Fetch every card's thumbnail as a UIImage. Missing images fall
    /// back to a placeholder tile so the grid stays visually aligned.
    @MainActor
    private static func fetchThumbs(for cards: [Card]) async -> [UIImage?] {
        // Resolve URLs on the main actor up front so the @Sendable
        // group.addTask closure only captures Sendable scalars (Int, URL?)
        // — Swift 6 strict concurrency rejects capturing the Card.
        let urls: [URL?] = cards.map { CDN.thumbURL(for: $0) }
        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask {
                    guard let url else { return (i, nil) }
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
    let options: ShowWallOptions
    let pairs: [(Card, UIImage?)]
    let prices: [String: Decimal]

    /// Tile edge. Larger tiles look better shared at native phone
    /// resolution (ImageRenderer scale=3 multiplies this).
    private let tileWidth: CGFloat = 170

    /// Resolved big-text line. Custom text wins; otherwise show name;
    /// otherwise nothing. Driven by both options + non-empty checks.
    private var resolvedTitle: String? {
        let trimmed = options.customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if options.includeTitle { return title }
        return nil
    }

    /// Whether anything renders in the header slot — used to suppress
    /// empty top padding when the streamer turned everything off.
    private var hasHeader: Bool {
        options.includeBranding || resolvedTitle != nil
    }

    var body: some View {
        let gridCols = Array(repeating: GridItem(.fixed(tileWidth), spacing: 10), count: columns)
        VStack(spacing: 14) {
            if hasHeader { header }
            LazyVGrid(columns: gridCols, spacing: 10) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    tile(for: pair.0, image: pair.1)
                }
            }
            .padding(.horizontal, 18)
            if options.includeBranding { footer }
        }
        .padding(.vertical, hasHeader ? 22 : 14)
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
            if options.includeBranding {
                Text("BOBA PLAYBOOK")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "FF4D00"))
            }
            if let title = resolvedTitle {
                Text(title)
                    .font(Design.Fonts.display(22))
                    .foregroundStyle(.white)
            }
            if options.includeBranding {
                Text("\(pairs.count) card\(pairs.count == 1 ? "" : "s")")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Color(hex: "A0A0C0"))
            }
        }
    }

    private var footer: some View {
        Text("bobaplaybook.com")
            .font(Design.Fonts.mono(9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color(hex: "606088"))
    }

    private func tile(for card: Card, image: UIImage?) -> some View {
        ZStack(alignment: .bottomLeading) {
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
            // Optional price chip — only when the streamer asked for it.
            if options.includePrices {
                Text(formatPrice(prices[card.id] ?? 0))
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(5)
            }
        }
        .frame(width: tileWidth, height: tileWidth * 7 / 5)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func formatPrice(_ value: Decimal) -> String {
        if value <= 0 { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        // Drop trailing zero cents on round numbers ($25 not $25.00)
        // for tighter overlay text. Mirrors how prices read on Whatnot.
        f.maximumFractionDigits = (value.rounded() == value) ? 0 : 2
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

extension Decimal {
    /// Rounded-to-zero-fraction-digits comparison helper for the price
    /// overlay's "drop trailing zeros" formatting decision.
    fileprivate func rounded() -> Decimal {
        var src = self
        var out = Decimal()
        NSDecimalRound(&out, &src, 0, .plain)
        return out
    }
}
