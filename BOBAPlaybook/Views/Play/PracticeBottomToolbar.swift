//
//  PracticeBottomToolbar.swift
//  BOBAPlaybook
//
//  Compact bottom toolbar for practice battle: deck count, bench toggle,
//  plays toggle, hot dog counter, and phase-appropriate action buttons.
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

            // Action buttons
            actionButtons
                .padding(.trailing, Design.Spacing.md)
                .tutorialTarget(.advance)
        }
        .frame(height: 50)
        .background(Design.Colors.surface.opacity(0.95))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
    }

    // MARK: - Hero Deck Stack

    private var heroStack: some View {
        VStack(spacing: 2) {
            Image(systemName: "figure.fencing")
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
        .tutorialTarget(.bench)
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
        .tutorialTarget(.plays)
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

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Group {
            switch store.phase {
            case .reveal:
                if store.battles[store.currentBattle].isRevealed {
                    // Cards already revealed — user sees matchup, press to enter play phase
                    Button("PLAY PHASE →", action: onAction)
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaCyan))
                } else {
                    Button("REVEAL", action: onAction)
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
                }

            case .sub:
                if store.mode.showBench {
                    HStack(spacing: 6) {
                        Button {
                            // Open bench panel for player to choose subs
                            // CPU sub happens automatically when advancing to reveal
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showBenchPanel = true
                                showPlaysPanel = false
                            }
                        } label: {
                            Text("CHOOSE SUBS")
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(Design.Colors.nearBlack)
                                .padding(.horizontal, 8)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.bobaOrange))
                        }
                        .buttonStyle(.plain)

                        Button {
                            // Skip subs — don't substitute, advance to reveal
                            onAction()
                        } label: {
                            Text("SKIP SUBS")
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button("NEXT", action: onAction)
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
                }

            case .play:
                if store.mode.showPlays {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPlaysPanel = true
                                showBenchPanel = false
                            }
                        } label: {
                            Text("CHOOSE PLAYS")
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(Design.Colors.nearBlack)
                                .padding(.horizontal, 8)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.bobaCyan))
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.playerPassPlays()
                        } label: {
                            Text("END TURN")
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button("NEXT", action: onAction)
                        .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
                }

            case .resolution:
                // Single button now chains through cleanup to the next
                // battle (see PracticeStore.advancePhase). Label reflects
                // that — no more double-tap between battles.
                Button("NEXT BATTLE", action: onAction)
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
            case .cleanup:
                // Only reachable from a mid-cleanup restore of an old
                // saved draft. Keep a neutral label.
                Button("NEXT BATTLE", action: onAction)
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
            case .matchOver:
                Button("DONE", action: onAction)
                    .buttonStyle(PracticeActionButtonStyle(color: Design.Colors.bobaOrange))
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.glass)
            .frame(width: 1, height: 30)
    }
}
