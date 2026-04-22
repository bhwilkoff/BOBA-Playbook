import Foundation

// MARK: - CollectionStore
// Manages the user's card collection state.
// Syncs with Supabase on load; all mutations go to Supabase first, then update local state.

@Observable
@MainActor
final class CollectionStore {

    private(set) var userCards: [UserCard] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let client = SupabaseClient.shared

    // MARK: - Load

    func loadCollection() async {
        guard client.isAuthenticated else { return }
        isLoading = true
        error = nil
        do {
            userCards = try await client.fetchUserCards()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func clearCollection() {
        userCards = []
    }

    // MARK: - Add

    func addCard(_ new: NewUserCard) async throws {
        let created = try await client.addUserCard(new)
        userCards.insert(created, at: 0)
    }

    // MARK: - Update

    func updateDesignation(id: UUID, designation: UserCard.Designation) async throws {
        let updated = try await client.updateUserCard(id: id, fields: UpdateUserCard(designation: designation))
        apply(updated)
    }

    func updateCard(id: UUID, fields: UpdateUserCard) async throws {
        let updated = try await client.updateUserCard(id: id, fields: fields)
        apply(updated)
    }

    // MARK: - Delete

    func deleteCard(id: UUID) async throws {
        try await client.deleteUserCard(id: id)
        userCards.removeAll { $0.id == id }
    }

    // MARK: - Derived queries

    /// All entries for a given card number, sorted by designation then acquired date.
    /// Used internally for pricing (which is per card number, not per treatment).
    func entries(for cardNumber: String) -> [UserCard] {
        userCards
            .filter { $0.cardNumber == cardNumber }
            .sorted {
                if $0.designation == $1.designation {
                    return $0.acquiredAt > $1.acquiredAt
                }
                return $0.designation.rawValue < $1.designation.rawValue
            }
    }

    /// All entries for a given bobaId (exact card + treatment combo), sorted by designation then acquired date.
    /// Falls back to cardNumber matching for legacy entries that have no bobaId stored.
    func entries(forBobaId identifier: String) -> [UserCard] {
        userCards
            .filter { $0.bobaId == identifier || ($0.bobaId == nil && $0.cardNumber == identifier) }
            .sorted {
                if $0.designation == $1.designation {
                    return $0.acquiredAt > $1.acquiredAt
                }
                return $0.designation.rawValue < $1.designation.rawValue
            }
    }

    /// Whether the user owns at least one copy of this card number (any owned designation).
    func isOwned(_ cardNumber: String) -> Bool {
        userCards.contains { $0.cardNumber == cardNumber && $0.designation.isOwned }
    }

    /// Whether the user owns at least one copy of this exact card (bobaId match).
    /// Falls back to cardNumber matching for legacy entries without a bobaId.
    func isOwned(bobaId identifier: String) -> Bool {
        userCards.contains {
            ($0.bobaId == identifier || ($0.bobaId == nil && $0.cardNumber == identifier))
            && $0.designation.isOwned
        }
    }

    /// Whether the card number is on any wishlist (wanted or grails).
    func isWanted(_ cardNumber: String) -> Bool {
        userCards.contains { $0.cardNumber == cardNumber && !$0.designation.isOwned }
    }

    /// Whether the exact card (bobaId) is on any wishlist.
    /// Falls back to cardNumber matching for legacy entries without a bobaId.
    func isWanted(bobaId identifier: String) -> Bool {
        userCards.contains {
            ($0.bobaId == identifier || ($0.bobaId == nil && $0.cardNumber == identifier))
            && !$0.designation.isOwned
        }
    }

    /// Unique card numbers grouped by designation (for collection list views).
    func uniqueCardNumbers(for designation: UserCard.Designation) -> [String] {
        Array(Set(
            userCards
                .filter { $0.designation == designation }
                .map { $0.cardNumber }
        )).sorted()
    }

    /// Unique card identifiers (bobaId when available, cardNumber for legacy entries)
    /// grouped by designation. Each distinct card + treatment combo appears as its own row.
    func uniqueBobaIds(for designation: UserCard.Designation) -> [String] {
        Array(Set(
            userCards
                .filter { $0.designation == designation }
                .map { $0.bobaId ?? $0.cardNumber }
        )).sorted()
    }

    /// Total purchase value for all owned cards (designation.isOwned == true).
    var totalPurchaseValue: Decimal {
        userCards
            .filter { $0.designation.isOwned }
            .compactMap { $0.purchasePrice }
            .reduce(0, +)
    }

    /// Sum of estimated_value for all owned entries. Each copy counts separately,
    /// so owning 3 copies of a $10 card contributes $30.
    var totalEstimatedValue: Decimal {
        userCards
            .filter { $0.designation.isOwned }
            .compactMap { $0.estimatedValue }
            .reduce(0, +)
    }

    /// How many owned card numbers have an estimated_value recorded.
    var valuedCardCount: Int {
        userCards.filter { $0.designation.isOwned && $0.estimatedValue != nil }.count
    }

    // MARK: - Pricing refresh

    /// Updates estimated_value + last_price_check for every entry of `cardNumber`
    /// only when the price data is stale (nil or older than 24 hours).
    func refreshPricingIfNeeded(for cardNumber: String, card: Card) async {
        guard needsPriceRefresh(cardNumber) else { return }
        await fetchAndStorePricing(for: cardNumber, card: card)
    }

    /// Force-refreshes estimated_value for every owned unique card number.
    /// Calls `progress(current, total)` after each card so the UI can show progress.
    func recalculateAllValues(cardStore: CardStore, progress: @escaping @MainActor (Int, Int) -> Void) async {
        let ownedNumbers = Array(Set(
            userCards.filter { $0.designation.isOwned }.map { $0.cardNumber }
        ))
        let total = ownedNumbers.count
        for (index, cardNumber) in ownedNumbers.enumerated() {
            await MainActor.run { progress(index + 1, total) }
            guard let card = cardStore.displayCards.first(where: { $0.cardNumber == cardNumber }) else { continue }
            await fetchAndStorePricing(for: cardNumber, card: card)
            // Light throttle so we don't flood the worker
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        await MainActor.run { progress(total, total) }
    }

    // MARK: - Private

    private func needsPriceRefresh(_ cardNumber: String) -> Bool {
        let latest = entries(for: cardNumber).compactMap { $0.lastPriceCheck }.max()
        guard let latest else { return true }
        return Date().timeIntervalSince(latest) > 86400  // 24 hours
    }

    private func fetchAndStorePricing(for cardNumber: String, card: Card) async {
        guard !WorkerConfig.ebayProxyURL.isEmpty else { return }
        do {
            let pricing = try await PricingService.shared.pricing(
                for: card.cardNumber,
                hero: card.hero,
                set: card.set,
                element: card.element,
                power: card.power,
                radishUrl: card.radishUrl,
                days: 30
            )
            let fields = UpdateUserCard(
                estimatedValue: pricing.average,
                lastPriceCheck: Date()
            )
            // Only stamp estimated_value on entries the user owns. Wanted
            // / grails cards aren't in the collection yet — showing them
            // a market value is fine at the card-detail level, but we
            // don't want to persist per-entry pricing on wishlist rows
            // that could later feel like they count toward collection
            // value. The aggregates already filter by isOwned; this keeps
            // the stored data consistent with the intent.
            for entry in entries(for: cardNumber) where entry.designation.isOwned {
                try await updateCard(id: entry.id, fields: fields)
            }
        } catch {
            // Silent — stale or missing price is acceptable
        }
    }

    private func apply(_ updated: UserCard) {
        if let idx = userCards.firstIndex(where: { $0.id == updated.id }) {
            userCards[idx] = updated
        }
    }
}
