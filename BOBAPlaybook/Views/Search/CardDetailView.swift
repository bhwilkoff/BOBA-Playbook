import SwiftUI

struct CardDetailView: View {
    // The card passed on init; navigation within the sheet updates `card` via state.
    private let initialCard: Card
    // Optional list of cards to swipe through (e.g. the current search results).
    // Empty = no prev/next navigation shown.
    var navigationCards: [Card] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore

    // The card currently being displayed — may change via prev/next navigation.
    @State private var card: Card

    // Zoom state (reset on card change)
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0
    @State private var showingAddSheet = false
    @State private var showingAddToDeck = false
    @State private var showingAddToShow = false
    @State private var showingSignIn = false
    @State private var showingDBSInfo = false
    /// Non-nil while a "Added to {deck}" toast should be visible. Cleared
    /// automatically after a short delay by the overlay's task.
    @State private var addedToDeckName: String?
    /// Toast surface reused for the Show add flow — "Added to {show}".
    @State private var addedToShowName: String?
    @State private var showSealedEbay = false
    @State private var showSealedRadish = false
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var isPreparingShare = false
    @State private var showingModEdit = false

    init(card: Card, navigationCards: [Card] = []) {
        self.initialCard = card
        self.navigationCards = navigationCards
        _card = State(initialValue: card)
    }

    // Other card_numbers with the same hero (same pattern as CollectionCardDetailView)
    private var variations: [Card] {
        cardStore.displayCards
            .filter { $0.hero == card.hero && $0.cardNumber != card.cardNumber }
            .sorted {
                let lImg = $0.imageFile != nil && !$0.imageFile!.isEmpty
                let rImg = $1.imageFile != nil && !$1.imageFile!.isEmpty
                if lImg != rImg { return lImg }
                return ($0.set, $0.treatment ?? "") < ($1.set, $1.treatment ?? "")
            }
    }

    private var effectiveScale: CGFloat { (scale * pinchDelta).clamped(to: 1...6) }

    // Index of the current card in the navigation list (-1 if not navigable).
    // Uses `card.id` (the full bobaId) not just cardNumber+hero, since the same
    // hero at the same card number can have multiple treatments/variations.
    private var navIndex: Int {
        navigationCards.firstIndex { $0.id == card.id } ?? -1
    }

    private var collectionStatusIcon: String? {
        if collection.isOwned(bobaId: card.id) { return "checkmark.circle.fill" }
        if collection.isWanted(bobaId: card.id) { return "star.fill" }
        return nil
    }

    // Shareable web URL — opens card modal on the web app.
    private var cardShareURL: URL? {
        var components = URLComponents(string: "https://bobaplaybook.com/")!
        var items = [URLQueryItem(name: "card", value: card.cardNumber)]
        if !card.hero.isEmpty { items.append(URLQueryItem(name: "hero", value: card.hero)) }
        if let treatment = card.treatment { items.append(URLQueryItem(name: "treatment", value: treatment)) }
        components.queryItems = items
        return components.url
    }

    private func prepareAndShare() async {
        guard let shareURL = cardShareURL else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        // Fetch card image for sharing.
        var image: UIImage? = nil
        if let imageURL = CDN.fullURL(for: card),
           let (data, _) = try? await URLSession.shared.data(from: imageURL) {
            image = UIImage(data: data)
        }

        // CardShareItemSource returns different data per activity type:
        // - Messages (.message): text string so URL appears in message body
        // - Notes, Mail, AirDrop, etc.: URL object so apps embed a tappable link
        let source = CardShareItemSource(card: card, url: shareURL, image: image)
        shareItems = image != nil ? [image!, source] : [source]
        showingShare = true
    }

