import SwiftUI

/// Bottom-of-screen chip that slides up when a card is detected.
///
/// Two modes:
///   • Multi-scan (and show-mode): minimal chip — tap opens detail.
///     The card is already queued by ScanView.commitDetected and will
///     auto-dismiss after a short timer.
///   • Single-scan: chip expands to include a quantity stepper + a
///     "Save N to Collection" button so coaches can record N copies
///     of the same card without re-scanning. Beta-tester ask:
///     "5 silver battlefoils — scan once, enter 5, save 5."
struct ScanDetectionChipView: View {
    let card: Card
    /// True when the scanner is in single-scan mode — drives the
    /// quick-save UI. False in multi/show mode (those modes route
    /// through the queue, which has its own quantity stepper).
    let isSingleMode: Bool
    /// Called when the user taps the chip body / VIEW affordance.
    /// Opens CardDetailView in ScanView.
    let onTap: () -> Void
    /// Called only in single-scan mode when the user taps "Add".
    /// Receives the chosen quantity (1…99).
    let onQuickSave: (Int) -> Void

    @State private var quantity: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle — visual cue for swipe-down dismiss.
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 32, height: 3)
                .padding(.top, 8)
                .padding(.bottom, 6)

            HStack(spacing: Design.Spacing.md) {
                // Thumb + name → tap opens detail (existing behavior).
                Button(action: onTap) {
                    HStack(spacing: Design.Spacing.md) {
                        CardImageView(card: card, size: .thumb)
                            .frame(width: 44, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                            .elementGlow(card.element)

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
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isSingleMode {
                    quantityStepper
                } else {
                    // Multi/show mode: keep the existing minimal chip.
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
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.bottom, isSingleMode ? Design.Spacing.sm : Design.Spacing.md)

            if isSingleMode {
                Button {
                    onQuickSave(quantity)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(quantity == 1
                             ? "Add to Collection"
                             : "Add \(quantity) to Collection")
                            .font(Design.Fonts.mono(13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaOrange)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.md)
            }
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
        // Reset quantity each time a new card is detected (the parent
        // re-creates the view when `card` changes).
        .onChange(of: card.id) { _, _ in quantity = 1 }
    }

    private var quantityStepper: some View {
        HStack(spacing: 4) {
            Button { quantity = max(1, quantity - 1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(quantity <= 1
                                     ? Design.Colors.textMuted
                                     : Design.Colors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(quantity <= 1)

            Text("\(quantity)")
                .font(Design.Fonts.mono(15, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .frame(minWidth: 28, alignment: .center)
                .monospacedDigit()

            Button { quantity = min(99, quantity + 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(quantity >= 99
                                     ? Design.Colors.textMuted
                                     : Design.Colors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(quantity >= 99)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quantity \(quantity)")
    }
}
