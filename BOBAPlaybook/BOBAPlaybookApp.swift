//
//  BOBAPlaybookApp.swift
//  BOBAPlaybook
//
//  Created by Ben Wilkoff on 4/3/26.
//

import SwiftUI
import CoreText

@main
struct BOBAPlaybookApp: App {
    @State private var cardStore = CardStore()

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
            ContentView()
                .environment(cardStore)
                .preferredColorScheme(.dark)
        }
    }
}
