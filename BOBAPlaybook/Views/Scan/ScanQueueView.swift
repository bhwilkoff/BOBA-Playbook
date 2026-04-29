import SwiftUI

struct ScanQueueView: View {
    @Environment(ScanStore.self)       private var scanStore
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(AuthManager.self)     private var auth
    @Environment(\.dismiss)           private var dismiss

    @State private var selectedCard: Card?
    @State private var isSavingAll    = false
    @State private var saveError:     String?
    @State private var saveSuccess    = false
    /// Show-mode only: per-card 30-day average prices. Fetched in parallel
    /// when the queue changes. Empty dict outside show mode.
    @State private var showPrices:   [String: Decimal] = [:]
    @State private var isLoadingShowPrices = false
    @State private var showAddToShow = false

    var body: some View {
        NavigationStack {
            Group {
                if scanStore.queuedCards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle(scanStore.isShowMode ? "Show Queue" : "Scan Queue")
            // Inline title — large-title transitions inside a sheet
            // presented over the full-screen camera surface flash an
            // empty material header on first frame.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .background(Design.Colors.nearBlack)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
        .sheet(isPresented: $showAddToShow) {
            AddToShowSheet(
                cards: scanStore.queuedCards.map(\.card),
                title: "Save \(scanStore.queuedCards.count) card\(scanStore.queuedCards.count == 1 ? "" : "s") to Show"
            ) { showName in
                // Successful add — clear the queue + surface the result.
                scanStore.clearQueue()
                saveSuccess = true
                saveError = "Saved to \(showName)"   // repurpose the slot for a green-ish line
            }
        }
        // The id concatenates the queued card list AND the global
        // pricing pulse — so prices refresh both when the queue
        // changes (new card scanned) AND when any other surface
        // invalidates the pricing cache (Collection toolbar refresh,
        // Show detail "Refresh Prices" button, individual card
        // forceRefresh). PricingPulse keeps the scanner in sync
        // without each surface needing its own coordination logic.
        .task(id: "\(scanStore.queuedCards.map(\.card.id).joined())|\(PricingPulse.shared.version)") {
            if scanStore.isShowMode { await refreshShowPrices() }
        }
        .onChange(of: scanStore.mode) { _, newValue in
            if newValue == .show { Task { await refreshShowPrices() } }
        }
    }

    // MARK: - Card list

    private var cardList: some View {
        // Switched from List to ScrollView+LazyVStack so each row is a
        // discrete rounded card with explicit horizontal padding +
        // gaps between rows. List was rendering edge-to-edge rectangles
        // with no separation, and the show-summary section couldn't
        // span the full safe-area width because of the list-row chrome.
        ScrollView {
            LazyVStack(spacing: Design.Spacing.sm) {
                if scanStore.isShowMode {
                    showModeSummary
                }
                if scanStore.source == .deckBuilder {
                    deckBuilderRouting
                }
                ForEach(scanStore.queuedCards) { queued in
                    queueRow(queued)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.lg)
        }
        .background(Design.Colors.nearBlack)
        .safeAreaInset(edge: .bottom) {
            if auth.isAuthenticated {
                saveAllButton
                    .padding(Design.Spacing.lg)
                    .background(.regularMaterial)
            }
        }
    }

    private func queueRow(_ queued: ScanStore.QueuedCard) -> some View {
        HStack(spacing: Design.Spacing.md) {
            // Tap thumb / name opens card detail.
            Button { selectedCard = queued.card } label: {
                HStack(spacing: Design.Spacing.md) {
                    CardImageView(card: queued.card, size: .thumb)
                        .frame(width: 44, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(queued.card.name)
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(1)
                        Text(queued.card.cardNumber)
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.bobaOrange)
                        if let power = queued.card.power, power > 0 {
                            Text("PWR \(power)  ·  \(queued.card.element)")
                                .font(Design.Fonts.mono(10))
                                .foregroundStyle(Design.Colors.element(queued.card.element))
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Quantity stepper — beta-tester ask. Tap −/+ to set how
            // many physical copies of this card the user owns.
            // Defaults to 1; auto-bumps when the same card is
            // re-scanned. Hidden in show-mode (single-stream prep
            // workflow doesn't need quantity tallying).
            if !scanStore.isShowMode {
                quantityStepper(for: queued)
            }

            // Show-mode price (30d avg) lives at the trailing edge.
            // Render "—" for cards we couldn't fetch a price for —
            // distinguishes "no data yet" from a literal $0.00 card.
            if scanStore.isShowMode {
                if let p = showPrices[queued.card.id] {
                    Text(formatCurrency(p))
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .frame(minWidth: 56, alignment: .trailing)
                } else {
                    Text("—")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textMuted)
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }

            // Quick-delete shortcut — per feature brief: the queue
            // "should have a quick delete feature."
            Button {
                if let idx = scanStore.queuedCards.firstIndex(where: { $0.id == queued.id }) {
                    scanStore.removeFromQueue(at: IndexSet(integer: idx))
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "C0392B").opacity(0.8))
                    .padding(8)
            }
            .buttonStyle(.plain)
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

    /// −/+ quantity stepper for a queued card. Compact pill design that
    /// fits inside the queue row trailing edge.
    private func quantityStepper(for queued: ScanStore.QueuedCard) -> some View {
        HStack(spacing: 4) {
            Button {
                scanStore.setQuantity(id: queued.id, quantity: queued.quantity - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(queued.quantity <= 1
                                     ? Design.Colors.textMuted
                                     : Design.Colors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(queued.quantity <= 1)

            Text("\(queued.quantity)")
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .frame(minWidth: 22, alignment: .center)
                .monospacedDigit()

            Button {
                scanStore.setQuantity(id: queued.id, quantity: queued.quantity + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(queued.quantity >= 99
                                     ? Design.Colors.textMuted
                                     : Design.Colors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(queued.quantity >= 99)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quantity \(queued.quantity)")
    }

    // MARK: - Deck-builder routing
    //
    // Replaces the show-mode header when the scanner was launched from
    // the deck builder. Surfaces:
    //   • the in-progress deck (always selected, can't be unticked —
    //     it's the implicit destination of the scan session)
    //   • each saved deck the coach has, with a multi-select toggle
    //   • a single checkbox to mirror everything to the Collection
    @ViewBuilder
    private var deckBuilderRouting: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("ADD TO")
                .font(Design.Fonts.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Design.Colors.textMuted)

            // In-progress deck — always selected, dimmed lock icon.
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Design.Colors.bobaOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scanStore.currentDeckLabel.isEmpty
                         ? "Current deck"
                         : scanStore.currentDeckLabel)
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("In progress · always added")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                Spacer()
            }
            .padding(Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.bobaOrange.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
            )

            // Saved-deck multi-select rows.
            ForEach(scanStore.availableSavedDecks) { deck in
                let selected = scanStore.selectedDeckIds.contains(deck.id)
                Button {
                    if selected {
                        scanStore.selectedDeckIds.remove(deck.id)
                    } else {
                        scanStore.selectedDeckIds.insert(deck.id)
                    }
                } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Design.Colors.bobaCyan : Design.Colors.textMuted)
                        Text(deck.name)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(selected ? Design.Colors.bobaCyan.opacity(0.10) : Design.Colors.glass)
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(selected ? Design.Colors.bobaCyan.opacity(0.4) : Design.Colors.glassBorder, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }

            // Mirror-to-Collection toggle.
            Toggle(isOn: Binding(
                get: { scanStore.alsoSaveToCollection },
                set: { scanStore.alsoSaveToCollection = $0 }
            )) {
                Text("Also add to Collection")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .toggleStyle(SwitchToggleStyle(tint: Design.Colors.bobaOrange))
            .padding(.top, 2)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
        )
    }

    /// Header block shown above the card rows in Show Mode. Same rounded-
    /// card styling as the row pills below so the whole list reads as a
    /// stack of consistent surfaces. The total spans the full LazyVStack
    /// width — the previous version was wrapped in a List Section that
    /// inset it inside the row chrome.
    private var showModeSummary: some View {
        let total = scanStore.queuedCards.reduce(Decimal(0)) { acc, q in
            acc + (showPrices[q.card.id] ?? 0)
        }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SHOW TOTAL · 30D AVG")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text(formatCurrency(total))
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
            Spacer()
            if isLoadingShowPrices {
                ProgressView().tint(Design.Colors.bobaCyan).scaleEffect(0.9)
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Save all

    private var saveAllButton: some View {
        VStack(spacing: Design.Spacing.sm) {
            if let error = saveError {
                Text(error)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(saveSuccess ? .green : .red)
            }
            if saveSuccess && saveError == nil {
                Label(scanStore.source == .deckBuilder
                      ? "Added to deck\(scanStore.selectedDeckIds.isEmpty ? "" : "s")"
                      : "All cards saved to Collection",
                      systemImage: "checkmark.circle.fill")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(.green)
            }

            Button {
                if scanStore.isShowMode {
                    // Hand off to the add-to-show sheet; it handles both
                    // add-to-existing and create-new flows.
                    showAddToShow = true
                } else if scanStore.source == .deckBuilder {
                    Task { await saveAllToDeckBuilder() }
                } else {
                    Task { await saveAllToCollection() }
                }
            } label: {
                HStack {
                    if isSavingAll {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        // Broadcast icon for show mode — captures the
                        // "going live" framing better than a TV silhouette.
                        Image(systemName: scanStore.isShowMode ? "dot.radiowaves.up.forward" : "tray.and.arrow.down.fill")
                    }
                    Text(saveAllLabel)
                        .font(Design.Fonts.display(15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(scanStore.isShowMode ? Design.Colors.bobaCyan : Design.Colors.bobaOrange)
                )
                .foregroundStyle(scanStore.isShowMode ? Design.Colors.nearBlack : .white)
            }
            .disabled(isSavingAll || (saveSuccess && !scanStore.isShowMode))
        }
    }

    private var saveAllLabel: String {
        if isSavingAll { return "Saving…" }
        if scanStore.isShowMode { return "Save all to Show" }
        if scanStore.source == .deckBuilder {
            let extra = scanStore.selectedDeckIds.count
            let collectionTag = scanStore.alsoSaveToCollection ? " + Collection" : ""
            switch extra {
            case 0:  return "Add to deck\(collectionTag)"
            case 1:  return "Add to 2 decks\(collectionTag)"
            default: return "Add to \(extra + 1) decks\(collectionTag)"
            }
        }
        return "Save All to Collection"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: scanStore.isShowMode ? "tv" : "tray")
                .font(.system(size: 48))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Queue Empty")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(scanStore.isShowMode
                 ? "Point the scanner at cards to add them to this show."
                 : "Enable Multi mode on the scanner and detected cards will appear here.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !scanStore.queuedCards.isEmpty {
                Button("Clear All") {
                    withAnimation { scanStore.clearQueue() }
                }
                .foregroundStyle(Design.Colors.textMuted)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
                .foregroundStyle(Design.Colors.bobaOrange)
        }
    }

    // MARK: - Save all (Deck-builder path)
    //
    // Two-stage commit:
    //   1. Hand the queued cards to the presenter via `onSaveToActiveDeck`
    //      so they land in the in-progress deck's heroes/plays/etc.
    //      lists. Persistence happens when the coach next saves the deck.
    //   2. For each saved deck the coach multi-selected, append the
    //      cards via SupabaseClient.appendCardsToDeck (writes directly
    //      to deck_cards, no rewrite of the existing rows).
    //   3. Optional Collection mirror — if the toggle is on, run the
    //      same path Find-mode uses.
    private func saveAllToDeckBuilder() async {
        isSavingAll = true
        saveError = nil
        // Expand the queue's quantity field — N copies → N entries.
        let cards: [Card] = scanStore.queuedCards.flatMap { queued in
            Array(repeating: queued.card, count: max(1, queued.quantity))
        }
        var firstError: String?

        // 1. Hand the cards back to the deck-builder presenter via
        //    ScanStore.pendingScannedCardsForActiveDeck. DeckBuilderView
        //    observes this array and appends to its in-memory deck.
        scanStore.pendingScannedCardsForActiveDeck = cards

        // 2. Append to each saved deck the user picked.
        for deckId in scanStore.selectedDeckIds {
            do {
                try await SupabaseClient.shared.appendCardsToDeck(
                    deckId: deckId, cards: cards
                )
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        // 3. Optional Collection mirror.
        if scanStore.alsoSaveToCollection {
            for card in cards {
                let entry = NewUserCard(
                    cardNumber: card.cardNumber,
                    bobaId: card.id,
                    designation: .personal
                )
                do { try await collectionStore.addCard(entry) }
                catch { if firstError == nil { firstError = error.localizedDescription } }
            }
        }

        isSavingAll = false
        if let err = firstError {
            saveError = err
        } else {
            saveSuccess = true
            scanStore.clearQueue()
        }
    }

    // MARK: - Save all (Collection path)

    private func saveAllToCollection() async {
        isSavingAll = true
        saveError   = nil
        var firstError: String?

        for queued in scanStore.queuedCards {
            // Save `quantity` distinct user_card rows for this scan.
            // Each represents one physical copy the user owns.
            for _ in 0..<max(1, queued.quantity) {
                let entry = NewUserCard(
                    cardNumber: queued.card.cardNumber,
                    bobaId: queued.card.id,
                    designation: .personal
                )
                do { try await collectionStore.addCard(entry) }
                catch { if firstError == nil { firstError = error.localizedDescription } }
            }
        }

        isSavingAll = false
        if let err = firstError {
            saveError = err
        } else {
            saveSuccess = true
            scanStore.clearQueue()
        }
    }

    // MARK: - Show-mode price fetch

    /// Sequential 30-day average fetch for every queued card —
    /// mirrors `ShowDetailView.refreshPrices`. Was a parallel
    /// `TaskGroup` with one fetch per card, which on shows with
    /// 14+ cards exceeded URLSession's default 4-connections-per-host
    /// limit. The queued requests then often hit the 7s timeout,
    /// returned `noData`, and the UI rendered $0 — even when the
    /// Worker was returning real data. Sequential fetches each get
    /// a clean connection and a fresh 7s budget; total time is
    /// ~14 × 0.5s ≈ 7s for a typical show, fast enough to ride
    /// through any pull-to-refresh window.
    ///
    /// Failed cards are intentionally left absent from
    /// `showPrices` — the UI renders "—" for nil entries (instead
    /// of the misleading "$0.00") and the next refresh re-attempts
    /// every absent card.
    private func refreshShowPrices() async {
        let cards = scanStore.queuedCards.map(\.card)
        guard !cards.isEmpty else { showPrices = [:]; return }
        isLoadingShowPrices = true
        defer { isLoadingShowPrices = false }
        var next: [String: Decimal] = [:]
        for c in cards {
            do {
                let p = try await PricingService.shared.pricing(
                    for: c.cardNumber,
                    hero: c.hero,
                    set: c.set,
                    element: c.element,
                    power: c.power,
                    radishUrl: c.resolvedRadishUrlString,
                    days: 30,
                    treatment: c.treatment
                )
                next[c.id] = p.average
                // Commit incrementally so the running total ticks
                // up as prices arrive instead of dropping in all
                // at once at the end.
                showPrices = next
            } catch {
                // Leave card absent from showPrices — UI shows "—".
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
