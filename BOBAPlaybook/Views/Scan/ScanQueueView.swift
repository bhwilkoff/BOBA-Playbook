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
        .task(id: scanStore.queuedCards.map(\.card.id).joined()) {
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

            // Show-mode price (30d avg) lives at the trailing edge.
            if scanStore.isShowMode {
                Text(formatCurrency(showPrices[queued.card.id] ?? 0))
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .frame(minWidth: 56, alignment: .trailing)
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
                Label("All cards saved to Collection", systemImage: "checkmark.circle.fill")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(.green)
            }

            Button {
                if scanStore.isShowMode {
                    // Hand off to the add-to-show sheet; it handles both
                    // add-to-existing and create-new flows.
                    showAddToShow = true
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
        return scanStore.isShowMode ? "Save all to Show" : "Save All to Collection"
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

    // MARK: - Save all (Collection path)

    private func saveAllToCollection() async {
        isSavingAll = true
        saveError   = nil
        var firstError: String?

        for queued in scanStore.queuedCards {
            let entry = NewUserCard(
                cardNumber: queued.card.cardNumber,
                bobaId: queued.card.id,
                designation: .personal
            )
            do { try await collectionStore.addCard(entry) }
            catch { if firstError == nil { firstError = error.localizedDescription } }
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

    /// Parallel 30-day average fetch for every queued card — mirrors
    /// ShowDetailView.refreshPrices. Default horizon is 30 days per the
    /// feature brief.
    private func refreshShowPrices() async {
        let cards = scanStore.queuedCards.map(\.card)
        guard !cards.isEmpty else { showPrices = [:]; return }
        isLoadingShowPrices = true
        defer { isLoadingShowPrices = false }
        await withTaskGroup(of: (String, Decimal).self) { group in
            for c in cards {
                // Pre-extract Sendable scalars so the @Sendable
                // group.addTask closure doesn't capture `c` (which
                // SwiftUI views push through a MainActor-isolated
                // capture and trip Swift 6 strict concurrency on).
                let id        = c.id
                let cardNum   = c.cardNumber
                let hero      = c.hero
                let set       = c.set
                let element   = c.element
                let power     = c.power
                let radishUrl = c.resolvedRadishUrlString
                let treatment = c.treatment
                group.addTask {
                    do {
                        let p = try await PricingService.shared.pricing(
                            for: cardNum, hero: hero, set: set, element: element,
                            power: power, radishUrl: radishUrl,
                            days: 30, treatment: treatment
                        )
                        return (id, p.average)
                    } catch { return (id, Decimal(0)) }
                }
            }
            var next: [String: Decimal] = [:]
            for await (id, avg) in group { next[id] = avg }
            showPrices = next
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