    private func navigateCard(by offset: Int) {
        let i = navIndex + offset
        guard i >= 0, i < navigationCards.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            card = navigationCards[i]
            scale = 1.0
            self.offset = .zero
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    artPanel
                    infoPanel
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                ToolbarItem(placement: .principal) {
                    Text(card.name)
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Menu (not confirmationDialog) so the popup drops from the
                    // Add button itself — on iPad the old dialog would anchor
                    // to the card art, not the touch target.
                    if auth.isAuthenticated {
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
                                // Streamers get a third add destination: a
                                // Whatnot/live-show prep list. Separate from
                                // the collection because show cards don't
                                // need to be in the user's collection.
                                if auth.isStreamer {
                                    Button {
                                        showingAddToShow = true
                                    } label: {
                                        Label("To Show", systemImage: "dot.radiowaves.up.forward")
                                    }
                                }
                            }
                        } label: {
                            addIconLabel
                        }
                    } else {
                        Button { showingSignIn = true } label: { addIconLabel }
                    }
                }
                if auth.isMod {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingModEdit = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await prepareAndShare() }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                                .tint(Design.Colors.bobaCyan)
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                    }
                    .disabled(isPreparingShare)
                }
                // Prev/Next navigation in the bottom toolbar — only when navigation list is available
                if navIndex >= 0 {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            navigateCard(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(navIndex > 0 ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                        }
                        .disabled(navIndex <= 0)
                    }
                    ToolbarItem(placement: .bottomBar) { Spacer() }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            navigateCard(by: +1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(navIndex < navigationCards.count - 1 ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                        }
                        .disabled(navIndex >= navigationCards.count - 1)
                    }
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .bottomBar)
            .toolbarBackground(navIndex >= 0 ? .visible : .hidden, for: .bottomBar)
            .sheet(isPresented: $showingAddSheet) {
                AddToCollectionSheet(card: card)
            }
            .sheet(isPresented: $showingAddToDeck) {
                AddToDeckSheet(card: card) { deckName in
                    showAddedToDeckToast(deckName)
                }
                .environment(cardStore)
            }
            .sheet(isPresented: $showingAddToShow) {
                AddToShowSheet(card: card) { showName in
                    showAddedToShowToast(showName)
                }
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView()
            }
            .sheet(isPresented: $showingShare) {
                ActivityShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showSealedEbay) {
                if let url = sealedEbayURL { SafariView(url: url) }
            }
            .sheet(isPresented: $showSealedRadish) {
                if let urlStr = card.radishUrl, let url = URL(string: urlStr) {
                    SafariView(url: url)
                }
            }
            .sheet(isPresented: $showingModEdit) {
                ModCardEditSheet(card: card)
            }
            .sheet(isPresented: $showingDBSInfo) {
                DBSInfoSheet()
            }
            // Confirmation toast for "Added to {deck}". Rendered inside the
            // NavigationStack so it floats above the card art and info panel.
            .overlay(alignment: .top) {
                if let name = addedToDeckName {
                    confirmationToast(text: "Added to \(name)")
                } else if let showName = addedToShowName {
                    confirmationToast(text: "Added to \(showName)")
                }
            }
        }
    }

    private var addIconLabel: some View {
        Image(systemName: collectionStatusIcon ?? "plus.circle.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(
                collectionStatusIcon != nil
                    ? (collection.isOwned(bobaId: card.id) ? Color.green : Design.Colors.bobaOrange)
                    : Design.Colors.bobaOrange
            )
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

    private func confirmationToast(text: String) -> some View {
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

    // MARK: - Format restrictions block
    //
    // Renders only when a card has a real per-card format restriction
    // — a Spec-ineligible hero, a Bonus Play or HTD Play that some
    // events toggle off, or a Trainer card banned in Elite. A plain
    // base-set hero under Power 160 produces no restrictions and this
    // block doesn't appear at all. Deck-building rules (DBS budget,
    // count limits) still live in the Decks tab's legality audit.
    @ViewBuilder
    private func formatRestrictionsBlock(_ notes: [CardRestriction]) -> some View {
        let amber = Design.Colors.bobaOrange
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("FORMAT RESTRICTIONS")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            VStack(spacing: 1) {
                ForEach(notes) { n in
                    HStack(alignment: .top, spacing: Design.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(amber)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.label)
                                .font(Design.Fonts.mono(12, weight: .bold))
                                .foregroundStyle(amber)
                            Text(n.detail)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                .strokeBorder(amber.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: - Art panel
    private var artPanel: some View {
        ZStack {
            // Element gradient background (orange accent for sealed products)
            LinearGradient(
                colors: [
                    (card.isSealed ? Design.Colors.bobaOrange : Design.Colors.element(card.element)).opacity(0.25),
                    Design.Colors.nearBlack
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 420)

            CardImageView(card: card, size: .full)
                .id(card.id)  // force view recreation on card change so loadedImage resets
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .scaleEffect(effectiveScale)
                .offset(
                    x: offset.width + (scale > 1 ? dragDelta.width : 0),
                    y: offset.height + (scale > 1 ? dragDelta.height : 0)
                )
                .clipped()
                .gesture(
                    MagnificationGesture()
                        .updating($pinchDelta) { value, state, _ in state = value }
                        .onEnded { value in
                            scale = (scale * value).clamped(to: 1...6)
                            if scale == 1 { offset = .zero }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragDelta) { value, state, _ in
                            if scale > 1 { state = value.translation }
                        }
                        .onEnded { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width:  offset.width  + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1 { scale = 1.0; offset = .zero }
                        else         { scale = 2.5 }
                    }
                }

        }
    }

    // MARK: - Info panel (branches on card type)
    private var infoPanel: some View {
        Group {
            if card.isSealed {
                sealedInfoPanel
            } else {
                cardInfoPanel
            }
        }
    }

    // MARK: - Regular card info panel
    private var cardInfoPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {

            // Name + primary stat row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text(card.displayName)
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(Design.Colors.textPrimary)
                    if let variation = card.variation, !variation.isEmpty, variation != card.displayName {
                        Text(variation)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                    } else if card.isHero, card.hero != card.name {
                        Text(card.hero)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                }
                Spacer()
                // Power — Hero cards only (power 0 on Play/HotDog is meaningless)
                if card.isHero, let power = card.power, power > 0 {
                    VStack(spacing: 0) {
                        Text("\(power)")
                            .font(Design.Fonts.arena(36))
                            .foregroundStyle(Design.Colors.element(card.element))
                        Text("POWER")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                    }
                } else if card.isPlay, let cost = card.playCost {
                    VStack(spacing: 0) {
                        Text(cost == 0 ? "FREE" : "\(cost)")
                            .font(Design.Fonts.arena(36))
                            .foregroundStyle(cost == 0 ? Color(hex: "7ecb82") : Design.Colors.bobaCyan)
                        Text(cost == 0 ? "COST" : "HOT DOG\(cost == 1 ? "" : "S")")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                    }
                }
            }

            // Badge row
            HStack(spacing: Design.Spacing.sm) {
                if card.isHero {
                    elementBadge
                } else if card.isPlay {
                    playTypeBadge
                } else if card.isHotDog {
                    hotDogBadge
                }
                if let treatment = card.treatment, !treatment.isEmpty {
                    treatmentBadge(treatment)
                }
                setBadge
            }

            Divider().background(Design.Colors.glassBorder)

            // Stats grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Design.Spacing.sm
            ) {
                statCell(label: "Card #",   value: card.cardNumber)
                if card.isHero {
                    statCell(label: "Element",  value: card.element, color: Design.Colors.element(card.element))
                }
                if card.isPlay, let cost = card.playCost {
                    statCell(label: "Cost", value: cost == 0 ? "FREE" : "\(cost) Hot Dog\(cost == 1 ? "" : "s")",
                             color: cost == 0 ? Color(hex: "7ecb82") : Design.Colors.bobaCyan)
                }
                // DBS (Deck Balancing System) cell — Plays only. Tappable
                // to open an info modal explaining the score and budget.
                if card.isPlay, let dbs = card.dbs {
                    dbsStatCell(dbs: dbs, tier: card.dbsTier)
                }
                statCell(label: "Set",      value: card.set)
                statCell(label: "Type",     value: card.cardType)
                if !card.isSealed {
                    statCell(label: "Rarity", value: card.rarityLabel)
                }
                if let sub = card.subSet {
                    statCell(label: "Sub-set", value: sub)
                }

            }

            // Per-card format restrictions — only renders when the card
            // actually has one (Spec-ineligible hero, Bonus Play / HTD
            // toggled-off in some events, Trainer banned in Elite).
            // Most cards render nothing here, which is the point.
            if !card.isSealed {
                let notes = CardFormatEligibility.restrictions(for: card)
                if !notes.isEmpty {
                    formatRestrictionsBlock(notes)
                }
            }

            // Play ability
            if let ability = card.playAbility, !ability.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("PLAY ABILITY")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    Text(ability)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.glass)
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                )
            }

            // Athlete inspiration
            if let athlete = card.athleteInspiration, !athlete.isEmpty {
                HStack(spacing: Design.Spacing.sm) {
                    Rectangle()
                        .fill(Design.Colors.element(card.element))
                        .frame(width: 3)
                        .cornerRadius(2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INSPIRED BY")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        Text(athlete)
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    if card.isInspiredInk {
                        Spacer()
                        Text("INSPIRED INK")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaViolet)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Design.Colors.bobaViolet.opacity(0.15))
                                .overlay(Capsule().strokeBorder(Design.Colors.bobaViolet.opacity(0.4), lineWidth: 0.5)))
                    }
                }
            }

            Divider().background(Design.Colors.glassBorder)

            PricingSection(card: card)

            if !variations.isEmpty {
                variationsSection
            }
        }
        .padding(Design.Spacing.lg)
    }

    // MARK: - Other Versions section

    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("OTHER VERSIONS (\(variations.count))")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.md) {
                    ForEach(variations, id: \.cardNumber) { variant in
                        NavigationLink(destination: CardDetailView(card: variant)) {
                            VStack(spacing: Design.Spacing.xs) {
                                CardImageView(card: variant, size: .thumb)
                                    .frame(width: 80, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))

                                Text(variant.treatment ?? variant.set)
                                    .font(Design.Fonts.mono(9))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .lineLimit(1)
                                    .frame(width: 80)

                                let owned = collection.isOwned(bobaId: variant.id)
                                let wanted = collection.isWanted(bobaId: variant.id)
                                if owned || wanted {
                                    Image(systemName: owned ? "checkmark.circle.fill" : "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(owned ? .green : Design.Colors.bobaOrange)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sealed product info panel
    private var sealedInfoPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {

            // Name + product type
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(card.name)
                    .font(Design.Fonts.display(22))
                    .foregroundStyle(Design.Colors.textPrimary)
                if let pt = card.productType {
                    Text(pt.replacingOccurrences(of: "-", with: " ").uppercased())
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .tracking(1)
                }
            }

            // Badge row
            HStack(spacing: Design.Spacing.sm) {
                Text(card.set.uppercased())
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaOrange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
                    )
                Text("SEALED PRODUCT")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.glass)
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                    )
            }

            Divider().background(Design.Colors.glassBorder)

            // Product stats grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Design.Spacing.sm
            ) {
                if let packs = card.packsPerBox {
                    statCell(label: "Packs/Box", value: "\(packs)")
                }
                if let cpp = card.cardsPerPack {
                    statCell(label: "Cards/Pack", value: "\(cpp)")
                }
                if let total = card.totalCards {
                    statCell(label: "Total Cards", value: "\(total)")
                }
                if let msrp = card.msrp {
                    statCell(label: "MSRP", value: Decimal(msrp).formatted(.currency(code: "USD")))
                }
                if let upc = card.upc {
                    statCell(label: "UPC", value: upc)
                }
            }

            // Highlights
            if let highlights = card.highlights, !highlights.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("WHAT'S INSIDE")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(highlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                                Text("·")
                                    .font(Design.Fonts.mono(13, weight: .bold))
                                    .foregroundStyle(Design.Colors.bobaOrange)
                                Text(highlight)
                                    .font(Design.Fonts.mono(12))
                                    .foregroundStyle(Design.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.glass)
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                )
            }

            // External links row
            HStack(spacing: Design.Spacing.sm) {
                // eBay sold listings
                if card.ebaySearchQuery != nil {
                    Button { showSealedEbay = true } label: {
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

                // Radish price guide
                if card.radishUrl != nil {
                    Button { showSealedRadish = true } label: {
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
        .padding(Design.Spacing.lg)
    }

    private var sealedEbayURL: URL? {
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

    // MARK: - Sub-components
    private var elementBadge: some View {
        Text(card.element)
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.element(card.element))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.element(card.element).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.element(card.element).opacity(0.45), lineWidth: 1))
            )
    }

    private var playTypeBadge: some View {
        let isBonus = card.isBonusPlay == true
        let color = isBonus ? Design.Colors.bobaCyan : Design.Colors.bobaViolet
        return Text(isBonus ? "BONUS PLAY" : "PLAY CARD")
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(color.opacity(0.35), lineWidth: 1))
            )
    }

    private var hotDogBadge: some View {
        Text("HOT DOG")
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Color(hex: "7ecb82"))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Color(hex: "4CAF50").opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Color(hex: "4CAF50").opacity(0.35), lineWidth: 1))
            )
    }

    private var setBadge: some View {
        Text(card.set.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.glass)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            )
    }

    private func treatmentBadge(_ treatment: String) -> some View {
        Text(treatment.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.bobaOrange.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
            )
    }

    private func statCell(label: String, value: String, color: Color = Design.Colors.textSecondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.2)
            Text(value)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.surface2)
        )
    }

    // DBS cell — same shape as statCell but tappable (opens explainer
    // modal). Color-coded by tier so coaches can scan at a glance.
    private func dbsStatCell(dbs: Int, tier: String?) -> some View {
        Button {
            showingDBSInfo = true
        } label: {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("DBS")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.2)
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(dbs)")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(dbsColor(for: tier))
                        if let t = tier, !t.isEmpty {
                            Text(t.uppercased())
                                .font(Design.Fonts.mono(9, weight: .bold))
                                .foregroundStyle(dbsColor(for: tier).opacity(0.85))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(dbsColor(for: tier).opacity(0.15)))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.surface2)
            )
        }
        .buttonStyle(.plain)
    }

    private func dbsColor(for tier: String?) -> Color {
        switch tier?.lowercased() {
        case "low":       return Color(hex: "7ecb82")
        case "medium":    return Design.Colors.bobaCyan
        case "high":      return .yellow
        case "very high": return Design.Colors.bobaOrange
        default:          return Design.Colors.textSecondary
        }
    }
}

