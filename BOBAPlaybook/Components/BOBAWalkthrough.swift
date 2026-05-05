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
                // Outer GeometryReader (NOT ignoring safe area) reads
                // the bottom safe-area inset so the bottom Skip/Done
                // bar can be padded above the tab bar. Inner reader
                // (ignoring safe area) provides full-screen coords
                // for the anchor rects + dim cutout.
                GeometryReader { outer in
                    let safeBottom = outer.safeAreaInsets.bottom
                    GeometryReader { proxy in
                        let frames: [BOBAWalkthrough.Anchor: CGRect] = anchors.reduce(into: [:]) { acc, pair in
                            acc[pair.key] = proxy[pair.value]
                        }
                        BOBAWalkthrough(
                            script: script,
                            anchorFrames: frames,
                            containerSize: proxy.size,
                            safeBottomInset: safeBottom,
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
}

// MARK: - The overlay view

struct BOBAWalkthrough: View {
    /// When true, step transitions emit a structured `print()` +
    /// `NSLog()` block to the Xcode console for the walkthroughs in
    /// `diagnosticWalkthroughIDs` (default: only the unsolved ones).
    /// Use to diagnose "why is the highlight clipped / off-screen /
    /// missing?" by running the walkthrough and pasting console
    /// output back. Set to false to silence everything.
    static var diagnosticsEnabled: Bool = true

    /// Subset of walkthrough IDs that emit diagnostic blocks. Keeps
    /// the console signal-to-noise high once a walkthrough is
    /// validated — solved walkthroughs (Find, Decks pool, Collection,
    /// Purchase, Scanner viewfinder, decksEditor save/stat/format) are
    /// silent; only walkthroughs we're still iterating on log.
    static var diagnosticWalkthroughIDs: Set<String> = [
        WalkthroughID.learnTab.rawValue,
        WalkthroughID.decksEditor.rawValue,
    ]

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
    /// Bottom safe-area inset of the host view, read from a non-
    /// ignoring GeometryReader in walkthroughOverlay. Used to pad
    /// the Skip/Done bar above the system tab bar — without this
    /// the bar renders at containerSize.height (under the tab bar)
    /// and is invisible on every tab except Scan (which itself
    /// ignoresSafeArea so its tab bar is hidden).
    let safeBottomInset: CGFloat
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

            // Skip/Done bar — adaptive position. When the current
            // step's anchor lives in the bottom half of the screen
            // (e.g., Scanner mode pills, Decks summary pill), the
            // bar moves to the TOP so it doesn't cover the controls
            // it's pointing to.
            VStack {
                if barAtTop {
                    bottomBar
                        .padding(.top, max(safeBottomInset, 16))
                    Spacer()
                } else {
                    Spacer()
                    bottomBar
                }
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .onAppear {
            // First step's stage prepare hook fires on appear so the
            // host can reveal the very first anchor if it's hidden.
            onStage?(step?.stage)
            logDiagnostics(event: "START")
        }
        // .onChange fires AFTER the next render — by then any
        // stage-driven host re-render has produced fresh anchorFrames,
        // so the diagnostic logs the post-stage rect (not the
        // pre-stage one). Without this, drawer-expansion steps would
        // always log "anchor not registered" because the diagnostic
        // ran before the drawer had laid out.
        .onChange(of: currentStep) { _, _ in
            logDiagnostics(event: "ADVANCE")
        }
    }

    // MARK: - Diagnostics

    /// Emits a structured block describing the current step's anchor
    /// state. Two output channels in parallel because iOS 26 routes
    /// stdout through Unified Logging by default and Xcode's debug
    /// area sometimes filters it out:
    ///
    ///  1. `print()` — the canonical channel (Xcode Debug → "All
    ///     Output" in the console area).
    ///  2. `NSLog()` — backup that goes through Apple System Log
    ///     and reliably surfaces in Xcode's debug area regardless
    ///     of stdout filter state. Format string `%@` + the block
    ///     as NSString.
    ///
    /// To see output: in Xcode, open the Debug area (Cmd-Shift-Y),
    /// look at the right pane (the console). If empty, click the
    /// pane filter dropdown at the bottom-right and switch to
    /// "All Output" instead of "Debugger Output".
    ///
    /// Each block is bounded by `WT[id] ━━━━━━━━━━━━━━` rules so
    /// multi-step transcripts read clearly when copied out.
    private func logDiagnostics(event: String) {
        guard Self.diagnosticsEnabled else { return }
        let id = script.id.rawValue
        // Suppress logging for walkthroughs already validated as
        // working — only the unsolved ones (in diagnosticWalkthroughIDs)
        // emit blocks. Keeps the Xcode console manageable.
        guard Self.diagnosticWalkthroughIDs.contains(id) else { return }
        let total = script.steps.count
        let stepNum = currentStep + 1

        var lines: [String] = []
        lines.append("WT[\(id)] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ \(event)")

        if event == "DISMISS" {
            lines.append("  → walkthrough dismissed at step \(stepNum)/\(total)")
            lines.append("  → onStage(nil) called — host should restore prior UI state")
            print(lines.joined(separator: "\n"))
            return
        }

        guard let step else {
            lines.append("  ✗ NO STEP — currentStep=\(currentStep) total=\(total)")
            print(lines.joined(separator: "\n"))
            return
        }

        lines.append("  step \(stepNum)/\(total)")
        lines.append("  copy: \"\(step.copy)\"")
        lines.append("  copy length: \(step.copy.split(separator: " ").count) words \(step.copy.count <= 12 * 8 ? "✓" : "⚠ likely > §6.10 cap of 12")")

        if let stage = step.stage {
            lines.append("  stage: \(stage) — host should prepare UI for this anchor")
        } else {
            lines.append("  stage: nil")
        }

        let container = containerSize
        lines.append("  container: \(fmt(container.width)) × \(fmt(container.height))")

        if let anchorKey = step.anchor {
            lines.append("  anchor key: \"\(anchorKey.key)\"")
            if let rect = anchorFrames[anchorKey] {
                lines.append("  anchor rect: x=\(fmt(rect.minX)) y=\(fmt(rect.minY)) w=\(fmt(rect.width)) h=\(fmt(rect.height))")
                let viewport = CGRect(origin: .zero, size: container)
                // 1pt tolerance — sub-pixel rounding (e.g., a 393.3pt
                // anchor in a 393.0pt viewport, 0.3pt overflow) is
                // visually invisible and shouldn't flag as CLIPPED.
                let tol: CGFloat = 1.0
                let leftIn   = rect.minX  >= viewport.minX - tol
                let rightIn  = rect.maxX  <= viewport.maxX + tol
                let topIn    = rect.minY  >= viewport.minY - tol
                let bottomIn = rect.maxY  <= viewport.maxY + tol
                let allIn    = leftIn && rightIn && topIn && bottomIn
                lines.append("  anchor on-screen: \(allIn ? "✓ FULLY ON-SCREEN" : "✗ CLIPPED")")
                if !leftIn   { lines.append("    ← clipped LEFT  by \(fmt(viewport.minX - rect.minX))pt") }
                if !rightIn  { lines.append("    → clipped RIGHT by \(fmt(rect.maxX - viewport.maxX))pt") }
                if !topIn    { lines.append("    ↑ clipped TOP   by \(fmt(viewport.minY - rect.minY))pt") }
                if !bottomIn { lines.append("    ↓ clipped BOTTOM by \(fmt(rect.maxY - viewport.maxY))pt") }
                // Spotlight ring is the anchor padded by ±8 BUT each
                // edge's pad is capped at the available viewport
                // margin (matches the spotlightRing pad-then-clamp
                // dance below). For an anchor that touches a screen
                // edge, that edge gets a 0pt inset instead of the
                // -8pt that would push the ring off-screen. Log the
                // actually-rendered rect, not a naïve ±8 expansion.
                let visible = rect.intersection(viewport)
                let leftCap   = min(8, visible.minX)
                let rightCap  = min(8, viewport.maxX - visible.maxX)
                let topCap    = min(8, visible.minY)
                let bottomCap = min(8, viewport.maxY - visible.maxY)
                let renderedRing = CGRect(
                    x: visible.minX - leftCap,
                    y: visible.minY - topCap,
                    width:  visible.width  + leftCap + rightCap,
                    height: visible.height + topCap  + bottomCap
                )
                let ringIn = viewport.contains(renderedRing)
                if ringIn {
                    if leftCap < 8 || rightCap < 8 || topCap < 8 || bottomCap < 8 {
                        // Ring is on-screen but the pad was clamped
                        // because the anchor touches a screen edge.
                        // Report the actual rendered rect for clarity.
                        lines.append("  spotlight ring (capped pad): ✓ FULLY ENCLOSED (pad clamped — left=\(fmt(leftCap)) right=\(fmt(rightCap)) top=\(fmt(topCap)) bottom=\(fmt(bottomCap)))")
                    } else {
                        lines.append("  spotlight ring (±8pt pad): ✓ FULLY ENCLOSED")
                    }
                } else {
                    // Should not normally happen post-clamp; report
                    // the rendered rect + overflow for diagnosis.
                    lines.append("  spotlight ring (rendered): x=\(fmt(renderedRing.minX)) y=\(fmt(renderedRing.minY)) w=\(fmt(renderedRing.width)) h=\(fmt(renderedRing.height))")
                    let rL = renderedRing.minX < viewport.minX ? viewport.minX - renderedRing.minX : 0
                    let rR = renderedRing.maxX > viewport.maxX ? renderedRing.maxX - viewport.maxX : 0
                    let rT = renderedRing.minY < viewport.minY ? viewport.minY - renderedRing.minY : 0
                    let rB = renderedRing.maxY > viewport.maxY ? renderedRing.maxY - viewport.maxY : 0
                    lines.append("  ✗ ring CLIPPED — left=\(fmt(rL)) right=\(fmt(rR)) top=\(fmt(rT)) bottom=\(fmt(rB))")
                }
                let intersects = viewport.intersects(rect)
                if !intersects {
                    lines.append("  ⚠ anchor entirely OFF-SCREEN — overlay falls back to centered tooltip + chevron")
                }
            } else {
                lines.append("  anchor rect: ✗ ANCHOR NOT REGISTERED")
                lines.append("  → no view in the current host has called .walkthroughAnchor(\"\(anchorKey.key)\")")
                lines.append("  → all currently-registered keys: \(anchorFrames.keys.map { $0.key }.sorted().joined(separator: ", "))")
            }
        } else {
            lines.append("  anchor: nil (full-screen step — intro/outro)")
        }

        let block = lines.joined(separator: "\n")
        print(block)
        // NSLog is verbose but reliably visible — print() can be
        // swallowed by Xcode filter state or stdout routing in iOS 26.
        NSLog("%@", block as NSString)
    }

    private func fmt(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
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

    /// True when the Skip/Done bar should render at the TOP of the
    /// screen rather than the bottom — used for steps whose anchor
    /// lives in the lower half of the viewport (Scanner mode pills,
    /// Decks summary pill, etc.) so the bar doesn't cover the very
    /// controls it's pointing at.
    private var barAtTop: Bool {
        guard let rect = currentAnchorRect, anchorIsVisible(rect) else {
            return false
        }
        return rect.midY > containerSize.height * 0.5
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
            // (e.g., expand a drawer to reveal the anchor). The
            // diagnostic log fires from .onChange(of: currentStep)
            // above so it reads the post-render anchor frames.
            onStage?(step?.stage)
        }
    }

    private func complete() {
        logDiagnostics(event: "DISMISS")
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
    /// each edge so all four sides remain visible. For full-width
    /// anchors (like the deck summary pill or the scanner mode
    /// pills), the inset is reduced so the ring stays inside the
    /// screen instead of pushing 8pt past either edge.
    @ViewBuilder
    private func spotlightRing(rect: CGRect) -> some View {
        let viewport = CGRect(origin: .zero, size: containerSize)
        let visible = rect.intersection(viewport)
        // Compute a per-edge inset that's normally -8 but caps at the
        // available margin on each side. This prevents the ring from
        // overflowing for anchors that touch the screen edges.
        let leftInset:   CGFloat = -min(8, visible.minX)
        let rightInset:  CGFloat = -min(8, viewport.maxX - visible.maxX)
        let topInset:    CGFloat = -min(8, visible.minY)
        let bottomInset: CGFloat = -min(8, viewport.maxY - visible.maxY)
        let clamped = CGRect(
            x: visible.minX + leftInset,
            y: visible.minY + topInset,
            width:  visible.width  - leftInset - rightInset,
            height: visible.height - topInset  - bottomInset
        ).intersection(viewport)
        if visible.width > 4 && visible.height > 4 {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Design.Colors.bobaCyan, lineWidth: 2)
                .frame(width: clamped.width, height: clamped.height)
                .position(x: clamped.midX, y: clamped.midY)
                .shadow(color: Design.Colors.bobaCyan.opacity(0.7), radius: 10)
                .allowsHitTesting(false)
        }
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
        // Bottom padding only applies when the bar is rendered at
        // the bottom — clears the system tab bar (≈49pt) + home
        // indicator (safeBottomInset, ≈34pt). When the bar is at
        // the top (adaptive layout above), the wrapping VStack adds
        // its own top padding instead and this value is irrelevant.
        .padding(.bottom, barAtTop ? 0 : safeBottomInset + 56)
    }
}

// MARK: - Walkthrough catalog (DESIGN.md §6.10.1)

extension BOBAWalkthrough.Script {

    static let findTab = BOBAWalkthrough.Script(
        id: .findTab,
        steps: [
            // Search anchor dropped — Tab(role: .search) puts the
            // field in the system tab bar, not the view. Ribbons
            // dropped — only render when showcaseMode is on
            // (default false), so they're not present on first
            // visit either. The four anchors below are all toolbar
            // items + first card cell, all guaranteed on-screen.
            .init(anchor: .init("find.menu"),     copy: "Open the menu for filters and Card Showcases."),
            .init(anchor: .init("find.cardCell"), copy: "Tap a card to see details, prices, and decks."),
            .init(anchor: .init("find.scan"),     copy: "Scan a real card to identify it instantly."),
            .init(anchor: .init("find.profile"),  copy: "Sign in to save cards to your collection.")
        ]
    )

    static let learnTab = BOBAWalkthrough.Script(
        id: .learnTab,
        // Both steps anchor on the first tile — the rootList anchor
        // (LazyVGrid wrapper) measured wrong on first appear because
        // its children hadn't laid out yet, so the spotlight landed
        // off-screen. Anchoring twice on the same first tile keeps
        // the spotlight in a consistent, always-visible spot.
        steps: [
            .init(anchor: .init("learn.firstRow"), copy: "Six learning paths to get better at BoBA."),
            .init(anchor: .init("learn.firstRow"), copy: "Tap any tile to read, watch, or browse.")
        ]
    )

    static let decksTab = BOBAWalkthrough.Script(
        id: .decksTab,
        // Pool-only walkthrough. The format chip + save button steps
        // moved out — those anchors live inside the fullScreenCover
        // editor (a separate presentation context) and are unreachable
        // from the pool view's overlay. The summary pill IS the entry
        // point to the editor; tapping it opens those features.
        steps: [
            .init(anchor: .init("decks.cardPool"),    copy: "Tap to view a card. Long-press to add to the deck."),
            .init(anchor: .init("decks.summaryPill"), copy: "Tap the summary to open your deck editor.")
        ]
    )

    static let collectionTab = BOBAWalkthrough.Script(
        id: .collectionTab,
        // scopeBar restored — the 250ms host-side deferral lets the
        // segmented Picker lay out before the walkthrough fires, so
        // the rect is no longer the pre-layout (-20,-20,40,47) artifact.
        steps: [
            .init(anchor: .init("collection.scopeBar"),    copy: "Switch between Personal, Sale, Trade, Wanted, and Grails."),
            .init(anchor: .init("collection.cardCell"),    copy: "Tap a card to view value, designation, and notes."),
            .init(anchor: .init("collection.displayMode"), copy: "Open the menu to change view or share a Wall image.")
        ]
    )

    /// Fires on first editor open from DecksView. The pool's
    /// decksTab walkthrough teaches the pool surfaces; this one
    /// teaches the editor (format, deck list with stat counts +
    /// DBS budget, save). Together they cover the full deck-build
    /// flow without crossing presentation boundaries.
    static let decksEditor = BOBAWalkthrough.Script(
        id: .decksEditor,
        steps: [
            .init(anchor: .init("decksEditor.statRow"),
                  copy: "Heroes, Plays, Bonus, Hot Dogs, DBS — your build at a glance."),
            .init(anchor: .init("decksEditor.formatChip"),
                  copy: "Format shapes the whole deck — pick before you build.",
                  placement: .below),
            .init(anchor: .init("decksEditor.deckList"),
                  copy: "Tap a card to view it. Tap × to remove."),
            // saveButton DOES register and is on-screen per the
            // diagnostic. Reverted from the deckName fallback —
            // deckName never registered (TextField inside HStack
            // inside a sheet's VStack apparently doesn't propagate)
            // while saveButton consistently does.
            .init(anchor: .init("decksEditor.saveButton"),
                  copy: "Sign in and tap SAVE to sync your deck across devices.",
                  placement: .below)
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

    /// Unified scanner overview — fires on first ScanView open.
    /// Two steps for everyone: viewfinder + mode pills. The Show-mode
    /// step that used to be conditional was dropped — `auth.isStreamer`
    /// can be stale at .onAppear time relative to render time, which
    /// produced an "anchor not registered" failure when the script
    /// was built thinking isStreamer=true but the modePill rendered
    /// with isStreamer=false. Streamers learn Show mode by seeing
    /// the SHOW pill in the row described by step 2.
    ///
    /// Anchors are deliberately limited to UI elements guaranteed to
    /// be on-screen the first time the scanner opens. Transient
    /// anchors (queue button, detection chip) excluded — users
    /// discover them naturally, and a "this appears here" step that
    /// points to nothing breaks worse than no step at all.
    static let scannerOverview = BOBAWalkthrough.Script(
        id: .scannerOverview,
        steps: [
            .init(anchor: .init("scanner.viewfinder"),
                  copy: "Hold a card in the frame — we identify it on-device."),
            .init(anchor: .init("scanner.modePills"),
                  copy: "Single saves one. Multi queues many. Grid captures 3–9.",
                  placement: .above)
        ]
    )
}
