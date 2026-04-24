//
//  PracticeTopBar.swift
//  BOBAPlaybook
//
//  Fixed top bar: mode tabs, scoreboard pips, phase indicator, CPU info, exit.
//

import SwiftUI

struct PracticeTopBar: View {
    let store: PracticeStore
    let onExit: () -> Void
    /// Tap-handler for the CPU play count chip — opens the discard
    /// inspector. Optional so existing call sites stay valid.
    var onInspectCpuDiscard: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            modeTabs
                .padding(.leading, Design.Spacing.md)
            Spacer()
            scoreboard
            Spacer()
            trailing
                .padding(.trailing, Design.Spacing.md)
        }
        .frame(height: 44)
        .background(Design.Colors.surface.opacity(0.95))
        .overlay(Divider().background(Design.Colors.glass), alignment: .bottom)
    }

    // MARK: - Mode Tabs

    private var modeTabs: some View {
        HStack(spacing: 4) {
            ForEach(PracticeMode.allCases) { mode in
                let isSelected = store.mode == mode
                Button {
                    if store.matchOver { store.mode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(Design.Fonts.mono(10, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Design.Colors.nearBlack : Design.Colors.textMuted)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(isSelected ? Design.Colors.bobaOrange : Design.Colors.glass))
                }
                .buttonStyle(.plain)
                .disabled(!store.matchOver)
            }
        }
    }

    // MARK: - Scoreboard

    private var scoreboard: some View {
        HStack(spacing: 8) {
            Text("\(store.playerScore)")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Color(hex: "4CAF50"))
            battlePips
            Text("\(store.cpuScore)")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Color(hex: "C0392B"))
        }
        .tutorialTarget(.scoreboard)
    }

    private var battlePips: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(pipColor(for: i))
                    .frame(width: 10, height: 10)
                    .overlay(
                        i == store.currentBattle && !store.matchOver
                        ? Circle().strokeBorder(Design.Colors.bobaOrange, lineWidth: 2) : nil
                    )
            }
        }
    }

    private func pipColor(for index: Int) -> Color {
        guard index < store.battles.count else { return Design.Colors.glass }
        switch store.battles[index].result {
        case .win:  return Color(hex: "4CAF50")
        case .lose: return Color(hex: "C0392B")
        case .tie:  return Design.Colors.textMuted
        case nil:
            return index == store.currentBattle ? Design.Colors.bobaOrange.opacity(0.4) : Design.Colors.glass
        }
    }

    // MARK: - Trailing (Phase + CPU info + Exit)

    private var trailing: some View {
        HStack(spacing: Design.Spacing.md) {
            // CPU resources compact badge
            if store.mode.showHotDogs || store.mode.showPlays {
                HStack(spacing: 6) {
                    if store.mode.showBench {
                        Label("\(store.cpuBench.count)", systemImage: "person.2.fill")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Color(hex: "C0392B").opacity(0.7))
                    }
                    if store.mode.showHotDogs {
                        Text("\(store.cpuHotDogs) HD")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Color(hex: "4CAF50"))
                    }
                    if store.mode.showPlays {
                        // Tap to inspect CPU's discard pile (UX#8).
                        Button {
                            onInspectCpuDiscard?()
                        } label: {
                            Label("\(store.cpuPlaysRemaining)", systemImage: "rectangle.stack")
                                .font(Design.Fonts.mono(9))
                                .foregroundStyle(Design.Colors.bobaViolet)
                        }
                        .buttonStyle(.plain)
                        .disabled(onInspectCpuDiscard == nil)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Design.Colors.glass.opacity(0.5)))
            }

            // Phase indicator
            HStack(spacing: 6) {
                Image(systemName: store.phase.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.bobaOrange)
                Text(store.phase.rawValue.uppercased())
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            // Exit
            Button(action: onExit) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .buttonStyle(.plain)
        }
    }
}