// MARK: - DBS Info Sheet
// Presented from the DBS stat cell on Plays. Explains the scoring system
// and its role in Nationals-style formats. Copy sourced from the
// 2026-04-22 Discord terminology handoff §4.1.

struct DBSInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    Text("What is DBS?")
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("The **Deck Balancing System** is a scoring system used in Nationals-style formats to keep high-powered plays from crowding out the rest of a deck.")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textSecondary)
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        bullet("Every Play card has a DBS score.")
                        bullet("Your deck's total DBS across all 30 Plays must be ≤ **1,000** in formats that enforce it.")
                        bullet("High-DBS plays are individually powerful but force you to fill the rest of the deck with low-DBS plays to stay under budget.")
                        bullet("Non-Nationals formats (Rookie, Substitution, Playmaker) ignore DBS entirely — it's only a constraint when a format opts in.")
                    }
                    Text("DBS tiers").font(Design.Fonts.display(16)).foregroundStyle(Design.Colors.textPrimary).padding(.top, Design.Spacing.sm)
                    VStack(spacing: 1) {
                        tierRow("Low",       "1–20",  Color(hex: "7ecb82"))
                        tierRow("Medium",    "21–40", Design.Colors.bobaCyan)
                        tierRow("High",      "41–60", .yellow)
                        tierRow("Very High", "67+",   Design.Colors.bobaOrange)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                    Text("The deck builder shows a running DBS total and warns you when you cross the budget — no mental math required.")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(.top, Design.Spacing.xs)
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Text("•")
                .font(Design.Fonts.mono(14, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text(.init(text))
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierRow(_ label: String, _ range: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(color)
            Spacer()
            Text(range)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface)
    }
}

// MARK: - Comparable clamp
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Activity sheet wrapper
import UIKit

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Per-app share item source
// Notes and similar apps handle URL objects as tappable embedded links.
// Messages requires a plain String so the URL appears in the message body.
final class CardShareItemSource: NSObject, UIActivityItemSource {
    private let card: Card
    private let url: URL
    private let image: UIImage?

    init(card: Card, url: URL, image: UIImage?) {
        self.card = card
        self.url = url
        self.image = image
    }

    // Placeholder tells the system what kind of item this is (URL).
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // Messages needs a String — URL objects get dropped when paired with an image.
        if activityType == .message {
            return "\(card.name) — BOBA Playbook\n\(url.absoluteString)"
        }
        // Notes, Mail, AirDrop, Copy, etc. all handle URL objects correctly.
        return url
    }

    // Subject line for Mail and Notes.
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        return "\(card.name) — BOBA Playbook"
    }
}
