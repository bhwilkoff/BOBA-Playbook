import SwiftUI

struct StoreListView: View {
    let stores: [StoreLocation]
    let distanceLabel: (StoreLocation) -> String
    let onTap: (StoreLocation) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Design.Spacing.xs) {
                ForEach(stores) { s in
                    Button { onTap(s) } label: { row(s) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
    }

    private func row(_ s: StoreLocation) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.md) {
            BOBAPinMarker(size: 26)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                Text(cityStateLine(s))
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                if !s.address.street.isEmpty {
                    Text(s.address.street)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                let d = distanceLabel(s)
                if !d.isEmpty {
                    Text(d)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
    }

    private func cityStateLine(_ s: StoreLocation) -> String {
        let city = s.address.city
        let state = s.address.stateShort
        if !city.isEmpty && !state.isEmpty { return "\(city), \(state)" }
        if !city.isEmpty { return city }
        if !state.isEmpty { return state }
        return s.address.full
    }
}
