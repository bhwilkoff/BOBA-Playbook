import SwiftUI
import UIKit

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

        // UIColor mirrors of the brand tokens. Needed for any code
        // path that draws into UIGraphics contexts (e.g.,
        // PricingOverlayComposer in ScanQueueView), where SwiftUI's
        // Color isn't directly usable. Hex values match the SwiftUI
        // tokens above; keep them in lockstep when changing brand
        // colors.
        static let bobaOrangeUI = UIColor(red: 0xFF/255.0, green: 0x4D/255.0, blue: 0x00/255.0, alpha: 1.0)
        static let bobaCyanUI   = UIColor(red: 0x00/255.0, green: 0xF5/255.0, blue: 0xFF/255.0, alpha: 1.0)
        static let nearBlackUI  = UIColor(red: 0x08/255.0, green: 0x08/255.0, blue: 0x10/255.0, alpha: 1.0)

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

// MARK: - Compact-only hero zoom (DESIGN.md §6.6.2)
//
// Wrappers around .matchedTransitionSource and
// .navigationTransition(.zoom(...)) that apply ONLY when
// horizontalSizeClass == .compact. On regular width (iPad), these
// are no-ops so the destination falls back to the system push
// transition. A corner cell zooming to a 1024pt destination on
// iPad reads as broken — the slingshot travels too far and the
// 200pt thumbnail can't sample 1024pt of detail cleanly.
//
// Use these everywhere we used to write
// `.matchedTransitionSource(id:in:)` / `.navigationTransition(.zoom...)`.

private struct CompactZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct CompactZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// Compact-only `.matchedTransitionSource` (DESIGN.md §6.6.2).
    /// No-op on regular width.
    func compactZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(CompactZoomSource(id: id, namespace: namespace))
    }

    /// Compact-only `.navigationTransition(.zoom(...))` (DESIGN.md §6.6.2).
    /// No-op on regular width — system push transition activates instead.
    func compactZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(CompactZoomDestination(id: id, namespace: namespace))
    }
}

// MARK: - GridDensity (DESIGN.md §6.6 — size-class-aware column counts)
//
// All grids that expose user-selectable column count (Find / Decks /
// Collection / ProfileView's settings) read sentinel `0` from
// @AppStorage as "unset" and resolve to a size-class default.
// Compact (iPhone) gets a denser/looser 1-3 range; regular (iPad)
// expands to 3-7 because a 3-col grid on a 1024pt screen is sparse.

extension Design {
    enum GridDensity {
        /// Returns user's stored choice (>0) or the size-class default.
        /// Compact uses the per-tab `compactDefault` (Find=2, Decks=3,
        /// Collection=3); regular falls back to 5 universally.
        static func resolved(stored: Int, sizeClass: UserInterfaceSizeClass?, compactDefault: Int) -> Int {
            if stored > 0 { return stored }
            return sizeClass == .regular ? 5 : compactDefault
        }

        /// Picker options per size class.
        static func columnOptions(for sizeClass: UserInterfaceSizeClass?) -> [Int] {
            sizeClass == .regular ? [3, 4, 5, 6, 7] : [1, 2, 3]
        }
    }

