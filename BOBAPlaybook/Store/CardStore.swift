import Foundation
import Observation

enum CardSortOrder: String, CaseIterable, Identifiable {
    case `default`   = "default"
    case nameAsc     = "name_asc"
    case nameDesc    = "name_desc"
    case powerDesc   = "power_desc"
    case powerAsc    = "power_asc"
    case numberAsc   = "number_asc"
    case numberDesc  = "number_desc"
    case variation   = "variation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default:   return "Default"
        case .nameAsc:   return "Name A → Z"
        case .nameDesc:  return "Name Z → A"
        case .powerDesc: return "Power: High → Low"
        case .powerAsc:  return "Power: Low → High"
        case .numberAsc: return "Card # Ascending"
        case .numberDesc: return "Card # Descending"
        case .variation: return "Variation"
        }
    }
}

@Observable
@MainActor
final class CardStore {

    // MARK: - Data
    private(set) var displayCards: [Card] = []
    private(set) var filteredCards: [Card] = []
    private(set) var isLoading = true           // false once head cards are ready
    private(set) var isLoadingMore = false      // true while full catalog loads in background
    private(set) var loadError: String?

    // MARK: - Filter options (populated after full load)
    private(set) var elements: [String] = []
    private(set) var sets: [String] = []
    private(set) var treatments: [String] = []

    // MARK: - Filter state
    var searchText = ""             { didSet { scheduleFilter() } }
    var selectedElements: Set<String> = [] { didSet { scheduleFilter() } }
    var selectedSet: String?        { didSet { scheduleFilter() } }
    var selectedTreatment: String?  { didSet { scheduleFilter() } }
    var powerMin: Int?              { didSet { scheduleFilter() } }
    var powerMax: Int?              { didSet { scheduleFilter() } }
    var hasImageOnly = false        { didSet { scheduleFilter() } }
    var sortOrder: CardSortOrder = .default { didSet { scheduleFilter() } }

    var activeFilterCount: Int {
        (selectedElements.isEmpty ? 0 : 1)
        + (selectedSet   == nil ? 0 : 1)
        + (selectedTreatment == nil ? 0 : 1)
        + ((powerMin != nil || powerMax != nil) ? 1 : 0)
        + (hasImageOnly ? 1 : 0)
        + (sortOrder != .default ? 1 : 0)
    }

    // MARK: - Image removal overrides
    // Card numbers whose images have been removed via the mod/admin panel.
    // Populated from card_image_overrides table on sign-in; updated immediately
    // when an admin submits a remove in ModCardEditSheet.
    private(set) var hiddenImageCardNumbers: Set<String> = []

    func isImageHidden(_ cardNumber: String) -> Bool {
        hiddenImageCardNumbers.contains(cardNumber)
    }

    /// Called from ModCardEditSheet immediately after a remove is submitted.
    func hideImage(cardNumber: String) {
        hiddenImageCardNumbers.insert(cardNumber)
    }

    /// Fetches all "remove" image overrides from Supabase and updates the hidden set.
    /// Safe to call with no auth — silently no-ops if unauthenticated or request fails.
    func loadImageRemovals() async {
        guard let removals = try? await SupabaseClient.shared.fetchImageRemovals() else { return }
        hiddenImageCardNumbers = Set(removals)
    }

    // MARK: - Deep link
    // Set by the URL handler when a bobaplaybook://card/{number} URL opens the app.
    // SearchView watches this and presents the card once displayCards is populated.
    var pendingCardNumber: String? = nil

    // MARK: - Internal
    private var filterTask: Task<Void, Never>?

    // MARK: - Init
    // Phase 1 runs synchronously here — before SwiftUI's first render pass.
    // 192 KB / 500 cards decodes in < 30 ms on device.
    init() {
        if let url   = Bundle.main.url(forResource: "cards-head", withExtension: "json"),
           let data  = try? Data(contentsOf: url),
           let cards = try? JSONDecoder().decode([Card].self, from: data) {
            displayCards  = cards
            isLoading     = false
            isLoadingMore = true
            applyFilters()   // honours the isLoadingMore sealed-product guard
        }
        // Phase 2: full catalog off main thread
        Task { await loadFullCatalog() }
    }

