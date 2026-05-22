import Foundation
import Observation
import SwiftUI

/// Sub-tab on the Find tab that scopes results by card purpose. The
/// Discord corpus (§8) shows players think of Plays / Hot Dogs / Sealed
/// as distinct categories, not as "cards mixed in with heroes."
enum CardPurpose: String, CaseIterable, Identifiable {
    case all      = "All"
    case heroes   = "Heroes"
    case plays    = "Plays"
    case hotDogs  = "Hot Dogs"
    case sealed   = "Sealed"
    var id: String { rawValue }
}

enum CardSortOrder: String, CaseIterable, Identifiable {
    case `default`       = "default"
    case recentlyAdded   = "recently_added"
    case nameAsc         = "name_asc"
    case nameDesc        = "name_desc"
    case powerDesc       = "power_desc"
    case powerAsc        = "power_asc"
    case numberAsc       = "number_asc"
    case numberDesc      = "number_desc"
    case costAsc         = "cost_asc"
    case costDesc        = "cost_desc"
    case variation       = "variation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default:        return "Default"
        case .recentlyAdded:  return "Recently Added"
        case .nameAsc:        return "Name A → Z"
        case .nameDesc:       return "Name Z → A"
        case .powerDesc:      return "Power: High → Low"
        case .powerAsc:       return "Power: Low → High"
        case .numberAsc:      return "Card # Ascending"
        case .numberDesc:     return "Card # Descending"
        case .costAsc:        return "Hot Dog Cost: Low → High"
        case .costDesc:       return "Hot Dog Cost: High → Low"
        case .variation:      return "Variation"
        }
    }
}

/// Lightweight Hashable route for the Find tab's NavigationStack.
/// Stored in `CardStore.findNavigationPath` so URL handlers (Universal
/// Links, custom-scheme) can append a route directly without going
/// through an observation chain. Resolver view renders from a route
/// — handles the catalog-not-loaded case by re-evaluating when
/// displayCards updates (Observable tracking).
///
/// bobaId is set when a Card object is in hand (in-app cell tap);
/// nil for URL deep-links where only cardNumber+treatment+hero are
/// known until the catalog resolves.
struct CardRoute: Hashable, Codable {
    let bobaId: String?
    let cardNumber: String
    let treatment: String?
    let hero: String?

    init(bobaId: String? = nil, cardNumber: String, treatment: String? = nil, hero: String? = nil) {
        self.bobaId = bobaId
        self.cardNumber = cardNumber
        self.treatment = treatment
        self.hero = hero
    }

    init(card: Card) {
        self.init(bobaId: card.id,
                  cardNumber: card.cardNumber,
                  treatment: card.treatment,
                  hero: card.hero)
    }
}

@Observable
@MainActor
final class CardStore {

    /// Navigation path for the Find tab. Owned here (not in SearchView's
    /// @State) so URL handlers can append routes directly. SearchView
    /// binds NavigationStack(path:) to this, eliminating the cold-launch
    /// race where pendingCardNumber-style observation could miss a
    /// value set before the view mounted.
    ///
    /// Type-erased (`NavigationPath`) rather than `[CardRoute]` so the
    /// stack accepts mixed value types: URL deep links push `CardRoute`,
    /// in-app pushes (e.g. `CardDetailView`'s "Other Versions" cells)
    /// push `Card`. A strictly-typed path silently rejects any value
    /// whose type doesn't match its element type — that was the cause
    /// of the variant-tap regression after the Universal Links refactor.
    var findNavigationPath = NavigationPath()

    // MARK: - Data
    private(set) var displayCards: [Card] = [] {
        didSet { rebuildIdIndexes() }
    }
    private(set) var filteredCards: [Card] = []

