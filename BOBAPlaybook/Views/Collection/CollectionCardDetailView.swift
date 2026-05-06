import SwiftUI

// MARK: - CollectionCardDetailView
// Shows all physical copies of a card in the user's collection.
// Also surfaces "variations" — other card_numbers with the same hero.

struct CollectionCardDetailView: View {
    /// bobaId (e.g. "BOJ-123-BoJax-Base") for new entries, or a plain cardNumber for legacy entries.
    let bobaId: String
    /// Sheet vs. push presentation — see CardDetailView.wrapInNavStack.
    var wrapInNavStack: Bool = true

    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var editingEntry: UserCard?
    @State private var showingAddSheet = false
    @State private var showingAddToDeck = false
    @State private var showingAddToShow = false
    @State private var deleteError: String?
    @State private var isRefreshingPrice = false
    @State private var addedToDeckName: String?
    @State private var addedToShowName: String?
    /// Custom decks this card is in. Loaded on appear when the user is
    /// authenticated. `nil` = not yet loaded, `[]` = loaded and empty.
    @State private var containingDecks: [SavedDeck]? = nil
    /// Selected copy for nav — identity comes from UserCard.id so
    /// multiple entries of the same bobaId can be paged through.
    @State private var focusedEntryID: UUID?
    /// Pushed card detail when coach taps a variation / other-copy tile.
    @State private var jumpBobaId: String?

    private var catalogCard: Card? {
        // Try exact bobaId match first, then fall back to cardNumber for legacy entries
        cardStore.displayCards.first { $0.id == bobaId }
        ?? cardStore.displayCards.first { $0.cardNumber == bobaId }
    }

    private var entries: [UserCard] {
        collection.entries(forBobaId: bobaId)
    }

    // Other card_numbers with the same hero (variations/other printings)
    private var variations: [Card] {
        guard let card = catalogCard else { return [] }
        return cardStore.displayCards
            .filter { $0.hero == card.hero && $0.id != bobaId }
            .sorted {
                let lImg = $0.imageFile != nil && !$0.imageFile!.isEmpty
                let rImg = $1.imageFile != nil && !$1.imageFile!.isEmpty
                if lImg != rImg { return lImg }
                return ($0.set, $0.treatment ?? "") < ($1.set, $1.treatment ?? "")
            }
    }

