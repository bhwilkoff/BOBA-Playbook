//
//  PracticeBottomToolbar.swift
//  BOBAPlaybook
//
//  Compact bottom toolbar for practice battle: deck count, bench toggle,
//  plays toggle, hot dog counter, and action button.
//

import SwiftUI

struct PracticeBottomToolbar: View {
    let store: PracticeStore
    @Binding var showBenchPanel: Bool
    @Binding var showPlaysPanel: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Hero deck count
            heroStack
                .frame(width: 50)

            divider

            // Bench toggle
            if store.mode.showBench {
                benchToggle
                divider
            }

            // Plays toggle
            if store.mode.showPlays {
                playsToggle
                divider
            }

            // Hot dog counter
            if store.mode.showHotDogs {
                hotDogCounter
                divider
            }

            Spacer()

            // Action button
            actionButton
                .padding(.trailing, Design.Spacing.md)
        }
        .frame(height: 50)
        .background(Design.Colors.surface.opacity(0.95))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
    }

    // MARK: - Hero Deck Stack

    private var heroStack: some View {
        VStack(spacing: 2) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "C0392B").opacity(0.8))
            Text("\(store.playerHeroDeck.count)")
                .font(Design.Fonts.mono(10, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }

    // MARK: - Bench Toggle

    private var benchToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showBenchPanel.toggle()
                if showBenchPanel { showPlaysPanel = false }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12))
                Text("BENCH")
                    .font(Design.Fonts.mono(8, weight: .bold))
            }
            .foregroundStyle(showBenchPanel ? Design.Colors.bobaOrange : (store.phase == .sub ? Design.Colors.bobaOrange.opacity(0.7) : Design.Colors.textMuted))
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plays Toggle

    private var playsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showPlaysPanel.toggle()
                if showPlaysPanel { showBenchPanel = false }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 12))
                Text("PLAYS")
                    .font(Design.Fonts.mono(8, weight: .bold))
            }
            .foregroundStyle(showPlaysPanel ? Design.Colors.bobaCyan : (store.phase == .play ? Design.Colors.bobaCyan.opacity(0.7) : Design.Colors.textMuted))
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hot Dog Counter

    private var hotDogCounter: some View {
        VStack(spacing: 2) {
            Text("\(store.playerHotDogs)")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Color(hex: "4CAF50"))
            Text("HOT DOGS")
                .font(Design.Fonts.mono(7, weight: .bold))
                .foregroundStyle(Color(hex: "4CAF50").opacity(0.7))
        }
        .frame(width: 60)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if store.phase == .sub && !store.playerSubstituted {
                Button("PASS SUBS", action: onAction)
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.textMuted))
            } else if store.phase == .play && !store.playerPassedPlays {
                Button("PASS PLAYS") { store.playerPassPlays() }
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaCyan))
            } else {
                Button(nextButtonLabel, action: onAction)
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
            }
        }
    }

    private var nextButtonLabel: String {
        switch store.phase {
        case .reveal:     return "REVEAL"
        case .sub:        return "DONE SUBS"
        case .play:       return "DONE PLAYS"
        case .resolution: return "NEXT"
        case .cleanup:    return "NEXT BATTLE"
        case .matchOver:  return "DONE"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.glass)
            .frame(width: 1, height: 30)
    }
}
