import SwiftUI

// MARK: - CustomRainbowDetailView
//
// Pushed when a user taps one of their own rainbows in the Rainbow
// list. Renders every card that matches the rainbow's criteria as
// a grid; owned cards display at full opacity, missing cards dim
// to 30% so the gap is obvious at a glance.
//
// Top: a header with the rainbow's name, criteria summary, and
// progress (X / Y, percent). Tapping a card pushes to the standard
// card detail. The toolbar Edit button opens the editor sheet.

struct CustomRainbowDetailView: View {
    @Environment(CardStore.self)          private var cardStore
    @Environment(CollectionStore.self)    private var collection
    @Environment(CustomRainbowStore.self) private var rainbowStore

    /// The rainbow id is the stable identity — we re-read the row
    /// from the store on each render so edits picked up via the
    /// editor sheet flow through automatically.
    let rainbowId: UUID

    @Binding var navigationPath: NavigationPath
    @State private var showingEditor = false

    private var rainbow: CustomRainbow? {
        rainbowStore.rainbows.first(where: { $0.id == rainbowId })
    }

    var body: some View {
        Group {
            if let rainbow {
                let cards   = matchingCards(for: rainbow)
                let owned   = ownedIds()
                let ownedN  = cards.filter { owned.contains($0.id) }.count

                ScrollView {
                    header(name: rainbow.name, summary: rainbow.criteria.summary,
                           owned: ownedN, total: cards.count)
                    if cards.isEmpty {
                        empty
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: Design.Spacing.sm), count: 3),
                            spacing: Design.Spacing.md
                        ) {
                            ForEach(cards, id: \.id) { card in
                                cell(card: card, isOwned: owned.contains(card.id))
                                    .onTapGesture { navigationPath.append(card.id) }
                            }
                        }
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.lg)
                    }
                }
                .scrollEdgeEffectStyle(.hard, for: .top)
            } else {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(rainbow?.name ?? "Custom Rainbow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(Design.Colors.nearBlack)
        .toolbar {
            if rainbow != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                    .accessibilityLabel("Edit rainbow")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let r = rainbow {
                CustomRainbowEditorSheet(existing: r)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(name: String, summary: String, owned: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(name)
                .font(Design.Fonts.display(20))
                .foregroundStyle(Design.Colors.textPrimary)
            if !summary.isEmpty {
                Text(summary)
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Text("\(owned) of \(total) collected")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Spacer()
                Text("\(percentLabel(owned: owned, total: total))")
                    .font(Design.Fonts.mono(15, weight: .bold))
                    .foregroundStyle(total > 0 && owned == total ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Colors.glass)
                    Capsule()
                        .fill(Design.Colors.bobaCyan)
                        .frame(width: proxy.size.width * progressFraction(owned: owned, total: total))
                }
            }
            .frame(height: 6)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.glassBorder).frame(height: 1)
        }
    }

    private var empty: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "rainbow")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.bobaCyan.opacity(0.6))
            Text("No cards match this rainbow's criteria")
                .font(Design.Fonts.display(15))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Tap the slider button to edit the filters.")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.top, Design.Spacing.xl)
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(card: Card, isOwned: Bool) -> some View {
        VStack(spacing: 4) {
            CardImageView(card: card, size: .thumb)
                .aspectRatio(5.0/7.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                .opacity(isOwned ? 1.0 : 0.3)
                .overlay {
                    if !isOwned {
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .stroke(Design.Colors.textMuted.opacity(0.3), lineWidth: 1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isOwned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .padding(4)
                    }
                }
            Text(card.hero.isEmpty ? card.name : card.hero)
                .font(Design.Fonts.mono(10, weight: .semibold))
                .foregroundStyle(isOwned ? Design.Colors.textPrimary : Design.Colors.textMuted)
                .lineLimit(1)
            Text(card.treatment ?? "")
                .font(Design.Fonts.mono(9))
                .foregroundStyle(Design.Colors.textMuted)
                .lineLimit(1)
        }
    }

    // MARK: - Data

    private func matchingCards(for rainbow: CustomRainbow) -> [Card] {
        cardStore.displayCards
            .filter { rainbow.criteria.matches($0) }
            .sorted { lhs, rhs in
                // Group by hero, then by card number — readable when the
                // rainbow spans multiple heroes.
                if lhs.hero != rhs.hero {
                    return lhs.hero.localizedCaseInsensitiveCompare(rhs.hero) == .orderedAscending
                }
                return lhs.cardNumber.localizedCaseInsensitiveCompare(rhs.cardNumber) == .orderedAscending
            }
    }
    private func ownedIds() -> Set<String> {
        Set(collection.userCards
                .filter { $0.designation.isOwned }
                .compactMap { $0.bobaId })
    }
    private func percentLabel(owned: Int, total: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int(((Double(owned) / Double(total)) * 100).rounded()))%"
    }
    private func progressFraction(owned: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(1.0, Double(owned) / Double(total)))
    }
}
