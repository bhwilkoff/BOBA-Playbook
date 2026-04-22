import SwiftUI

// MARK: - CollectionView
// Main Collection tab. Shows cards grouped by designation with a value summary.
// One row per unique card_number — multiple physical copies are shown on the detail page.

struct CollectionView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore

    @State private var selectedDesignation: UserCard.Designation = .personal
    @State private var selectedCard: BobaIdWrapper?
    @State private var showingSignIn    = false
    @State private var showTradeRoom    = false
    @State private var discord          = DiscordService()
    /// Top-level view mode. Rainbow is a collecting-progress lens across
    /// all owned heroes — a different axis than the designation tabs,
    /// which partition cards by intent (Personal / For Sale / Wanted).
    /// Keeping these on separate toggles so coaches don't confuse "how I'm
    /// using this card" with "how close am I to completing this hero."
    @State private var viewMode: CollectionViewMode = .myCards
    @State private var isRecalculating = false
    @State private var recalcProgress: (current: Int, total: Int)? = nil

    enum CollectionViewMode: String, CaseIterable, Identifiable {
        case myCards = "My Cards"
        case rainbow = "Rainbow Progress"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isAuthenticated {
                    unauthenticatedView
                } else {
                    authenticatedView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
                if auth.isAuthenticated {
                    ToolbarItem(placement: .topBarTrailing) {
                        collectionMenu
                    }
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(item: $selectedCard) { wrapper in
            CollectionCardDetailView(bobaId: wrapper.id)
        }
        .task {
            if auth.isAuthenticated {
                await collection.loadCollection()
            }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task { await collection.loadCollection() }
            } else {
                collection.clearCollection()
            }
        }
    }

    // MARK: - Unauthenticated state

    private var unauthenticatedView: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Design.Colors.textMuted)
            Text("My Collection")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Sign in to track owned cards,\nwishlist, and portfolio value.")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
            Button {
                showingSignIn = true
            } label: {
                Text("Sign In")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .frame(maxWidth: 200)
                    .frame(height: 50)
                    .background(Design.Colors.bobaOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Authenticated state

    private var authenticatedView: some View {
        // .refreshable intentionally does NOT go on this VStack — it would
        // attach to the first ancestor scroll view (the horizontal
        // designation pill row), bringing its vertical bounce back and
        // firing the refresh on the wrong surface. Each inner ScrollView
        // (cardList / rainbowList) attaches its own .refreshable so the
        // pull-to-refresh gesture lives where the refresh actually shows.
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if isRecalculating, let p = recalcProgress {
                    recalcProgressBanner(current: p.current, total: p.total)
                }
                modePicker
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)

                switch viewMode {
                case .myCards:
                    valueSummary
                    designationPicker
                    cardList
                case .rainbow:
                    rainbowIntro
                    rainbowList
                }
            }
            .background(Design.Colors.nearBlack)

            // tradeRoomFAB — hidden until Discord bot is added to server
        }
        .sheet(isPresented: $showTradeRoom) {
            TradeRoomSheet(discord: discord)
        }
    }

    // MARK: - Top-level view mode picker

    private var modePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(CollectionViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Collection menu (toolbar)

    private var collectionMenu: some View {
        Menu {
            Button {
                Task { await recalculateAll() }
            } label: {
                Label(isRecalculating ? "Refreshing prices…" : "Refresh market values",
                      systemImage: "arrow.clockwise")
            }
            .disabled(isRecalculating)
        } label: {
            if isRecalculating {
                ProgressView().tint(Design.Colors.bobaOrange)
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
        }
    }

    private func recalcProgressBanner(current: Int, total: Int) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            ProgressView().tint(Design.Colors.bobaOrange).scaleEffect(0.85)
            Text(total == 0
                 ? "Refreshing market values…"
                 : "Updating \(current) of \(total) cards…")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
        .background(Design.Colors.surface)
    }

    private func recalculateAll() async {
        isRecalculating = true
        recalcProgress = (0, 0)
        await collection.recalculateAllValues(cardStore: cardStore) { current, total in
            recalcProgress = (current, total)
        }
        isRecalculating = false
        recalcProgress = nil
    }

    // MARK: - Value summary

    private var valueSummary: some View {
        let estimated = collection.totalEstimatedValue
        let purchased = collection.totalPurchaseValue
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(estimated > 0 ? "EST. MARKET VALUE" : "COST BASIS")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                let displayValue = estimated > 0 ? estimated : purchased
                Text(displayValue == 0 ? "—" : formatCurrency(displayValue))
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(displayValue == 0 ? Design.Colors.textMuted : Design.Colors.bobaOrange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("CARDS OWNED")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text("\(collection.userCards.filter { $0.designation.isOwned }.count)")
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .background(Design.Colors.surface)
    }

    // MARK: - Designation picker

    private var designationPicker: some View {
        // Fixed-height row (34pt pill + 12pt × 2 vertical padding = 58).
        // Without this, the horizontal ScrollView inherits flexible
        // height from its parent VStack and the pull-to-refresh bounce
        // from the enclosing `.refreshable` scroll can tug the pill row
        // up and down, making it feel like the pills scroll vertically.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.sm) {
                ForEach(UserCard.Designation.allCases) { d in
                    let count = collection.uniqueBobaIds(for: d).count
                    Button {
                        selectedDesignation = d
                    } label: {
                        HStack(spacing: Design.Spacing.xs) {
                            Image(systemName: d.icon)
                                .font(.system(size: 11))
                            Text(d.displayName)
                                .font(Design.Fonts.mono(12, weight: selectedDesignation == d ? .bold : .regular))
                            if count > 0 {
                                Text("\(count)")
                                    .font(Design.Fonts.mono(10))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(selectedDesignation == d ? Design.Colors.nearBlack.opacity(0.3) : Design.Colors.glass))
                            }
                        }
                        .foregroundStyle(selectedDesignation == d ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                        .padding(.horizontal, Design.Spacing.md)
                        .frame(height: 34)
                        .background(selectedDesignation == d ? Design.Colors.bobaOrange : Design.Colors.glass)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(height: 58)
        .background(Design.Colors.surface)
    }

    // MARK: - Rainbow intro
    // Short explainer shown at the top of the Rainbow view so coaches who
    // haven't heard the term know what they're looking at and why. "Rainbow"
    // is a community collecting goal, not a game mechanic — worth spelling
    // out when someone first encounters the tab.
    private var rainbowIntro: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "rainbow").font(.system(size: 16))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Text("What is a Rainbow?")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            Text("Community collecting goal — owning every treatment (Base + every foil + every autograph) of a single hero. If you own at least one card of a hero, that hero shows up here with progress toward a complete set.")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sorted by percent complete. Tap a row to jump to the card.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.Colors.glassBorder).frame(height: 1) }
    }

    // MARK: - Card list

    private var cardList: some View {
        let identifiers = collection.uniqueBobaIds(for: selectedDesignation)

        // Always wrap in a vertical ScrollView so .refreshable has a
        // valid attachment point, whether or not there are cards. Empty
        // state still pulls to refresh so users can retry from a blank
        // list without having to background-foreground the app.
        return Group {
            if collection.isLoading {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if identifiers.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        LazyVStack(spacing: Design.Spacing.sm) {
                            ForEach(identifiers, id: \.self) { identifier in
                                collectionRow(identifier: identifier)
                                    .onTapGesture { selectedCard = BobaIdWrapper(id: identifier) }
                            }
                        }
                        .padding(Design.Spacing.lg)
                    }
                }
                .refreshable {
                    await collection.loadCollection()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer()
            Image(systemName: selectedDesignation.icon)
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No \(selectedDesignation.displayName) cards")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Add cards from any card detail view.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rainbow list
    //
    // For every hero the user owns at least one card of, show rainbow
    // progress: owned treatments vs. every treatment that exists for
    // that hero across all variations. Tap a row → open the card-number
    // detail view for the first owned card of that hero (entry point
    // into seeing variants). Missing-treatment jumps into Find are a
    // P2 follow-up — the list itself already shows the gap.

    private struct RainbowProgress: Identifiable {
        let hero: String
        let owned: Int
        let total: Int
        let coverCard: Card
        var id: String { hero }
        var percent: Double { total == 0 ? 0 : Double(owned) / Double(total) }
    }

    private var rainbowRows: [RainbowProgress] {
        // Owned (any designation that counts as owned, e.g. .personal / .for_sale / .for_trade).
        let ownedBobaIds: Set<String> = Set(
            collection.userCards
                .filter { $0.designation.isOwned }
                .compactMap { $0.bobaId }
        )
        // Group every hero-card in the catalog by hero.
        var byHero: [String: [Card]] = [:]
        for c in cardStore.displayCards where c.isHero && !c.hero.isEmpty {
            byHero[c.hero, default: []].append(c)
        }
        // Keep only heroes the user owns at least one printing of.
        var rows: [RainbowProgress] = []
        for (hero, cards) in byHero {
            let owned = cards.filter { ownedBobaIds.contains($0.id) }
            if owned.isEmpty { continue }
            // Prefer an owned card with an image as the cover; fall back to
            // the first card in the hero group.
            let cover = owned.first { $0.imageFile?.isEmpty == false } ?? owned.first ?? cards.first!
            rows.append(.init(
                hero: hero,
                owned: owned.count,
                total: cards.count,
                coverCard: cover
            ))
        }
        // Almost-complete rainbows are the collector's primary signal —
        // surface those first, then alphabetical.
        return rows.sorted { lhs, rhs in
            if lhs.percent != rhs.percent { return lhs.percent > rhs.percent }
            return lhs.hero.localizedCompare(rhs.hero) == .orderedAscending
        }
    }

    private var rainbowList: some View {
        let rows = rainbowRows
        // Same pattern as cardList — always in a ScrollView so pull-to-
        // refresh has a real scroll view to attach to.
        return ScrollView {
            if rows.isEmpty {
                VStack(spacing: Design.Spacing.md) {
                    Image(systemName: "rainbow")
                        .font(.system(size: 36))
                        .foregroundStyle(Design.Colors.bobaCyan.opacity(0.6))
                    Text("No rainbows in progress yet")
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textMuted)
                    Text("Add any hero card to your collection — we'll show rainbow progress here.")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.Spacing.xl)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.top, Design.Spacing.xl)
            } else {
                LazyVStack(spacing: Design.Spacing.sm) {
                    ForEach(rows) { row in
                        rainbowRow(row)
                            .onTapGesture {
                                selectedCard = BobaIdWrapper(id: row.coverCard.id)
                            }
                    }
                }
                .padding(Design.Spacing.lg)
            }
        }
        .refreshable {
            await collection.loadCollection()
        }
    }

    private func rainbowRow(_ row: RainbowProgress) -> some View {
        HStack(spacing: Design.Spacing.md) {
            CardImageView(card: row.coverCard, size: .thumb)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.hero)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                // Segmented progress bar — each cell = one treatment.
                // Filled = owned, dim = still needed.
                HStack(spacing: 2) {
                    ForEach(0..<row.total, id: \.self) { i in
                        Rectangle()
                            .fill(i < row.owned ? Design.Colors.bobaCyan : Design.Colors.glass)
                            .frame(height: 4)
                    }
                }
                .clipShape(Capsule())
                Text("\(row.owned) of \(row.total) treatments")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            Spacer()
            Text("\(Int((row.percent * 100).rounded()))%")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(row.percent == 1.0 ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface))
        .contentShape(Rectangle())
    }

    private func collectionRow(identifier: String) -> some View {
        // identifier is a bobaId (e.g. "BOJ-123-BoJax-Base") for new entries,
        // or a plain cardNumber for legacy entries without a bobaId stored.
        let catalog = cardStore.displayCards.first { $0.id == identifier }
                   ?? cardStore.displayCards.first { $0.cardNumber == identifier }
        let copies = collection.entries(forBobaId: identifier).filter { $0.designation == selectedDesignation }
        let totalPaid = copies.compactMap { $0.purchasePrice }.reduce(Decimal(0), +)

        return HStack(spacing: Design.Spacing.md) {
            // Thumbnail
            if let card = catalog {
                CardImageView(card: card, size: .thumb)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
            } else {
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.surface2)
                    .frame(width: 44, height: 62)
            }

            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(catalog?.name ?? catalog?.cardNumber ?? identifier)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Design.Spacing.xs) {
                    if let element = catalog?.element {
                        Text(element)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.element(element))
                    }
                    Text(catalog?.cardNumber ?? identifier)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                if copies.count > 1 {
                    Text("\(copies.count) copies")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // "PAID" only makes sense for owned designations. Wanted
                // / Grails rows get a neutral "WANTED" tag instead so
                // coaches don't read any purchase-price field on a
                // wishlist entry as money actually spent.
                if selectedDesignation.isOwned {
                    if totalPaid > 0 {
                        Text(formatCurrency(totalPaid))
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("PAID")
                            .font(Design.Fonts.mono(8))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    } else {
                        Text("$—")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                } else {
                    Text(selectedDesignation.displayName.uppercased())
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .tracking(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Trade Room FAB

    private var tradeRoomFAB: some View {
        Button {
            showTradeRoom = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: "5865F2"))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                // Unread badge
                if discord.unreadCount > 0 {
                    Text(discord.unreadCount > 99 ? "99+" : "\(discord.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color(hex: "F23F43"))
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - BobaIdWrapper
// Identifiable wrapper so we can use sheet(item:) with a bobaId or legacy cardNumber string.
private struct BobaIdWrapper: Identifiable {
    let id: String
}

