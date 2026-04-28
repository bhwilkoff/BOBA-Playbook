import SwiftUI
import UIKit

// MARK: - ShowWallComposer
//
// Renders a grid of card thumbnails into a single UIImage for sharing.
// Streamers drop this into Whatnot chat / Discord / screenshots to
// advertise what's coming up in the show. Uses ImageRenderer (iOS 17+)
// against a SwiftUI layout so the output inherits the app's styling
// automatically — no separate Core Graphics composition.
//
// Sizing rule (user ask 2026-04-27): the wall is always laid out to a
// fixed PORTRAIT-CARD ASPECT (5:7) at a social-media-friendly canvas
// size. Cards inside keep their own 5:7 aspect; columns and rows are
// chosen responsively so every card fits without making the canvas
// taller than the target. Big-hit cards still get a gold-border /
// glow accent but no longer get their own oversized hero row — that
// was the source of "the wall keeps getting longer."

// MARK: - Wall options
struct ShowWallOptions: Sendable {
    var includeBranding: Bool = true   // BOBA PLAYBOOK header tag
    var includeTitle:    Bool = true   // Show name as the big header
    var customText:      String = ""   // Replaces / adds to the title
    var includePrices:   Bool = false  // Per-tile price overlay

    static var `default`: ShowWallOptions { ShowWallOptions() }
}

enum ShowWallComposer {

    /// Target canvas size — 5:7 portrait, sized for clean rendering
    /// at 3× scale on Whatnot / Discord / Instagram / X. 1080 × 1512
    /// is also small enough that JPEG output stays under typical
    /// social-share size limits (≤2 MB at q=0.92).
    static let canvasWidth:  CGFloat = 1080
    static let canvasHeight: CGFloat = 1512   // 1080 × 7/5

