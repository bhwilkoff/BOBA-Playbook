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
    @Environment(DeckBuilderStore.self) private var deckBuilder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var editingEntry: UserCard?
    @State private var showingAddSheet = false
    @State private var showingAddToDeck = false
    @State private var showingAddToShow = false
    @State private var showingHeroShot = false
    @State private var deleteError: String?
    @State private var isRefreshingPrice = false
    @State private var addedToDeckName: String?
    @State private var addedToShowName: String?
    /// Tick 122 — "Removed X" toast after the swipe-delete on per-copy
    /// rows. Distinct state from addedToDeckName so the toast doesn't
    /// prepend the "Added to " text the existing overlay wraps.
    @State private var removedEntryName: String?
    /// Tick 152 — snapshot of the deck draft right before "In your
    /// decks" load wipes it. Non-nil while the Undo banner is on
    /// screen; tapping UNDO re-applies it via store.applySnapshot.
    /// Mirrors Android tick 149.
    @State private var preLoadDraftSnapshot: (snapshot: DeckBuilderStore.DraftSnapshot, deckName: String)?
    /// Custom decks this card is in. Loaded on appear when the user is
    /// authenticated. `nil` = not yet loaded, `[]` = loaded and empty.
    @State private var containingDecks: [SavedDeck]? = nil
    /// Pushed card detail when coach taps a variation / other-copy tile.
    @State private var jumpBobaId: String?
    /// Mutable "current bobaId" so swipe-between-cards can advance
    /// without popping/pushing the navigation stack. Initialized from
    /// the constructor's `bobaId` parameter on first appearance.
    @State private var currentBobaId: String? = nil

    // Tick 523 — true horizontal swipe animation (replaces fade). See
    // CardDetailView's matching swipeDirection for the same shape.
    @State private var swipeDirection: Int = 1

    /// The bobaId actually displayed. Falls back to the init-time
    /// parameter until the @State has been seeded.
    private var activeBobaId: String { currentBobaId ?? bobaId }

    private var catalogCard: Card? {
        // O(1) — was a 17k linear scan that ran on every view re-render.
        cardStore.resolveCard(byId: activeBobaId)
    }

    private var entries: [UserCard] {
        collection.entries(forBobaId: activeBobaId)
    }

    /// Every owned bobaId, deduped, ordered by most-recent acquisition
    /// first. Drives swipe-between-cards on this surface.
    private var ownedBobaIdsByRecency: [String] {
        var best: [String: Date] = [:]
        for uc in collection.userCards {
            let key = uc.bobaId ?? uc.cardNumber
            if let prior = best[key] {
                if uc.acquiredAt > prior { best[key] = uc.acquiredAt }
            } else {
                best[key] = uc.acquiredAt
            }
        }
        return best
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    /// Advance to next/previous owned card by recency. Wraps at ends.
    private func advanceOwnedCard(by delta: Int) {
        let list = ownedBobaIdsByRecency
        guard list.count > 1 else { return }
        guard let i = list.firstIndex(of: activeBobaId) else { return }
        let n = list.count
        let next = ((i + delta) % n + n) % n
        guard next != i else { return }
        swipeDirection = delta
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            currentBobaId = list[next]
        }
    }

    // Other card_numbers with the same hero (variations/other printings).
    // @State, not a computed property — the computed form filtered + sorted
    // all 17K displayCards on EVERY body evaluation (swipe-nav animation
    // frames included). Recomputed once per card change via the
    // .onChange(of: activeBobaId) hook at the body root. Same fix as
    // Find's CardDetailView, per DESIGN.md §8.6 (surfaces stay in lockstep).
    @State private var variations: [Card] = []

    private func recomputeVariations() {
        guard let card = catalogCard else {
            variations = []
            return
        }
        variations = cardStore.displayCards
            .filter { $0.hero == card.hero && $0.id != activeBobaId }
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
                // Tick 523 — true horizontal swipe transition. activeBobaId
                // identity changes drive the slide; see swipeDirection.
                VStack(spacing: 0) {
                    if let card = catalogCard {
                        artPanel(for: card)
                    }

                    VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                        if let card = catalogCard {
                            cardMetadata(for: card)
                        }

                        // Card content — canonical 6-cell stats grid +
                        // Cost/DBS for Plays + format legality strip +
                        // format restrictions + play ability + athlete
                        // inspiration + (for sealed) product fields +
                        // highlights. Shared with Find via the
                        // CardContentSection struct (CardDetailView.swift
                        // §"CardContentSection"). Same struct = same
                        // render = no drift between surfaces, per
                        // DESIGN.md §8.6's binding rule that detail
                        // surfaces share content verbatim.
                        if let card = catalogCard {
                            CardContentSection(card: card)
                        }

                        copiesSection

                        if auth.isAuthenticated {
                            decksSection
                        }

                        // Pricing surface — sealed products DO get pricing
                        // (the eBay lookup works on Sealed Product bobaIds
                        // and Find already displays it for sealed). The
                        // earlier `!card.isSealed` gate hid pricing from
                        // sealed entries in Collection only — fixed per
                        // beta feedback 2026-05-20.
                        //
                        // `externalLinksRow` removed 2026-05-28 per Ben's
                        // audit: PricingSection already renders both the
                        // "eBay Sales" and "View on Radish" footer buttons
                        // (PricingSection.swift §"External links"). Calling
                        // externalLinksRow alongside duplicated both, so
                        // Collection rendered each twice. The duplicates
                        // are gone; PricingSection is the single source.
                        if let card = catalogCard {
                            PricingSection(card: card, showActiveListings: false)
                        }

                        if !variations.isEmpty {
                            variationsSection
                        }
                    }
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.top, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.lg)
                }
                .id(activeBobaId)
                .transition(.asymmetric(
                    insertion: .move(edge: swipeDirection > 0 ? .trailing : .leading),
                    removal:   .move(edge: swipeDirection > 0 ? .leading  : .trailing)
                ))
            }
            // Swipe left/right between owned cards (beta feedback
            // 2026-05-20). Mirrors the CardDetailView gesture — only
            // fires on horizontal swipe at rest. Drag bounds (|dx|>60,
            // |dy|<40) yield to vertical scrolling.
            .simultaneousGesture(
                DragGesture(minimumDistance: 60)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 60, abs(dy) < 40 else { return }
                        if dx < 0 { advanceOwnedCard(by:  1) }
                        else      { advanceOwnedCard(by: -1) }
                    }
            )
            .onAppear { if currentBobaId == nil { currentBobaId = bobaId } }
            // Recompute the Other Versions list only when the displayed
            // card actually changes (initial render + swipe nav) — see
            // the @State `variations` comment.
            .onChange(of: activeBobaId, initial: true) {
                recomputeVariations()
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
                if catalogCard != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingHeroShot = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                        .accessibilityLabel("Hero Shot — share a 3D video of this card")
                        .help("Hero Shot — share a 3D video of this card")
                    }
                }
                // iOS 27 pins the primary Add action so it never collapses into
                // overflow when the Hero Shot share button competes at large
                // Dynamic Type; iOS 26 keeps the standard trailing placement.
                // `.topBarPinnedTrailing` is an iOS-27-SDK symbol, so it's
                // compile-gated (DECISIONS.md #066) — GM builds use the 26 path.
                #if IOS27_SDK
                if #available(iOS 27, *) {
                    ToolbarItem(placement: .topBarPinnedTrailing) { addToolbarButton }
                } else {
                    ToolbarItem(placement: .topBarTrailing) { addToolbarButton }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) { addToolbarButton }
                #endif
            }
            // Hide nav bar background — gradient is the visual top.
            .toolbarBackground(.hidden, for: .navigationBar)
            // The four "Add to X" / Edit sheets are action-shaped per
            // DESIGN.md §6.6 — popover on iPad anchored to the trigger
            // button; sheet on compact.
            .sheet(isPresented: $showingAddSheet) {
                if let card = catalogCard {
                    AddToCollectionSheet(card: card) { designationLabel in
                        showAddedToDeckToast("Added to \(designationLabel)")
                    }
                        .presentationCompactAdaptation(.popover)
                }
            }
            .sheet(isPresented: $showingAddToDeck) {
                if let card = catalogCard {
                    AddToDeckSheet(card: card) { deckName in
                        showAddedToDeckToast(deckName)
                    }
                    .environment(cardStore)
                    .presentationCompactAdaptation(.popover)
                }
            }
            .sheet(isPresented: $showingAddToShow) {
                if let card = catalogCard {
                    AddToShowSheet(card: card) { showName in
                        showAddedToShowToast(showName)
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }
            .sheet(item: $editingEntry) { entry in
                if let card = catalogCard {
                    EditCollectionEntrySheet(entry: entry, card: card)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .fullScreenCover(isPresented: $showingHeroShot) {
                if let card = catalogCard {
                    HeroShotView(card: card)
                }
            }
            .task {
                // Silently refresh estimated_value when the view appears if data is stale.
                guard let card = catalogCard else { return }
                isRefreshingPrice = true
                await collection.refreshPricingIfNeeded(for: card)
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
                if let pending = preLoadDraftSnapshot {
                    overwriteUndoBanner(deckName: pending.deckName, snapshot: pending.snapshot)
                } else if let name = addedToDeckName {
                    confirmationToast("Added to \(name)")
                } else if let showName = addedToShowName {
                    confirmationToast("Added to \(showName)")
                } else if let removed = removedEntryName {
                    confirmationToast("Removed \(removed)")
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

    /// Cyan-accent banner with a tappable UNDO. Surfaced after "In your
    /// decks" load wipes a non-empty draft. Tick 152 — mirrors Android
    /// tick 149 destructive-overwrite warning + Undo flow.
    private func overwriteUndoBanner(deckName: String, snapshot: DeckBuilderStore.DraftSnapshot) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(Design.Colors.bobaCyan)
            Text("Loaded “\(deckName)” — draft replaced")
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(2)
            Button {
                deckBuilder.applySnapshot(snapshot, allCards: cardStore.displayCards)
                withAnimation(.easeOut(duration: 0.2)) { preLoadDraftSnapshot = nil }
            } label: {
                Text("UNDO")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
            .accessibilityLabel("Undo deck load")
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.Colors.bobaCyan.opacity(0.4), lineWidth: 1))
        .padding(.top, Design.Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// The primary "Add" action. Extracted so the iOS 27
    /// `.topBarPinnedTrailing` branch and the iOS 26 `.topBarTrailing` fallback
    /// share one definition (keeps Add in the bar even when Hero Shot share
    /// competes at large Dynamic Type).
    @ViewBuilder
    private var addToolbarButton: some View {
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

    private func showAddedToDeckToast(_ name: String) {
        withAnimation(.easeOut(duration: 0.25)) { addedToDeckName = name }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { addedToDeckName = nil }
        }
    }

    private func showRemovedToast(_ name: String) {
        withAnimation(.easeOut(duration: 0.25)) { removedEntryName = name }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { removedEntryName = nil }
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
    /// Matches CardDetailView.artPanel. Sealed-product gradient uses
    /// `Design.Colors.bobaOrange` accent instead of the element color
    /// (sealed products have no element) — without this, sealed
    /// boxes / blasters in the Collection grid open with a muddy
    /// transparent gradient. Synced with CardDetailView 2026-05-20
    /// per DESIGN.md §8.6 "All three detail structs share these
    /// blocks — drift is the bug."
    private func artPanel(for card: Card) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    (card.isSealed ? Design.Colors.bobaOrange : Design.Colors.element(card.element)).opacity(0.25),
                    Design.Colors.nearBlack
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Design.CardDetailMetrics.panelHeight(for: horizontalSizeClass))

            CardImageView(card: card, size: .full)
                .aspectRatio(5.0/7.0, contentMode: .fit)
                .frame(height: Design.CardDetailMetrics.imageHeight(for: horizontalSizeClass))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: (card.isSealed ? Design.Colors.bobaOrange : Design.Colors.element(card.element)).opacity(0.4), radius: 16, y: 6)
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
                // iOS 27: enables the per-row swipe-to-remove below — these rows
                // live in a VStack, not a List, where swipeActions was a no-op
                // pre-27. iOS 26 users still remove via the row's edit sheet.
                .bobaSwipeActionsContainer()
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
                // Capture the catalog card for the toast copy BEFORE the
                // async delete fires. iOS tick 117 added the equivalent
                // for Decks; Android tick 119 added the equivalent for
                // Collection (with Undo). iOS Undo here defers — the
                // confirmationToast helper is text-only; Undo requires
                // a richer action-state overlay.
                let cardLabel = catalogCard?.displayName
                    ?? (entry.cardNumber)
                Task {
                    do {
                        try await collection.deleteCard(id: entry.id)
                        showRemovedToast(cardLabel)
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
                    if let company = entry.gradingCompany, !company.isEmpty {
                        Text(company)
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    if let serial = entry.serialNumber {
                        Text("#\(serial)")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                }
                // Notes — surface the per-copy notes inline (beta
                // feedback 2026-05-20: "should show on the collection
                // individual detail"). Capped at 2 lines so a long
                // note doesn't push the price column off-screen.
                if let n = entry.notes, !n.isEmpty {
                    Text(n)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
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
            .accessibilityLabel("Edit this copy")
            .help("Edit this copy")
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
                        // Tap-to-load row — parity with Android tick 94.
                        // Loads the saved deck into the draft + fires the
                        // green-checkmark toast so the user sees the
                        // action register. Without this, the row was
                        // read-only and a real coaching workflow ("oh,
                        // that deck has this card — let me open it")
                        // required opening Decks tab and finding the
                        // deck manually.
                        Button {
                            // Capture pre-load draft so the Undo banner
                            // can restore it. Mirrors Android tick 149.
                            let hadDraft = !deckBuilder.heroes.isEmpty
                                || !deckBuilder.plays.isEmpty
                                || !deckBuilder.bonusPlays.isEmpty
                                || !deckBuilder.hotDogs.isEmpty
                            let captured = hadDraft ? deckBuilder.currentSnapshot() : nil
                            Task {
                                do {
                                    _ = try await deckBuilder.loadSavedDeck(deck, cards: cardStore.displayCards)
                                    if let snap = captured {
                                        preLoadDraftSnapshot = (snap, deck.name)
                                        // Auto-dismiss after 6s so the
                                        // banner doesn't linger forever
                                        // if the user navigates away.
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .seconds(6))
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                preLoadDraftSnapshot = nil
                                            }
                                        }
                                    } else {
                                        showAddedToDeckToast("Loaded “\(deck.name)” into Decks")
                                    }
                                } catch {
                                    // Silent failure — Snackbar would
                                    // overlay the green-checkmark toast.
                                    // Stay quiet; user can retry.
                                }
                            }
                        } label: {
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
                                // Trailing chevron — universal "tappable"
                                // affordance. Same shape as the row
                                // already had visually, just now actionable.
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Design.Colors.textMuted)
                            }
                            .padding(Design.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Design.Radius.sm)
                                    .fill(Design.Colors.bobaCyan.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                        .strokeBorder(Design.Colors.bobaCyan.opacity(0.25), lineWidth: 1))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Loads this deck into the Decks editor")
                    }
                }
            }
        }
    }

    /// "eBay Sales" + "View on Radish" row, mirrors the Find-tab card
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
            // Per Radish (2026-05-23): ordinary user-facing link only,
            // opens external browser. Uses the legacy catalog
            // `radishUrl` field when present; falls back to the
            // Radish homepage when null.
            Link(destination: card.radishDisplayURL) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text("View on Radish")
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

    // MARK: - Variations section

    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            sectionHeader("OTHER VERSIONS (\(variations.count))")
            ScrollView(.horizontal, showsIndicators: false) {
                // LazyHStack, not HStack — popular heroes have 100-150
                // variants, and a plain HStack instantiated every cell
                // eagerly, firing 150 simultaneous thumb downloads
                // through an 8-connection pool. Lazy loads only the
                // ~4 visible tiles.
                LazyHStack(spacing: Design.Spacing.md) {
                    // ID is .id (bobaId) not .cardNumber — multiple
                    // variants can share a cardNumber. Non-unique
                    // ForEach IDs corrupt SwiftUI identity tracking
                    // and broke the variations push (it bounced back
                    // to root). Un-owned variants use value-based
                    // NavigationLink so they route via the parent
                    // NavigationStack's path + navigationDestination
                    // (for: Card.self) handler — value-less
                    // .destination: mixes badly with path-driven
                    // NavigationStack.
                    ForEach(variations, id: \.id) { variant in
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
                            NavigationLink(value: variant) {
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
            // No overlays on the card art per DECISIONS.md #061 — the
            // only on-grid overlay allowed is Collection's price chip
            // (DESIGN.md §8.8). The treatment label below the tile +
            // ownership pip below it carry the disambiguation; the
            // art stays clean.
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
                    // Asking price — relevant for For Sale / For Trade.
                    HStack {
                        Text("Asking Price")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Spacer()
                        HStack(spacing: 2) {
                            Text("$")
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textMuted)
                            TextField("0.00", text: $askingPriceText)
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)

                // Condition + grading — added per beta feedback 2026-05-20.
                // These fields were already on UserCard / UpdateUserCard
                // but the sheet never rendered them; only the @State
                // vars existed. So users couldn't edit them anywhere.
                Section("CONDITION & GRADING") {
                    Picker("Condition", selection: $condition) {
                        Text("Unspecified").tag("")
                        ForEach(["Mint", "Near Mint", "Excellent", "Good", "Fair", "Poor"], id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .font(Design.Fonts.mono(14))
                    HStack {
                        Text("Grade")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Spacer()
                        TextField("e.g. 9.5", text: $grade)
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Grading Company", selection: $gradingCompany) {
                        Text("Ungraded").tag("")
                        ForEach(["PSA", "BGS", "SGC", "CGC", "Other"], id: \.self) { g in
                            Text(g).tag(g)
                        }
                    }
                    .font(Design.Fonts.mono(14))
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
            askingPrice: askingPriceText.isEmpty ? nil : Decimal(string: askingPriceText),
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
