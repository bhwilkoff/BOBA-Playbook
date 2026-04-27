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

    /// Choose a column count for the regular (non-big-hit) grid that
    /// keeps each thumbnail readable without making the wall
    /// ridiculously tall. The Whatnot / Discord message preview
    /// generally displays ≈1:1 → 4:3, so biasing to a near-square
    /// grid keeps thumbnails reasonably sized.
    fileprivate static func columnCount(for count: Int) -> Int {
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
    /// `bigHits` is the parallel array of is_big_hit flags. Big hits
    /// land in a hero row at the top of the wall at much larger size;
    /// the rest fill a standard grid below. The split is responsive:
    ///   1 big hit  → one wide hero tile alone
    ///   2-3 hits   → side-by-side hero row
    ///   4+ hits    → multiple hero rows of up to 3 each
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
        bigHits: [Bool],
        title: String,
        options: ShowWallOptions,
        prices: [String: Decimal]
    ) async -> UIImage? {
        guard !cards.isEmpty else { return nil }

        let images = await fetchFullImages(for: cards)
        // Pad bigHits to match cards length (defensive against
        // mismatched call sites).
        let flags: [Bool] = (0..<cards.count).map { i in
            i < bigHits.count ? bigHits[i] : false
        }
        let entries: [WallGrid.Entry] = (0..<cards.count).map { i in
            WallGrid.Entry(card: cards[i], image: images[i], isBigHit: flags[i])
        }
        let regularCount = entries.filter { !$0.isBigHit }.count
        // When the show is all-big-hits (no standard grid below), the
        // canvas would otherwise collapse to a 1-column-wide column
        // count and the hero rows would be cramped. Force a minimum
        // of 4 grid columns in that case so big-hit tiles render at
        // a respectable size.
        let cols = regularCount == 0 ? 4 : columnCount(for: regularCount)

        let content = WallGrid(
            title: title,
            columns: cols,
            options: options,
            entries: entries,
            prices: prices
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Fetch every card's full-resolution image as a UIImage. Big-hit
    /// tiles render at hundreds of points wide on a 3×-rendered canvas,
    /// so the 200px thumb tier visibly pixelates — the wall is the one
    /// surface where we always pay for the ≤1200px tier. Missing
    /// images fall back to a placeholder tile so the grid stays
    /// visually aligned.
    @MainActor
    private static func fetchFullImages(for cards: [Card]) async -> [UIImage?] {
        // Resolve URLs on the main actor up front so the @Sendable
        // group.addTask closure only captures Sendable scalars (Int, URL?)
        // — Swift 6 strict concurrency rejects capturing the Card.
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
//
// Plain SwiftUI layout fed to ImageRenderer. Kept separate so the
// renderer sees a deterministic tree (no async work, no environment
// lookups).

fileprivate struct WallGrid: View {
    let title: String
    /// Column count for the standard (non-big-hit) grid.
    let columns: Int
    let options: ShowWallOptions
    let entries: [Entry]
    let prices: [String: Decimal]

    struct Entry {
        let card: Card
        let image: UIImage?
        let isBigHit: Bool
    }

    /// Tile edge for the standard grid. Larger tiles look better
    /// shared at native phone resolution (ImageRenderer scale=3
    /// multiplies this).
    private let tileWidth: CGFloat = 170
    private let gridSpacing: CGFloat = 10

    /// Total canvas width — derived from the regular grid's column
    /// count so the standard tiles fill the wall and the big-hit
    /// rows match the same width.
    private var canvasWidth: CGFloat {
        CGFloat(columns) * (tileWidth + gridSpacing) + 36
    }

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

    /// Big hits, in their original order (so the streamer's row
    /// ordering controls who appears first).
    private var bigHits: [Entry] { entries.filter { $0.isBigHit } }
    private var regulars: [Entry] { entries.filter { !$0.isBigHit } }

    /// Group big hits into rows. The user spec:
    ///   1 hit:   one row, single tile spanning the row
    ///   2 hits:  one row, side-by-side
    ///   3 hits:  one row, three across
    ///   4+ hits: multiple rows of up to 3 (last row may have fewer)
    private var bigHitRows: [[Entry]] {
        let hits = bigHits
        guard !hits.isEmpty else { return [] }
        if hits.count <= 3 { return [hits] }
        // 4+ hits: chunk into rows of 3
        var rows: [[Entry]] = []
        var cursor = 0
        while cursor < hits.count {
            let end = min(cursor + 3, hits.count)
            rows.append(Array(hits[cursor..<end]))
            cursor = end
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 14) {
            if hasHeader { header }
            // Big-hit hero rows at the top.
            ForEach(Array(bigHitRows.enumerated()), id: \.offset) { _, row in
                bigHitRow(row)
            }
            // Standard grid below for non-big-hit cards.
            if !regulars.isEmpty {
                let gridCols = Array(
                    repeating: GridItem(.fixed(tileWidth), spacing: gridSpacing),
                    count: columns
                )
                LazyVGrid(columns: gridCols, spacing: gridSpacing) {
                    ForEach(Array(regulars.enumerated()), id: \.offset) { _, entry in
                        tile(for: entry, width: tileWidth)
                    }
                }
                .padding(.horizontal, 18)
            }
            if options.includeBranding { footer }
        }
        .padding(.vertical, hasHeader ? 22 : 14)
        .frame(width: canvasWidth)
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

    /// Render one hero row of big hits. Tile width derives from how
    /// many sit in the row so the row always fills the canvas width.
    /// One hit gets a tile capped at ~70% of canvas (otherwise a single
    /// big hit on a narrow wall reads as a giant standalone splash).
    @ViewBuilder
    private func bigHitRow(_ row: [Entry]) -> some View {
        let availableWidth = canvasWidth - 36
        let interTileSpacing: CGFloat = 14
        let totalGap = interTileSpacing * CGFloat(max(0, row.count - 1))
        let perTileFull = (availableWidth - totalGap) / CGFloat(row.count)
        // Cap the single-hit tile a bit — fully-stretched looks gawky
        // when the wall has many regular cards below at 170px.
        let perTile: CGFloat = row.count == 1
            ? min(perTileFull, max(tileWidth * 2.2, 380))
            : perTileFull
        HStack(spacing: interTileSpacing) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, entry in
                tile(for: entry, width: perTile)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }

    private var header: some View {
        // VStack(spacing: 2) collapses to its single visible child when
        // only one block renders, so a title-only configuration shows the
        // show name in the same prominent position as the full branding
        // block. Card count is treated as belonging to whatever's at the
        // top of the wall — it shows when there's any header content,
        // not only when branding is on.
        VStack(spacing: 4) {
            if options.includeBranding {
                Text("BOBA PLAYBOOK")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "FF4D00"))
            }
            if let title = resolvedTitle {
                Text(title)
                    .font(Design.Fonts.display(28))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            // Card count rides with the title, not the branding —
            // streamers want it visible whenever they're naming the show.
            Text("\(entries.count) card\(entries.count == 1 ? "" : "s")")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Color(hex: "A0A0C0"))
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        Text("bobaplaybook.com")
            .font(Design.Fonts.mono(9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color(hex: "606088"))
    }

    private func tile(for entry: Entry, width: CGFloat) -> some View {
        let isBig = entry.isBigHit
        let card = entry.card
        // Price font scales with tile size — a 10pt overlay reads as
        // tiny on a 380px hero tile; bumping it keeps the chip visible
        // against bigger card art.
        let priceFontSize: CGFloat = isBig ? 16 : 10
        // Border + corner scale with tile size for visual coherence.
        let cornerRadius: CGFloat = isBig ? 14 : 8
        return ZStack(alignment: .bottomLeading) {
            if let img = entry.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(hex: "1A1A28"))
                    .overlay(
                        Text(String((card.hero.isEmpty ? card.name : card.hero).prefix(2)).uppercased())
                            .font(Design.Fonts.display(isBig ? 36 : 22))
                            .foregroundStyle(Color(hex: "FF4D00"))
                    )
            }
            if options.includePrices {
                Text(formatPrice(prices[card.id] ?? 0))
                    .font(Design.Fonts.mono(priceFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isBig ? 8 : 5)
                    .padding(.vertical, isBig ? 4 : 2)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(isBig ? 8 : 5)
            }
        }
        .frame(width: width, height: width * 7 / 5)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isBig ? Color(hex: "FFD700").opacity(0.85) : Color.white.opacity(0.12),
                    lineWidth: isBig ? 3 : 0.5
                )
        )
        // Subtle gold glow under big-hit tiles so they read as "premium"
        // even when the row has just one or two cards. No-op for
        // standard tiles.
        .shadow(
            color: isBig ? Color(hex: "FFD700").opacity(0.4) : .clear,
            radius: isBig ? 16 : 0,
            x: 0, y: 0
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
