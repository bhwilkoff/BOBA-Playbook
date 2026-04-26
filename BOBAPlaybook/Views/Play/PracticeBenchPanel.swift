//
//  PracticeBenchPanel.swift
//  BOBAPlaybook
//
//  Slide-up overlay panel showing the player's hero bench.
//  Tap a card to see details; during the sub phase the SUBSTITUTE button
//  swaps the selected bench hero into the active battle.
//

import SwiftUI

struct PracticeBenchPanel: View {
    let store: PracticeStore
    @Binding var selectedBenchIdx: Int?
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Header
            //
            // (Substitution-positioning hint moved out of this panel —
            // it was pushing the bench thumbnails + detail area off
            // the bottom of the screen and forcing coaches to dismiss
            // it before they could substitute. The hint now floats as
            // a top overlay on PracticeView when applicable.)
            HStack {
                Text("YOUR BENCH")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text("(\(store.playerBench.count))")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Bench cards — compact thumbnails so the panel's detail
            // area below has room to render all of a card's info
            // without clipping. Mirrors PracticePlaysPanel.
            if store.playerBench.isEmpty {
                Text("No heroes on bench")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(.vertical, Design.Spacing.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(store.playerBench.enumerated()), id: \.offset) { idx, card in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedBenchIdx = selectedBenchIdx == idx ? nil : idx
                                }
                            } label: {
                                benchCardLarge(card: card, selected: selectedBenchIdx == idx)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Selected card detail — rigid container that sizes to
            // its content. Same treatment as PracticePlaysPanel:
            // dropped the fixed-height frame because clipping the
            // bottom of the detail (which got worse once the active
            // -effects band ate vertical space) hid critical info.
            // We trade thumbnail size (72×100 → 60×84) and panel
            // padding (md → sm vertical) so the panel hugs its
            // natural height and never clips at the bottom.
            if let idx = selectedBenchIdx, idx < store.playerBench.count {
                cardDetail(card: store.playerBench[idx], idx: idx)
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface.opacity(0.98))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
        .onChange(of: store.phase) { _, _ in selectedBenchIdx = nil }
    }

    // MARK: - Large Bench Card

    private func benchCardLarge(card: Card, selected: Bool) -> some View {
        let active = store.phase == .sub && !store.playerSubstituted
        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let file = card.imageFile, !file.isEmpty {
                        CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                    } else {
                        cardPlaceholder(card: card)
                    }
                }
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                        selected ? Design.Colors.bobaCyan : (active ? Design.Colors.bobaOrange.opacity(0.5) : Design.Colors.element(card.element).opacity(0.3)),
                        lineWidth: selected ? 3 : (active ? 2 : 1)
                    )
                )

                // Power badge at bottom
                Text("\(card.power ?? 0)")
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 3)
            }

            Text(card.hero.isEmpty ? card.name : card.hero)
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(selected ? Design.Colors.bobaCyan : Design.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: 60)
        }
    }

    // MARK: - Card Detail

    private func cardDetail(card: Card, idx: Int) -> some View {
        let canAfford = store.playerHotDogs >= 2
        let isSubPhase = store.phase == .sub && !store.playerSubstituted

        return HStack(alignment: .top, spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                // Name + power chip on the same row to save a line.
                HStack(spacing: 8) {
                    Text(card.hero.isEmpty ? card.name : card.hero)
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                    Text("\(card.power ?? 0) PW")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Design.Colors.bobaOrange))
                }

                HStack(spacing: 8) {
                    Text(card.element)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.element(card.element))
                    if let t = card.treatment, !t.isEmpty {
                        Text(t)
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(1)
                    }
                }

                if let athlete = card.athleteInspiration, !athlete.isEmpty {
                    Text("Inspired by \(athlete)")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSubPhase {
                Button {
                    guard canAfford else { return }
                    store.playerSubstitute(benchIndex: idx)
                    selectedBenchIdx = nil
                } label: {
                    Text(canAfford ? "SUB\n2 HD" : "NEED\n2 HD")
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(canAfford ? Design.Colors.nearBlack : Design.Colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .frame(width: 76, height: 48)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(canAfford ? Design.Colors.bobaOrange : Design.Colors.glass))
                }
                .buttonStyle(.plain)
                .disabled(!canAfford)
            }
        }
        .padding(Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.glass))
    }

    private func cardPlaceholder(card: Card) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Design.Colors.element(card.element).opacity(0.2))
            .overlay(
                Text(String(card.hero.prefix(3)).uppercased())
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.element(card.element).opacity(0.6))
            )
    }
}
