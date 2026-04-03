import SwiftUI

/// Inline navigation bar wordmark — "BOBA" in arena font + "Playbook" in display font.
/// Matches the brand identity established in the web app.
struct BOBAWordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("BOBA")
                .font(Design.Fonts.arena(22))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text(" Playbook")
                .font(Design.Fonts.arena(22))
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .accessibilityLabel("BOBA Playbook")
    }
}