    @ViewBuilder
    private func navStackIfNeeded<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if wrapInNavStack {
            NavigationStack { content() }
        } else {
            content()
        }
    }

    var body: some View {
        navStackIfNeeded {
            ScrollView {
                VStack(spacing: 0) {
                    if let card = catalogCard {
                        artPanel(for: card)
                    }

                    VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                        if let card = catalogCard {
                            cardMetadata(for: card)
                        }

                        copiesSection

                        if auth.isAuthenticated {
                            decksSection
                        }

                        if let card = catalogCard, !(card.isSealed) {
                            PricingSection(card: card, showActiveListings: false)
                        }

                        if let card = catalogCard, !(card.isSealed) {
                            externalLinksRow(card: card)
                        }

                        if !variations.isEmpty {
                            variationsSection
                        }
                    }
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.top, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.lg)
                }
            }
            // STANDARDIZED toolbar setup — IDENTICAL to Find's
            // CardDetailView and Decks's BrowserCardDetailSheet.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if wrapInNavStack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(catalogCard?.name ?? catalogCard?.cardNumber ?? bobaId)
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let card = catalogCard {
                        // Menu drops from the Add button itself (replaces the
                        // old iPad popover which anchored to the card art).
                        Menu {
                            Section("Add \(card.name)") {
                                Button {
                                    showingAddSheet = true
                                } label: {
                                    Label("To Collection", systemImage: "folder.badge.plus")
                                }
                                if card.isHero || card.isPlay || card.isHotDog {
                                    Button {
                                        showingAddToDeck = true
                                    } label: {
                                        Label("To Custom Deck", systemImage: "rectangle.stack.badge.plus")
                                    }
                                }
                                // Streamer-only add-to-Show destination.
                                if auth.isStreamer {
                                    Button {
                                        showingAddToShow = true
                                    } label: {
                                        Label("To Show", systemImage: "dot.radiowaves.up.forward")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
                }
            }
            // Hide nav bar background — gradient is the visual top.
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddSheet) {
                if let card = catalogCard {
                    AddToCollectionSheet(card: card)
                }
            }
            .sheet(isPresented: $showingAddToDeck) {
                if let card = catalogCard {
                    AddToDeckSheet(card: card) { deckName in
                        showAddedToDeckToast(deckName)
                    }
                    .environment(cardStore)
                }
            }
            .sheet(isPresented: $showingAddToShow) {
                if let card = catalogCard {
                    AddToShowSheet(card: card) { showName in
                        showAddedToShowToast(showName)
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                if let card = catalogCard {
                    EditCollectionEntrySheet(entry: entry, card: card)
                }
            }
            .task {
                // Silently refresh estimated_value when the view appears if data is stale.
                guard let card = catalogCard else { return }
                isRefreshingPrice = true
                await collection.refreshPricingIfNeeded(for: card.cardNumber, card: card)
                isRefreshingPrice = false
            }
            .task(id: auth.isAuthenticated) {
                guard auth.isAuthenticated else {
                    containingDecks = []
                    return
                }
                // One-shot load of custom decks containing this card.
                // Failures are silent — the section just stays hidden
                // rather than surfacing a network error on a view
                // that's already dense.
                do {
                    containingDecks = try await SupabaseClient.shared.decksContaining(bobaId: bobaId)
                } catch {
                    containingDecks = []
                }
            }
            .navigationDestination(item: $jumpBobaId) { other in
                CollectionCardDetailView(bobaId: other)
            }
            .overlay(alignment: .top) {
                if let name = addedToDeckName {
                    confirmationToast("Added to \(name)")
                } else if let showName = addedToShowName {
                    confirmationToast("Added to \(showName)")
                }
            }
        }
    }

    private func confirmationToast(_ text: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "4CAF50"))
            Text(text)
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "4CAF50").opacity(0.4), lineWidth: 1))
        .padding(.top, Design.Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func showAddedToDeckToast(_ name: String) {
        withAnimation(.easeOut(duration: 0.25)) { addedToDeckName = name }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { addedToDeckName = nil }
        }
    }

    private func showAddedToShowToast(_ name: String) {
        withAnimation(.easeOut(duration: 0.25)) { addedToShowName = name }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { addedToShowName = nil }
        }
    }

    // MARK: - Card header

    /// Standardized art panel — IDENTICAL shape/size/padding/gradient
    /// across Find / Decks / Collection per user request. Any
    /// difference between the three card-detail surfaces should live
    /// in the body BELOW this panel, never in the panel itself.
    /// Matches CardDetailView.artPanel.
    private func artPanel(for card: Card) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Design.Colors.element(card.element).opacity(0.25),
                    Design.Colors.nearBlack
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Design.CardDetailMetrics.panelHeight(for: horizontalSizeClass))

            CardImageView(card: card, size: .full)
                .aspectRatio(5.0/7.0, contentMode: .fit)
                .frame(height: Design.CardDetailMetrics.imageHeight(for: horizontalSizeClass))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Design.Colors.element(card.element).opacity(0.4), radius: 16, y: 6)
        }
    }

    /// The metadata that used to live in cardHeader's right column.
    /// Now sits below the artPanel as a clean horizontal row.
    private func cardMetadata(for card: Card) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text(card.name)
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(card.cardNumber)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
            HStack(spacing: Design.Spacing.xs) {
                Text(card.element)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.element(card.element))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.element(card.element).opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.element(card.element).opacity(0.4), lineWidth: 1))
                    )
                if let treatment = card.treatment {
                    Text(treatment)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .fill(Design.Colors.bobaOrange.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                    .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
                        )
                }
                if card.rarityTier > 0 {
                    Text(card.rarityLabel)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .fill(Design.Colors.bobaCyan.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                    .strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                        )
                }
            }
            if let power = card.power {
                Text("\(power) POWER")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
    }

    // MARK: - Copies section

    private var copiesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            sectionHeader("MY COPIES (\(entries.count))")

            if entries.isEmpty {
                Text("No copies in collection")
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(Design.Spacing.md)
            } else {
                VStack(spacing: Design.Spacing.sm) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: UserCard) -> some View {
        // Whole row is tappable → opens the inline edit sheet. Feels
        // like "tap the field to edit" since every visible value lives
        // in the same row; the dedicated pencil button still works for
        // users who expect it.
        Button {
            editingEntry = entry
        } label: {
            entryRowBody(entry)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    do {
                        try await collection.deleteCard(id: entry.id)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func entryRowBody(_ entry: UserCard) -> some View {
        HStack(spacing: Design.Spacing.md) {
            // Designation icon
            Image(systemName: entry.designation.icon)
                .font(.system(size: 14))
                .foregroundStyle(designationColor(entry.designation))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.designation.displayName)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                HStack(spacing: Design.Spacing.sm) {
                    if let condition = entry.condition {
                        Text(condition)
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    if let grade = entry.grade {
                        Text("Grade: \(grade)")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    if let serial = entry.serialNumber {
                        Text("#\(serial)")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                }
            }

            Spacer()

            // Price columns: what was paid + current market estimate
            HStack(spacing: Design.Spacing.md) {
                if let price = entry.purchasePrice, price > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatPrice(price))
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("PAID")
                            .font(Design.Fonts.mono(8))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    }
                }
                if let est = entry.estimatedValue, est > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatPrice(est))
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                        Text("MKT")
                            .font(Design.Fonts.mono(8))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    }
                } else if isRefreshingPrice {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Design.Colors.bobaOrange)
                }
            }

            // Edit button
            Button {
                editingEntry = entry
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.textMuted)
                    .frame(width: 32, height: 32)
            }
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

    // MARK: - Decks containing this card
    //
    // Lists custom decks the user has saved that include this exact
    // bobaId. Hidden until loaded so the section doesn't flicker. An
    // empty result stays hidden — only show when there's something to
    // surface.
    @ViewBuilder
    private var decksSection: some View {
        if let decks = containingDecks, !decks.isEmpty {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                sectionHeader("IN YOUR DECKS (\(decks.count))")
                VStack(spacing: 6) {
                    ForEach(decks) { deck in
                        HStack(spacing: Design.Spacing.md) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 13))
                                .foregroundStyle(Design.Colors.bobaCyan)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.name)
                                    .font(Design.Fonts.mono(13, weight: .bold))
                                    .foregroundStyle(Design.Colors.textPrimary)
                                if !deck.format.isEmpty {
                                    Text(deck.format.uppercased())
                                        .font(Design.Fonts.mono(9))
                                        .foregroundStyle(Design.Colors.textMuted)
                                        .tracking(1.2)
                                }
                            }
                            Spacer()
                        }
                        .padding(Design.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .fill(Design.Colors.bobaCyan.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                    .strokeBorder(Design.Colors.bobaCyan.opacity(0.25), lineWidth: 1))
                        )
                    }
                }
            }
        }
    }

    /// "eBay Sales" + "Radish Guide" row, mirrors the Find-tab card
    /// detail but skips the active "Buy Now" button.
    private func externalLinksRow(card: Card) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            if let url = ebaySoldURL(for: card) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 11))
                        Text("eBay Sales")
                            .font(Design.Fonts.mono(12))
                    }
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaOrange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
                    )
                }
            }
            if let radishStr = card.radishUrl, let url = URL(string: radishStr) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11))
                        Text("Radish Guide")
                            .font(Design.Fonts.mono(12))
                    }
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaCyan.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                    )
                }
            }
        }
    }

    // MARK: - Variations section

    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            sectionHeader("OTHER VERSIONS (\(variations.count))")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.md) {
                    ForEach(variations, id: \.cardNumber) { variant in
                        // Owned variants route back into this view so
                        // coaches can edit that copy's designation /
                        // price / notes in the same flow. Un-owned
                        // variants fall through to the Find-tab detail
                        // where they can add a new copy.
                        if collection.isOwned(bobaId: variant.id) {
                            Button {
                                jumpBobaId = variant.id
                            } label: {
                                variationTile(variant)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: CardDetailView(card: variant)) {
                                variationTile(variant)
                            }
                        }
                    }
                }
            }
        }
    }

    private func variationTile(_ card: Card) -> some View {
        VStack(spacing: Design.Spacing.xs) {
            CardImageView(card: card, size: .thumb)
                .frame(width: 80, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))

            Text(card.treatment ?? card.set)
                .font(Design.Fonts.mono(9))
                .foregroundStyle(Design.Colors.textMuted)
                .lineLimit(1)
                .frame(width: 80)

            // Ownership indicator
            let owned = collection.isOwned(bobaId: card.id)
            let wanted = collection.isWanted(bobaId: card.id)
            if owned || wanted {
                Image(systemName: owned ? "checkmark.circle.fill" : "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(owned ? .green : Design.Colors.bobaOrange)
            }
        }
    }

    // MARK: - Helpers

    private func ebaySoldURL(for card: Card) -> URL? {
        guard let query = card.ebaySearchQuery else { return nil }
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")!
        components.queryItems = [
            URLQueryItem(name: "_nkw",        value: query),
            URLQueryItem(name: "LH_Sold",     value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "_sacat",      value: "0"),
        ]
        return components.url
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Design.Fonts.mono(9, weight: .bold))
            .foregroundStyle(Design.Colors.textMuted)
            .tracking(1.5)
    }

    private func designationColor(_ d: UserCard.Designation) -> Color {
        switch d {
        case .personal:  return .green
        case .for_sale:  return Design.Colors.bobaOrange
        case .for_trade: return Design.Colors.bobaCyan
        case .wanted:    return .yellow
        case .grails:    return Design.Colors.bobaViolet
        }
    }

    private func formatPrice(_ price: Decimal) -> String {
        if price == 0 { return "$—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: price as NSDecimalNumber) ?? "$\(price)"
    }
}

