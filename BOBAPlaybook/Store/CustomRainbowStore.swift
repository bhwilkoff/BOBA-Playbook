import Foundation

// MARK: - CustomRainbowStore
//
// Manages the user's custom rainbows. Syncs with Supabase on load;
// all mutations go through Supabase first, then update the local
// list so reads are fast and the rainbow UI doesn't re-fetch on
// every render.

@Observable
@MainActor
final class CustomRainbowStore {

    private(set) var rainbows: [CustomRainbow] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let client = SupabaseClient.shared

    // MARK: - Load

    func load() async {
        guard client.isAuthenticated else {
            rainbows = []
            return
        }
        isLoading = true
        error = nil
        do {
            rainbows = try await client.fetchCustomRainbows()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        rainbows = []
        error = nil
    }

    // MARK: - Mutations

    /// Inserts a new rainbow row in Supabase and prepends it to
    /// the local list (matches the created_at-desc order returned
    /// by load()).
    @discardableResult
    func create(name: String, criteria: RainbowCriteria) async throws -> CustomRainbow {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "CustomRainbowStore", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Name can't be empty."])
        }
        let rainbow = try await client.createCustomRainbow(name: trimmed, criteria: criteria)
        rainbows.insert(rainbow, at: 0)
        return rainbow
    }

    /// Patches the named row's name/criteria server-side and updates
    /// the matching local entry in place.
    func update(_ rainbow: CustomRainbow, name: String, criteria: RainbowCriteria) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "CustomRainbowStore", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Name can't be empty."])
        }
        try await client.updateCustomRainbow(id: rainbow.id, name: trimmed, criteria: criteria)
        if let idx = rainbows.firstIndex(where: { $0.id == rainbow.id }) {
            var updated = rainbows[idx]
            updated.name      = trimmed
            updated.criteria  = criteria
            updated.updatedAt = Date()
            rainbows[idx] = updated
        }
    }

    func delete(_ rainbow: CustomRainbow) async throws {
        try await client.deleteCustomRainbow(id: rainbow.id)
        rainbows.removeAll(where: { $0.id == rainbow.id })
    }

    // MARK: - Catalog projections

    /// Cards in the given catalog that match this rainbow's criteria.
    /// Used by the rainbow detail view + the progress bar to compute
    /// owned/total without re-implementing match logic in the views.
    func matchingCards(for rainbow: CustomRainbow, in catalog: [Card]) -> [Card] {
        catalog.filter { rainbow.criteria.matches($0) }
    }
}
