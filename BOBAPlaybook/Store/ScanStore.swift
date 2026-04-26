import SwiftUI
import Observation

@Observable
@MainActor
final class ScanStore {

    // MARK: - Queued card wrapper
    struct QueuedCard: Identifiable {
        let id = UUID()
        let card: Card
        let scannedAt = Date()
    }

    /// Scanner destination mode. `single` and `multi` keep the existing
    /// behavior (dismiss after one card vs. queue many). `show` is a
    /// streamer-only third mode that queues cards bound for a Show
    /// (Whatnot prep) instead of the collection. The queue itself is
    /// the same array — the mode flag dictates what "Save all" does.
    enum Mode: String {
        case single, multi, show
    }

    /// Where the scanner was opened from. The save-all path branches on
    /// this: `.find` routes to the user's Collection (today's behavior);
    /// `.deckBuilder` routes scanned cards into the in-progress deck and
    /// any saved decks the user multi-selects, with an opt-in checkbox
    /// to mirror to Collection at the same time. Always reset to
    /// `.find` on queue clear so a Find-tab scan doesn't accidentally
    /// inherit a stale deck-builder context.
    enum Source { case find, deckBuilder }

    /// Lightweight reference to a saved deck the user can target. Mirrors
    /// SavedDeck (id + name) without depending on DeckBuilderStore — keeps
    /// ScanStore's import surface small and free of circular references.
    struct DeckTarget: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    // MARK: - State
    var mode: Mode = .single
    var queuedCards: [QueuedCard] = []

    // MARK: - Deck-builder routing
    /// Source of the current scanning session (default Find tab).
    var source: Source = .find
    /// Display label for the in-progress deck the scanner was launched
    /// from (e.g. "Fire Aggro v2"). Used in the queue's destination
    /// row. Empty when source != .deckBuilder.
    var currentDeckLabel: String = ""
    /// Saved decks the user can additionally route scanned cards to.
    /// Snapshot taken at scanner-open time so the queue UI doesn't
    /// re-fetch from Supabase. Empty when source != .deckBuilder OR
    /// the user has no saved decks beyond the in-progress one.
    var availableSavedDecks: [DeckTarget] = []
    /// IDs of saved decks the user has ticked in the queue picker.
    /// In-progress deck routing is implicit (always on for source =
    /// .deckBuilder) and isn't tracked here.
    var selectedDeckIds: Set<UUID> = []
    /// When source == .deckBuilder: also write each scanned card to
    /// Collection (designation = .personal). Off by default — the
    /// scenario the feature targets is "drafting a deck, scan some
    /// physical cards in." Toggled by a checkbox in the queue.
    var alsoSaveToCollection: Bool = false
    /// Cards delivered FROM the queue back TO the deck-builder
    /// presenter. Set by the queue's Save All path; observed by
    /// DeckBuilderView via .onChange — when non-empty, the view
    /// appends the cards to its in-memory deck (heroes / plays /
    /// bonusPlays / hotDogs lists) and clears this back to []. The
    /// presenter clears it; the scan store never auto-resets it
    /// because there's no obvious moment "after the deck builder
    /// has consumed it" the store could observe.
    var pendingScannedCardsForActiveDeck: [Card] = []

    /// Back-compat — the rest of the scanner pipeline still asks
    /// "should I keep the overlay up and queue more" via this flag.
    /// Both multi and show modes queue.
    var isMultiCardMode: Bool {
        get { mode != .single }
        set { mode = newValue ? .multi : .single }
    }

    var isShowMode: Bool { mode == .show }
    var queueCount: Int { queuedCards.count }

    // MARK: - Queue operations

    /// Adds a card to the queue. Silently ignores if the same cardNumber is already queued.
    func addToQueue(_ card: Card) {
        guard !queuedCards.contains(where: { $0.card.cardNumber == card.cardNumber }) else { return }
        queuedCards.append(QueuedCard(card: card))
    }

    func removeFromQueue(at offsets: IndexSet) {
        queuedCards.remove(atOffsets: offsets)
    }

    func clearQueue() {
        queuedCards.removeAll()
    }

    /// Initialize scanner state for a deck-builder scanning session.
    /// Called by DeckBuilderView right before presenting the scanner.
    /// The queue defaults to multi mode so coaches can scan a stack;
    /// switching to single mode is still available from the scanner.
    func beginDeckBuilderSession(currentDeckLabel: String,
                                 availableSavedDecks: [DeckTarget]) {
        self.source = .deckBuilder
        self.mode = .multi
        self.currentDeckLabel = currentDeckLabel
        self.availableSavedDecks = availableSavedDecks
        self.selectedDeckIds = []
        self.alsoSaveToCollection = false
        self.queuedCards = []
    }

    /// Reset everything back to the Find-tab default. Called when the
    /// scanner closes via the Find path so a future deck-builder
    /// session doesn't inherit stale state.
    func endDeckBuilderSession() {
        self.source = .find
        self.currentDeckLabel = ""
        self.availableSavedDecks = []
        self.selectedDeckIds = []
        self.alsoSaveToCollection = false
    }

    /// Replace the most-recently-queued card with a refined version.
    /// Used by the feature-print disambiguation path: OCR queues a
    /// candidate, and a subsequent image-similarity check produces a
    /// better answer for the same physical scan. The queue ordering is
    /// preserved; the row's UUID changes, which is acceptable since
    /// SwiftUI will already re-render the row for the new card content.
    func replaceLastInQueue(with refined: Card) {
        guard !queuedCards.isEmpty else { return }
        queuedCards.removeLast()
        queuedCards.append(QueuedCard(card: refined))
    }
}