    /// Card-detail artPanel sizing per DESIGN.md §6.6 — iPad gets
    /// taller frames so the card-art focal point doesn't read as
    /// claustrophobic in landscape. Used by CardDetailView,
    /// CollectionCardDetailView, and BrowserCardDetailSheet (the
    /// three canonical detail surfaces from §8.6).
    enum CardDetailMetrics {
        static func panelHeight(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
            sizeClass == .regular ? 560 : 420
        }
        static func imageHeight(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
            sizeClass == .regular ? 520 : 380
        }
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
    /// First Glossary visit — tells coaches the term rows are tap-to-copy
    /// (handy for pasting "term — definition" into Discord / game-night
    /// chat). Mirrors Android tick 84.
    case glossaryTapToCopy       = "hint.glossary_tap_to_copy"
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
        // One-time migration: earlier builds defaulted hints to ON and
        // wrote `true` to UserDefaults on first launch, so the new
        // default-OFF behavior wouldn't reach upgraders — their stored
        // `true` survived the policy change. Force-clear the key once
        // so the new default applies, then mark the migration done.
        let migrationKey = "hints.default_off_migration_v1"
        if !dflt.bool(forKey: migrationKey) {
            dflt.removeObject(forKey: "hints.enabled")
            dflt.set(true, forKey: migrationKey)
        }
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
        // Opaque dark surface + faint gold wash so the message reads
        // cleanly over busy practice content (cards, glows, animations).
        // The gold border still carries the visual accent.
        RoundedRectangle(cornerRadius: Design.Radius.sm)
            .fill(Color(hex: "12121C"))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Color(hex: "FFD700").opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .strokeBorder(Color(hex: "FFD700").opacity(0.55), lineWidth: 1)
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

// ════════════════════════════════════════════════════════════════
// MARK: - Feature walkthroughs (DESIGN.md §6.10)
// ════════════════════════════════════════════════════════════════
//
// Inlined alongside HintsManager for the same Xcode synchronized-group
// reliability reason (DECISIONS.md #031). Walkthroughs are the
// just-in-time onboarding pattern: anchored multi-step tutorials that
// fire on first feature use. Distinct from hints — see DESIGN.md §6.10
// vs §6.8.

enum WalkthroughID: String, CaseIterable {
    case findTab        = "walkthrough.find_tab"
    case learnTab       = "walkthrough.learn_tab"
    case decksTab       = "walkthrough.decks_tab"
    case collectionTab  = "walkthrough.collection_tab"
    case purchaseTab    = "walkthrough.purchase_tab"
    case cardDetail     = "walkthrough.card_detail"
    case pricingPanels  = "walkthrough.pricing_panels"
    case wallView       = "walkthrough.wall_view"
    case scanFromFind   = "walkthrough.scan_from_find"
    case scanFromDecks  = "walkthrough.scan_from_decks"
    case scanFromCollection = "walkthrough.scan_from_collection"
    case multiCardScan  = "walkthrough.multi_card_scan"
    /// Unified scanner walkthrough (replaces the per-context scanFrom*
    /// scripts in DESIGN.md §6.10.1). Fires on first ScanView open.
    /// Role-aware — streamers see an extra step about Show mode.
    case scannerOverview = "walkthrough.scanner_overview"
    /// Fires the first time a user opens the Decks editor (the
    /// fullScreenCover that grows out of the summary pill). The
    /// pool view's decksTab walkthrough can't reach the editor's
    /// anchors (different presentation context), so the editor
    /// teaches its own surfaces — format chip strip, deck list,
    /// save button — in a separate walkthrough that fires the first
    /// time the cover opens.
    case decksEditor    = "walkthrough.decks_editor"
}

@Observable
final class WalkthroughsManager {
    static let shared = WalkthroughsManager()

    /// Master toggle — when false, no walkthroughs render.
    var walkthroughsEnabled: Bool {
        didSet { UserDefaults.standard.set(walkthroughsEnabled, forKey: "walkthroughs.enabled") }
    }

    /// Walkthrough IDs the user has dismissed (or completed). Tracked
    /// stored property so toggling triggers SwiftUI re-render.
    private(set) var dismissedIDs: Set<String>

    init() {
        let dflt = UserDefaults.standard
        // Default ON — first-visit teaching is the whole point. Users
        // can disable from Profile / Settings.
        self.walkthroughsEnabled = dflt.object(forKey: "walkthroughs.enabled") as? Bool ?? true
        var initial: Set<String> = []
        for id in WalkthroughID.allCases where dflt.bool(forKey: id.rawValue) {
            initial.insert(id.rawValue)
        }
        self.dismissedIDs = initial
    }

    func isDismissed(_ id: WalkthroughID) -> Bool {
        dismissedIDs.contains(id.rawValue)
    }

    func dismiss(_ id: WalkthroughID) {
        UserDefaults.standard.set(true, forKey: id.rawValue)
        dismissedIDs.insert(id.rawValue)
    }

    func shouldShow(_ id: WalkthroughID) -> Bool {
        walkthroughsEnabled && !isDismissed(id)
    }

    /// Force a walkthrough to re-fire (used by the "?" toolbar button
    /// in each surface — DESIGN.md §6.10 re-launchable rule).
    func relaunch(_ id: WalkthroughID) {
        UserDefaults.standard.removeObject(forKey: id.rawValue)
        dismissedIDs.remove(id.rawValue)
    }