    // MARK: - Full catalog load (background)
    private func loadFullCatalog() async {
        guard let jsonURL = Bundle.main.url(forResource: "display-cards", withExtension: "json") else {
            if displayCards.isEmpty {
                loadError = "display-cards.json not found in bundle."
                isLoading = false
            }
            isLoadingMore = false
            return
        }

        do {
            let cards: [Card] = try await Task.detached(priority: .background) {
                let data = try Data(contentsOf: jsonURL)
                return try JSONDecoder().decode([Card].self, from: data)
            }.value

            let elementList = Array(Set(cards.map { $0.element }).filter { !$0.isEmpty && $0 != "NONE" }).sorted()
            let setList     = Array(Set(cards.map { $0.set     }).filter { !$0.isEmpty }).sorted()
            let treatList   = Array(Set(cards.compactMap { $0.treatment }).filter { !$0.isEmpty }).sorted()

            displayCards  = cards
            elements      = elementList
            sets          = setList
            treatments    = treatList
            isLoading     = false
            isLoadingMore = false
            applyFilters()

        } catch {
            isLoadingMore = false
            if displayCards.isEmpty {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Filtering
    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            self.applyFilters()
        }
    }

    private func applyFilters() {
        let search    = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let elements  = selectedElements
        let set       = selectedSet
        let treatment = selectedTreatment
        let pMin      = powerMin
        let pMax      = powerMax
        let imgOnly   = hasImageOnly

        filteredCards = displayCards.filter { card in
            if isLoadingMore && card.isSealed           { return false }
            if imgOnly && !card.imageAvailable          { return false }
            if !elements.isEmpty && !elements.contains(card.element) { return false }
            if let s = set,       !s.isEmpty, card.set      != s     { return false }
            if let t = treatment, !t.isEmpty, card.treatment != t    { return false }
            if let min = pMin, let p = card.power, p < min           { return false }
            if let max = pMax, let p = card.power, p > max           { return false }
            if !search.isEmpty {
                let match = card.name.lowercased().contains(search)
                    || card.cardNumber.lowercased().contains(search)
                    || card.hero.lowercased().contains(search)
                    || (card.athleteInspiration?.lowercased().contains(search) == true)
                    || card.element.lowercased().contains(search)
                    || (card.treatment?.lowercased().contains(search) == true)
                    || card.set.lowercased().contains(search)
                if !match { return false }
            }
            return true
        }.sorted { a, b in
            // Sealed products always follow regular cards in the grid.
            if a.isSealed != b.isSealed { return !a.isSealed }
            // Cards with images always before image-pending, regardless of sort.
            let aImg = a.imageFile != nil && !a.imageFile!.isEmpty
            let bImg = b.imageFile != nil && !b.imageFile!.isEmpty
            if aImg != bImg { return aImg }
            switch sortOrder {
            case .nameAsc:
                return a.hero.localizedCompare(b.hero) == .orderedAscending
            case .nameDesc:
                return a.hero.localizedCompare(b.hero) == .orderedDescending
            case .powerDesc:
                let pa = a.power ?? 0, pb = b.power ?? 0
                return pa != pb ? pa > pb : a.hero.localizedCompare(b.hero) == .orderedAscending
            case .powerAsc:
                let pa = a.power ?? 0, pb = b.power ?? 0
                return pa != pb ? pa < pb : a.hero.localizedCompare(b.hero) == .orderedAscending
            case .numberAsc:
                return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
            case .numberDesc:
                return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedDescending
            case .variation:
                let va = a.variation ?? "", vb = b.variation ?? ""
                return va != vb ? va.localizedCompare(vb) == .orderedAscending
                                : a.hero.localizedCompare(b.hero) == .orderedAscending
            default:
                // Default: card number ascending.
                return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
            }
        }
    }

    // MARK: - Clear
    func clearAllFilters() {
        searchText        = ""
        selectedElements  = []
        selectedSet       = nil
        selectedTreatment = nil
        powerMin          = nil
        powerMax          = nil
        hasImageOnly      = false
        sortOrder         = .default
    }
}
