import SwiftUI

// MARK: - AppIconOption + helpers
// SettingsView itself was folded into ProfileView (DESIGN.md §3.6 +
// per the v2.064 profile overhaul — settings are now Profile sections,
// not a separate destination). What remains here is the icon-option
// catalog used by Profile's Display section to render the App Icon
// Menu and to derive the user's accent color.

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