// MARK: - EditCollectionEntrySheet
// Inline edit for an existing UserCard entry.

struct EditCollectionEntrySheet: View {
    let entry: UserCard
    let card: Card

    @Environment(CollectionStore.self) private var collection
    @Environment(\.dismiss) private var dismiss

    @State private var designation: UserCard.Designation
    @State private var condition: String
    @State private var grade: String
    @State private var gradingCompany: String
    @State private var purchasePriceText: String
    @State private var askingPriceText: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showDeleteConfirmation = false

    init(entry: UserCard, card: Card) {
        self.entry = entry
        self.card = card
        _designation = State(initialValue: entry.designation)
        _condition = State(initialValue: entry.condition ?? "")
        _grade = State(initialValue: entry.grade ?? "")
        _gradingCompany = State(initialValue: entry.gradingCompany ?? "")
        _purchasePriceText = State(initialValue: entry.purchasePrice.map { "\($0)" } ?? "")
        _askingPriceText = State(initialValue: entry.askingPrice.map { "\($0)" } ?? "")
        _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("DESIGNATION") {
                    Picker("Designation", selection: $designation) {
                        ForEach(UserCard.Designation.allCases) { d in
                            Label(d.displayName, systemImage: d.icon).tag(d)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .tint(Design.Colors.bobaOrange)
                }
                .listRowBackground(Design.Colors.surface)

                Section("PRICING") {
                    HStack {
                        Text("Purchase Price")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Spacer()
                        HStack(spacing: 2) {
                            Text("$")
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textMuted)
                            TextField("0.00", text: $purchasePriceText)
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)

                Section("NOTES") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(3...6)
                }
                .listRowBackground(Design.Colors.surface)

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Remove from Collection")
                            .font(Design.Fonts.mono(14))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listRowBackground(Design.Colors.surface)

                if let err = saveError {
                    Section {
                        Text(err).font(Design.Fonts.mono(13)).foregroundStyle(.red)
                    }
                    .listRowBackground(Design.Colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        if isSaving { ProgressView().tint(Design.Colors.bobaOrange) }
                        else {
                            Text("Save")
                                .font(Design.Fonts.mono(14, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "Remove from Collection",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        try? await collection.deleteCard(id: entry.id)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove this entry from your collection.")
            }
        }
    }

    private func save() {
        isSaving = true
        let fields = UpdateUserCard(
            designation: designation,
            condition: condition.isEmpty ? nil : condition,
            grade: grade.isEmpty ? nil : grade,
            gradingCompany: gradingCompany.isEmpty ? nil : gradingCompany,
            purchasePrice: Decimal(string: purchasePriceText.isEmpty ? "0" : purchasePriceText),
            notes: notes.isEmpty ? nil : notes
        )
        Task {
            do {
                try await collection.updateCard(id: entry.id, fields: fields)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
