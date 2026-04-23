import Foundation
import Observation

// MARK: - ShowsStore
//
// Holds a streamer's Show list + per-show card cache. The Collection
// tab's "My Shows" view reads from this store; the add-to-show flow
// (card detail, Show Mode scanner) writes through it.
//
// Role-gated at the UI layer — this store doesn't itself check role.

@Observable
@MainActor
final class ShowsStore {
    private(set) var shows: [Show] = []
    private(set) var cardsByShowId: [UUID: [ShowCard]] = [:]
    private(set) var isLoading = false
    private(set) var error: String?

    private let client = SupabaseClient.shared

    // MARK: - Shows

    func loadShows() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            shows = try await client.fetchShows()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Creates a new show, optionally seeded with an initial batch of
    /// bobaIds. Returns the fresh show so callers can navigate into it.
    @discardableResult
    func createShow(name: String, initialCardBobaIds: [String] = []) async throws -> Show {
        let show = try await client.createShow(name: name)
        if !initialCardBobaIds.isEmpty {
            try await client.addCardsToShow(showId: show.id, bobaIds: initialCardBobaIds)
        }
        // Refresh local state so the Shows list + card cache are consistent
        // without requiring a separate pull from the UI.
        await loadShows()
        if !initialCardBobaIds.isEmpty {
            _ = try? await loadCards(for: show.id)
        }
        return show
    }

    func rename(showId: UUID, to newName: String) async throws {
        try await client.renameShow(id: showId, name: newName)
        if let idx = shows.firstIndex(where: { $0.id == showId }) {
            // Patch the local copy so the UI updates without a round-trip.
            var updated = shows[idx]
            updated = Show(
                id: updated.id,
                name: newName,
                createdAt: updated.createdAt,
                updatedAt: Date()
            )
            shows[idx] = updated
        }
    }

    func delete(showId: UUID) async throws {
        try await client.deleteShow(id: showId)
        shows.removeAll { $0.id == showId }
        cardsByShowId[showId] = nil
    }

    // MARK: - Show cards

    @discardableResult
    func loadCards(for showId: UUID) async throws -> [ShowCard] {
        let rows = try await client.fetchShowCards(showId: showId)
        cardsByShowId[showId] = rows
        return rows
    }

    func addCards(showId: UUID, bobaIds: [String]) async throws {
        try await client.addCardsToShow(showId: showId, bobaIds: bobaIds)
        _ = try? await loadCards(for: showId)
    }

    func setExcluded(showId: UUID, cardId: UUID, excluded: Bool) async throws {
        try await client.setShowCardExcluded(id: cardId, excluded: excluded)
        if var rows = cardsByShowId[showId],
           let idx = rows.firstIndex(where: { $0.id == cardId }) {
            rows[idx].excludedFromTotal = excluded
            cardsByShowId[showId] = rows
        }
    }

    func removeCard(showId: UUID, cardId: UUID) async throws {
        try await client.deleteShowCard(id: cardId)
        if var rows = cardsByShowId[showId] {
            rows.removeAll { $0.id == cardId }
            cardsByShowId[showId] = rows
        }
    }
}
