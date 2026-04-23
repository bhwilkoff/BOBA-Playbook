import SwiftUI
import UIKit

// MARK: - ShowDetailView
//
// The main prep surface for a streamer's Whatnot show. Lists every
// card in the show with:
//   • its market value at the selected horizon (7d…9mo)
//   • a check-to-exclude toggle (excluded cards drop out of the total)
//   • a one-tap delete
//   • tap-to-open → full CardDetailView
//
// "Generate Wall" composes all the card thumbnails into one image the
// streamer can drop into Whatnot chat, Discord, or the share sheet.

struct ShowDetailView: View {
    let show: Show

    @Environment(\.dismiss) private var dismiss
    @Environment(ShowsStore.self) private var shows
    @Environment(CardStore.self) private var cardStore

    @State private var horizon: ShowHorizon = .d30
    /// Market-price cache keyed by (bobaId, horizon.days). Primed as a
    /// parallel batch fetch whenever horizon or card list changes.
    @State private var prices: [String: Decimal] = [:]
    @State private var priceKey: String = ""
    @State private var isLoadingPrices = false
    @State private var selectedCardForDetail: Card?
    @State private var showWall = false
    @State private var wallImage: UIImage? = nil
    @State private var isGeneratingWall = false
    @State private var showRenameSheet = false
    @State private var renameText: String = ""
    @State private var actionError: String? = nil

    // MARK: - Derived

    private var showCards: [ShowCard] { shows.cardsByShowId[show.id] ?? [] }

    /// Look each ShowCard.bobaId up against the live catalog. Skips
    /// orphans (card was renamed or isn't in display-cards.json yet).
    private var resolved: [(row: ShowCard, card: Card)] {
        let byId = Dictionary(uniqueKeysWithValues: cardStore.displayCards.map { ($0.id, $0) })
        let byNumber = Dictionary(
            cardStore.displayCards.map { ($0.cardNumber, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        return showCards.compactMap { row in
            if let c = byId[row.bobaId] { return (row, c) }
            // Legacy fallback: rows inserted before bobaId was canonical
            // might have a plain cardNumber.
            if let c = byNumber[row.bobaId] { return (row, c) }
            return nil
        }
    }

    private var includedTotal: Decimal {
        resolved.reduce(Decimal(0)) { acc, pair in
            if pair.row.excludedFromTotal { return acc }
            return acc + (prices[pair.card.id] ?? 0)
        }
    }
    private var excludedTotal: Decimal {
        resolved.reduce(Decimal(0)) { acc, pair in
            if !pair.row.excludedFromTotal { return acc }
            return acc + (prices[pair.card.id] ?? 0)
        }
    }
    private var includedCount: Int { resolved.filter { !$0.row.excludedFromTotal }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                headerSummary
                horizonPicker
                if isLoadingPrices {
                    HStack { Spacer(); ProgressView().tint(Design.Colors.bobaOrange); Spacer() }
                        .padding(.vertical, Design.Spacing.md)
                }
                cardRows
                generateWallButton
            }
            .padding(Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xl)
        }
        .background(Design.Colors.nearBlack)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
            ToolbarItem(placement: .principal) {
                Text(show.name)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = show.name
                        showRenameSheet = true
                    } label: { Label("Rename show", systemImage: "pencil") }
                    Button {
                        Task { await refreshPrices(force: true) }
                    } label: { Label("Refresh prices", systemImage: "arrow.clockwise") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
            }
        }
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            _ = try? await shows.loadCards(for: show.id)
            await refreshPrices(force: false)
        }
        .onChange(of: horizon) { _, _ in
            Task { await refreshPrices(force: false) }
        }
        .onChange(of: showCards.map(\.bobaId).joined()) { _, _ in
            Task { await refreshPrices(force: false) }
        }
        .sheet(item: $selectedCardForDetail) { card in
            CardDetailView(card: card)
        }
        .fullScreenCover(isPresented: $showWall) {
            wallViewer
        }
        .sheet(isPresented: $showRenameSheet) { renameSheet }
        .alert("Couldn't finish that", isPresented: .init(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) { Button("OK") { actionError = nil } } message: { Text(actionError ?? "") }
    }

