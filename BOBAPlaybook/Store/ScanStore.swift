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

    // MARK: - State
    var mode: Mode = .single
    var queuedCards: [QueuedCard] = []

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
