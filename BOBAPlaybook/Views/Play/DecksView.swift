//
//  DecksView.swift
//  BOBAPlaybook
//
//  The "Decks" tab — deck builder landing. Thin wrapper around
//  DeckBuilderView presented as a tab root so the Done button is
//  hidden and the wordmark sits centered in the navigation bar.
//

import SwiftUI

struct DecksView: View {
    var body: some View {
        DeckBuilderView(isRootView: true)
    }
}
