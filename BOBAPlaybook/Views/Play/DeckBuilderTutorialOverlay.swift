//
//  DeckBuilderTutorialOverlay.swift
//  BOBAPlaybook
//
//  First-run walkthrough for the Deck Builder. Mirrors the Practice Battle
//  tutorial pattern (PracticeTutorialOverlay) — anchor-preference targets
//  on the real subviews, a glowing ring to spotlight each one, and a
//  tooltip card with a directional arrow. Fires once per install.
//
//  Separate from PracticeTutorialOverlay so each feature has its own
//  targeting vocabulary; the rendering code is intentionally duplicated
//  because it's small and the two tutorials have different step counts.
//

import SwiftUI

// ════════════════════════════════════════════════════════════════
// MARK: - Target identity
// ════════════════════════════════════════════════════════════════

enum DeckBuilderTutorialTarget: Hashable {
    case formatPicker
    case rulesButton
    case browser
    case deckList
    case deckMenu
    case helpButton
    case collectionToggle
    case legalityButton
}

struct DeckBuilderAnchorKey: PreferenceKey {
    static var defaultValue: [DeckBuilderTutorialTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DeckBuilderTutorialTarget: Anchor<CGRect>],
                       nextValue: () -> [DeckBuilderTutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Register this view as the highlight target for `target`.
    ///
    /// Uses `transformAnchorPreference` rather than `anchorPreference` so
    /// the child's contribution merges into the dict rolled up from
    /// descendants instead of replacing it. The original
    /// `anchorPreference` form drops sibling/descendant entries — that
    /// caused the cardBrowser-wrapping `.deckBuilderTutorialTarget(.browser)`
    /// to wipe out anchors set on inner buttons (collectionToggle, etc.),
    /// which manifested as the walkthrough silently skipping those steps.
    func deckBuilderTutorialTarget(_ target: DeckBuilderTutorialTarget) -> some View {
        transformAnchorPreference(key: DeckBuilderAnchorKey.self, value: .bounds) { dict, anchor in
            dict[target] = anchor
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Step definitions
// ════════════════════════════════════════════════════════════════

struct DeckBuilderTutorialStep: Identifiable {
    enum Placement { case above, below, leading, trailing }
    let id = UUID()
    let target: DeckBuilderTutorialTarget
    let title: String
    let message: String
    let placement: Placement
}

extension Array where Element == DeckBuilderTutorialStep {
    static let deckBuilderDefault: [DeckBuilderTutorialStep] = [
        .init(target: .formatPicker, title: "Pick a Hero Format",
              message: "Apex (no power cap), Spec (≤160), Elite (8,250 total with no Trainers), or SPEC+ (up to 70 heroes with tiered 175-200 slots). Each shapes what you can build.",
              placement: .below),
        .init(target: .rulesButton, title: "Rule Sets + Divisions",
              message: "Pick a preset from the 2026 Nationals events (Apex Playmaker, Brawl, Blast, Tecmo Bowl, Granny's Gum…) — or start casual. Toggle individual rules like 6-per-hero, per-power caps, or DBS enforcement any time.",
              placement: .below),
        .init(target: .legalityButton, title: "Legality at a Glance",
              message: "Tap the seal to see exactly which rule each card breaks (or passes) under the active format + divisions. The badge in the stats bar flips between LEGAL and ILLEGAL in real time as you build.",
              placement: .below),
        .init(target: .browser, title: "Browse the Catalog",
              message: "Search 17k+ cards, filter by weapon, switch tabs for Heroes / Plays / Hot Dogs. Tap a card to preview — or flip Quick-Add to tap-to-add instantly.",
              placement: .above),
        .init(target: .collectionToggle, title: "Build From What You Own",
              message: "Toggle the grid icon next to the search field to restrict the picker to cards already in your Collection. Great for figuring out what's actually playable from your binder right now.",
              placement: .below),
        .init(target: .deckList, title: "Your Deck",
              message: "Cards land here as you build. Tap the chevron to expand each section, edit the deck name any time, and watch the legality + DBS chips update in real time.",
              placement: .above),
        .init(target: .deckMenu, title: "Save, Load, Import",
              message: "Save your deck to the cloud, reload a saved deck, or import one from a CSV exported from the official deck builder. Your work auto-saves when you leave — you won't lose it.",
              placement: .below),
        .init(target: .helpButton, title: "Replay This Walkthrough",
              message: "Tap the question mark any time to see this tour again. We added new bits when the legality auditor and per-power caps shipped — pop back in if you want a refresher.",
              placement: .below)
    ]
}

// ════════════════════════════════════════════════════════════════
// MARK: - Overlay
// ════════════════════════════════════════════════════════════════

struct DeckBuilderTutorialOverlay: View {
    let steps: [DeckBuilderTutorialStep]
    let targetFrames: [DeckBuilderTutorialTarget: CGRect]
    let containerSize: CGSize
    /// Top + bottom safe-area insets read from the host so tooltip
    /// placement excludes the iPad menu bar / nav bar / tab bar
    /// regions instead of using the hardcoded 12pt margins. Without
    /// this the tooltip can land under the iPad menu bar in landscape.
    let safeTopInset: CGFloat
    let safeBottomInset: CGFloat
    let onFinish: () -> Void

    @State private var index: Int = 0

    init(steps: [DeckBuilderTutorialStep] = .deckBuilderDefault,
         targetFrames: [DeckBuilderTutorialTarget: CGRect],
         containerSize: CGSize,
         safeTopInset: CGFloat = 0,
         safeBottomInset: CGFloat = 0,
         onFinish: @escaping () -> Void) {
        self.steps = steps
        self.targetFrames = targetFrames
        self.containerSize = containerSize
        self.safeTopInset = safeTopInset
        self.safeBottomInset = safeBottomInset
        self.onFinish = onFinish
    }

    private var step: DeckBuilderTutorialStep { steps[index] }
    private var isLast: Bool { index >= steps.count - 1 }
    private var targetRect: CGRect? { targetFrames[step.target] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            if let rect = targetRect, isOnScreen(rect) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Design.Colors.bobaOrange, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Design.Colors.bobaOrange.opacity(0.35), lineWidth: 6)
                    )
                    .shadow(color: Design.Colors.bobaOrange.opacity(0.55), radius: 14)
                    .frame(width: rect.width + 12, height: rect.height + 12)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                tooltipView(for: rect)
            } else {
                // Anchor missing or off-screen — render the tooltip
                // centered with no highlight ring so the user still
                // sees the step's title + message instead of a blank
                // dimmed page.
                centeredTooltip
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: index)
    }

    /// True when the rect lives within the proxy bounds with at least
    /// some pixels visible. A rect that lands fully off-screen (e.g.,
    /// because an anchor lives in a coordinate space the proxy doesn't
    /// cover) would otherwise produce a highlight ring no one can see.
    private func isOnScreen(_ rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let visible = CGRect(x: 0, y: 0,
                             width: containerSize.width,
                             height: containerSize.height)
        return visible.intersects(rect)
    }

    private var centeredTooltip: some View {
        cardBody
            .frame(width: min(360, containerSize.width - 32))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Design.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
            )
            .position(x: containerSize.width / 2, y: containerSize.height / 2)
    }

