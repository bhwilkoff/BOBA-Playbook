//
//  CollectionWallSheet.swift
//  BOBAPlaybook
//
//  Generic Wall view for the Collection tab per DESIGN.md §8.4 + §8.8.
//  Renders the cards under the active designation as a tile-able image
//  using ShowWallComposer (the underlying composer is role-agnostic;
//  only the streamer-specific ShowDetailView invocation path was gated).
//
//  Per DECISIONS.md #036, this lifts Wall view from streamer-only.
//
//  Anatomy per §8.8:
//   - Title strip (top): contextual, editable
//   - Aspect ratio picker: source-context default
//   - Save / Share / Copy + overlay toggle
//   - Optional Price Overlay (per-designation defaults per §8.8)
//

import SwiftUI

struct CollectionWallSheet: View {
    let designation: UserCard.Designation
    let cards: [Card]
    let prices: [String: Decimal]   // bobaId → estimated value (for Price Overlay)
    let onDismiss: () -> Void

    @State private var title: String
    @State private var includePrices: Bool
    @State private var includeBranding: Bool = true
    @State private var wallImage: UIImage? = nil
    @State private var isComposing = false
    @State private var showShare = false
    @State private var walkthrough: BOBAWalkthrough.Script? = nil

    init(
        designation: UserCard.Designation,
        cards: [Card],
        prices: [String: Decimal] = [:],
        onDismiss: @escaping () -> Void
    ) {
        self.designation = designation
        self.cards = cards
        self.prices = prices
        self.onDismiss = onDismiss
        _title = State(initialValue: Self.defaultTitle(for: designation))
        _includePrices = State(initialValue: Self.defaultPriceOverlay(for: designation))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    titleField
                    overlayToggle
                    wallPreview
                    if let img = wallImage {
                        actionsRow(img: img)
                    }
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Wall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDismiss() }
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Branding", isOn: $includeBranding)
                        Toggle("Prices", isOn: $includePrices)
                        Divider()
                        Button {
                            WalkthroughsManager.shared.relaunch(.wallView)
                            walkthrough = .wallView
                        } label: {
                            Label("Show walkthrough", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    .accessibilityLabel("Wall options")
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay {
                if let script = walkthrough {
                    BOBAWalkthrough(script: script) {
                        WalkthroughsManager.shared.dismiss(script.id)
                        walkthrough = nil
                    }
                }
            }
            .task {
                await compose()
                if WalkthroughsManager.shared.shouldShow(.wallView) {
                    walkthrough = .wallView
                }
            }
            .onChange(of: includePrices) { _, _ in Task { await compose() } }
            .onChange(of: includeBranding) { _, _ in Task { await compose() } }
            .onChange(of: title) { _, _ in Task { await compose() } }
        }
    }

    // MARK: - UI pieces

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TITLE")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            TextField("Wall title", text: $title)
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
                .submitLabel(.done)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .fill(Design.Colors.glass)
                )
        }
    }

    private var overlayToggle: some View {
        HStack(spacing: Design.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PRICE OVERLAY")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text(priceOverlayCaption)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $includePrices)
                .labelsHidden()
                .tint(Design.Colors.bobaCyan)
        }
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.glass)
        )
        .walkthroughAnchor("wall.overlay")
    }

    private var priceOverlayCaption: String {
        switch designation {
        case .for_sale: return "Show your asking price on each tile"
        case .for_trade: return "Show market estimate for trade discussion"
        case .wanted:    return "Show estimated value (WTB) for each card"
        default:         return "Show estimated value on each tile"
        }
    }

    private var wallPreview: some View {
        Group {
            if isComposing {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if let img = wallImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(5.0/7.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                    )
                    .walkthroughAnchor("wall.aspect")
            } else {
                BOBAEmptyState(
                    title: "Couldn't render wall",
                    systemImage: "photo.on.rectangle.angled",
                    message: cards.isEmpty
                        ? "Add cards to this designation, then come back."
                        : "Try toggling Branding or Prices."
                ) {
                    EmptyView()
                }
            }
        }
    }

    private func actionsRow(img: UIImage) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Button {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaCyan.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaCyan.opacity(0.4), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            Button {
                showShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaOrange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .walkthroughAnchor("wall.share")
            .sheet(isPresented: $showShare) {
                ActivityShareSheet(items: [img])
            }
        }
    }

    // MARK: - Composition

    private func compose() async {
        guard !cards.isEmpty else { wallImage = nil; return }
        isComposing = true
        let opts = ShowWallOptions(
            includeBranding: includeBranding,
            includeTitle: !title.isEmpty,
            customText: title,
            includePrices: includePrices
        )
        // No "big hits" semantics outside streamer shows — every tile
        // gets equal weight.
        let bigHits = Array(repeating: false, count: cards.count)
        let img = await ShowWallComposer.compose(
            cards: cards,
            bigHits: bigHits,
            title: title,
            options: opts,
            prices: includePrices ? prices : [:]
        )
        wallImage = img
        isComposing = false
    }

    // MARK: - Defaults per designation (§8.8)

    private static func defaultTitle(for d: UserCard.Designation) -> String {
        switch d {
        case .personal:  return "My Collection"
        case .for_sale:  return "For Sale"
        case .for_trade: return "For Trade"
        case .wanted:    return "Wanted (WTB)"
        case .grails:    return "My Grails"
        }
    }

    /// Per DESIGN.md §8.8 per-designation Price Overlay defaults.
    private static func defaultPriceOverlay(for d: UserCard.Designation) -> Bool {
        switch d {
        case .for_sale, .for_trade, .wanted: return true
        case .personal, .grails:             return false
        }
    }
}
