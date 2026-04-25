import SwiftUI

struct StoreDetailSheet: View {
    let store: StoreLocation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    header
                    addressBlock
                    if let tel = store.telURL {
                        contactRow(icon: "phone.fill", label: store.phone) { openURL(tel) }
                    }
                    if let web = store.websiteURL {
                        contactRow(icon: "safari.fill", label: store.website) { openURL(web) }
                    }
                    if !store.email.isEmpty,
                       let mail = URL(string: "mailto:\(store.email)") {
                        contactRow(icon: "envelope.fill", label: store.email) { openURL(mail) }
                    }

                    directionsButtons
                        .padding(.top, Design.Spacing.sm)

                    if !store.lastVerifiedLabel.isEmpty {
                        Text(store.lastVerifiedLabel)
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.name)
                .font(Design.Fonts.display(22))
                .foregroundStyle(Design.Colors.textPrimary)
            if !store.address.city.isEmpty {
                Text("\(store.address.city), \(store.address.stateShort)")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
    }

    private var addressBlock: some View {
        Button {
            if let url = store.appleMapsURL { UIApplication.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.md) {
                iconCircle("mappin.and.ellipse", tint: Design.Colors.bobaOrange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.address.full.isEmpty
                         ? "\(store.address.street), \(store.address.city)"
                         : store.address.full)
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap to open in Maps")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
    }

    private func contactRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.md) {
                iconCircle(icon, tint: Design.Colors.bobaCyan)
                Text(label)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
    }

    private func iconCircle(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(tint.opacity(0.15))
                    .overlay(Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1))
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.md)
            .fill(Design.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
            )
    }

    private var directionsButtons: some View {
        VStack(spacing: Design.Spacing.sm) {
            if let url = store.appleMapsURL {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Open in Apple Maps")
                    }
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(Design.Colors.bobaOrange))
                }
                .buttonStyle(.plain)
            }
            if let url = store.googleMapsURL {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Image(systemName: "globe")
                        Text("Open in Google Maps")
                    }
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(Design.Colors.glass)
                        .overlay(Capsule().strokeBorder(Design.Colors.glassBorder, lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