    // MARK: - Tooltip layout

    @ViewBuilder
    private func tooltipView(for rect: CGRect) -> some View {
        let layout = computeLayout(for: rect)
        ZStack(alignment: layout.arrowAlignment) {
            cardBody
                .frame(width: layout.cardSize.width)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Design.Colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
                )

            TutorialArrow()
                .fill(Design.Colors.surface)
                .overlay(TutorialArrow().stroke(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                .frame(width: 14, height: 14)
                .rotationEffect(layout.arrowRotation)
                .offset(layout.arrowOffset)
        }
        .position(x: layout.origin.x, y: layout.origin.y)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Text("STEP \(index + 1) OF \(steps.count)")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Design.Colors.bobaCyan.opacity(0.12)))
                Spacer()
                Button { finish() } label: {
                    Text("SKIP")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            Text(step.title)
                .font(Design.Fonts.display(20))
                .foregroundStyle(Design.Colors.textPrimary)

            Text(step.message)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Design.Colors.bobaOrange : Design.Colors.textMuted.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }

            Button { advance() } label: {
                Text(isLast ? "GOT IT" : "NEXT")
                    .font(Design.Fonts.mono(12, weight: .bold))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .padding(.horizontal, 24)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.bobaOrange))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    // MARK: - Layout math

    private struct TooltipLayout {
        let origin: CGPoint
        let cardSize: CGSize
        let arrowAlignment: Alignment
        let arrowRotation: Angle
        let arrowOffset: CGSize
    }

    private func computeLayout(for rect: CGRect) -> TooltipLayout {
        let cardWidth: CGFloat = min(360, containerSize.width - 32)
        let estimatedHeight: CGFloat = 200
        let gap: CGFloat = 16
        let halfW = cardWidth / 2
        let halfH = estimatedHeight / 2

        let below = CGPoint(x: rect.midX, y: rect.maxY + gap + halfH)
        let above = CGPoint(x: rect.midX, y: rect.minY - gap - halfH)
        let lead  = CGPoint(x: rect.minX - gap - halfW, y: rect.midY)
        let trail = CGPoint(x: rect.maxX + gap + halfW, y: rect.midY)

        // Reserve safe-area chrome (status bar / nav bar / iPad menu
        // bar at top, tab bar at bottom) plus a small margin. Without
        // this the tooltip can sit under the iPad menu bar in landscape.
        let topBound = safeTopInset + 12
        let bottomBound = containerSize.height - safeBottomInset - 12
        func fits(_ p: CGPoint) -> Bool {
            p.x - halfW >= 12 && p.x + halfW <= containerSize.width - 12 &&
            p.y - halfH >= topBound && p.y + halfH <= bottomBound
        }

        var order: [(CGPoint, DeckBuilderTutorialStep.Placement)] = []
        switch step.placement {
        case .below:    order = [(below, .below), (above, .above), (trail, .trailing), (lead, .leading)]
        case .above:    order = [(above, .above), (below, .below), (trail, .trailing), (lead, .leading)]
        case .trailing: order = [(trail, .trailing), (lead, .leading), (below, .below), (above, .above)]
        case .leading:  order = [(lead, .leading),  (trail, .trailing), (below, .below), (above, .above)]
        }

        var chosen = order[0]
        for (pt, pl) in order where fits(pt) { chosen = (pt, pl); break }

        let clamped = CGPoint(
            x: min(max(chosen.0.x, halfW + 12), containerSize.width - halfW - 12),
            y: min(max(chosen.0.y, halfH + 12), containerSize.height - halfH - 12)
        )

        let alignment: Alignment
        let rotation: Angle
        let offset: CGSize
        switch chosen.1 {
        case .below:
            alignment = .top
            rotation  = .degrees(0)
            offset    = CGSize(width: clamp(rect.midX - (clamped.x - halfW), 20, cardWidth - 20) - halfW, height: -7)
        case .above:
            alignment = .bottom
            rotation  = .degrees(180)
            offset    = CGSize(width: clamp(rect.midX - (clamped.x - halfW), 20, cardWidth - 20) - halfW, height: 7)
        case .trailing:
            alignment = .leading
            rotation  = .degrees(-90)
            offset    = CGSize(width: -7, height: 0)
        case .leading:
            alignment = .trailing
            rotation  = .degrees(90)
            offset    = CGSize(width: 7, height: 0)
        }

        return TooltipLayout(
            origin: clamped,
            cardSize: CGSize(width: cardWidth, height: estimatedHeight),
            arrowAlignment: alignment,
            arrowRotation: rotation,
            arrowOffset: offset
        )
    }

    private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

    // MARK: - Navigation
    private func advance() {
        if isLast { finish() } else { index += 1 }
    }
    private func finish() { onFinish() }
}

/// Upward-pointing triangle for tooltip arrows.
private struct TutorialArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
