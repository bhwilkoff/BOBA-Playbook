//
//  PracticeTutorialOverlay.swift
//  BOBAPlaybook
//
//  First-run spotlight walkthrough for Practice Battle. Each step traces
//  a glowing ring around the real UI element it describes and anchors a
//  tooltip card adjacent with a directional arrow. The backdrop is a
//  faint scrim — no blur — so the user can always see the feature.
//
//  Subviews opt into targeting with `.tutorialTarget(.case)`. PracticeView
//  collects the anchors via preference and resolves them to screen frames
//  before handing them to this overlay.
//

import SwiftUI

// ════════════════════════════════════════════════════════════════
// MARK: - Target identity
// ════════════════════════════════════════════════════════════════

enum TutorialTarget: Hashable {
    case scoreboard
    case activeBattle
    case bench
    case plays
    case advance
}

struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>],
                       nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) {
            [target: $0]
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Step definitions
// ════════════════════════════════════════════════════════════════

struct PracticeTutorialStep: Identifiable {
    enum Placement { case above, below, leading, trailing }
    let id = UUID()
    let target: TutorialTarget
    let title: String
    let message: String
    let placement: Placement
}

extension Array where Element == PracticeTutorialStep {
    static let practiceDefault: [PracticeTutorialStep] = [
        .init(target: .scoreboard,   title: "Battle Score",
              message: "Your wins vs. the CPU's. First to 4 Battles wins the match. If it's 3–3 after Battle 7, Sudden Death decides the game.",
              placement: .below),
        .init(target: .activeBattle, title: "The Active Battle",
              message: "Your Hero faces the CPU's. Higher Power wins this Battle. If Power is tied, a Hero with a Super Weapon wins — otherwise the Battle is a draw (no trophy).",
              placement: .below),
        .init(target: .bench,        title: "Your Bench",
              message: "Before Heroes are revealed, the Honors player may spend 2 Hot Dogs to swap their face-down Hero for one from the Bench. One Sub per Battle.",
              placement: .above),
        .init(target: .plays,        title: "Your Plays",
              message: "After Heroes reveal, the Honors player goes first. Play any number of Plays (paying Hot Dogs) or pass — each player gets one turn to play Plays per Battle.",
              placement: .above),
        .init(target: .advance,      title: "Advance the Battle",
              message: "Each Battle runs: Substitute → Reveal → Play → Resolve. After the Battle, both players draw 1 Play and the winner takes Honors next. Tap here to advance.",
              placement: .above)
    ]
}

// ════════════════════════════════════════════════════════════════
// MARK: - Overlay
// ════════════════════════════════════════════════════════════════

struct PracticeTutorialOverlay: View {
    let steps: [PracticeTutorialStep]
    let targetFrames: [TutorialTarget: CGRect]
    let containerSize: CGSize
    let onFinish: () -> Void

    @State private var index: Int = 0

    init(steps: [PracticeTutorialStep] = .practiceDefault,
         targetFrames: [TutorialTarget: CGRect],
         containerSize: CGSize,
         onFinish: @escaping () -> Void) {
        self.steps = steps
        self.targetFrames = targetFrames
        self.containerSize = containerSize
        self.onFinish = onFinish
    }

    private var step: PracticeTutorialStep { steps[index] }
    private var isLast: Bool { index >= steps.count - 1 }
    private var targetRect: CGRect? { targetFrames[step.target] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Faint scrim — blocks interaction without blurring content.
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            if let rect = targetRect {
                // Glowing ring tracing the target element
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

                // Tooltip card + arrow
                tooltipView(for: rect)
            }
            // If targetRect is nil we just show the scrim and wait — anchors
            // may still be propagating on the first frame. The next render
            // (once preferences settle) will show the ring + tooltip.
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: index)
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

            arrowShape
                .fill(Design.Colors.surface)
                .overlay(arrowShape.stroke(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                .frame(width: 14, height: 14)
                .rotationEffect(layout.arrowRotation)
                .offset(layout.arrowOffset)
        }
        .position(x: layout.origin.x, y: layout.origin.y)
    }

    private var arrowShape: some Shape {
        Triangle()
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
        let origin: CGPoint              // center position for ZStack.position
        let cardSize: CGSize
        let arrowAlignment: Alignment    // where the arrow sits in the ZStack
        let arrowRotation: Angle
        let arrowOffset: CGSize
    }

    private func computeLayout(for rect: CGRect) -> TooltipLayout {
        let cardWidth: CGFloat = min(380, containerSize.width - 32)
        let estimatedHeight: CGFloat = 180  // rough; tooltip auto-sizes vertically
        let gap: CGFloat = 16
        let halfW = cardWidth / 2
        let halfH = estimatedHeight / 2

        // Compute candidate centers in each direction
        let below = CGPoint(x: rect.midX, y: rect.maxY + gap + halfH)
        let above = CGPoint(x: rect.midX, y: rect.minY - gap - halfH)
        let lead  = CGPoint(x: rect.minX - gap - halfW, y: rect.midY)
        let trail = CGPoint(x: rect.maxX + gap + halfW, y: rect.midY)

        // Fit-check helper
        func fits(_ p: CGPoint) -> Bool {
            p.x - halfW >= 12 && p.x + halfW <= containerSize.width - 12 &&
            p.y - halfH >= 12 && p.y + halfH <= containerSize.height - 12
        }

        // Start with preferred placement, fall back in order
        var order: [(CGPoint, PracticeTutorialStep.Placement)] = []
        switch step.placement {
        case .below:    order = [(below, .below), (above, .above), (trail, .trailing), (lead, .leading)]
        case .above:    order = [(above, .above), (below, .below), (trail, .trailing), (lead, .leading)]
        case .trailing: order = [(trail, .trailing), (lead, .leading), (below, .below), (above, .above)]
        case .leading:  order = [(lead, .leading),  (trail, .trailing), (below, .below), (above, .above)]
        }

        var chosen = order[0]
        for (pt, pl) in order where fits(pt) { chosen = (pt, pl); break }

        // Clamp center so card stays on screen
        let clamped = CGPoint(
            x: min(max(chosen.0.x, halfW + 12), containerSize.width - halfW - 12),
            y: min(max(chosen.0.y, halfH + 12), containerSize.height - halfH - 12)
        )

        // Arrow points toward target; rotation aims the triangle's tip at the ring
        let alignment: Alignment
        let rotation: Angle
        let offset: CGSize
        switch chosen.1 {
        case .below:
            alignment = .top
            rotation  = .degrees(0)              // tip up
            offset    = CGSize(width: clamp(rect.midX - (clamped.x - halfW), 20, cardWidth - 20) - halfW, height: -7)
        case .above:
            alignment = .bottom
            rotation  = .degrees(180)            // tip down
            offset    = CGSize(width: clamp(rect.midX - (clamped.x - halfW), 20, cardWidth - 20) - halfW, height: 7)
        case .trailing:
            alignment = .leading
            rotation  = .degrees(-90)            // tip left
            offset    = CGSize(width: -7, height: 0)
        case .leading:
            alignment = .trailing
            rotation  = .degrees(90)             // tip right
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

// Simple upward-pointing triangle used for the tooltip arrow.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX,  y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX,  y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX,  y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
