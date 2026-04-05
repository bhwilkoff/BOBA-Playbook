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
                .onOpenURL { url in
                    // bobaplaybook://scan → jump straight to the Scan tab.
                    // This is triggered by the QR code on the desktop web app,
                    // bypassing the web auth that doesn't work in restricted web views.
                    if url.scheme == "bobaplaybook", url.host == "scan" {
                        selectedTab = 1
                        return
                    }
                    authManager.handleDeepLink(url)
                }
        }
    }
}
