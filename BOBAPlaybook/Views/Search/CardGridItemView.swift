import SwiftUI

struct CardGridItemView: View {
    let card: Card

    var body: some View {
        ZStack(alignment: .bottom) {
            // Image layer is the canonical BOBACardCell primitive
            // per DESIGN.md §11.1 / §4.3. Find adds the type-specific
            // footer (element pill / play badge / hot dog) + treatment
            // ribbon as overlays composed below.
            BOBACardCell(card: card)

            // Bottom info strip
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
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
                } else if card.isHero {
                    HStack(spacing: Design.Spacing.xs) {
                        // Element pill — Hero cards only
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
                        if let power = card.power, power > 0 {
                            Text("\(power)")
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(Design.Colors.element(card.element))
                        }
                    }
                } else if card.isPlay {
                    HStack(spacing: Design.Spacing.xs) {
                        // Play type badge
                        Text(card.isBonusPlay == true ? "BONUS" : "PLAY")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(card.isBonusPlay == true ? Design.Colors.bobaCyan : Design.Colors.bobaViolet)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((card.isBonusPlay == true ? Design.Colors.bobaCyan : Design.Colors.bobaViolet).opacity(0.12))
                                    .overlay(Capsule().strokeBorder((card.isBonusPlay == true ? Design.Colors.bobaCyan : Design.Colors.bobaViolet).opacity(0.3), lineWidth: 0.5))
                            )
                        Spacer()
                        if let label = card.playCostLabel {
                            Text(label)
                                .font(Design.Fonts.mono(10, weight: .bold))
                                .foregroundStyle(card.playCost == 0 ? Color(hex: "7ecb82") : Design.Colors.bobaCyan)
                        }
                    }
                } else if card.isHotDog {
                    HStack(spacing: Design.Spacing.xs) {
                        Text("HOT DOG")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Color(hex: "7ecb82"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "4CAF50").opacity(0.12))
                                    .overlay(Capsule().strokeBorder(Color(hex: "4CAF50").opacity(0.3), lineWidth: 0.5))
                            )
                        Spacer()
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
        // Re-clip the ZStack so the footer gradient + treatment ribbon
        // overlays follow BOBACardCell's rounded corners. BOBACardCell
        // owns the border + element glow; we just need the outer mask
        // here for the overlays.
        .clipShape(RoundedRectangle(cornerRadius: BOBACardCell.cornerRadius))
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
        if t.contains("colosseum")    { return (Color(hex: "A0522D"), "COLOSSEUM") }
        if t.contains("battlefoil")   { return (Color(hex: "FF4D00"), "BATTLEFOIL") }
        if t.contains("inspired ink") { return (Color(hex: "8B00FF"), "INK") }
        if t.contains("logofoil")     { return (Color(hex: "C0C0C0"), "LOGOFOIL") }
        if t.contains("blast")        { return (Color(hex: "FF4D00"), "BLAST") }
        if t.contains("paper")        { return (Color(hex: "8A9BB0"), "PAPER") }
        return (Color(hex: "FF4D00"), "SPECIAL")
    }
}