    /// O(1) lookup by `Card.id` (== bobaId). Built each time
    /// `displayCards` is reassigned or mutated through `applyImageOverrides`
    /// / `applyImageRemovals`. Used by hot paths that previously did
    /// `displayCards.first { $0.id == id }` per item — that's a linear
    /// scan of ~17k cards which became catastrophic when called per
    /// keystroke from Collection search (500 owned cards × 17k catalog
    /// scan × per-keystroke recompute = ~8.5M comparisons / character).
    private(set) var cardsById: [String: Card] = [:]
    /// Secondary lookup keyed by cardNumber. Some legacy collection
    /// rows store cardNumber where bobaId would now go; this index
    /// preserves the fallback the old code did via a second `.first { $0.cardNumber == id }`.
    private(set) var cardsByCardNumber: [String: Card] = [:]

    /// Tick 352 — catalog-order index by bobaId. Used by the
    /// `.recentlyAdded` sort (catalog order is chronological — new sets
    /// append). O(1) lookup vs O(n) `displayCards.firstIndex(of:)`.
    private(set) var catalogOrderById: [String: Int] = [:]

    /// Rebuild the two id → Card lookup tables. O(n) over displayCards;
    /// runs only on data-load or image-override application, NOT per
    /// keystroke.
    func rebuildIdIndexes() {
        var byId: [String: Card] = [:]
        var byNum: [String: Card] = [:]
        var orderById: [String: Int] = [:]
        byId.reserveCapacity(displayCards.count)
        byNum.reserveCapacity(displayCards.count)
        orderById.reserveCapacity(displayCards.count)
        for (i, c) in displayCards.enumerated() {
            byId[c.id] = c
            if byNum[c.cardNumber] == nil { byNum[c.cardNumber] = c }
            orderById[c.id] = i
        }
        cardsById = byId
        cardsByCardNumber = byNum
        catalogOrderById = orderById
    }

    /// Resolve a Card by either bobaId or cardNumber. O(1) — replaces
    /// the old `displayCards.first { $0.id == id } ?? displayCards.first
    /// { $0.cardNumber == id }` pattern at every hot call site.
    func resolveCard(byId id: String) -> Card? {
        cardsById[id] ?? cardsByCardNumber[id]
    }
    private(set) var isLoading = true           // false once head cards are ready
    private(set) var isLoadingMore = false      // true while full catalog loads in background
    private(set) var loadError: String?

    // MARK: - Filter options (populated after full load)
    private(set) var elements: [String] = []
    private(set) var sets: [String] = []
    private(set) var treatments: [String] = []
    private(set) var releases: [String] = []

    // MARK: - Filter state
    var searchText = ""             { didSet { scheduleFilter() } }
    var selectedElements: Set<String> = [] { didSet { scheduleFilter() } }
    var selectedSet: String?        { didSet { scheduleFilter() } }
    var selectedTreatment: String?  { didSet { scheduleFilter() } }
    var selectedRelease: String?    { didSet { scheduleFilter() } }
    var powerMin: Int?              { didSet { scheduleFilter() } }
    var powerMax: Int?              { didSet { scheduleFilter() } }
    var hasImageOnly = false        { didSet { scheduleFilter() } }
    var sortOrder: CardSortOrder = .default { didSet { scheduleFilter() } }
    var cardPurpose: CardPurpose = .all { didSet { scheduleFilter() } }
    /// Optional curated-list filter. Lives alongside the other filter
    /// dimensions so a showcase can combine with element / power / etc.
    /// Nil when no showcase is selected (the typical case).
    var selectedShowcaseId: String?     { didSet { scheduleFilter() } }