    // MARK: - Header + Horizon

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatCurrency(includedTotal))
                    .font(Design.Fonts.arena(32))
                    .foregroundStyle(Design.Colors.bobaOrange)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("INCLUDED")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted).tracking(1.5)
                    Text("\(includedCount) of \(resolved.count) cards")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            if excludedTotal > 0 {
                HStack {
                    Text("EXCLUDED")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted).tracking(1.5)
                    Text(formatCurrency(excludedTotal))
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface))
    }

    private var horizonPicker: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("PRICE HORIZON")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted).tracking(1.5)
            Picker("Horizon", selection: $horizon) {
                ForEach(ShowHorizon.allCases) { h in
                    Text(h.shortLabel).tag(h)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardRows: some View {
        if resolved.isEmpty {
            VStack(spacing: Design.Spacing.sm) {
                Image(systemName: "tv.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(Design.Colors.textMuted)
                Text("No cards in this show yet")
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textMuted)
                Text("Scan cards with Show Mode or tap \"To Show\" on a card.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Design.Spacing.xxl)
        } else {
            LazyVStack(spacing: 6) {
                ForEach(resolved, id: \.row.id) { pair in
                    cardRow(row: pair.row, card: pair.card)
                }
            }
        }
    }

    private func cardRow(row: ShowCard, card: Card) -> some View {
        let excluded = row.excludedFromTotal
        return HStack(spacing: Design.Spacing.md) {
            // Exclusion toggle — primary new interaction this view adds.
            Button {
                Task { await toggleExclude(row: row) }
            } label: {
                Image(systemName: excluded ? "square" : "checkmark.square.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(excluded ? Design.Colors.textMuted : Design.Colors.bobaCyan)
            }
            .buttonStyle(.plain)

            CardImageView(card: card, size: .thumb)
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                .onTapGesture { selectedCardForDetail = card }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(excluded ? Design.Colors.textMuted : Design.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(card.cardNumber)
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                    if let t = card.treatment, !t.isEmpty {
                        Text("· \(t)")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let price = prices[card.id] {
                Text(formatCurrency(price))
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(excluded ? Design.Colors.textMuted : Design.Colors.bobaOrange)
            } else {
                Text("—")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textMuted)
            }

            Button {
                Task { await removeCard(row: row) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "C0392B").opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Design.Radius.sm)
            .fill(excluded ? Design.Colors.surface2.opacity(0.5) : Design.Colors.surface))
    }

    // MARK: - Wall

    private var generateWallButton: some View {
        Button {
            Task { await generateWall() }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                if isGeneratingWall {
                    ProgressView().tint(Design.Colors.nearBlack)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                Text(isGeneratingWall ? "Composing…" : "Generate Wall")
                    .font(Design.Fonts.mono(14, weight: .bold))
            }
            .foregroundStyle(Design.Colors.nearBlack)
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaCyan))
        }
        .buttonStyle(.plain)
        .disabled(isGeneratingWall || resolved.isEmpty)
        .padding(.top, Design.Spacing.sm)
    }

    @ViewBuilder
    private var wallViewer: some View {
        if let img = wallImage {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { showWall = false }
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview("\(show.name) — \(resolved.count) cards",
                                                        image: Image(uiImage: img))) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rename

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Show name", text: $renameText)
                        .font(Design.Fonts.mono(14))
                }
                .listRowBackground(Design.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Rename Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !newName.isEmpty else { return }
                        Task {
                            do { try await shows.rename(showId: show.id, to: newName); showRenameSheet = false }
                            catch { actionError = error.localizedDescription }
                        }
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.height(200)])
    }

    // MARK: - Actions

    private func toggleExclude(row: ShowCard) async {
        do {
            try await shows.setExcluded(showId: show.id, cardId: row.id, excluded: !row.excludedFromTotal)
        } catch { actionError = error.localizedDescription }
    }

    private func removeCard(row: ShowCard) async {
        do { try await shows.removeCard(showId: show.id, cardId: row.id) }
        catch { actionError = error.localizedDescription }
    }

    /// Fetch market averages for every card in the show at the current
    /// horizon, in parallel. Cache by (bobaId, days) so switching between
    /// horizons the user already viewed doesn't re-fetch.
    private func refreshPrices(force: Bool) async {
        let cards = resolved.map { $0.card }
        guard !cards.isEmpty else { return }
        let key = "\(horizon.days):\(cards.map(\.id).joined(separator: ","))"
        if !force && key == priceKey && !prices.isEmpty { return }
        priceKey = key
        isLoadingPrices = true
        defer { isLoadingPrices = false }

        await withTaskGroup(of: (String, Decimal).self) { group in
            for c in cards {
                group.addTask {
                    do {
                        let p = try await PricingService.shared.pricing(
                            for: c.cardNumber,
                            hero: c.hero,
                            set: c.set,
                            element: c.element,
                            power: c.power,
                            radishUrl: c.resolvedRadishUrlString,
                            days: horizon.days,
                            treatment: c.treatment
                        )
                        return (c.id, p.average)
                    } catch {
                        return (c.id, Decimal(0))
                    }
                }
            }
            var next: [String: Decimal] = [:]
            for await (id, avg) in group { next[id] = avg }
            prices = next
        }
    }

    @MainActor
    private func generateWall() async {
        isGeneratingWall = true
        defer { isGeneratingWall = false }
        let cards = resolved.map { $0.card }
        guard !cards.isEmpty else { return }
        wallImage = await ShowWallComposer.compose(cards: cards, title: show.name)
        if wallImage != nil { showWall = true }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
