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

    /// Whether the user owns at least one copy of this card number (any owned designation).
    func isOwned(_ cardNumber: String) -> Bool {
        userCards.contains { $0.cardNumber == cardNumber && $0.designation.isOwned }
    }

    /// Whether the card number is on any wishlist (wanted or grails).
    func isWanted(_ cardNumber: String) -> Bool {
        userCards.contains { $0.cardNumber == cardNumber && !$0.designation.isOwned }
    }

    /// Unique card numbers grouped by designation (for collection list views).
    func uniqueCardNumbers(for designation: UserCard.Designation) -> [String] {
        Array(Set(
            userCards
                .filter { $0.designation == designation }
                .map { $0.cardNumber }
        )).sorted()
    }

    /// Total purchase value for all owned cards (designation.isOwned == true).
    var totalPurchaseValue: Decimal {
        userCards
            .filter { $0.designation.isOwned }
            .compactMap { $0.purchasePrice }
            .reduce(0, +)
    }

    // MARK: - Private

    private func apply(_ updated: UserCard) {
        if let idx = userCards.firstIndex(where: { $0.id == updated.id }) {
            userCards[idx] = updated
        }
    }
}
