import SwiftUI

struct MarketFeedView: View {
    @Environment(CardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sales: [RecentSale] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var error: String? = nil
    @State private var selectedCard: Card? = nil
    @State private var lastUpdated: Date? = nil

    private let pageSize = 20

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sales.isEmpty {
                    loadingView
                } else if let error, sales.isEmpty {
                    errorView(error)
                } else if sales.isEmpty {
                    emptyView
                } else {
                    feedList
                }
            }
            .navigationTitle("Market Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadFeed(replace: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(isLoading ? Design.Colors.textMuted : Design.Colors.textPrimary)
                    }
                    .disabled(isLoading)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .background(Design.Colors.nearBlack)
        .task { await loadFeed(replace: false) }
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card, navigationCards: store.filteredCards)
        }
    }

    // MARK: - Feed List

    private var feedList: some View {
        ScrollView {
            if let lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.top, Design.Spacing.sm)
            }

            LazyVStack(spacing: 0) {
                ForEach(sales) { sale in
                    FeedItemRow(sale: sale, matchedCard: matchCard(sale)) { card in
                        selectedCard = card
                    }
                    Divider()
                        .background(Design.Colors.glassBorder)
                        .padding(.horizontal, Design.Spacing.lg)
                }

                if hasMore {
                    loadMoreButton
                }

                if isLoading && !sales.isEmpty {
                    HStack {
                        ProgressView()
                            .tint(Design.Colors.bobaOrange)
                            .scaleEffect(0.8)
                        Text("Loading more…")
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Design.Spacing.lg)
                }

                Spacer().frame(height: Design.Spacing.xl)
            }
        }
        .background(Design.Colors.nearBlack)
        .refreshable {
            await loadFeed(replace: true)
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await loadFeed(replace: false) }
        } label: {
            Text("Load More")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
                .padding(.vertical, Design.Spacing.md)
                .frame(maxWidth: .infinity)
        }
        .disabled(isLoading)
    }

    // MARK: - Placeholder States

    private var loadingView: some View {
        VStack(spacing: Design.Spacing.lg) {
            ProgressView()
                .tint(Design.Colors.bobaOrange)
                .scaleEffect(1.4)
            Text("Loading recent sales…")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text("Could not load feed")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(message)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xl)
            Button("Retry") {
                Task { await loadFeed(replace: true) }
            }
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    private var emptyView: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No recent sales yet")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textSecondary)
            Text("The cron job runs every 30 minutes.\nCheck back soon.")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Data

    private func matchCard(_ sale: RecentSale) -> Card? {
        guard let num = sale.cardNumber else { return nil }
        let candidates = store.displayCards.filter { $0.cardNumber == num }
        if candidates.isEmpty { return nil }
        if candidates.count == 1 { return candidates[0] }
        // Multiple cards share this card number — try to disambiguate by hero
        if let hero = sale.hero,
           let match = candidates.first(where: { $0.hero?.lowercased() == hero.lowercased() }) {
            return match
        }
        return candidates.first
    }

    private func loadFeed(replace: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        let cursor: Date? = replace ? nil : sales.last?.soldDate
        do {
            let page = try await SupabaseClient.shared.fetchRecentSales(limit: pageSize, before: cursor)
            if replace {
                sales = page
            } else {
                sales.append(contentsOf: page)
            }
            hasMore = page.count == pageSize
            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Feed Item Row

private struct FeedItemRow: View {
    let sale: RecentSale
    let matchedCard: Card?
    let onCardTap: (Card) -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.md) {
            // Thumbnail
            imageCell
                .frame(width: 64, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                .onTapGesture {
                    if let card = matchedCard { onCardTap(card) }
                }

            // Body
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                // Hero + element dot
                if let card = matchedCard {
                    HStack(spacing: Design.Spacing.xs) {
                        Circle()
                            .fill(Design.Colors.element(card.element ?? ""))
                            .frame(width: 8, height: 8)
                        Text(card.hero ?? card.name)
                            .font(Design.Fonts.display(13))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(1)
                        if let power = card.power, power > 0 {
                            Text("·  \(power)")
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                    }
                }

                // Title
                Text(sale.title)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(matchedCard != nil ? Design.Colors.textSecondary : Design.Colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Treatment pill (if matched)
                if let treatment = matchedCard?.treatment ?? sale.treatment {
                    Text(treatment)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Design.Colors.bobaCyan.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                // Footer: price + date + eBay link
                HStack(alignment: .center) {
                    Text(sale.price as NSDecimalNumber, formatter: Self.priceFormatter)
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)

                    Text(Self.dateFormatter.string(from: sale.soldDate))
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)

                    Spacer()

                    Link(destination: URL(string: sale.ebayUrl)!) {
                        HStack(spacing: 3) {
                            Text("eBay")
                                .font(Design.Fonts.mono(11, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .padding(.horizontal, Design.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Design.Colors.bobaCyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .background(matchedCard != nil ? Design.Colors.surface.opacity(0.6) : Color.clear)
    }

    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    @ViewBuilder
    private var imageCell: some View {
        if let card = matchedCard {
            CardImageView(card: card, size: .thumb)
        } else if let urlStr = sale.imageUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    placeholderThumb
                @unknown default:
                    placeholderThumb
                }
            }
        } else {
            placeholderThumb
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            Design.Colors.surface2
            Image(systemName: "photo")
                .foregroundStyle(Design.Colors.textMuted)
                .font(.system(size: 20))
        }
    }
}