    /// Produce a UIImage from the cards' CDN thumbnails. Runs on the
    /// main actor because ImageRenderer requires it. Returns nil if
    /// there are no cards to compose.
    @MainActor
    static func compose(
        cards: [Card],
        bigHits: [Bool],
        title: String,
        options: ShowWallOptions,
        prices: [String: Decimal]
    ) async -> UIImage? {
        guard !cards.isEmpty else { return nil }

        let images = await fetchFullImages(for: cards)
        let flags: [Bool] = (0..<cards.count).map { i in
            i < bigHits.count ? bigHits[i] : false
        }
        let entries: [WallGrid.Entry] = (0..<cards.count).map { i in
            WallGrid.Entry(card: cards[i], image: images[i], isBigHit: flags[i])
        }

        let content = WallGrid(
            title: title,
            options: options,
            entries: entries,
            prices: prices
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.5
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Fetch every card's full-resolution image as a UIImage. Missing
    /// images fall back to a placeholder tile so the grid stays
    /// visually aligned.
    @MainActor
    private static func fetchFullImages(for cards: [Card]) async -> [UIImage?] {
        let urls: [URL?] = cards.map { CDN.fullURL(for: $0) }
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

fileprivate struct WallGrid: View {
    let title: String
    let options: ShowWallOptions
    let entries: [Entry]
    let prices: [String: Decimal]

    struct Entry {
        let card: Card
        let image: UIImage?
        let isBigHit: Bool
    }

    /// Edge insets + spacing for the layout calculation.
    private let sidePadding: CGFloat = 24
    private let gap: CGFloat = 8
    private let topGap: CGFloat = 12
    private let bottomGap: CGFloat = 12

    /// Reserved vertical space for header + footer (estimates — within
    /// ~10pt of the rendered chrome). Used to size the grid area.
    private var headerHeight: CGFloat { hasHeader ? 80 : 0 }
    private var footerHeight: CGFloat { options.includeBranding ? 28 : 0 }

    /// Resolved big-text line. Custom text wins; otherwise show name;
    /// otherwise nothing.
    private var resolvedTitle: String? {
        let trimmed = options.customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if options.includeTitle { return title }
        return nil
    }

    private var hasHeader: Bool {
        options.includeBranding || resolvedTitle != nil
    }

    /// Layout result: cols, computed tile width.
    private struct Layout {
        let cols: Int
        let tileWidth: CGFloat
    }

    /// Pick the smallest column count that lets every entry fit
    /// inside the reserved grid area — that maximizes per-tile size.
    /// Tie cards keep their own 5:7 aspect; rows = ceil(N/cols).
    private func computeLayout() -> Layout {
        let n = entries.count
        guard n > 0 else { return Layout(cols: 1, tileWidth: 0) }
        let canvasW = ShowWallComposer.canvasWidth
        let canvasH = ShowWallComposer.canvasHeight
        let availableW = canvasW - sidePadding * 2
        let availableH = canvasH - headerHeight - footerHeight - topGap - bottomGap

        // Try cols 1...n, pick the smallest one that fits both:
        //   • per-tile size readable (tile_width ≥ ~70 at canvas scale)
        //   • computed rows × tile_height fits within availableH
        // The smallest cols that fits gives the LARGEST tiles.
        var best: Layout? = nil
        for cols in 1...n {
            let tileW = (availableW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let tileH = tileW * 7.0 / 5.0
            let rows  = Int((Double(n) / Double(cols)).rounded(.up))
            let needed = CGFloat(rows) * tileH + CGFloat(rows - 1) * gap
            if needed <= availableH {
                best = Layout(cols: cols, tileWidth: tileW)
                break   // smallest fitting cols wins (= largest tiles)
            }
        }
        // Fallback: every cols overflowed (huge N). Use a high cols
        // and let the grid scale down past readability — better to
        // ship a too-dense wall than no wall.
        if best == nil {
            let cols = Int(ceil(sqrt(Double(n) * 5.0 / 7.0)))
            let tileW = (availableW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            best = Layout(cols: cols, tileWidth: tileW)
        }
        return best!
    }

    var body: some View {
        let layout = computeLayout()
        let cols = layout.cols
        let tileW = layout.tileWidth

        VStack(spacing: 0) {
            if hasHeader {
                header
                    .frame(height: headerHeight)
            }
            Spacer().frame(height: topGap)
            // Center the grid in the remaining vertical space so a
            // smaller card count doesn't leave a giant gap at the bottom.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                let gridCols = Array(
                    repeating: GridItem(.fixed(tileW), spacing: gap),
                    count: cols
                )
                LazyVGrid(columns: gridCols, spacing: gap) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        tile(for: entry, width: tileW)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            Spacer().frame(height: bottomGap)
            if options.includeBranding {
                footer.frame(height: footerHeight)
            }
        }
        .frame(width: ShowWallComposer.canvasWidth,
               height: ShowWallComposer.canvasHeight)
        .background(
            LinearGradient(
                colors: [Color(hex: "0D0D1A"), Color(hex: "080810")],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var header: some View {
        VStack(spacing: 4) {
            if options.includeBranding {
                Text("BOBA PLAYBOOK")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(Color(hex: "FF4D00"))
            }
            if let title = resolvedTitle {
                Text(title)
                    .font(Design.Fonts.display(34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, sidePadding)
            }
            Text("\(entries.count) card\(entries.count == 1 ? "" : "s")")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Color(hex: "A0A0C0"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var footer: some View {
        Text("bobaplaybook.com")
            .font(Design.Fonts.mono(11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color(hex: "606088"))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
    }

    private func tile(for entry: Entry, width: CGFloat) -> some View {
        let isBig = entry.isBigHit
        let card = entry.card
        // Corner + price font scale with tile size so a small grid of
        // huge tiles still reads well.
        let cornerRadius: CGFloat = max(6, width * 0.06)
        let priceFontSize: CGFloat = max(10, width * 0.085)
        return ZStack(alignment: .bottomLeading) {
            if let img = entry.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(hex: "1A1A28"))
                    .overlay(
                        Text(String((card.hero.isEmpty ? card.name : card.hero).prefix(2)).uppercased())
                            .font(Design.Fonts.display(max(18, width * 0.18)))
                            .foregroundStyle(Color(hex: "FF4D00"))
                    )
            }
            if options.includePrices {
                Text(formatPrice(prices[card.id] ?? 0))
                    .font(Design.Fonts.mono(priceFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, max(4, width * 0.04))
                    .padding(.vertical, max(2, width * 0.02))
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(max(4, width * 0.035))
            }
        }
        .frame(width: width, height: width * 7 / 5)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isBig ? Color(hex: "FFD700").opacity(0.85) : Color.white.opacity(0.12),
                    lineWidth: isBig ? max(2, width * 0.025) : 0.5
                )
        )
        .shadow(
            color: isBig ? Color(hex: "FFD700").opacity(0.4) : .clear,
            radius: isBig ? max(8, width * 0.12) : 0
        )
    }

    private func formatPrice(_ value: Decimal) -> String {
        if value <= 0 { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = (value.rounded() == value) ? 0 : 2
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

extension Decimal {
    fileprivate func rounded() -> Decimal {
        var src = self
        var out = Decimal()
        NSDecimalRound(&out, &src, 0, .plain)
        return out
    }
}
