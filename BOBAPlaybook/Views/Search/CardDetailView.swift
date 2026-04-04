import SwiftUI

struct CardDetailView: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection

    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0
    @State private var showingAddSheet = false
    @State private var showingSignIn = false

    private var effectiveScale: CGFloat { (scale * pinchDelta).clamped(to: 1...6) }

    private var collectionStatusIcon: String? {
        if collection.isOwned(card.cardNumber) { return "checkmark.circle.fill" }
        if collection.isWanted(card.cardNumber) { return "star.fill" }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    artPanel
                    infoPanel
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                ToolbarItem(placement: .principal) {
                    Text(card.name)
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if auth.isAuthenticated { showingAddSheet = true }
                        else { showingSignIn = true }
                    } label: {
                        if let icon = collectionStatusIcon {
                            Image(systemName: icon)
                                .foregroundStyle(collection.isOwned(card.cardNumber) ? .green : Design.Colors.bobaOrange)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAddSheet) {
                AddToCollectionSheet(card: card)
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView()
            }
        }
    }

    // MARK: - Art panel
    private var artPanel: some View {
        ZStack {
            // Element gradient background
            LinearGradient(
                colors: [
                    Design.Colors.element(card.element).opacity(0.25),
                    Design.Colors.nearBlack
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 420)

            CardImageView(card: card, size: .full)
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .scaleEffect(effectiveScale)
                .offset(
                    x: offset.width + (scale > 1 ? dragDelta.width : 0),
                    y: offset.height + (scale > 1 ? dragDelta.height : 0)
                )
                .clipped()
                .gesture(
                    MagnificationGesture()
                        .updating($pinchDelta) { value, state, _ in state = value }
                        .onEnded { value in
                            scale = (scale * value).clamped(to: 1...6)
                            if scale == 1 { offset = .zero }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragDelta) { value, state, _ in
                            if scale > 1 { state = value.translation }
                        }
                        .onEnded { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width:  offset.width  + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1 { scale = 1.0; offset = .zero }
                        else         { scale = 2.5 }
                    }
                }

            // Zoom hint
            if scale == 1 {
                VStack {
                    Spacer()
                    Text("pinch or double-tap to zoom")
                        .font(Design.Fonts.mono(9))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(.bottom, 8)
                }
                .frame(height: 380)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Info panel
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {

            // Name + badges row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text(card.name)
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text(card.hero)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                Spacer()
                if let power = card.power {
                    VStack(spacing: 0) {
                        Text("\(power)")
                            .font(Design.Fonts.arena(36))
                            .foregroundStyle(Design.Colors.element(card.element))
                        Text("POWER")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                    }
                }
            }

            // Badge row
            HStack(spacing: Design.Spacing.sm) {
                elementBadge
                if let treatment = card.treatment, !treatment.isEmpty {
                    treatmentBadge(treatment)
                }
                setBadge
            }

            Divider().background(Design.Colors.glassBorder)

            // Stats grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Design.Spacing.sm
            ) {
                statCell(label: "Card #",   value: card.cardNumber)
                statCell(label: "Element",  value: card.element, color: Design.Colors.element(card.element))
                statCell(label: "Set",      value: card.set)
                statCell(label: "Type",     value: card.cardType)
                if let sub = card.subSet {
                    statCell(label: "Sub-set", value: sub)
                }
                if let playCost = card.playCost {
                    statCell(label: "Play Cost", value: "\(playCost)")
                }
            }

            // Play ability
            if let ability = card.playAbility, !ability.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("PLAY ABILITY")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    Text(ability)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.glass)
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                )
            }

            // Athlete inspiration
            if let athlete = card.athleteInspiration, !athlete.isEmpty {
                HStack(spacing: Design.Spacing.sm) {
                    Rectangle()
                        .fill(Design.Colors.element(card.element))
                        .frame(width: 3)
                        .cornerRadius(2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INSPIRED BY")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        Text(athlete)
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    if card.isInspiredInk {
                        Spacer()
                        Text("INSPIRED INK")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaViolet)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Design.Colors.bobaViolet.opacity(0.15))
                                .overlay(Capsule().strokeBorder(Design.Colors.bobaViolet.opacity(0.4), lineWidth: 0.5)))
                    }
                }
            }
        }
        .padding(Design.Spacing.lg)
    }

    // MARK: - Sub-components
    private var elementBadge: some View {
        Text(card.element)
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.element(card.element))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.element(card.element).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.element(card.element).opacity(0.45), lineWidth: 1))
            )
    }

    private var setBadge: some View {
        Text(card.set.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.glass)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            )
    }

    private func treatmentBadge(_ treatment: String) -> some View {
        Text(treatment.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.bobaOrange.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
            )
    }

    private func statCell(label: String, value: String, color: Color = Design.Colors.textSecondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.2)
            Text(value)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.surface2)
        )
    }
}

// MARK: - Comparable clamp
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
