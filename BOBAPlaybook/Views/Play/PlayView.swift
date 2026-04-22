//
//  PlayView.swift
//  BOBAPlaybook
//
//  The new "Play" tab — practice battle landing. Before the nav refactor
//  the Play tab hosted rules/strategy/collecting *and* the practice
//  battle entry; now the informational content lives in LearnView and
//  this tab is purely for launching a practice match.
//

import SwiftUI

struct PlayView: View {
    var body: some View {
        PracticeSetupView(isRootView: true)
    }
}
