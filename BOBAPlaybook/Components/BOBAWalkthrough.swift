//
//  BOBAWalkthrough.swift
//  BOBAPlaybook
//
//  Anchor-based, multi-step first-visit tutorial overlay per
//  DESIGN.md §6.10. Replaces ad-hoc per-feature tutorials with a
//  single component the rest of the app composes from.
//
//  Pattern source: extracted from the prior
//  `DeckBuilderTutorialOverlay`. The same anchor-spotlight + glass
//  tooltip mechanic, generalized so every tab can fire its
//  walkthrough script from §6.10.1 with a few lines.
//
//  Usage (host view):
//  ```
//  @State private var walkthrough: BOBAWalkthrough.Script? = nil
//  // somewhere
//  ZStack {
//      content
//      if let script = walkthrough,
//         WalkthroughsManager.shared.shouldShow(script.id) {
//          BOBAWalkthrough(script: script) {
//              WalkthroughsManager.shared.dismiss(script.id)
//              walkthrough = nil
//          }
//      }
//  }
//  .onAppear { walkthrough = .findTab }
//  ```
//

import SwiftUI

// MARK: - Script model

extension BOBAWalkthrough {
    /// Single step inside a walkthrough script.
    struct Step: Identifiable {
        let id = UUID()
        /// The view to highlight. Nil = full-screen step (rare; use
        /// only for the first introductory step or final celebration).
        let anchor: Anchor?
        /// Copy displayed in the glass tooltip. ≤12 words per
        /// DESIGN.md §6.10 voice rule.
        let copy: String
        /// Where to place the tooltip relative to the anchor. Auto-
        /// resolved when nil — defaults to the side with more space.
        let placement: Placement?

        init(anchor: Anchor?, copy: String, placement: Placement? = nil) {
            self.anchor = anchor
            self.copy = copy
            self.placement = placement
        }
    }

    /// Anchor identifier — host views attach `anchorPreference`
    /// modifiers tagged with these enum cases on real UI elements.
    /// The walkthrough overlay reads back the rect via
    /// `PreferenceKey` to position its spotlight.
    struct Anchor: Equatable, Hashable {
        let key: String
        init(_ key: String) { self.key = key }
    }

    enum Placement {
        case above, below, leading, trailing
    }

    /// A complete walkthrough script — id + ordered steps.
    struct Script: Identifiable {
        let id: WalkthroughID
        let steps: [Step]

        init(id: WalkthroughID, steps: [Step]) {
            assert(steps.count <= 5, "Walkthroughs are capped at 5 steps per DESIGN.md §6.10")
            self.id = id
            self.steps = steps
        }
    }
}

// MARK: - PreferenceKey for collecting anchor frames

