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
                    guard url.scheme == "bobaplaybook" else { return }
                    switch url.host {
                    case "scan":
                        // bobaplaybook://scan — also raised by StartScanIntent
                        // (Spotlight / Siri / Action Button). Jumps to Find
                        // (tab 0) and flags the scanner sheet which SearchView
                        // observes.
                        selectedTab = 0
                        cardStore.pendingScan = true
                    case "card":
                        // bobaplaybook://card/CBF-656 — also raised by OpenCardIntent.
                        let cardNumber = String(url.path.dropFirst())  // strip leading "/"
                        if !cardNumber.isEmpty {
                            selectedTab = 0
                            cardStore.pendingCardNumber = cardNumber.uppercased()
                        }
                    case "search":
                        // bobaplaybook://search?q=... — raised by SearchCardIntent.
                        // Jumps to Find with the query string pre-loaded.
                        selectedTab = 0
                        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
                        if !q.isEmpty {
                            cardStore.pendingSearchQuery = q
                        }
                    default:
                        authManager.handleDeepLink(url)
                    }
                }
        }
    }
}
