import SwiftUI

/// Bottom-of-screen chip that slides up when a card is detected.
/// Tap to open card detail. Swipe down to dismiss.
struct ScanDetectionChipView: View {
    let card: Card
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Drag handle — visual cue for swipe-down dismiss
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 32, height: 3)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                HStack(spacing: Design.Spacing.md) {

                    // Thumbnail
                    CardImageView(card: card, size: .thumb)
                        .frame(width: 44, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                        .elementGlow(card.element)

                    // Card info
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        Text(card.name)
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(1)
                        Text(card.cardNumber)
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.bobaOrange)
                        if let power = card.power {
                            Text("PWR \(power)")
                                .font(Design.Fonts.mono(10))
                                .foregroundStyle(Design.Colors.element(card.element))
                        }
                    }

                    Spacer()

                    // Tap hint
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Design.Colors.textMuted)
                        Text("VIEW")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1)
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.lg)
                    .fill(Design.Colors.surface.opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.lg)
                            .strokeBorder(
                                Design.Colors.element(card.element).opacity(0.5),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 4)
            )
            .padding(.horizontal, Design.Spacing.lg)
        }
        .buttonStyle(.plain)
    }
}
