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
        /// Optional stage that the host uses to prepare the view
        /// before the step renders (e.g., expand a drawer, scroll to
        /// a section). When the step advances or the walkthrough
        /// dismisses, the host receives `nil` and should restore the
        /// prior state.
        let stage: Stage?

        init(anchor: Anchor?, copy: String, placement: Placement? = nil, stage: Stage? = nil) {
            self.anchor = anchor
            self.copy = copy
            self.placement = placement
            self.stage = stage
        }
    }

    /// Hints the host can act on to prepare the UI for an off-screen
    /// step. The walkthrough overlay calls onStage(.foo) when the
    /// step becomes current and onStage(nil) when the walkthrough
    /// completes — host saves prior state on activate, restores on nil.
    enum Stage: Equatable, Hashable {
        case decksDrawerExpanded   // expand the Decks drawer to mid height
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

    /// Single-line host wiring for a walkthrough overlay. Place this on
    /// the host view (the view containing the .walkthroughAnchor()
    /// targets). Reads the anchor preferences via .overlayPreferenceValue
    /// and resolves them through a GeometryReader, then hands resolved
    /// CGRects to BOBAWalkthrough.
    ///
    /// `onStage` is the optional prepare/restore callback. Hosts that
    /// have steps with a `Stage` (e.g., decksDrawerExpanded) implement
    /// it: on stage activation save current state and reveal the
    /// anchor; on nil restore prior state.
    @ViewBuilder
    func walkthroughOverlay(
        _ binding: Binding<BOBAWalkthrough.Script?>,
        onStage: ((BOBAWalkthrough.Stage?) -> Void)? = nil
    ) -> some View {
        self.overlayPreferenceValue(WalkthroughAnchorKey.self) { anchors in
            if let script = binding.wrappedValue {
                GeometryReader { proxy in
                    let frames: [BOBAWalkthrough.Anchor: CGRect] = anchors.reduce(into: [:]) { acc, pair in
                        acc[pair.key] = proxy[pair.value]
                    }
                    BOBAWalkthrough(
                        script: script,
                        anchorFrames: frames,
                        containerSize: proxy.size,
                        onStage: onStage
                    ) {
                        WalkthroughsManager.shared.dismiss(script.id)
                        binding.wrappedValue = nil
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - The overlay view

struct BOBAWalkthrough: View {
    let script: Script
    /// Pre-resolved anchor frames (host view's coordinate space) for the
    /// current view-tree state. Computed at the call site via
    /// `.overlayPreferenceValue(WalkthroughAnchorKey.self) { anchors in
    /// GeometryReader { proxy in ... proxy[anchors[key]!] } }` so the
    /// rects are converted out of `Anchor<CGRect>` and into screen-space
    /// CGRects before they reach the overlay. The earlier inside-out
    /// approach (Color.clear .backgroundPreferenceValue) failed because
    /// preferences only flow through a view's own descendants — anchors
    /// set on the host's content never reached an overlay tree.
    let anchorFrames: [Anchor: CGRect]
    let containerSize: CGSize
    /// Optional callback the host implements to prepare the view for a
    /// step's anchor (e.g., expand a drawer). Called with the new
    /// step's stage when advancing; called with nil when the
    /// walkthrough completes so the host can restore prior state.
    let onStage: ((Stage?) -> Void)?
    let onComplete: () -> Void

    @State private var currentStep: Int = 0

    var body: some View {
        ZStack {
            // Dim the world. Cuts a "window" into the dim around the
            // current anchor so the highlighted UI stays readable.
            dimWithCutout

            // Cyan ring + tooltip on top of the dim.
            spotlightAndTooltip

            // Bottom controls.
            VStack {
                Spacer()
                bottomBar
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .onAppear {
            // First step's stage prepare hook fires on appear so the
            // host can reveal the very first anchor if it's hidden.
            onStage?(step?.stage)
        }
    }

    private var step: Step? {
        guard currentStep < script.steps.count else { return nil }
        return script.steps[currentStep]
    }

    private var isLastStep: Bool { currentStep == script.steps.count - 1 }

    private var currentAnchorRect: CGRect? {
        guard let step, let anchorKey = step.anchor else { return nil }
        return anchorFrames[anchorKey]
    }

    /// Approximate safe viewport — keeps the spotlight ring + tooltip
    /// out of the navigation bar and bottom-bar regions. Tooltip width
    /// is capped at 280; height varies with copy length but caps near
    /// 140 (≈4 lines wrapped). Bottom bar reserves the lowest 96pt.
    private var safeViewport: CGRect {
        CGRect(
            x: 16,
            y: 60,                                // clear status bar + nav title row
            width: max(0, containerSize.width - 32),
            height: max(0, containerSize.height - 60 - 96)
        )
    }

    private static let tooltipMaxWidth: CGFloat = 280
    private static let tooltipEstimatedHeight: CGFloat = 140

    /// True when the anchor's center is INSIDE the safe viewport. We
    /// treat partially-on-screen anchors as on-screen but render the
    /// spotlight ring clipped to the visible region; fully-off-screen
    /// anchors fall back to a centered tooltip + directional hint.
    private func anchorIsVisible(_ rect: CGRect) -> Bool {
        let viewport = CGRect(origin: .zero, size: containerSize)
        return viewport.intersects(rect)
    }

    private func advance() {
        if isLastStep {
            complete()
        } else {
            currentStep += 1
            // Notify host of the new step's stage so it can prepare
            // (e.g., expand a drawer to reveal the anchor).
            onStage?(step?.stage)
        }
    }

    private func complete() {
        // Restore prior state before tearing down.
        onStage?(nil)
        onComplete()
    }

    /// Renders the 60% black dim with a rounded-rect cutout where the
    /// current anchor sits. The cutout uses .blendMode(.destinationOut)
    /// inside a .compositingGroup so the punched-through region lets the
    /// anchored UI shine through at full opacity. Cutout intersects with
    /// the screen so off-screen portions don't render as visible holes.
    @ViewBuilder
    private var dimWithCutout: some View {
        if let rect = currentAnchorRect, anchorIsVisible(rect) {
            ZStack {
                Color.black.opacity(0.6)
                // Cutout matches the spotlight ring exactly — pad
                // outward 8pt, clamp to viewport so the punched-out
                // rectangle never overflows the screen edge.
                let viewport = CGRect(origin: .zero, size: containerSize)
                let clamped = rect.intersection(viewport).insetBy(dx: -8, dy: -8).intersection(viewport)
                RoundedRectangle(cornerRadius: 14)
                    .frame(width: clamped.width, height: clamped.height)
                    .position(x: clamped.midX, y: clamped.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .ignoresSafeArea()
            .onTapGesture { advance() }
        } else {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { advance() }
        }
    }

    @ViewBuilder
    private var spotlightAndTooltip: some View {
        if let step {
            ZStack {
                if let rect = currentAnchorRect, anchorIsVisible(rect) {
                    spotlightRing(rect: rect)
                }
                tooltip(for: step, anchorRect: currentAnchorRect)
                if let rect = currentAnchorRect, !anchorIsVisible(rect) {
                    offscreenIndicator(for: rect)
                }
            }
        }
    }

    /// Spotlight ring — only renders the visible portion of the anchor,
    /// AND clamps the ring's bounding box so its full perimeter stays
    /// inside the viewport (no edge of the cyan rectangle ever runs
    /// off-screen). The pad-then-clamp dance: compute the desired
    /// padded rect, then shrink it by however much it overflows on
    /// each edge so all four sides remain visible.
    @ViewBuilder
    private func spotlightRing(rect: CGRect) -> some View {
        let visible = rect.intersection(CGRect(origin: .zero, size: containerSize))
        guard visible.width > 4 && visible.height > 4 else {
            return AnyView(EmptyView())
        }
        let pad: CGFloat = 8
        let viewport = CGRect(origin: .zero, size: containerSize)
        // Pad outward, then intersect with viewport to clamp every edge.
        let clamped = visible.insetBy(dx: -pad, dy: -pad).intersection(viewport)
        return AnyView(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Design.Colors.bobaCyan, lineWidth: 2)
                .frame(width: clamped.width, height: clamped.height)
                .position(x: clamped.midX, y: clamped.midY)
                .shadow(color: Design.Colors.bobaCyan.opacity(0.7), radius: 10)
                .allowsHitTesting(false)
        )
    }

    /// When the current step's anchor is entirely off-screen (e.g., a
    /// row that's been scrolled past), show a directional chevron at
    /// the screen edge in the direction of the anchor. Better UX than
    /// "pointless tooltip with no spotlight."
    @ViewBuilder
    private func offscreenIndicator(for rect: CGRect) -> some View {
        let needsUp   = rect.maxY < 0
        let needsDown = rect.minY > containerSize.height
        let icon = needsUp ? "chevron.up" : (needsDown ? "chevron.down" : "")
        if !icon.isEmpty {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
                .padding(12)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .position(
                    x: containerSize.width / 2,
                    y: needsUp ? 80 : (containerSize.height - 130)
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func tooltip(for step: Step, anchorRect: CGRect?) -> some View {
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
            .frame(maxWidth: Self.tooltipMaxWidth)
            .allowsHitTesting(false)

        let position = clampedTooltipCenter(anchor: anchorRect, step: step)
        copy.position(x: position.x, y: position.y)
    }

    /// Computes a tooltip center point that's guaranteed to keep the
    /// full ~280×140 bounding box inside the safeViewport. Prefers the
    /// side of the anchor that the step's placement (or autopick)
    /// requested, but if that side has no room, falls back to the
    /// opposite side. Clamps X/Y so even very-edge anchors (e.g., a
    /// top-leading toolbar button at x=20) yield an on-screen tooltip.
    private func clampedTooltipCenter(anchor: CGRect?, step: Step) -> CGPoint {
        let viewport = safeViewport
        let halfW = Self.tooltipMaxWidth / 2
        let halfH = Self.tooltipEstimatedHeight / 2

        // Allowed center range so the tooltip's bounding box stays in
        // the safe viewport.
        let minCx = viewport.minX + halfW
        let maxCx = viewport.maxX - halfW
        let minCy = viewport.minY + halfH
        let maxCy = viewport.maxY - halfH

        guard let anchor, anchorIsVisible(anchor) else {
            // Anchor missing or off-screen — center the tooltip in the
            // safe viewport. Off-screen indicator (above) handles
            // direction.
            return CGPoint(
                x: clamp(viewport.midX, minCx, maxCx),
                y: clamp(viewport.midY, minCy, maxCy)
            )
        }

        // Auto-pick side: try requested first, then opposite if no room.
        let requested: Placement = step.placement ?? (
            anchor.midY > containerSize.height / 2 ? .above : .below
        )

        // Compute candidate Y for above/below; prefer the requested side.
        let aboveY = anchor.minY - 24 - halfH    // tooltip bottom 24pt above anchor
        let belowY = anchor.maxY + 24 + halfH    // tooltip top 24pt below anchor

        let chosenY: CGFloat = {
            switch requested {
            case .above:
                if aboveY >= minCy { return aboveY }
                if belowY <= maxCy { return belowY }
                return clamp(viewport.midY, minCy, maxCy)
            case .below:
                if belowY <= maxCy { return belowY }
                if aboveY >= minCy { return aboveY }
                return clamp(viewport.midY, minCy, maxCy)
            case .leading, .trailing:
                // Side placements ignore Y heuristic — center on anchor.
                return clamp(anchor.midY, minCy, maxCy)
            }
        }()

        let chosenX: CGFloat = {
            switch requested {
            case .leading:
                let leftCx = anchor.minX - 16 - halfW
                if leftCx >= minCx { return leftCx }
                let rightCx = anchor.maxX + 16 + halfW
                if rightCx <= maxCx { return rightCx }
                return clamp(viewport.midX, minCx, maxCx)
            case .trailing:
                let rightCx = anchor.maxX + 16 + halfW
                if rightCx <= maxCx { return rightCx }
                let leftCx = anchor.minX - 16 - halfW
                if leftCx >= minCx { return leftCx }
                return clamp(viewport.midX, minCx, maxCx)
            case .above, .below:
                // Center on anchor X, then clamp.
                return clamp(anchor.midX, minCx, maxCx)
            }
        }()

        return CGPoint(x: chosenX, y: chosenY)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi >= lo else { return (lo + hi) / 2 }   // pathological viewport
        return min(max(v, lo), hi)
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
            .init(anchor: .init("find.search"),   copy: "Search any of 17,968 cards by name, hero, or weapon."),
            .init(anchor: .init("find.menu"),     copy: "Open the menu for filters and Card Showcases."),
            .init(anchor: .init("find.cardCell"), copy: "Tap a card to see details, prices, and decks."),
            .init(anchor: .init("find.scan"),     copy: "Scan a real card to identify it instantly."),
            .init(anchor: .init("find.profile"),  copy: "Sign in to save cards to your collection.")
        ]
    )

    static let learnTab = BOBAWalkthrough.Script(
        id: .learnTab,
        steps: [
            .init(anchor: .init("learn.rootList"), copy: "Six paths to learn BoBA — read, watch, or browse."),
            .init(anchor: .init("learn.firstRow"), copy: "Tap any tile to dive into that path.")
        ]
    )

    static let decksTab = BOBAWalkthrough.Script(
        id: .decksTab,
        steps: [
            .init(anchor: .init("decks.cardPool"),    copy: "Tap to view a card. Long-press to add to the deck."),
            .init(anchor: .init("decks.sheetHandle"), copy: "Drag up for the full deck, format picker, and rules."),
            // Drawer auto-expands so the format chip is on-screen for
            // this step, then collapses back when the walkthrough
            // dismisses (host implements via onStage).
            .init(anchor: .init("decks.formatChip"),  copy: "Format shapes the whole deck — pick before you build.",
                  stage: .decksDrawerExpanded),
            .init(anchor: .init("decks.saveButton"),  copy: "Sign in and Save to sync your deck across devices.")
        ]
    )

    static let collectionTab = BOBAWalkthrough.Script(
        id: .collectionTab,
        steps: [
            .init(anchor: .init("collection.scopeBar"),    copy: "Switch between Personal, Sale, Trade, Wanted, and Grails."),
            .init(anchor: .init("collection.cardCell"),    copy: "Tap a card to view value, designation, and notes."),
            .init(anchor: .init("collection.displayMode"), copy: "Open the menu for List, Grid, or Wall sharing.")
        ]
    )

    static let purchaseTab = BOBAWalkthrough.Script(
        id: .purchaseTab,
        steps: [
            .init(anchor: .init("purchase.picker"),   copy: "Switch between Live Breaks and Find a Store."),
            .init(anchor: .init("purchase.showTile"), copy: "Tap a show to open it in Whatnot.")
        ]
    )

    static let cardDetail = BOBAWalkthrough.Script(
        id: .cardDetail,
        steps: [
            .init(anchor: .init("cardDetail.statsGrid"), copy: "Six cells: Card #, Type, Treatment, Weapon, Set, Sub-set."),
            .init(anchor: .init("cardDetail.actionBar"), copy: "Add to Collection, Add to Deck, or Share via the menu.")
        ]
    )

    /// Pricing walkthrough fires when the user actually scrolls to the
    /// PricingSection (via .onAppear there), not on CardDetailView open
    /// — so both anchors are guaranteed visible at trigger time.
    static let pricingPanels = BOBAWalkthrough.Script(
        id: .pricingPanels,
        steps: [
            .init(anchor: .init("pricing.buyNow"), copy: "Live asking prices from eBay."),
            .init(anchor: .init("pricing.sold"),   copy: "Recent sales drive the market estimate above.")
        ]
    )

    static let wallView = BOBAWalkthrough.Script(
        id: .wallView,
        steps: [
            .init(anchor: .init("wall.overlay"),  copy: "Toggle prices to show on each tile."),
            .init(anchor: .init("wall.selector"), copy: "Tap to include cards. Long-press to highlight as big-hits."),
            .init(anchor: .init("wall.share"),    copy: "Save the image or share it once you've picked your cards.")
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