    var activeFilterCount: Int {
        (selectedElements.isEmpty ? 0 : 1)
        + (selectedSet   == nil ? 0 : 1)
        + (selectedTreatment == nil ? 0 : 1)
        + (selectedRelease == nil ? 0 : 1)
        + ((powerMin != nil || powerMax != nil) ? 1 : 0)
        + (hasImageOnly ? 1 : 0)
        + (sortOrder != .default ? 1 : 0)
        + (cardPurpose != .all ? 1 : 0)
        + (selectedShowcaseId == nil ? 0 : 1)
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

    // MARK: - Applied image-replacement overrides
    // Companion to the removal set above. Once the boba-mod-merge Worker
    // has processed an approved card_image_overrides row (downloaded
    // from Supabase Storage → wrote to R2 → purged CF cache), it sets
    // applied_image_file on the row. iOS reads those on sign-in and
    // resolves card_number / boba_id → filename here, so the runtime
    // image URL reflects the new file even before cards.json's
    // imageFile is updated by the next pipeline-cron + git deploy.
    // Key precedence:
    //   appliedImageFile[bobaId]      (most specific — set on every new submission)
    //   appliedImageFile[cardNumber]  (legacy rows without boba_id)
    //   card.imageFile from cards.json
    private(set) var appliedImageOverridesByBobaId:     [String: String] = [:]
    private(set) var appliedImageOverridesByCardNumber: [String: String] = [:]

    /// Resolves the active image filename for a card, applying any
    /// runtime override on top of cards.json's imageFile.
    func resolvedImageFile(for card: Card) -> String? {
        if let f = appliedImageOverridesByBobaId[card.id] { return f }
        if let f = appliedImageOverridesByCardNumber[card.cardNumber] { return f }
        return card.imageFile
    }

    /// Convenience builders matching CDN.thumbURL / fullURL that bake
    /// the runtime override resolution in.
    func thumbURL(for card: Card) -> URL? {
        CDN.thumbURL(for: card, override: resolvedImageFile(for: card))
    }
    func fullURL(for card: Card) -> URL? {
        CDN.fullURL(for: card, override: resolvedImageFile(for: card))
    }

    /// Called by SupabaseClient.applyImageOverride right after the merge
    /// Worker returns, OR by loadImageRemovals' sibling fetch on launch.
    /// Updates the runtime map AND the in-memory displayCards array so
    /// every callsite (CDN.fullURL/thumbURL(for: card), CardImageView,
    /// the various Play/Decks views reading card.imageFile directly)
    /// picks up the new filename without needing to consult a separate
    /// resolver.
    /// v2.280 — also rebuilds filteredCards via applyFilters(). Without
    /// this, the SearchView grid (which renders from filteredCards, a
    /// derived array) stayed stale even though displayCards was mutated.
    func setAppliedOverride(cardNumber: String, bobaId: String?, imageFile: String) {
        if let id = bobaId, !id.isEmpty {
            appliedImageOverridesByBobaId[id] = imageFile
        }
        appliedImageOverridesByCardNumber[cardNumber] = imageFile
        for i in displayCards.indices {
            let c = displayCards[i]
            if (bobaId.map { !$0.isEmpty && c.id == $0 } ?? false)
                || c.cardNumber == cardNumber {
                displayCards[i].imageFile = imageFile
            }
        }
        applyFilters()
    }

    /// Fetches all applied overrides from Supabase and replaces the
    /// runtime maps. Safe to call without auth.
    func loadAppliedImageOverrides() async {
        guard let rows = try? await SupabaseClient.shared.fetchAppliedImageOverrides() else { return }
        var byBoba: [String: String] = [:]
        var byCN:   [String: String] = [:]
        for row in rows {
            if let bid = row.bobaId, !bid.isEmpty { byBoba[bid] = row.appliedImageFile }
            byCN[row.cardNumber] = row.appliedImageFile
        }
        appliedImageOverridesByBobaId     = byBoba
        appliedImageOverridesByCardNumber = byCN
        // v2.278 — mirror the web pattern: mutate displayCards
        // imageFile in-memory so every existing call site
        // (CDN.fullURL(for: card), CardImageView, the 25+ Play views
        // that read card.imageFile directly) picks up the override
        // without having to thread an explicit override parameter
        // through. Card.imageFile is `var` for exactly this purpose.
        applyRuntimeImageOverrides()
    }

    /// Re-applies the runtime override map to displayCards. Called
    /// after loadAppliedImageOverrides AND from loadFullCatalog so a
    /// fresh catalog load doesn't wipe the override mutations.
    /// v2.280 — also rebuilds filteredCards via applyFilters(). The
    /// SearchView grid renders from filteredCards (derived), not
    /// displayCards directly, so mutating the source isn't visible
    /// to the UI without rebuilding the derivative.
    func applyRuntimeImageOverrides() {
        guard !appliedImageOverridesByBobaId.isEmpty
                || !appliedImageOverridesByCardNumber.isEmpty
        else { return }
        for i in displayCards.indices {
            let card = displayCards[i]
            // bobaId is the canonical primary key; cardNumber is a
            // fallback for legacy rows that didn't include boba_id.
            // For Sealed Products Card.id (uses hero) != Card.bobaId
            // (falls back to name), so prefer card.bobaId here.
            if let f = appliedImageOverridesByBobaId[card.bobaId] {
                displayCards[i].imageFile = f
            } else if let f = appliedImageOverridesByCardNumber[card.cardNumber] {
                displayCards[i].imageFile = f
            }
        }
        applyFilters()
    }

    // MARK: - Deep link
    // Card-detail deep links go through findNavigationPath (above)
    // — the URL handler appends a CardRoute directly. The previous
    // pendingCardNumber/Treatment/Hero observation chain was removed
    // because it was racy on cold-launch (URL set values before
    // SearchView observed them) and unnecessary once the path lives
    // here for the URL handler to mutate.

    /// Set by the URL handler when a bobaplaybook://scan URL opens the app
    /// (the QR code on the web version uses this to jump straight to scanning).
    /// SearchView watches this and presents the ScanView sheet.
    var pendingScan: Bool = false

    /// Set by the URL handler when a bobaplaybook://search?q=... URL opens
    /// the app — typically from SearchCardIntent (Spotlight / Siri /
    /// Action Button per DESIGN.md §7). SearchView observes this and
    /// pre-populates the search field on tab activation.
    var pendingSearchQuery: String? = nil

    /// Set by the URL handler when a bobaplaybook://learn/{category} URL
    /// opens the app — DESIGN.md §7.2 stable section IDs (rules, strategy,
    /// collect, glossary, tournament). LearnView observes this and pushes
    /// the corresponding category sub-view on tab activation.
    var pendingLearnCategory: String? = nil

    /// Set when a deep link includes ?action=addToCollection (raised by
    /// AddToCollectionIntent — DESIGN.md §7). CardDetailView observes
    /// this on first appearance and auto-presents the AddToCollection
    /// sheet. Cleared once consumed.
    var pendingCardAction: String? = nil

    // MARK: - Internal
    private var filterTask: Task<Void, Never>?

    // MARK: - Community aliases (DISCORD_TERMINOLOGY.md §2, §3)
    // Flat lookup: lowercase alias → array of canonical lowercase strings
    // that should also be matched when the user's search text equals the
    // alias. Built once at init from the two bundled JSON files; read-only
    // after that.
    private var aliasIndex: [String: [String]] = [:]

    // MARK: - Init
    // Phase 1 runs synchronously here — before SwiftUI's first render pass.
    // 192 KB / 500 cards decodes in < 30 ms on device.
    init() {
        aliasIndex = Self.loadAliasIndex()
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

    /// Parse the two alias JSON files into a flat lowercase lookup.
    /// Silent fallback to empty if either file is missing — aliases only
    /// expand the search; they don't gate it.
    private static func loadAliasIndex() -> [String: [String]] {
        struct AliasFile: Decodable {
            let aliases: [String: [String]]?
            let element_aliases: [String: [String]]?
        }
        var result: [String: [String]] = [:]
        let files = ["hero_aliases", "treatment_aliases"]
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(AliasFile.self, from: data) else { continue }
            // Hero / treatment aliases: canonical name → [slang]. Invert
            // to slang → [canonical] so a search-term lookup is O(1).
            for (canonical, slangs) in (file.aliases ?? [:]) {
                for slang in slangs {
                    result[slang.lowercased(), default: []].append(canonical.lowercased())
                }
            }
            // Element aliases (grillen → FIRE, chillen → ICE, etc.) live
            // in the same dict — canonical is already UPPERCASE, matched
            // against card.element below.
            for (canonical, slangs) in (file.element_aliases ?? [:]) {
                for slang in slangs {
                    result[slang.lowercased(), default: []].append(canonical.lowercased())
                }
            }
        }
        return result
    }

    /// Returns the search term plus any canonical strings it aliases to.
    /// All lowercase. Callers match each expansion against card fields
    /// independently (OR match).
    func expandedSearchTerms(_ term: String) -> [String] {
        let lower = term.lowercased()
        if let expansions = aliasIndex[lower] {
            return [lower] + expansions
        }
        return [lower]
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
            let releaseList = Array(Set(cards.map { $0.release }).filter { !$0.isEmpty }).sorted()

            displayCards  = cards
            elements      = elementList
            sets          = setList
            treatments    = treatList
            releases      = releaseList
            isLoading     = false
            isLoadingMore = false
            // v2.280 — re-apply the runtime override map BEFORE
            // building filteredCards. Without this, a fresh catalog
            // load wipes any in-place imageFile mutations the
            // override map had previously written. (Race confirmed
            // by the v2.279 audit — full-catalog load can finish
            // after loadAppliedImageOverrides.)
            applyRuntimeImageOverrides()
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
        let release   = selectedRelease
        let pMin      = powerMin
        let pMax      = powerMax
        let imgOnly   = hasImageOnly

        let purpose = cardPurpose
        // Pre-resolve whichever showcase is active from both the picker
        // AND the search bar (e.g. typing "WOBA" activates the WOBA
        // showcase without the filter sheet). The search path takes
        // precedence on a given keystroke.
        let pickedShowcase:   Showcase? = selectedShowcaseId.flatMap { Showcases.byId($0) }
        let typedShowcase:    Showcase? = search.isEmpty ? nil : Showcases.matching(searchToken: search)
        let activeShowcase:   Showcase? = typedShowcase ?? pickedShowcase

        // Search tokens the user's bar text resolves to. "fire" → FIRE
        // element; "bojax" → BoJax + alias expansion; "battlefoil" →
        // treatment; "woba" → already handled by activeShowcase above
        // so we strip it from the text-match path.
        let isShowcaseSearch = typedShowcase != nil
        let searchTerms: [String] = isShowcaseSearch ? [] : expandedSearchTerms(search)

        filteredCards = displayCards.filter { card in
            if isLoadingMore && card.isSealed           { return false }
            switch purpose {
            case .all:     break
            case .heroes:  if !card.isHero    { return false }
            case .plays:   if !card.isPlay    { return false }
            case .hotDogs: if !card.isHotDog  { return false }
            case .sealed:  if !card.isSealed  { return false }
            }
            if let showcase = activeShowcase, !showcase.match(card) { return false }
            if imgOnly && !card.imageAvailable          { return false }
            if !elements.isEmpty && !elements.contains(card.element) { return false }
            if let s = set,       !s.isEmpty, card.set      != s     { return false }
            if let t = treatment, !t.isEmpty, card.treatment != t    { return false }
            if let r = release,   !r.isEmpty, card.release   != r    { return false }
            if let min = pMin, let p = card.power, p < min           { return false }
            if let max = pMax, let p = card.power, p > max           { return false }
            if !search.isEmpty && !isShowcaseSearch {
                // Smart match. Build the list of lowercased haystack
                // strings once per card, then check each search term
                // against it. Previously we OR'd ~10 optional-chained
                // expressions in a single return; Swift 6's type-checker
                // couldn't close that inference in reasonable time.
                let match = searchTerms.contains { term in
                    cardMatchesSearchTerm(card, term: term)
                }
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
            case .recentlyAdded:
                // Reverse catalog order — newer sets append, so higher
                // index = newer card. Tick 352 (iOS port of web tick 283).
                let ia = catalogOrderById[a.id] ?? 0
                let ib = catalogOrderById[b.id] ?? 0
                return ia != ib ? ia > ib
                                : a.hero.localizedCompare(b.hero) == .orderedAscending
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
            case .costAsc:
                // Cards without a Hot Dog cost (Heroes/HotDogs/Sealed)
                // sort after Plays so the cost-ordered run stays contiguous.
                let aHas = a.playCost != nil, bHas = b.playCost != nil
                if aHas != bHas { return aHas }
                let ca = a.playCost ?? 0, cb = b.playCost ?? 0
                return ca != cb ? ca < cb : a.hero.localizedCompare(b.hero) == .orderedAscending
            case .costDesc:
                let aHas = a.playCost != nil, bHas = b.playCost != nil
                if aHas != bHas { return aHas }
                let ca = a.playCost ?? 0, cb = b.playCost ?? 0
                return ca != cb ? ca > cb : a.hero.localizedCompare(b.hero) == .orderedAscending
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
        searchText         = ""
        selectedElements   = []
        selectedSet        = nil
        selectedTreatment  = nil
        selectedRelease    = nil
        powerMin           = nil
        powerMax           = nil
        hasImageOnly       = false
        sortOrder          = .default
        cardPurpose        = .all
        selectedShowcaseId = nil
    }

    /// Word-prefix match: the query and every searchable field are split
    /// into words, and the card matches when every query word is a
    /// prefix of at least one card word. Mirrors how humans search —
    /// "griff" finds Griffey, "amon" finds Amon-Ra, but "amon" does NOT
    /// find Johnny **D**amon (mid-word substring). Matches the web's
    /// pre-built `searchTokens` behavior so iOS + web stay aligned.
    private nonisolated func cardMatchesSearchTerm(_ card: Card, term: String) -> Bool {
        let queryWords = wordSplit(term)
        if queryWords.isEmpty { return true }
        let haystack = haystackWords(for: card)
        return queryWords.allSatisfy { q in
            haystack.contains { $0.hasPrefix(q) }
        }
    }

    private nonisolated func wordSplit(_ s: String) -> [String] {
        CardSearch.wordSplit(s)
    }

    private nonisolated func haystackWords(for card: Card) -> [String] {
        CardSearch.haystackWords(for: card)
    }
}

/// Shared word-prefix search helpers. Used by `CardStore`'s Find filter
/// AND by Collection / Deck pool searches so every card-search surface
/// behaves the same: "amon" finds Amon-Ra but NOT Johnny Damon.
/// `nonisolated` because the project default isolation is MainActor
/// and callers run from background filter tasks.
nonisolated enum CardSearch {
    static func wordSplit(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func haystackWords(for card: Card) -> [String] {
        var w: [String] = []
        w.append(contentsOf: wordSplit(card.name))
        w.append(contentsOf: wordSplit(card.cardNumber))
        w.append(contentsOf: wordSplit(card.hero))
        w.append(contentsOf: wordSplit(card.element))
        w.append(contentsOf: wordSplit(card.set))
        if let a = card.athleteInspiration { w.append(contentsOf: wordSplit(a)) }
        if let t = card.treatment          { w.append(contentsOf: wordSplit(t)) }
        if let s = card.subSet             { w.append(contentsOf: wordSplit(s)) }
        if let v = card.variation          { w.append(contentsOf: wordSplit(v)) }
        return w
    }

    /// True when every word in `query` is a prefix of at least one word
    /// in `haystack`. Empty query matches everything.
    static func matches(query: String, in haystack: [String]) -> Bool {
        let qWords = wordSplit(query)
        if qWords.isEmpty { return true }
        return qWords.allSatisfy { q in
            haystack.contains { $0.hasPrefix(q) }
        }
    }

    /// Match against a card's full searchable surface (Find tab fields).
    static func matches(query: String, card: Card) -> Bool {
        matches(query: query, in: haystackWords(for: card))
    }

    /// Match against an arbitrary scoped list of fields (Collection /
    /// Deck pool search a narrower set than Find).
    static func matches(query: String, fields: [String?]) -> Bool {
        var words: [String] = []
        for f in fields {
            if let f { words.append(contentsOf: wordSplit(f)) }
        }
        return matches(query: query, in: words)
    }
}
