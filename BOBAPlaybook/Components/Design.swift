import SwiftUI

// MARK: - Design Tokens
// Matches the web design system in css/styles.css

enum Design {

    // MARK: Colors
    enum Colors {
        static let bobaOrange   = Color(hex: "FF4D00")
        static let bobaCyan     = Color(hex: "00F5FF")
        static let bobaViolet   = Color(hex: "8B00FF")
        static let nearBlack    = Color(hex: "080810")
        static let surface      = Color(hex: "0F0F1A")
        static let surface2     = Color(hex: "16162A")
        static let textPrimary  = Color.white
        static let textSecondary = Color(white: 1, opacity: 0.6)
        static let textMuted    = Color(white: 1, opacity: 0.35)
        static let glass        = Color(white: 1, opacity: 0.08)
        static let glassBorder  = Color(white: 1, opacity: 0.15)

        static func element(_ name: String) -> Color {
            switch name.uppercased() {
            case "FIRE":  return Color(hex: "FF4D00")
            case "ICE":   return Color(hex: "00BFFF")
            case "HEX":   return Color(hex: "8B00FF")
            case "STEEL": return Color(hex: "8A9BB0")
            case "BRAWL": return Color(hex: "C0392B")
            case "GLOW":  return Color(hex: "FFD700")
            case "GUM":   return Color(hex: "FF69B4")
            case "SUPER": return Color(hex: "FF00FF")
            default:      return Color(hex: "666680")
            }
        }
    }

    // MARK: Fonts
    // Custom fonts must be added to the bundle and declared in Info.plist under
    // "Fonts provided by application". Falls back to system fonts if not found.
    enum Fonts {
        /// Bebas Neue — wordmark/arena marquee identity
        static func arena(_ size: CGFloat) -> Font {
            Font.custom("BebasNeue-Regular", size: size, relativeTo: .title)
        }
        /// Russo One — display headings, card names, nav labels
        static func display(_ size: CGFloat) -> Font {
            Font.custom("RussoOne-Regular", size: size, relativeTo: .headline)
        }
        /// Chakra Petch — stats, data labels, numbers, body text
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            let name = weight == .bold ? "ChakraPetch-Bold" : "ChakraPetch-Regular"
            return Font.custom(name, size: size, relativeTo: .caption)
        }
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radius
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
    }
}

// MARK: - Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Element glow modifier
struct ElementGlow: ViewModifier {
    let element: String
    func body(content: Content) -> some View {
        content.shadow(color: Design.Colors.element(element).opacity(0.55), radius: 8, x: 0, y: 0)
    }
}

extension View {
    func elementGlow(_ element: String) -> some View {
        modifier(ElementGlow(element: element))
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - First-run contextual hints (handoff §7)
// ════════════════════════════════════════════════════════════════
//
// Inlined here rather than living in a standalone HintBanner.swift —
// Xcode's file-system-synchronized group occasionally fails to pick
// up newly-added files in this project even after a Clean Build.
// Co-locating with Design.swift (which is already on the compile
// manifest) sidesteps the issue with no behavior change.

enum HintID: String, CaseIterable {
    /// Surfaces inside the bench panel during the first Sub phase.
    case substitutionPositioning = "hint.substitution_positioning"
    /// Surfaces inside the deck builder when bonus-play count reaches 7.
    case bonusPlayCeiling        = "hint.bonus_play_ceiling"
    /// Surfaces inside the deck builder on first build.
    case deckCompositionTriad    = "hint.deck_composition_triad"
    /// Surfaces when a play with cost ≥3 is added — coaches use the
    /// "10-points-per-HD" heuristic.
    case hdValueHeuristic        = "hint.hd_value_heuristic"
}

@Observable
final class HintsManager {
    static let shared = HintsManager()

    /// Master toggle — when false, no hints render. Lets coaches
    /// silence the entire system from Settings. Stored property
    /// (not computed) so SwiftUI's `@Observable` tracking actually
    /// fires when the value changes; UserDefaults is the durable
    /// mirror.
    var hintsEnabled: Bool {
        didSet { UserDefaults.standard.set(hintsEnabled, forKey: "hints.enabled") }
    }

    /// Dismissed hint IDs. Tracked stored property — reads from
    /// `body` register a SwiftUI dependency, so toggling dismissal
    /// re-renders any HintBanner currently on screen. Without this,
    /// the X button updated UserDefaults but the view never knew.
    private(set) var dismissedIDs: Set<String>

    init() {
        let dflt = UserDefaults.standard
        // Default to DISABLED when the key has never been written.
        // Coaches who want the hint system can flip it on from
        // Settings; making them opt in keeps the practice mat
        // uncluttered for the common case (and stops banners from
        // pushing actionable controls off-screen on small phones).
        self.hintsEnabled = dflt.object(forKey: "hints.enabled") as? Bool ?? false
        var initial: Set<String> = []
        for id in HintID.allCases where dflt.bool(forKey: id.rawValue) {
            initial.insert(id.rawValue)
        }
        self.dismissedIDs = initial
    }

    func isDismissed(_ id: HintID) -> Bool {
        dismissedIDs.contains(id.rawValue)
    }

    func dismiss(_ id: HintID) {
        UserDefaults.standard.set(true, forKey: id.rawValue)
        dismissedIDs.insert(id.rawValue)
    }

    func shouldShow(_ id: HintID) -> Bool {
        hintsEnabled && !isDismissed(id)
    }

    func resetAll() {
        for id in HintID.allCases {
            UserDefaults.standard.removeObject(forKey: id.rawValue)
        }
        dismissedIDs.removeAll()
    }
}

/// Inline contextual hint card. Renders only when the hint hasn't
/// been dismissed AND the global toggle is on. Self-dismissing — tap
/// the X to mark this hint as seen forever (or until Settings reset).
struct HintBanner: View {
    let id: HintID
    let title: String
    /// Renamed from `body` to avoid colliding with SwiftUI's body.
    let message: String
    @State private var hints = HintsManager.shared

    @ViewBuilder
    var body: some View {
        if hints.shouldShow(id) {
            bannerContent
        }
    }

    private var bannerContent: some View {
        let row = HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "FFD700"))
            textStack
            Spacer(minLength: 0)
            dismissButton
        }
        return row
            .padding(Design.Spacing.sm)
            .background(bannerBackground)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Color(hex: "FFD700"))
                .tracking(0.6)
            Text(message)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.sm)
            .fill(Color(hex: "FFD700").opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .strokeBorder(Color(hex: "FFD700").opacity(0.4), lineWidth: 1)
            )
    }

    private var dismissButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                hints.dismiss(id)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "FFD700").opacity(0.7))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}
