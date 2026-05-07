//
//  ScanCoordinator.swift
//  BOBAPlaybook
//
//  Per DESIGN.md §6.5 — single coordinator for the cross-cutting Scan
//  capability. Find / Decks / Collection each invoke the same modal
//  ScanView through this coordinator; the destination determines what
//  happens to captured cards (held in queue vs. added to deck vs. added
//  to a collection designation).
//
//  The ScanView + GridScanView UI stays unchanged — this is the
//  *invocation* layer. Removes three parallel showScan @State + per-tab
//  fullScreenCover implementations and replaces them with one
//  centrally-presented sheet at ContentView level.
//
//  The .tabViewBottomAccessory persistent strip mentioned in §6.5 is a
//  follow-up — the active state currently lives inside ScanQueueView's
//  modal. When it ships, this coordinator owns the source of truth that
//  the bottom accessory observes.
//

import SwiftUI

@MainActor
@Observable
final class ScanCoordinator {

    /// Where captured cards land. Defaults to .find (identify-only)
    /// when no scan session is active.
    enum Destination {
        /// Find tab — captures land in the queue, user reviews each
        /// and taps to push CardDetailView. No mutation of decks or
        /// collection.
        case find

        /// Decks tab — captures append to the current in-progress deck.
        /// `currentDeckLabel` shows in the queue header so the coach
        /// knows which deck they're scanning into; `savedDecks` lets
        /// the queue offer fan-out to other saved decks.
        case deck(label: String, savedDecks: [SavedDeck])

        /// Collection tab — captures land in the user's collection
        /// under the chosen designation. ScanStore.activeCollection-
        /// Designation drives every save path (queue saveAll, single-
        /// card chip quick-save). Cleared on dismiss.
        case collection(designation: UserCard.Designation)

        var isDeck: Bool {
            if case .deck = self { return true }
            return false
        }
    }

    /// Driven by `start(...)` and `dismiss()`. Read by ContentView's
    /// fullScreenCover binding.
    var isPresenting: Bool = false

    /// Last-requested destination. Held even after dismissal so the
    /// queue review UI knows what context to render in.
    var destination: Destination = .find

    /// Begin a scan session. The view that calls this should also have
    /// the `ScanStore` from environment — we don't hold a reference to
    /// the store here so the coordinator stays single-source-of-truth
    /// without coupling lifetimes.
    func start(_ destination: Destination, scanStore: ScanStore) {
        self.destination = destination
        switch destination {
        case .find:
            // Reset deck-builder context so a returning Find scan
            // doesn't inherit "scanning into Deck X" UI.
            scanStore.endDeckBuilderSession()
        case .deck(let label, let savedDecks):
            let targets = savedDecks.map { ScanStore.DeckTarget(id: $0.id, name: $0.name) }
            scanStore.beginDeckBuilderSession(
                currentDeckLabel: label,
                availableSavedDecks: targets
            )
        case .collection(let designation):
            // Collection-destination scan — captures land in the
            // chosen designation when saved from the queue or the
            // single-card chip. Reset deck context so the queue UI
            // doesn't render in deck-builder mode.
            scanStore.endDeckBuilderSession()
            scanStore.beginCollectionSession(designation: designation)
        }
        isPresenting = true
    }

    /// Called when the modal cover dismisses. Cleans up any per-session
    /// state in ScanStore so the next invocation starts fresh.
    func dismiss(scanStore: ScanStore) {
        if destination.isDeck {
            scanStore.endDeckBuilderSession()
        }
        // Always clear the collection-session marker — the next
        // invocation may be Find (identify-only), and lingering
        // designation state would silently misroute saves.
        scanStore.endCollectionSession()
        destination = .find
        isPresenting = false
    }
}
