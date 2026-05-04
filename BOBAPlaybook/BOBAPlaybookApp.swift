//
//  BOBAPlaybookApp.swift
//  BOBAPlaybook
//

import SwiftUI
import CoreText

@main
struct BOBAPlaybookApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var cardStore = CardStore()
    @State private var authManager = AuthManager()
    @State private var collectionStore = CollectionStore()
    @State private var scanStore = ScanStore()
    @State private var scanCoordinator = ScanCoordinator()
    @State private var showsStore = ShowsStore()
    @State private var selectedDestination: Destination = .find

    /// Set of known Learn category slugs — gates the
    /// bobaplaybook://learn/{category} deep link so a typo doesn't
    /// silently switch tabs.
    private static let learnCategories: Set<String> = ["rules", "strategy", "collect", "glossary", "tournament"]

    init() {
        // Persist AsyncImage responses across sessions
        URLCache.shared.memoryCapacity = 100 * 1024 * 1024  // 100 MB
        URLCache.shared.diskCapacity   = 500 * 1024 * 1024  // 500 MB

        // Register custom fonts — avoids Info.plist editing with GENERATE_INFOPLIST_FILE
        for name in ["BebasNeue-Regular", "RussoOne-Regular", "ChakraPetch-Regular", "ChakraPetch-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(selectedDestination: $selectedDestination)
                .environment(cardStore)
                .environment(authManager)
                .environment(collectionStore)
                .environment(scanStore)
                .environment(scanCoordinator)
                .environment(showsStore)
                .preferredColorScheme(.dark)
                .task(id: authManager.userId) {
                    // Reload image removal overrides whenever auth state changes.
                    // No-ops silently if unauthenticated or the request fails.
                    if authManager.userId != nil {
                        await cardStore.loadImageRemovals()
                    }
                }
                .task {
                    // Load the feature-print index in the background.
                    // Quietly no-ops if `feature-prints.bin` isn't bundled
                    // (e.g. dev builds before Phase 2 ships) — the
                    // scanner's OCR pipeline runs unaffected. Loading
                    // costs ~50ms parsing + ~40MB resident at steady
                    // state, but the file is mmap'd so resident pages
                    // are paged in only as the search touches them.
                    await FeaturePrintIndex.shared.loadFromBundle()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Re-fetch role when the app comes back to the foreground.
                    // The access token may have expired while backgrounded; fetchRole uses
                    // executeArray which auto-refreshes via the stored refresh token.
                    guard authManager.isAuthenticated else { return }
                    Task { await authManager.fetchRole() }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                // Universal Links per DESIGN.md §8.4 — taps on
                // https://bobaplaybook.com/* land here when the app is
                // installed (apple-app-site-association on the server
                // gates which paths route in vs. open the web). Iframed
                // through the same handler that takes bobaplaybook://
                // URLs so the routing stays one source of truth.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    handleUniversalLink(url)
                }
        }
    }

    /// Single handler for both bobaplaybook:// custom-scheme URLs and
    /// Universal Link https://bobaplaybook.com/* fallbacks. Routes the
    /// canonical paths from DESIGN.md (card / search / scan / learn /
    /// u/{user}/{designation}) and forwards anything else to AuthManager.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "bobaplaybook" else { return }
        switch url.host {
        case "scan":
            selectedDestination = .find
            cardStore.pendingScan = true
        case "card":
            let cardNumber = String(url.path.dropFirst())
            if !cardNumber.isEmpty {
                selectedDestination = .find
                cardStore.pendingCardNumber = cardNumber.uppercased()
                // Optional ?action=addToCollection hint from
                // AddToCollectionIntent — CardDetailView reads this
                // and auto-presents the AddToCollection sheet on
                // first appearance.
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let action = comps?.queryItems?.first(where: { $0.name == "action" })?.value {
                    cardStore.pendingCardAction = action
                }
            }
        case "search":
            selectedDestination = .find
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            if !q.isEmpty {
                cardStore.pendingSearchQuery = q
            }
        case "learn":
            // bobaplaybook://learn/{category} — DESIGN.md §7.2 stable
            // section identifiers (forward-compat for iOS 27 Siri
            // summaries). Currently switches to the Learn tab; per-
            // section deep linking lands once the sub-views grow
            // section-anchor IDs.
            let slug = String(url.path.dropFirst()).lowercased()
            selectedDestination = .learn
            if !slug.isEmpty, Self.learnCategories.contains(slug) {
                cardStore.pendingLearnCategory = slug
            }
        default:
            authManager.handleDeepLink(url)
        }
    }

    /// https://bobaplaybook.com/{card,search,scan,learn,u/{id}/{designation}}
    /// path mirror of the custom-scheme URLs above. Translates to the
    /// custom scheme so a single switch handles both inbound paths.
    @MainActor
    private func handleUniversalLink(_ url: URL) {
        guard url.host == "bobaplaybook.com" else { return }
        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let first = pathParts.first?.lowercased() else { return }
        switch first {
        case "card" where pathParts.count >= 2:
            let translated = URL(string: "bobaplaybook://card/\(pathParts[1])")!
            handleDeepLink(translated)
        case "scan":
            handleDeepLink(URL(string: "bobaplaybook://scan")!)
        case "search":
            // /search?q=...
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            handleDeepLink(URL(string: "bobaplaybook://search?q=\(encoded)")!)
        case "learn" where pathParts.count >= 2:
            let cat = pathParts[1]
            handleDeepLink(URL(string: "bobaplaybook://learn/\(cat)")!)
        case "u" where pathParts.count >= 3:
            // /u/{userId}/{designation} — public collection wall.
            // Currently routes to Collection; future work surfaces
            // the public-designation read-only view.
            selectedDestination = .collection
        default:
            break
        }
    }
}
