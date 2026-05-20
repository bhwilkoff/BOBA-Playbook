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

    // MARK: - Export
    //
    // Renders the whole collection as a CSV. Columns are a superset of
    // the deck-importer format (`Slot,Card#,Name,Cost,Ability,DBS`) so
    // the file round-trips through DeckBuilderStore.importDeckCSV — the
    // Slot column is left blank per row, which the importer treats as a
    // Play slot. Collection-specific columns follow afterward for human
    // use: CardType, Element, Power, Hero, Treatment, Set, Designation,
    // PurchasePrice, AcquiredAt, Notes, BobaId.
    //
    // Set-prefix mapping mirrors DeckBuilderStore.setPrefixMap. Keeping
    // the two in lockstep avoids a round-trip mismatch where an exported
    // play can't find its set on re-import.
    private static let exportSetPrefixMap: [String: String] = [
        "Alpha Edition":   "A",
        "Alpha Update":    "U",
        "Griffey Edition": "G",
    ]

    /// Exports user-card rows as CSV. Pass `restrictTo` to scope the
    /// export to a subset of bobaIds — used by the Collection view to
    /// honor the active filter (element / set / treatment / etc.). Nil
    /// → export every userCard. Empty set → export none. Match is by
    /// bobaId where present (the canonical key); cards persisted on
    /// older app versions without a bobaId fall through to cardNumber
    /// matching against the catalog.
    func exportCSV(cardStore: CardStore,
                   restrictTo: Set<String>? = nil) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let money = NumberFormatter()
        money.minimumFractionDigits = 2
        money.maximumFractionDigits = 2

        var rows: [String] = [
            "Slot,Card#,Name,Cost,Ability,DBS,CardType,Element,Power,Hero,Treatment,Set,Designation,PurchasePrice,AcquiredAt,Notes,BobaId"
        ]

        // Build the source slice: full collection or filter-restricted.
        // Filter resolution: prefer bobaId; if a userCard has no
        // bobaId (legacy rows), look up its cardNumber in the catalog
        // and check whether any catalog row at that number is in the
        // allowed set.
        let source: [UserCard]
        if let allowed = restrictTo {
            // Pre-build cardNumber → allowed-bobaIds index for legacy
            // (bobaId-less) rows so we don't re-scan displayCards once
            // per userCard. One pass over the catalog, O(allowed) lookup.
            var byCardNumber: [String: Set<String>] = [:]
            for card in cardStore.displayCards where allowed.contains(card.id) {
                byCardNumber[card.cardNumber, default: []].insert(card.id)
            }
            source = userCards.filter { uc in
                if let bid = uc.bobaId, !bid.isEmpty {
                    return allowed.contains(bid)
                }
                return (byCardNumber[uc.cardNumber] ?? []).isEmpty == false
            }
        } else {
            source = userCards
        }

        // Sort: owned first, then by card number for stable diffs.
        let sorted = source.sorted { a, b in
            if a.designation.isOwned != b.designation.isOwned { return a.designation.isOwned }
            return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
        }

        for uc in sorted {
            let catalog = uc.bobaId.flatMap { cardStore.cardsById[$0] }
                ?? cardStore.cardsByCardNumber[uc.cardNumber]

            let prefix = catalog.map { Self.exportSetPrefixMap[$0.set].map { "\($0) - " } ?? "" } ?? ""
            let cardNumCell = "\(prefix)\(uc.cardNumber)"
            let name  = catalog?.name ?? ""
            let cost  = catalog?.playCost.map(String.init) ?? ""
            let abil  = catalog?.playAbility ?? ""
            let dbs   = catalog?.dbs.map(String.init) ?? ""
            let ctype = catalog?.cardType ?? ""
            let elem  = catalog?.element ?? ""
            let pwr   = catalog?.power.map(String.init) ?? ""
            let hero  = catalog?.hero ?? ""
            let trt   = catalog?.treatment ?? ""
            let setNm = catalog?.set ?? ""
            let des   = uc.designation.rawValue
            let price = uc.purchasePrice.flatMap { money.string(from: $0 as NSDecimalNumber) } ?? ""
            let acq   = iso.string(from: uc.acquiredAt)
            let note  = uc.notes ?? ""
            let bid   = uc.bobaId ?? ""

            // Swift 6's type-checker times out on a single 17-element
            // array + map + join in one expression — build the row in
            // two steps so the inference stays tractable.
            var fields: [String] = []
            fields.append("") // Slot left blank — deck importer still
                              // routes these as plays; non-plays land
                              // in its unresolved list, which is the
                              // expected behavior for a mixed export.
            fields.append(cardNumCell)
            fields.append(name)
            fields.append(cost)
            fields.append(abil)
            fields.append(dbs)
            fields.append(ctype)
            fields.append(elem)
            fields.append(pwr)
            fields.append(hero)
            fields.append(trt)
            fields.append(setNm)
            fields.append(des)
            fields.append(price)
            fields.append(acq)
            fields.append(note)
            fields.append(bid)
            let escaped = fields.map { Self.csvEscape($0) }
            rows.append(escaped.joined(separator: ","))
        }

        return rows.joined(separator: "\r\n")
    }

    private static func csvEscape(_ s: String) -> String {
        let needsQuotes = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        if !needsQuotes { return s }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
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

    /// Per DESIGN.md §8.4 / §8.8 — bobaId → summed estimated_value across
    /// all copies under the given designation. Used by the Collection
    /// Wall sheet's Price Overlay to render per-tile asking/value chips.
    func estimatedValuesByBobaId(forDesignation d: UserCard.Designation) -> [String: Decimal] {
        var out: [String: Decimal] = [:]
        for entry in userCards where entry.designation == d {
            guard let bobaId = entry.bobaId, let value = entry.estimatedValue else { continue }
            out[bobaId, default: 0] += value
        }
        return out
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
            // Force-refresh bypasses the in-memory PricingService
            // cache so an explicit user-triggered refresh actually
            // re-hits the Worker (and the Worker's edge cache) for
            // every owned card. Without this, "Refresh market values"
            // and pull-to-refresh would silently no-op for any card
            // viewed in the last hour.
            await fetchAndStorePricing(for: cardNumber, card: card, forceRefresh: true)
            // Light throttle so we don't flood the worker
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        await MainActor.run { progress(total, total) }
        // Notify every open PricingSection (card detail, show queue,
        // scanner) to re-fetch. The per-card forceRefresh calls
        // already bumped the pulse for owned cards; this final bump
        // makes sure any view that's keyed on the pulse picks up a
        // change even if it loaded BEFORE recalc started.
        await PricingService.shared.bumpAll()
    }

    // MARK: - Private

    private func needsPriceRefresh(_ cardNumber: String) -> Bool {
        let latest = entries(for: cardNumber).compactMap { $0.lastPriceCheck }.max()
        guard let latest else { return true }
        return Date().timeIntervalSince(latest) > 86400  // 24 hours
    }

    private func fetchAndStorePricing(for cardNumber: String, card: Card, forceRefresh: Bool = false) async {
        guard !WorkerConfig.ebayProxyURL.isEmpty else { return }
        do {
            let pricing = try await PricingService.shared.pricing(
                for: card.cardNumber,
                hero: card.hero,
                set: card.set,
                element: card.element,
                power: card.power,
                radishUrl: card.resolvedRadishUrlString,
                days: 30,
                treatment: card.treatment,
                forceRefresh: forceRefresh
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
