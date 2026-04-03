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
