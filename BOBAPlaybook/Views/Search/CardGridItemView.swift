import SwiftUI

struct CardGridItemView: View {
    let card: Card

    var body: some View {
        ZStack(alignment: .bottom) {
            // Card image
            CardImageView(card: card, size: .thumb)
                .aspectRatio(3/4, contentMode: .fill)
                .clipped()

            // Bottom info strip
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(Design.Fonts.display(11))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if card.isSealed {
                    HStack(spacing: Design.Spacing.xs) {
                        Text(card.set.uppercased())
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Design.Colors.bobaOrange.opacity(0.15))
                                    .overlay(Capsule().strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 0.5))
                            )
                        Spacer()
                        if let msrp = card.msrp {
                            Text(Decimal(msrp), format: .currency(code: "USD"))
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                    }
                } else {
                    HStack(spacing: Design.Spacing.xs) {
                        // Element pill
                        Text(card.element)
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.element(card.element))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Design.Colors.element(card.element).opacity(0.15))
                                    .overlay(Capsule().strokeBorder(Design.Colors.element(card.element).opacity(0.4), lineWidth: 0.5))
                            )
                        Spacer()
                        // Power
                        if let power = card.power {
                            Text("\(power)")
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(Design.Colors.element(card.element))
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.sm)
            .background(
                LinearGradient(
                    colors: [.clear, Design.Colors.nearBlack.opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // Treatment ribbon (top-right)
            if let treatment = card.treatment, !treatment.isEmpty, treatment.lowercased() != "base set" {
                VStack {
                    HStack {
                        Spacer()
                        treatmentRibbon(treatment)
                    }
                    Spacer()
                }
                .padding(Design.Spacing.xs)
            }
        }
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .strokeBorder(
                    card.isSealed
                        ? Design.Colors.bobaOrange.opacity(0.30)
                        : Design.Colors.element(card.element).opacity(0.25),
                    lineWidth: 1
                )
        )
        .elementGlow(card.isSealed ? "NONE" : card.element)
    }

    @ViewBuilder
    private func treatmentRibbon(_ treatment: String) -> some View {
        let (color, label) = treatmentStyle(treatment)
        Text(label)
            .font(Design.Fonts.mono(7, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.85)))
    }

    private func treatmentStyle(_ treatment: String) -> (Color, String) {
        let t = treatment.lowercased()
        if t.contains("blizzard")     { return (Color(hex: "00BFFF"), "BLIZZARD") }
        if t.contains("superfoil")    { return (Color(hex: "FFD700"), "SUPERFOIL") }
        if t.contains("battlefoil")   { return (Color(hex: "FF4D00"), "BATTLEFOIL") }
        if t.contains("inspired ink") { return (Color(hex: "8B00FF"), "INK") }
        if t.contains("logofoil")     { return (Color(hex: "C0C0C0"), "LOGOFOIL") }
        if t.contains("blast")        { return (Color(hex: "FF4D00"), "BLAST") }
        if t.contains("paper")        { return (Color(hex: "8A9BB0"), "PAPER") }
        return (Color(hex: "FF4D00"), "SPECIAL")
    }
}
