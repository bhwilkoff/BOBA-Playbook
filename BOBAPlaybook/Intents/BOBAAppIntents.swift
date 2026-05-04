//
//  BOBAAppIntents.swift
//  BOBAPlaybook
//
//  App Intents per DESIGN.md §7 — primary actions exposed as intents
//  so Spotlight, Siri, the Action Button, Shortcuts, and the iOS 27
//  natural-language Siri layer all consume them automatically.
//
//  Each intent leverages the existing bobaplaybook:// URL deep-link
//  handler in BOBAPlaybookApp.swift so there's a single state-flow
//  into the running app — no need for AppIntent ↔ View IPC machinery.
//

import AppIntents
import SwiftUI

// MARK: - Search a card

/// Opens the Find tab with `query` pre-loaded into the search field.
/// Spotlight / Siri / Shortcuts / Action Button all consume this.
struct SearchCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Cards"
    static var description = IntentDescription(
        "Search the BOBA Playbook catalog by name, hero, or card number."
    )
    /// `openAppWhenRun = true` opens the app (foregrounded if running);
    /// the URL handler in BOBAPlaybookApp routes the intent payload to
    /// the Find tab.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Search", description: "Card name, hero, or card number")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "bobaplaybook://search?q=\(encoded)")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Open a card by number

/// Deep links to a specific card detail by card number.
struct OpenCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Card"
    static var description = IntentDescription(
        "Open a specific BOBA card by its card number (e.g., RBF-72)."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Card Number", description: "e.g. RBF-72, IBF-191")
    var cardNumber: String

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let encoded = cardNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let url = URL(string: "bobaplaybook://card/\(encoded)")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Add a card to collection

/// Routes through the existing card-detail "Add to Collection" sheet.
/// Identifies the target card by card number, then opens the app to
/// the card's detail view with the add sheet auto-presented. The user
/// confirms designation + designation in the sheet (we don't infer).
///
/// Per DESIGN.md §7 — "Add to Collection" is one of the four primary
/// actions an AppIntent must surface. Per DESIGN.md §6.5, write
/// actions require auth; if the user isn't signed in, the standard
/// CardDetailView.AddToCollectionSheet falls through to the inline
/// sign-in prompt rather than failing silently.
struct AddToCollectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Card to Collection"
    static var description = IntentDescription(
        "Add a BOBA card to your collection by its card number."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Card Number", description: "e.g. RBF-72, IBF-191")
    var cardNumber: String

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // Encodes the auto-add hint as a query param the deep-link
        // handler reads. The card-detail view, on first appearance,
        // checks the flag and presents the AddToCollection sheet.
        let encoded = cardNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let url = URL(string: "bobaplaybook://card/\(encoded)?action=addToCollection")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Start scan

/// Jumps straight into the camera scanner. Most useful via Action Button
/// or Shortcuts automation ("when I open my card binder, run this").
struct StartScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a Card"
    static var description = IntentDescription(
        "Open the BOBA card scanner to identify a physical card."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "bobaplaybook://scan")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - App Shortcuts provider

/// Surfaces the canonical phrases Siri / Spotlight discover from the
/// app. Each phrase MUST include `\(.applicationName)`. App Shortcuts
/// only support parameterless invocations or parameters typed as
/// AppEntity/AppEnum — for parameterized SearchCardIntent and
/// OpenCardIntent, users invoke them via Shortcuts.app or the iOS 27
/// natural-language Siri layer (which can synthesize String params
/// from natural speech without a phrase template).
struct BOBAAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanIntent(),
            phrases: [
                "Scan a card with \(.applicationName)",
                "Open the scanner in \(.applicationName)",
                "Identify a card in \(.applicationName)"
            ],
            shortTitle: "Scan a Card",
            systemImageName: "camera.viewfinder"
        )
    }
}
