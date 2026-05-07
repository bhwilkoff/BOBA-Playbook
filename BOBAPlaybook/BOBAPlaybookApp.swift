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
    @State private var selectedTab = 0

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
            ContentView(selectedTab: $selectedTab)
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
                    print("[DeepLink] onOpenURL fired: \(url.absoluteString)")
                    handleDeepLink(url)
                }
                // Universal Links per DESIGN.md §8.4 — taps on
                // https://bobaplaybook.com/* land here when the app is
                // installed (apple-app-site-association on the server
                // gates which paths route in vs. open the web). Iframed
                // through the same handler that takes bobaplaybook://
                // URLs so the routing stays one source of truth.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    print("[DeepLink] onContinueUserActivity fired. webpageURL=\(activity.webpageURL?.absoluteString ?? "nil")")
                    guard let url = activity.webpageURL else {
                        print("[DeepLink]   ↳ no webpageURL on activity, ignoring")
                        return
                    }
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
        print("[DeepLink] handleDeepLink: scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil") path=\(url.path)")
        guard url.scheme == "bobaplaybook" else {
            print("[DeepLink]   ↳ wrong scheme, ignoring")
            return
        }
        switch url.host {
        case "scan":
            selectedTab = 0
            cardStore.pendingScan = true
        case "card":
            let cardNumber = String(url.path.dropFirst())
            if !cardNumber.isEmpty {
                selectedTab = 0
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let q = comps?.queryItems
                // Optional ?action=addToCollection hint from
                // AddToCollectionIntent — CardDetailView reads this
                // and auto-presents the AddToCollection sheet on
                // first appearance.
                if let action = q?.first(where: { $0.name == "action" })?.value {
                    cardStore.pendingCardAction = action
                }
                // Push CardRoute directly onto the Find tab's path
                // — no observation chain. CardRouteResolver at the
                // destination handles catalog-not-loaded by re-
                // evaluating when displayCards populates.
                let route = CardRoute(
                    cardNumber: cardNumber.uppercased(),
                    treatment: q?.first(where: { $0.name == "treatment" })?.value,
                    hero: q?.first(where: { $0.name == "hero" })?.value
                )
                cardStore.findNavigationPath.append(route)
                print("[DeepLink]   ↳ appended CardRoute to findNavigationPath. " +
                      "cardNumber=\(route.cardNumber) treatment=\(route.treatment ?? "nil") " +
                      "hero=\(route.hero ?? "nil") pathCount=\(cardStore.findNavigationPath.count) " +
                      "displayCards=\(cardStore.displayCards.count)")
            } else {
                print("[DeepLink]   ↳ card path empty, ignoring")
            }
        case "search":
            selectedTab = 0
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
            selectedTab = 1
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
    /// Also handles the web app's root-path query-string format:
    /// https://bobaplaybook.com/?card=BL-B81&treatment=Blue+Blast&hero=...
    /// — the SPA-style URL the web build emits when you share a card.
    @MainActor
    private func handleUniversalLink(_ url: URL) {
        print("[DeepLink] handleUniversalLink: \(url.absoluteString)")
        guard url.host == "bobaplaybook.com" else {
            print("[DeepLink]   ↳ wrong host (\(url.host ?? "nil")), ignoring")
            return
        }
        let pathParts = url.path.split(separator: "/").map(String.init)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryDesc = comps?.queryItems?
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: ", ") ?? "nil"
        print("[DeepLink]   pathParts=\(pathParts) queryItems=\(queryDesc)")

        // Root-path SPA URLs: /?card=X&treatment=Y&hero=Z
        // Take precedence over path-based parsing when ?card= is
        // present, since the web app's canonical share URL is this
        // shape.
        if let cardQ = comps?.queryItems?.first(where: { $0.name == "card" })?.value,
           !cardQ.isEmpty {
            print("[DeepLink]   ↳ root-path SPA URL with ?card=\(cardQ); translating")
            let treatment = comps?.queryItems?.first(where: { $0.name == "treatment" })?.value
            let hero      = comps?.queryItems?.first(where: { $0.name == "hero" })?.value
            // Build a custom-scheme URL preserving every query param so
            // handleDeepLink's existing parsing handles the rest.
            var newComps = URLComponents()
            newComps.scheme = "bobaplaybook"
            newComps.host = "card"
            newComps.path = "/\(cardQ)"
            var items: [URLQueryItem] = []
            if let t = treatment { items.append(URLQueryItem(name: "treatment", value: t)) }
            if let h = hero      { items.append(URLQueryItem(name: "hero",      value: h)) }
            if !items.isEmpty { newComps.queryItems = items }
            if let translated = newComps.url {
                handleDeepLink(translated)
                return
            }
        }

        guard let first = pathParts.first?.lowercased() else { return }
        switch first {
        case "card" where pathParts.count >= 2:
            let translated = URL(string: "bobaplaybook://card/\(pathParts[1])")!
            handleDeepLink(translated)
        case "scan":
            handleDeepLink(URL(string: "bobaplaybook://scan")!)
        case "search":
            // /search?q=...
            let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            handleDeepLink(URL(string: "bobaplaybook://search?q=\(encoded)")!)
        case "learn" where pathParts.count >= 2:
            let cat = pathParts[1]
            handleDeepLink(URL(string: "bobaplaybook://learn/\(cat)")!)
        case "u" where pathParts.count >= 3:
            // /u/{userId}/{designation} — public collection wall.
            // Currently routes to Collection tab; future work surfaces
            // the public-designation read-only view.
            selectedTab = 4
        default:
            break
        }
    }
}
