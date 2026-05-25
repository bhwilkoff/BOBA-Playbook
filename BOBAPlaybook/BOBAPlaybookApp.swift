//
//  BOBAPlaybookApp.swift
//  BOBAPlaybook
//

import SwiftUI
import CoreText
import RealityKit
import UIKit

@main
struct BOBAPlaybookApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var cardStore = CardStore()
    @State private var authManager = AuthManager()
    @State private var collectionStore = CollectionStore()
    @State private var scanStore = ScanStore()
    @State private var scanCoordinator = ScanCoordinator()
    @State private var showsStore = ShowsStore()
    @State private var customRainbowStore = CustomRainbowStore()
    /// Hoisted to app-root tick 135 (fixes tick-97 bug — CollectionCardDetailView
    /// read DeckBuilderStore from @Environment but no parent injected it,
    /// crashing on the per-deck tap-to-load action). DecksView / DeckBuilderView
    /// switched to @Environment too so they read the same instance — the
    /// load-saved-deck call in CollectionCardDetailView now actually
    /// propagates to the Decks tab.
    @State private var deckBuilderStore = DeckBuilderStore()
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

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView(selectedTab: $selectedTab)
                .environment(cardStore)
                .environment(authManager)
                .environment(collectionStore)
                .environment(scanStore)
                .environment(scanCoordinator)
                .environment(showsStore)
                .environment(customRainbowStore)
                .environment(deckBuilderStore)
                .preferredColorScheme(.dark)
                .task(id: authManager.userId) {
                    // v2.280 — image overrides apply globally (every
                    // user sees admin-approved updates), so fetch
                    // them whether the user is signed in or not.
                    // RLS on card_image_overrides / card_image_removals
                    // already permits anon SELECT. The auth-gated
                    // version of this task left signed-out users
                    // looking at the pre-override catalog.
                    await cardStore.loadImageRemovals()
                    await cardStore.loadAppliedImageOverrides()
                }
                .task {
                    // Headless Hero Shot CLI hook. When env var
                    // BOBA_HERO_SHOT_CLI=1 is set, render the 4
                    // material-variant comparison grid to disk and
                    // exit(0). See HeroShotCLIRunner + the driver
                    // script at tools/render-hero-shot-variants.sh.
                    if #available(iOS 18.0, *), HeroShotCLIRunner.isRequested {
                        await HeroShotCLIRunner.run(cardStore: cardStore)
                        return
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
                // Single URL entry point. iOS 17+ routes both
                // bobaplaybook:// custom-scheme URLs AND https://
                // Universal Links through onOpenURL — the older
                // NSUserActivityTypeBrowsingWeb path is largely
                // superseded. Dispatch by scheme.
                .onOpenURL { url in
                    routeIncoming(url)
                }
                // onContinueUserActivity kept as a fallback for older
                // iOS versions / Handoff scenarios where the system
                // still uses the activity-based delivery.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    routeIncoming(url)
                }
        }
    }

    /// Dispatcher for incoming URLs from either scheme. Universal
    /// Links arrive as https://bobaplaybook.com/...; custom-scheme
    /// links arrive as bobaplaybook://.... Routes each to its
    /// dedicated handler so the parsing stays simple.
    @MainActor
    private func routeIncoming(_ url: URL) {
        switch url.scheme {
        case "https":
            handleUniversalLink(url)
        case "bobaplaybook":
            handleDeepLink(url)
        default:
            break
        }
    }

    /// Single handler for bobaplaybook:// custom-scheme URLs.
    /// Universal Links go through handleUniversalLink which translates
    /// to a custom-scheme URL and calls this — one parser, two entry
    /// shapes.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "bobaplaybook" else { return }
        switch url.host {
        case "render-test-comparison":
            // v6.2 debug entry: render the 4-up material comparison
            // grid for the first card in the catalog, save to the
            // app's documents dir, log the path. Lets the iOS Simulator
            // generate a comparison render via simctl openurl — no
            // UI navigation needed.
            Task { @MainActor in
                await runHeroShotComparisonDebug()
            }
            return
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
                    hero: q?.first(where: { $0.name == "hero" })?.value,
                    element: q?.first(where: { $0.name == "element" })?.value
                )
                cardStore.findNavigationPath.append(route)
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
        guard url.host == "bobaplaybook.com" else { return }
        let pathParts = url.path.split(separator: "/").map(String.init)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Root-path SPA URLs: /?card=X&treatment=Y&hero=Z
        // Take precedence over path-based parsing when ?card= is
        // present, since the web app's canonical share URL is this
        // shape.
        if let cardQ = comps?.queryItems?.first(where: { $0.name == "card" })?.value,
           !cardQ.isEmpty {
            let treatment = comps?.queryItems?.first(where: { $0.name == "treatment" })?.value
            let hero      = comps?.queryItems?.first(where: { $0.name == "hero" })?.value
            let element   = comps?.queryItems?.first(where: { $0.name == "element" })?.value
            // Build a custom-scheme URL preserving every query param so
            // handleDeepLink's existing parsing handles the rest.
            var newComps = URLComponents()
            newComps.scheme = "bobaplaybook"
            newComps.host = "card"
            newComps.path = "/\(cardQ)"
            var items: [URLQueryItem] = []
            if let t = treatment { items.append(URLQueryItem(name: "treatment", value: t)) }
            if let h = hero      { items.append(URLQueryItem(name: "hero",      value: h)) }
            if let e = element   { items.append(URLQueryItem(name: "element",   value: e)) }
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

    /// v6.2 debug — render the Hero Shot 4-up material comparison grid
    /// for the first foil-treatment card in the catalog. Saves PNG to
    /// the app's documents dir at "hero-shot-comparison.png". Logs the
    /// full path so the iOS Simulator harness can pull the file via
    /// `simctl get_app_container … data`.
    @MainActor
    @available(iOS 18.0, *)
    private func runHeroShotComparisonDebug() async {
        // Marker file so we can confirm this function was reached
        // even if subsequent steps fail.
        let docs = FileManager.default.urls(for: .documentDirectory,
                                             in: .userDomainMask)[0]
        let marker = docs.appendingPathComponent("hero-debug-marker.txt")
        try? "fn called at \(Date())".write(to: marker, atomically: true,
                                             encoding: .utf8)
        NSLog("[HoloDebug] runHeroShotComparisonDebug entered")

        // Pick a foil card with a visible treatment so the comparison
        // is meaningful. First non-base card we find. CardStore stores
        // cards in `displayCards`; `cardStore` here is a non-Binding
        // @State so we access properties directly.
        let allCards = cardStore.displayCards
        NSLog("[HoloDebug] displayCards count = \(allCards.count)")
        try? "fn called; cards=\(allCards.count) at \(Date())"
            .write(to: marker, atomically: true, encoding: .utf8)
        let card = allCards.first { c in
            guard let t = c.treatment?.lowercased(), !t.isEmpty else { return false }
            return t.contains("battlefoil") || t.contains("superfoil")
                || t.contains("blizzard") || t.contains("inspired")
        } ?? allCards.first
        guard let card else {
            print("[HoloDebug] no card available")
            return
        }
        guard let url = CDN.fullURL(for: card) else {
            print("[HoloDebug] no CDN URL for \(card.id)")
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else {
            print("[HoloDebug] failed to fetch \(url)")
            return
        }
        let rounded = BOBACardEntity.roundedCorners(image) ?? image
        guard let cg = rounded.cgImage,
              let frontTex = try? await TextureResource(
                  image: cg, withName: nil,
                  options: TextureResource.CreateOptions(
                      semantic: .color, mipmapsMode: .allocateAndGenerateAll
                  )) else {
            print("[HoloDebug] texture create failed")
            return
        }
        var backTex: TextureResource?
        if let path = Bundle.main.url(forResource: "card-back", withExtension: "png"),
           let img = UIImage(contentsOfFile: path.path),
           let bcg = (BOBACardEntity.roundedCorners(img) ?? img).cgImage {
            backTex = try? await TextureResource(
                image: bcg, withName: nil,
                options: TextureResource.CreateOptions(
                    semantic: .color, mipmapsMode: .none))
        }
        let renderer = HeroShotRenderer()
        let config = HeroShotRenderer.Config(
            card: card,
            frontTexture: frontTex,
            backTexture: backTex,
            frontImage: rounded,
            includeWatermark: false
        )
        do {
            // v6.4 debug: single-frame preview (not comparison grid).
            // The 4-variant comparison grid renders 4 frames which
            // hangs in iOS Simulator's RealityRenderer. Single frame
            // is what's currently shipped.
            let grid = try await renderer.renderPreviewFrame(
                config, normalizedTime: 0.95)
            if let pngData = grid.pngData() {
                let docs = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0]
                let out = docs.appendingPathComponent("hero-shot-comparison.png")
                try? pngData.write(to: out)
                print("[HoloDebug] wrote \(out.path) (\(pngData.count) bytes)")
                print("[HoloDebug] card: \(card.id) treatment=\(card.treatment ?? "nil")")
            } else {
                print("[HoloDebug] pngData() failed")
            }
        } catch {
            print("[HoloDebug] render failed: \(error)")
        }
    }
}
