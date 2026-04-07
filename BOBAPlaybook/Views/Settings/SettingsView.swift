import SwiftUI

// MARK: - SettingsView
// App customization: icon color, and future preferences.

struct SettingsView: View {
    @AppStorage("selectedIconName") private var selectedIconName: String = "default"

    var body: some View {
        List {
            Section {
                Text("Choose an element color for the app icon. The change takes effect immediately on your home screen.")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textMuted)
                    .listRowBackground(Design.Colors.surface)
            } header: {
                Text("APP ICON")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                    ForEach(AppIconOption.all) { option in
                        IconOptionCell(option: option, isSelected: selectedIconName == option.iconName) {
                            applyIcon(option)
                        }
                    }
                }
                .padding(.vertical, Design.Spacing.sm)
            }
            .listRowBackground(Design.Colors.surface)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func applyIcon(_ option: AppIconOption) {
        let name: String? = option.iconName == "default" ? nil : option.iconName
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil {
                selectedIconName = option.iconName
            }
        }
    }
}

// MARK: - Icon option cell

private struct IconOptionCell: View {
    let option: AppIconOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black)
                        .frame(width: 60, height: 60)
                    Image(uiImage: option.previewImage)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(option.color, lineWidth: 3)
                            .frame(width: 60, height: 60)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white, option.color)
                            .offset(x: 20, y: -20)
                    }
                }
                Text(option.label)
                    .font(Design.Fonts.mono(10, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? option.color : Design.Colors.textMuted)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AppIconOption

struct AppIconOption: Identifiable {
    let id: String
    let label: String
    let iconName: String   // "default" or the CFBundleAlternateIcons key
    let color: Color
    let previewImageName: String  // matches the .appiconset name in Assets.xcassets

    var previewImage: UIImage {
        if iconName == "default" {
            return UIImage(named: "AppIcon") ?? UIImage()
        }
        return UIImage(named: previewImageName) ?? UIImage()
    }

    static let all: [AppIconOption] = [
        AppIconOption(id: "default", label: "Fire",  iconName: "default",      color: Design.Colors.bobaOrange, previewImageName: ""),
        AppIconOption(id: "ice",     label: "Ice",   iconName: "AppIcon-Ice",   color: Color(hex: "#00BFFF"),    previewImageName: "AppIcon-Ice"),
        AppIconOption(id: "hex",     label: "Hex",   iconName: "AppIcon-Hex",   color: Design.Colors.bobaViolet, previewImageName: "AppIcon-Hex"),
        AppIconOption(id: "steel",   label: "Steel", iconName: "AppIcon-Steel", color: Color(hex: "#8A9BB0"),    previewImageName: "AppIcon-Steel"),
        AppIconOption(id: "brawl",   label: "Brawl", iconName: "AppIcon-Brawl", color: Color(hex: "#C0392B"),    previewImageName: "AppIcon-Brawl"),
        AppIconOption(id: "glow",    label: "Glow",  iconName: "AppIcon-Glow",  color: Color(hex: "#FFD700"),    previewImageName: "AppIcon-Glow"),
        AppIconOption(id: "gum",     label: "Gum",   iconName: "AppIcon-Gum",   color: Color(hex: "#FF69B4"),    previewImageName: "AppIcon-Gum"),
        AppIconOption(id: "super",   label: "Super", iconName: "AppIcon-Super", color: Color(hex: "#FF00FF"),    previewImageName: "AppIcon-Super"),
    ]
}