struct WalkthroughAnchorKey: PreferenceKey {
    static var defaultValue: [BOBAWalkthrough.Anchor: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [BOBAWalkthrough.Anchor: Anchor<CGRect>],
        nextValue: () -> [BOBAWalkthrough.Anchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Attach this to any view that's an anchor target for a
    /// walkthrough step. The string key matches `BOBAWalkthrough.Anchor`.
    func walkthroughAnchor(_ key: String) -> some View {
        anchorPreference(
            key: WalkthroughAnchorKey.self,
            value: .bounds
        ) { [BOBAWalkthrough.Anchor(key): $0] }
    }
}

// MARK: - The overlay view

struct BOBAWalkthrough: View {
    let script: Script
    let onComplete: () -> Void

    @State private var currentStep: Int = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Dim the world.
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { advance() }

                // Reads back the latest anchor frames captured by hosts
                // and positions the spotlight + tooltip.
                spotlightAndTooltip(proxy: proxy)

                // Bottom controls.
                VStack {
                    Spacer()
                    bottomBar
                }
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }

    private var step: Step? {
        guard currentStep < script.steps.count else { return nil }
        return script.steps[currentStep]
    }

    private var isLastStep: Bool { currentStep == script.steps.count - 1 }

    private func advance() {
        if isLastStep { complete() } else { currentStep += 1 }
    }

    private func complete() { onComplete() }

    @ViewBuilder
    private func spotlightAndTooltip(proxy: GeometryProxy) -> some View {
        if let step {
            // Hidden background that consumes the latest anchor map.
            Color.clear
                .backgroundPreferenceValue(WalkthroughAnchorKey.self) { anchors in
                    GeometryReader { geo in
                        if let anchorKey = step.anchor,
                           let anchor = anchors[anchorKey] {
                            let rect = geo[anchor]
                            ZStack {
                                spotlightCutout(rect: rect, in: geo.size)
                                tooltip(for: step, anchorRect: rect, screen: geo.size)
                            }
                        } else {
                            // Anchor missing — render tooltip centered.
                            tooltip(for: step, anchorRect: nil, screen: geo.size)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func spotlightCutout(rect: CGRect, in size: CGSize) -> some View {
        let inset: CGFloat = 12
        let cutout = rect.insetBy(dx: -inset, dy: -inset)

        // Cyan ring around the anchor.
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Design.Colors.bobaCyan, lineWidth: 2)
            .frame(width: cutout.width, height: cutout.height)
            .position(x: cutout.midX, y: cutout.midY)
            .shadow(color: Design.Colors.bobaCyan.opacity(0.6), radius: 8)
    }

    @ViewBuilder
    private func tooltip(for step: Step, anchorRect: CGRect?, screen: CGSize) -> some View {
        let copy = Text(step.copy)
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(Design.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Color(hex: "12121C"))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.bobaCyan.opacity(0.55), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 280)

        let position = tooltipPosition(anchor: anchorRect, screen: screen, step: step)
        copy.position(x: position.x, y: position.y)
    }

    private func tooltipPosition(anchor: CGRect?, screen: CGSize, step: Step) -> CGPoint {
        guard let anchor else {
            return CGPoint(x: screen.width / 2, y: screen.height / 2)
        }
        let auto: Placement = {
            if let p = step.placement { return p }
            // Pick the side with more room (above vs. below).
            return anchor.midY > screen.height / 2 ? .above : .below
        }()
        switch auto {
        case .above:    return CGPoint(x: anchor.midX, y: anchor.minY - 60)
        case .below:    return CGPoint(x: anchor.midX, y: anchor.maxY + 60)
        case .leading:  return CGPoint(x: max(140, anchor.minX - 150), y: anchor.midY)
        case .trailing: return CGPoint(x: min(screen.width - 140, anchor.maxX + 150), y: anchor.midY)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Skip") {
                complete()
            }
            .font(Design.Fonts.mono(13))
            .foregroundStyle(Design.Colors.textSecondary)

            Spacer()

            // Step dots
            HStack(spacing: 6) {
                ForEach(0..<script.steps.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentStep ? Design.Colors.bobaCyan : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            Button(isLastStep ? "Done" : "Next") {
                advance()
            }
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(Design.Colors.bobaCyan)
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, Design.Spacing.xl)
        .padding(.bottom, Design.Spacing.xl)
    }
}

// MARK: - Walkthrough catalog (DESIGN.md §6.10.1)

extension BOBAWalkthrough.Script {

    static let findTab = BOBAWalkthrough.Script(
        id: .findTab,
        steps: [
            .init(anchor: .init("find.search"),    copy: "Search any of 17,968 cards by name, hero, or weapon."),
            .init(anchor: .init("find.ribbons"),   copy: "Browse by weapon, sport, or featured collections."),
            .init(anchor: .init("find.cardCell"),  copy: "Tap a card to see details, prices, and decks."),
            .init(anchor: .init("find.scan"),      copy: "Scan a real card to identify it instantly."),
            .init(anchor: .init("find.profile"),   copy: "Sign in to save cards to your collection.")
        ]
    )

    static let learnTab = BOBAWalkthrough.Script(
        id: .learnTab,
        steps: [
            .init(anchor: .init("learn.rootList"),   copy: "Five learning paths, from Rules to Tournament."),
            .init(anchor: .init("learn.firstRow"),   copy: "Tap to read articles, strategy, and glossary."),
            .init(anchor: .init("learn.scopeBar"),   copy: "Switch between Rookie, Substitution, and Playmaker views."),
            .init(anchor: .init("learn.search"),     copy: "Search across every Learn article from here.")
        ]
    )

    static let decksTab = BOBAWalkthrough.Script(
        id: .decksTab,
        steps: [
            .init(anchor: .init("decks.cardPool"),  copy: "Tap any card to add it to your deck."),
            .init(anchor: .init("decks.sheetHandle"), copy: "Drag up to see your full deck list."),
            .init(anchor: .init("decks.formatChip"), copy: "Set your format — it shapes the whole deck."),
            .init(anchor: .init("decks.searchBar"), copy: "Filter with tokens for element, cost, or hero."),
            .init(anchor: .init("decks.saveButton"), copy: "Sign in and save to access your deck anywhere.")
        ]
    )

    static let collectionTab = BOBAWalkthrough.Script(
        id: .collectionTab,
        steps: [
            .init(anchor: .init("collection.scopeBar"),   copy: "Personal, For Sale, Trade, Wanted, Grails — switch here."),
            .init(anchor: .init("collection.cardCell"),   copy: "Tap to edit designation, valuation, or notes."),
            .init(anchor: .init("collection.scan"),       copy: "Scan to bulk-add cards to a designation."),
            .init(anchor: .init("collection.displayMode"), copy: "Switch to List for triage or Wall for sharing."),
            .init(anchor: .init("collection.share"),      copy: "Share by URL or as a Wall image.")
        ]
    )

    static let purchaseTab = BOBAWalkthrough.Script(
        id: .purchaseTab,
        steps: [
            .init(anchor: .init("purchase.picker"),  copy: "Upcoming Breaks or Find a Store."),
            .init(anchor: .init("purchase.showTile"), copy: "Tap a show to open it in Whatnot."),
            .init(anchor: .init("purchase.storeMap"), copy: "Find indie shops or big-box near you.")
        ]
    )

    static let cardDetail = BOBAWalkthrough.Script(
        id: .cardDetail,
        steps: [
            .init(anchor: .init("cardDetail.statsGrid"), copy: "Six cells: Card #, Type, Treatment, Weapon, Set, Sub-set."),
            .init(anchor: .init("cardDetail.pricing"),   copy: "Buy Now is asking; Sold is transacted. Kept separate."),
            .init(anchor: .init("cardDetail.actionBar"), copy: "Add to Collection, Add to Deck, or Share.")
        ]
    )

    static let pricingPanels = BOBAWalkthrough.Script(
        id: .pricingPanels,
        steps: [
            .init(anchor: .init("pricing.buyNow"), copy: "Live asking prices from eBay and COMC."),
            .init(anchor: .init("pricing.sold"),   copy: "Recent sales drive the market estimate above.")
        ]
    )

    static let wallView = BOBAWalkthrough.Script(
        id: .wallView,
        steps: [
            .init(anchor: .init("wall.aspect"),  copy: "Pick wallpaper, square, or 16:9 sizing."),
            .init(anchor: .init("wall.overlay"), copy: "Show prices on each card for sale lists."),
            .init(anchor: .init("wall.share"),   copy: "Save the image or share it directly.")
        ]
    )

    static let scanFromFind = BOBAWalkthrough.Script(
        id: .scanFromFind,
        steps: [
            .init(anchor: .init("scan.viewfinder"), copy: "Cards land in your scan queue as you capture."),
            .init(anchor: .init("scan.modeToggle"), copy: "Switch to grid mode for 3–9 cards at once.")
        ]
    )

    static let scanFromDecks = BOBAWalkthrough.Script(
        id: .scanFromDecks,
        steps: [
            .init(anchor: .init("scan.viewfinder"), copy: "Captured cards add directly to your current deck."),
            .init(anchor: .init("scan.queue"),      copy: "Tap any card to remove if mis-scanned.")
        ]
    )

    static let scanFromCollection = BOBAWalkthrough.Script(
        id: .scanFromCollection,
        steps: [
            .init(anchor: .init("scan.destinationChooser"), copy: "Pick a designation — captures land there."),
            .init(anchor: .init("scan.viewfinder"),         copy: "Scan as many cards as you'd like in one session."),
            .init(anchor: .init("scan.queue"),              copy: "Change a card's designation here before finishing.")
        ]
    )

    static let multiCardScan = BOBAWalkthrough.Script(
        id: .multiCardScan,
        steps: [
            .init(anchor: .init("gridScan.viewfinder"), copy: "Position 3 to 9 cards in a grid pattern."),
            .init(anchor: .init("gridScan.shutter"),    copy: "One tap captures all visible cards."),
            .init(anchor: .init("gridScan.queue"),      copy: "Confirm matches or pick from alternatives.")
        ]
    )
}
