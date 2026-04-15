//
//  PracticeBenchPanel.swift
//  BOBAPlaybook
//
//  Slide-up overlay panel showing the player's hero bench.
//  Larger cards (72x100) for legibility.
//

import SwiftUI

struct PracticeBenchPanel: View {
    let store: PracticeStore
    @Binding var selectedBenchIdx: Int?
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: Design.Spacing.sm) {
            // Header
            HStack {
                Text("YOUR BENCH")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                if store.phase == .sub && !store.playerSubstituted {
                    Button {
                        if let idx = selectedBenchIdx, store.playerHotDogs >= 2 {
                            store.playerSubstitute(benchIndex: idx)
                            selectedBenchIdx = nil
                        }
                    } label: {
                        Text("SUBSTITUTE (2 HD)")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(selectedBenchIdx != nil && store.playerHotDogs >= 2 ? Design.Colors.nearBlack : Design.Colors.textMuted)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(selectedBenchIdx != nil && store.playerHotDogs >= 2 ? Design.Colors.bobaOrange : Design.Colors.glass))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedBenchIdx == nil || store.playerHotDogs < 2)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Bench cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(store.playerBench.enumerated()), id: \.offset) { idx, card in
                        Button {
                            guard store.phase == .sub, !store.playerSubstituted else { return }
                            selectedBenchIdx = selectedBenchIdx == idx ? nil : idx
                        } label: {
                            benchCardLarge(card: card, selected: selectedBenchIdx == idx)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.phase != .sub || store.playerSubstituted)
                    }
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surface.opacity(0.98))
        .overlay(Divider().background(Design.Colors.glass), alignment: .top)
        .onChange(of: store.phase) { _, _ in selectedBenchIdx = nil }
    }

    // MARK: - Large Bench Card

    private func benchCardLarge(card: Card, selected: Bool) -> some View {
        let active = store.phase == .sub && !store.playerSubstituted
        let canAfford = store.playerHotDogs >= 2
        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let file = card.imageFile, !file.isEmpty {
                        CachedAsyncCardImage(url: CDN.thumb(for: file), contentMode: .fill)
                    } else {
                        cardPlaceholder(card: card)
                    }
                }
                .frame(width: 72, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                        selected ? Design.Colors.bobaCyan : (active ? Design.Colors.bobaOrange.opacity(0.5) : Design.Colors.element(card.element).opacity(0.3)),
                        lineWidth: selected ? 3 : (active ? 2 : 1)
                    )
                )

                // Power badge at bottom
                Text("\(card.power ?? 0)")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 4)
            }

            Text(card.hero.isEmpty ? card.name : card.hero)
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(selected ? Design.Colors.bobaCyan : Design.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: 72)
        }
        .opacity(active && !canAfford ? 0.35 : 1)
        .overlay {
            if active && !canAfford {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 72, height: 100)
                    .overlay(
                        Text("2 HD")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Color(hex: "C0392B"))
                    )
            }
        }
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
