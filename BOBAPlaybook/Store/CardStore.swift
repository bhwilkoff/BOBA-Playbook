import Foundation
import Observation

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

    var activeFilterCount: Int {
        (selectedElements.isEmpty ? 0 : 1)
        + (selectedSet   == nil ? 0 : 1)
        + (selectedTreatment == nil ? 0 : 1)
        + ((powerMin != nil || powerMax != nil) ? 1 : 0)
        + (hasImageOnly ? 1 : 0)
    }

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
            filteredCards = cards
            isLoading     = false
            isLoadingMore = true
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
                if !match { return false }
            }
            return true
        }.sorted {
            let lImg = $0.imageFile != nil && !$0.imageFile!.isEmpty
            let rImg = $1.imageFile != nil && !$1.imageFile!.isEmpty
            return lImg && !rImg
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
    }
}