    func resetAll() {
        for id in WalkthroughID.allCases {
            UserDefaults.standard.removeObject(forKey: id.rawValue)
        }
        dismissedIDs.removeAll()
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBAEmptyState (DESIGN.md §6.7 + §11.1)
// ════════════════════════════════════════════════════════════════

/// Wrapper around `ContentUnavailableView` with brand voice + a
/// canonical "productive next action" slot. Replace ad-hoc empty
/// rendering everywhere.
struct BOBAEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String?
    @ViewBuilder let actions: () -> Actions

    init(
        title: String,
        systemImage: String,
        message: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
        } description: {
            if let message {
                Text(message)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        } actions: {
            actions()
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBAErrorBanner (DESIGN.md §6.7 + §11.1)
// ════════════════════════════════════════════════════════════════

/// Inline error banner for action failures (Save deck, Sync, Pricing
/// fetch). Distinct from HintBanner (gold) — orange-bordered to signal
/// attention required. Includes optional retry callback.
struct BOBAErrorBanner: View {
    let title: String
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.bobaOrange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .tracking(0.6)
                Text(message)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let retry {
                Button("Retry", action: retry)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
        }
        .padding(Design.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Color(hex: "12121C"))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBASignInPrompt (DESIGN.md §6.5 Auth + §11.1)
// ════════════════════════════════════════════════════════════════

/// Inline "Sign in to do this" row at the point of action. Per
/// DESIGN.md §6.5, never block exploration on sign-in — surface auth
/// only when the user attempts a write that requires it.
struct BOBASignInPrompt: View {
    let actionDescription: String  // e.g. "save this deck", "designate this card"
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.bobaCyan)
            Text("Sign in to \(actionDescription).")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer(minLength: Design.Spacing.sm)
            Button("Sign In", action: onSignIn)
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.bobaCyan.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBAOfflinePill (DESIGN.md §6.7 + §11.1)
// ════════════════════════════════════════════════════════════════

/// Subtle "Offline" pill for the nav bar. Tap to surface a sheet
/// explaining what's degraded (Cloud actions disabled, cached data
/// shown). Hosting view manages the connectivity check + presentation.
struct BOBAOfflinePill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 10, weight: .bold))
            Text("OFFLINE")
                .font(Design.Fonts.mono(10, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(Design.Colors.textMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBASectionHeader (DESIGN.md §4.2 typography hierarchy)
// ════════════════════════════════════════════════════════════════

/// Uppercase Bebas Neue section header. Replaces colored-box section
/// labels (§4.1 anti-pattern: no background tints on lists).
struct BOBASectionHeader: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Design.Fonts.arena(15))
                .tracking(1.2)
                .foregroundStyle(Design.Colors.textSecondary)
            Spacer(minLength: Design.Spacing.sm)
            if let trailing {
                Text(trailing)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.xs)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBASectionRow (DESIGN.md §11.1)
// ════════════════════════════════════════════════════════════════

/// Single-line row for root list views (Learn root, Profile, Settings).
/// Title + optional count + chevron. Use NavigationLink wrapped around
/// this for push navigation.
struct BOBASectionRow: View {
    let title: String
    let subtitle: String?
    let count: Int?
    let systemImage: String?

    init(title: String, subtitle: String? = nil, count: Int? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Design.Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Design.Spacing.sm)
            if let count {
                Text("\(count)")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(.vertical, Design.Spacing.sm)
        .contentShape(Rectangle())
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBAFilterToken (DESIGN.md §6.4)
// ════════════════════════════════════════════════════════════════

/// Search-token type for `.searchable(text:tokens:suggestedTokens:)`.
/// Per DESIGN.md §6.4, tokens replace every "filter pill" row with the
/// iOS-native chip-in-search-field pattern. Filter axes are
/// orthogonal; multiple cases of the same axis OR together (FIRE
/// OR ICE), different axes AND together (FIRE AND 3 HD).
///
/// Currently consumed by DecksView's pool filter; ready for re-use
/// in any future search surface that needs orthogonal filters.
enum BOBAFilterToken: Identifiable, Hashable {
    case weapon(String)   // "FIRE", "ICE", "STEEL", etc.
    case cost(Int)        // 0 = FREE, 1...8 = HD cost
    case hero(String)     // hero name (e.g. "Maverick")

    var id: String {
        switch self {
        case .weapon(let e): return "weapon:\(e)"
        case .cost(let c):   return "cost:\(c)"
        case .hero(let h):   return "hero:\(h)"
        }
    }

    var label: String {
        switch self {
        case .weapon(let e): return e.capitalized
        case .cost(let c):   return c == 0 ? "FREE" : "\(c) HD"
        case .hero(let h):   return h
        }
    }

    var systemImageName: String {
        switch self {
        case .weapon: return "circle.fill"
        case .cost:   return "dollarsign.circle"
        case .hero:   return "person.fill"
        }
    }

    /// Per-token tint per user feedback — weapon tokens render in
    /// their canonical element color (FIRE chip is FIRE-colored, ICE
    /// chip is ICE-colored, etc.) so the eye recognizes them at a
    /// glance. Cost tokens use cyan, hero tokens orange.
    var tint: Color {
        switch self {
        case .weapon(let e): return Design.Colors.element(e)
        case .cost:          return Design.Colors.bobaCyan
        case .hero:          return Design.Colors.bobaOrange
        }
    }

    /// All eight canonical weapon tokens.
    static let weapons: [BOBAFilterToken] = [
        .weapon("FIRE"), .weapon("ICE"), .weapon("STEEL"), .weapon("BRAWL"),
        .weapon("GLOW"), .weapon("HEX"), .weapon("GUM"), .weapon("SUPER"),
    ]

    /// Common play-cost tokens (0 = FREE through 4 HD). Higher costs
    /// exist but rarely; users can filter via the search text.
    static let costs: [BOBAFilterToken] = (0...4).map { BOBAFilterToken.cost($0) }
}

// ════════════════════════════════════════════════════════════════
// MARK: - BOBACardCell (DESIGN.md §11.1 + §4.3 small multiples)
// ════════════════════════════════════════════════════════════════

/// Canonical card-image primitive — uniform image aspect, corner
/// radius, element-tinted border, and element glow. Per DESIGN.md
/// §11.1 and §4.3, every card cell across Find / Decks / Collection /
/// Wall composes from this so the eye scans content via invariant
/// frame.
///
/// Usage: wrap with context-specific footers / overlays / gestures.
/// The cell itself does NOT include name, power, badges, or tap
/// handling — those are caller-owned so deck-violation greying,
/// collection multi-designation pills, and find treatment ribbons
/// can each compose differently.
struct BOBACardCell: View {
    let card: Card
    /// Image resolution. Default .thumb keeps existing single-card
    /// callers (rainbow row covers, scan chips, etc.) on the smaller
    /// 200px WebP. BOBACardGridItem passes .full when the column
    /// count is dense enough that the thumb pixelates (1- or 2-across).
    var size: CardImageView.ImageSize = .thumb

    /// 5:7 portrait card aspect — matches every BoBA card. Constant
    /// so the small-multiples guarantee holds across surfaces.
    static let aspectRatio: CGFloat = 5.0 / 7.0
    static let cornerRadius: CGFloat = Design.Radius.md

    var body: some View {
        CardImageView(card: card, size: size)
            .aspectRatio(Self.aspectRatio, contentMode: .fill)
            .clipped()
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) { printRunBadge }
            .overlay(alignment: .bottomLeading) { formatLegalityHintBadge }
            .elementGlow(card.isSealed ? "NONE" : card.element)
    }

    private var borderColor: Color {
        card.isSealed
            ? Design.Colors.bobaOrange.opacity(0.30)
            : Design.Colors.element(card.element).opacity(0.25)
    }

    /// Top-trailing print-run chip (Android tick 456 parity / Discord
    /// backlog #7 per-cell). Only renders at `.full` size — the .thumb
    /// path is reserved for very small surfaces (scan chips, suggestion
    /// thumbnails) where the labelSmall would be illegible.
    @ViewBuilder
    private var printRunBadge: some View {
        if size == .full, let label = card.printRunLabel, !label.isEmpty {
            PrintRunBadge(label: label).padding(4)
        }
    }

    /// Bottom-leading format-legality hint. .full-only gate matches
    /// printRunBadge.
    @ViewBuilder
    private var formatLegalityHintBadge: some View {
        if size == .full, let hint = CardFormatEligibility.restrictedLegalAbbrev(for: card) {
            FormatLegalityHintBadge(label: hint).padding(4)
        }
    }
}

/// Tick 497 — shared corner chip used by both PrintRunBadge (top-
/// trailing, cyan/orange) and FormatLegalityHintBadge (bottom-leading,
/// amber). Mirrors the Android CardCornerBadge extraction at tick 495.
struct CardCornerBadge: View {
    let label: String
    let accent: Color

    var body: some View {
        Text(label)
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Bottom-leading format-legality hint (Discord backlog #4 carry-forward).
struct FormatLegalityHintBadge: View {
    let label: String
    var body: some View {
        CardCornerBadge(label: label, accent: Design.Colors.bobaOrange)
    }
}

/// Top-trailing print-run chip — orange for SSP, cyan otherwise (Inspired Ink).
struct PrintRunBadge: View {
    let label: String
    var body: some View {
        CardCornerBadge(
            label: label,
            accent: label == "SSP" ? Design.Colors.bobaOrange : Design.Colors.bobaCyan
        )
    }
}

// MARK: - BOBACardGridItem
//
// Unified grid cell used by Find, Decks, and Collection. Card art
// (BOBACardCell) on top — UNOBSTRUCTED, no overlays, no gradients.
// Hero name + weapon + power (or sealed-product equivalents) render
// BELOW the card in a clean caption that adapts to column count.
//
// Per user feedback (2026-05-04): the prior CardGridItemView
// superimposed text on the card image, obscuring the artwork; this
// version keeps the artwork pristine. Caption uses textPrimary for
// the values and an element-tinted capsule for the weapon name so
// HEX (#8B00FF) stays readable on dark backgrounds — the legibility
// regression the user flagged on the Decks tab.
//
// `columnCount` (1 / 2 / 3) controls typography and density. 1-col
// gets the largest typography (a single tall card per row); 3-col
// is the compact density users currently see.

struct BOBACardGridItem: View {
    let card: Card
    var columnCount: Int = 2

    /// 1- through 4-across cells render large enough that the 200px
    /// thumb pixelates noticeably — pull the ≤1200px full WebP at
    /// those densities. 5+ across (iPad-only territory per
    /// Design.GridDensity) stays on thumbs to keep network usage
    /// proportional to cell area. CardImageView handles the loading:
    /// NSCache (60MB) + URLCache (100MB mem / 500MB disk, configured
    /// in App.init) dedupe across instances; a 150ms debounce skips
    /// fly-by cells during fast scrolls; cached thumbs render as a
    /// base layer while the full image loads, so the user sees the
    /// card immediately and the high-res replaces it.
    private var imageSize: CardImageView.ImageSize {
        columnCount <= 4 ? .full : .thumb
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BOBACardCell(card: card, size: imageSize)
            caption
        }
    }

    @ViewBuilder
    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.displayName)
                .font(Design.Fonts.display(nameSize))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                weaponPill
                Spacer(minLength: 4)
                trailingValue
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Caption components

    @ViewBuilder
    private var weaponPill: some View {
        if card.isSealed {
            label(card.set.uppercased(), color: Design.Colors.bobaOrange)
        } else if card.isHero, !card.element.isEmpty {
            label(card.element.uppercased(), color: Design.Colors.element(card.element))
        } else if card.isPlay {
            let isBonus = card.isBonusPlay == true
            label(isBonus ? "BONUS" : "PLAY",
                  color: isBonus ? Design.Colors.bobaCyan : Design.Colors.bobaViolet)
        } else if card.isHotDog {
            label("HOT DOG", color: Color(hex: "7ecb82"))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingValue: some View {
        if card.isSealed {
            if let msrp = card.msrp {
                Text(Decimal(msrp), format: .currency(code: "USD"))
                    .font(Design.Fonts.mono(valueSize, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        } else if card.isHero, let power = card.power, power > 0 {
            Text("\(power)")
                .font(Design.Fonts.mono(valueSize, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
        } else if card.isPlay, let costLabel = card.playCostLabel {
            Text(costLabel)
                .font(Design.Fonts.mono(valueSize, weight: .bold))
                .foregroundStyle(card.playCost == 0 ? Color(hex: "7ecb82") : Design.Colors.textPrimary)
        } else {
            EmptyView()
        }
    }

    /// Element/weapon label — ALWAYS renders text in textPrimary inside
    /// an element-tinted capsule. Solves the HEX-on-black readability
    /// problem (the dark purple element color was illegible as foreground
    /// text on near-black backgrounds).
    @ViewBuilder
    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Design.Fonts.mono(pillSize, weight: .bold))
            .foregroundStyle(Design.Colors.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.30))
                    .overlay(Capsule().strokeBorder(color.opacity(0.55), lineWidth: 0.5))
            )
    }

    // MARK: - Density-adaptive typography

    private var nameSize: CGFloat {
        switch columnCount {
        case 1: return 18
        case 2: return 14
        default: return 11
        }
    }

    private var valueSize: CGFloat {
        switch columnCount {
        case 1: return 16
        case 2: return 13
        default: return 11
        }
    }

    private var pillSize: CGFloat {
        switch columnCount {
        case 1: return 11
        case 2: return 10
        default: return 9
        }
    }
}
