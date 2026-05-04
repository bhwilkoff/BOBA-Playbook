import SwiftUI

// MARK: - SettingsView
// App customization: icon color, and future preferences.

struct SettingsView: View {
    @AppStorage("selectedIconName") private var selectedIconName: String = "default"
    @State private var hints = HintsManager.shared
    @State private var walkthroughs = WalkthroughsManager.shared
    /// Brief banner shown after the Reset button fires. Without this
    /// the action looks silent — hints have contextual triggers
    /// (substitution phase, deck builder, etc.) so the visible
    /// effect doesn't surface until the coach is back in that
    /// context. The banner closes that perception gap.
    @State private var resetConfirmation: String?
    @State private var walkthroughResetConfirmation: String?

    var body: some View {
        List {
            Section {
                Text("Choose a weapon color for the app icon. The change takes effect immediately on your home screen.")
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

            // Practice-mode hints — first-run-only contextual tips
            // (substitution positioning, bonus play ceiling, etc.)
            // The toggle silences the entire system; "Reset" replays
            // every hint as if the coach had never dismissed any.
            Section {
                Toggle(isOn: Binding(
                    get: { hints.hintsEnabled },
                    set: { hints.hintsEnabled = $0 }
                )) {
                    Text("Show first-run hints")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .tint(Design.Colors.bobaCyan)
                Button("Reset hints") {
                    hints.resetAll()
                    let count = HintID.allCases.count
                    resetConfirmation = "Cleared \(count) hint dismissals. Tips will reappear at their trigger moments."
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        resetConfirmation = nil
                    }
                }
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.bobaOrange)
                if let msg = resetConfirmation {
                    Text(msg)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .transition(.opacity)
                }
            } header: {
                Text("PRACTICE HINTS")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            } footer: {
                Text("Lightbulb tips appear at key moments — substitution positioning, deck composition, bonus-play limits. Each one shows only once per device unless you reset them here.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .listRowBackground(Design.Colors.surface)

            // Feature walkthroughs — anchored multi-step first-visit
            // tutorials per DESIGN.md §6.10. Distinct from the
            // Practice Hints above (single-tip banners). The toggle
            // silences the entire system; "Reset" replays every
            // walkthrough as if the user had never seen any.
            Section {
                Toggle(isOn: Binding(
                    get: { walkthroughs.walkthroughsEnabled },
                    set: { walkthroughs.walkthroughsEnabled = $0 }
                )) {
                    Text("Show walkthroughs on first visit")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .tint(Design.Colors.bobaCyan)
                Button("Reset walkthroughs") {
                    walkthroughs.resetAll()
                    let count = WalkthroughID.allCases.count
                    walkthroughResetConfirmation = "Cleared \(count) walkthrough dismissals. Each will fire again on next visit."
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        walkthroughResetConfirmation = nil
                    }
                }
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.bobaOrange)
                if let msg = walkthroughResetConfirmation {
                    Text(msg)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .transition(.opacity)
                }
            } header: {
                Text("FEATURE WALKTHROUGHS")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            } footer: {
                Text("Anchored multi-step tutorials that fire the first time you open a tab or feature. Each shows once per device unless you reset them here. Re-launchable from any tab's overflow menu via 'Show walkthrough'.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            .listRowBackground(Design.Colors.surface)
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
                    Image(option.previewAssetName)
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

    // Loads from a *-Preview.imageset in Assets.xcassets (appiconsets aren't UIImage-accessible)
    var previewAssetName: String {
        iconName == "default" ? "AppIcon-Fire-Preview" : "\(iconName)-Preview"
    }

    static let all: [AppIconOption] = [
        AppIconOption(id: "default", label: "Fire",  iconName: "default",      color: Design.Colors.bobaOrange),
        AppIconOption(id: "ice",     label: "Ice",   iconName: "AppIcon-Ice",   color: Color(hex: "#00BFFF")),
        AppIconOption(id: "hex",     label: "Hex",   iconName: "AppIcon-Hex",   color: Design.Colors.bobaViolet),
        AppIconOption(id: "steel",   label: "Steel", iconName: "AppIcon-Steel", color: Color(hex: "#8A9BB0")),
        AppIconOption(id: "brawl",   label: "Brawl", iconName: "AppIcon-Brawl", color: Color(hex: "#C0392B")),
        AppIconOption(id: "glow",    label: "Glow",  iconName: "AppIcon-Glow",  color: Color(hex: "#FFD700")),
        AppIconOption(id: "gum",     label: "Gum",   iconName: "AppIcon-Gum",   color: Color(hex: "#FF69B4")),
        AppIconOption(id: "super",   label: "Super", iconName: "AppIcon-Super", color: Color(hex: "#FF00FF")),
    ]

    /// Resolves the currently-selected icon's accent color. Used by any
    /// accent UI that should mirror the user's chosen app-icon — e.g.
    /// the Find-tab profile icon. Falls back to the default Fire color
    /// if the stored name isn't found (e.g. after deleting an alt icon).
    static func currentColor(for storedName: String) -> Color {
        all.first(where: { $0.iconName == storedName })?.color
            ?? all.first!.color
    }
}

