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

    // MARK: - State
    var isMultiCardMode = false
    var queuedCards: [QueuedCard] = []

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
}
