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
                .preferredColorScheme(.dark)
                .task(id: authManager.userId) {
                    // Reload image removal overrides whenever auth state changes.
                    // No-ops silently if unauthenticated or the request fails.
                    if authManager.userId != nil {
                        await cardStore.loadImageRemovals()
                    }
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
                        // bobaplaybook://scan — QR code on web opens Scan tab directly.
                        selectedTab = 1
                    case "card":
                        // bobaplaybook://card/CBF-656 — deep link to a specific card.
                        let cardNumber = String(url.path.dropFirst())  // strip leading "/"
                        if !cardNumber.isEmpty {
                            selectedTab = 0  // switch to Search tab
                            cardStore.pendingCardNumber = cardNumber.uppercased()
                        }
                    default:
                        authManager.handleDeepLink(url)
                    }
                }
        }
    }
}
