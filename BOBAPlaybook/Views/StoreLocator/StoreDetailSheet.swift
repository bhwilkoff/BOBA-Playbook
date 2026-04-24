import SwiftUI

struct StoreDetailSheet: View {
    let store: StoreLocation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    header
                    Divider().overlay(Design.Colors.glassBorder)
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

                    Divider().overlay(Design.Colors.glassBorder)

                    directionsButtons

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
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.bobaOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.address.full.isEmpty
                         ? "\(store.address.street), \(store.address.city)"
                         : store.address.full)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap to open in Maps")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func contactRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(width: 24)
                Text(label)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .padding(.vertical, Design.Spacing.xs)
        }
        .buttonStyle(.plain)
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
