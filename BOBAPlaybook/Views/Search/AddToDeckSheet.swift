import SwiftUI

// MARK: - AddToDeckSheet
// Lightweight deck picker presented from a card's "Add → To Custom Deck" action.
// Mirrors the top of the DeckBuilder "Load" tab (saved decks + new-deck button)
// but never opens the full builder — adding drops the card and dismisses.

struct AddToDeckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CardStore.self) private var cardStore

    let card: Card
    /// Called after the card is successfully added. Parent shows a toast.
    var onAdded: (String) -> Void

    @State private var decks: [SavedDeck] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var busyDeckId: UUID?
    @State private var isCreatingNew = false
    @State private var errorMessage: String?
    /// Tick 177 — bobaIds in each saved deck so the row can show an
    /// "Already in deck" hint (Android parity, tick 174). Lazy-loaded
    /// in parallel after the deck list lands so the sheet isn't slow
    /// to first-paint.
    @State private var deckBobaIds: [UUID: Set<String>] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {

                    // Saved Custom Decks list
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        Text("SAVED CUSTOM DECKS")
                            .font(Design.Fonts.mono(11, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .padding(.horizontal, Design.Spacing.lg)

                        if isLoading {
                            ProgressView("Loading saved decks…")
                                .tint(Design.Colors.bobaCyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Design.Spacing.xl)
                        } else if let err = loadError {
                            Text(err)
                                .font(Design.Fonts.mono(12))
                                .foregroundStyle(Design.Colors.textMuted)
                                .padding(.horizontal, Design.Spacing.lg)
                        } else if decks.isEmpty {
                            Text("No saved decks yet")
                                .font(Design.Fonts.mono(12))
                                .foregroundStyle(Design.Colors.textMuted)
                                .padding(.horizontal, Design.Spacing.lg)
                                .padding(.vertical, Design.Spacing.md)
                        } else {
                            VStack(spacing: Design.Spacing.xs) {
                                ForEach(decks) { deck in
                                    deckRow(deck)
                                }
                            }
                            .padding(.horizontal, Design.Spacing.sm)
                        }
                    }

                    // Start New Custom Deck — primary action
                    Button {
                        Task { await createNewDeck() }
                    } label: {
                        HStack {
                            if isCreatingNew {
                                ProgressView().tint(Design.Colors.nearBlack)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Design.Colors.nearBlack)
                            }
                            Text("Start New Custom Deck")
                                .font(Design.Fonts.mono(14, weight: .bold))
                                .foregroundStyle(Design.Colors.nearBlack)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaOrange))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreatingNew || busyDeckId != nil)
                    .padding(.horizontal, Design.Spacing.lg)

                    if let err = errorMessage {
                        Text(err)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.vertical, Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Add to Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                ToolbarItem(placement: .principal) {
                    Text("Add \(card.name)")
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await fetchDecks() }
    }

    // MARK: - Row

    private func deckRow(_ deck: SavedDeck) -> some View {
        let alreadyIn = deckBobaIds[deck.id]?.contains(card.bobaId) == true
        return Button {
            Task { await add(to: deck) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Design.Spacing.xs) {
                        Text(deck.name)
                            .font(Design.Fonts.display(16))
                            .foregroundStyle(Design.Colors.textPrimary)
                        if alreadyIn {
                            Text("· Already in deck")
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                    }
                    Text(deck.format.uppercased())
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                Spacer()
                if busyDeckId == deck.id {
                    ProgressView().tint(Design.Colors.bobaCyan)
                } else if alreadyIn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Design.Colors.bobaCyan)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .padding(.vertical, Design.Spacing.sm)
            .padding(.horizontal, Design.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.md)
                            .stroke(alreadyIn ? Design.Colors.bobaCyan.opacity(0.4) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(busyDeckId != nil || isCreatingNew)
    }

    // MARK: - Network

    private func fetchDecks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            decks = try await SupabaseClient.shared.fetchDecks()
        } catch {
            loadError = "Couldn't load decks"
            return
        }
        // Tick 177 — prefetch each deck's bobaIds in parallel so the
        // "Already in deck" hint renders without blocking the row list.
        // Typical user has 3–10 saved decks; N+1 is fine at this scale.
        // Failures per-deck are silent — the hint just doesn't show
        // for that row.
        await withTaskGroup(of: (UUID, Set<String>?).self) { group in
            for deck in decks {
                group.addTask {
                    let rows = try? await SupabaseClient.shared.fetchDeckCards(deckId: deck.id)
                    return (deck.id, rows.map { Set($0.map(\.bobaId)) })
                }
            }
            for await (id, ids) in group {
                if let ids { deckBobaIds[id] = ids }
            }
        }
    }

    /// Pull a deck's cards, add the new one, and save. Reuses the builder's
    /// `replaceDeckCards` path via `SupabaseClient.saveDeck(store:)` so deck
    /// rules / sort_order stay consistent with the full builder.
    private func add(to deck: SavedDeck) async {
        busyDeckId = deck.id
        errorMessage = nil
        defer { busyDeckId = nil }
        do {
            let rows = try await SupabaseClient.shared.fetchDeckCards(deckId: deck.id)
            let byId = Dictionary(uniqueKeysWithValues: cardStore.displayCards.map { ($0.id, $0) })

            let tempStore = DeckBuilderStore()
            tempStore.deckName = deck.name
            tempStore.currentDeckId = deck.id
            if let f = DeckFormat.allCases.first(where: { $0.supabaseValue == deck.format }) {
                tempStore.format = f
            }
            for row in rows {
                guard let c = byId[row.bobaId] else { continue }
                let role: DeckCardRole = switch row.cardType {
                    case "hero":       .hero
                    case "play":       .play
                    case "bonus_play": .bonusPlay
                    case "hot_dog":    .hotDog
                    case "sideboard":  .sideboard
                    default:           .hero
                }
                tempStore.addCard(c, role: role)
            }
            tempStore.addCard(card, role: roleForCard())
            try await SupabaseClient.shared.saveDeck(tempStore)
            onAdded(deck.name)
            dismiss()
        } catch {
            errorMessage = "Couldn't add to \(deck.name)"
        }
    }

    private func createNewDeck() async {
        isCreatingNew = true
        errorMessage = nil
        defer { isCreatingNew = false }
        do {
            let tempStore = DeckBuilderStore()
            tempStore.deckName = "New Deck"
            tempStore.addCard(card, role: roleForCard())
            try await SupabaseClient.shared.saveDeck(tempStore)
            onAdded(tempStore.deckName)
            dismiss()
        } catch {
            errorMessage = "Couldn't create deck"
        }
    }

    private func roleForCard() -> DeckCardRole {
        if card.isHero { return .hero }
        if card.isHotDog { return .hotDog }
        return .play  // addCard routes bonus plays correctly
    }
}
