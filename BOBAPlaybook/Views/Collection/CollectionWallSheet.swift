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
    /// Per user feedback #10 — coaches with large collections need to
    /// curate the wall: which cards to include, and which to highlight
    /// (rendered with the gold-glow accent the streamer ShowDetailView
    /// uses). Both default to "everything in / nothing highlighted" so
    /// small collections work without explicit selection. `included`
    /// is a Set of bobaIds; cards not in the set are excluded.
    /// `bigHits` is a Set of bobaIds for the highlight accent.
    @State private var included: Set<String> = []
    @State private var bigHits: Set<String> = []

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
        // Default everything to included so small collections render
        // out of the box. Coaches can deselect what they don't want.
        _included = State(initialValue: Set(cards.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Order per user feedback: select cards FIRST, see the
                // preview at the bottom. Selecting before previewing
                // matches the user's mental model — "build the wall,
                // then see what it looks like."
                VStack(spacing: Design.Spacing.lg) {
                    titleField
                    overlayToggle
                    cardSelector
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
            .walkthroughOverlay($walkthrough)
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
                    // wall.aspect anchor removed — there's no aspect
                    // picker in the new layout. Replaced by wall.selector
                    // which lives on the always-visible card grid.
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

    // MARK: - Card selector (user feedback #10)

    /// Grid of every card under the active designation with two
    /// per-card toggles: tap to include/exclude (cyan ring when
    /// included), long-press to mark as a big-hit highlight (gold
    /// ring + star — same accent the streamer ShowDetailView's wall
    /// uses to call out chase cards). Coaches with large collections
    /// can curate exactly what lands on the wall instead of being
    /// forced to use every card under the designation.
    @ViewBuilder
    private var cardSelector: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Text("CARDS ON THE WALL")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Spacer()
                Text("\(included.count) of \(cards.count) · ★ \(bigHits.count) highlighted")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            HStack(spacing: Design.Spacing.sm) {
                Button("Select all") {
                    included = Set(cards.map(\.id))
                    Task { await compose() }
                }
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
                Button("Select none") {
                    included.removeAll()
                    bigHits.removeAll()
                    Task { await compose() }
                }
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                Spacer()
                Text("Tap = include · Long-press = highlight")
                    .font(Design.Fonts.mono(9))
                    .foregroundStyle(Design.Colors.textMuted)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: Design.Spacing.sm)],
                spacing: Design.Spacing.sm
            ) {
                ForEach(cards) { card in
                    selectorTile(card)
                }
            }
            .walkthroughAnchor("wall.selector")
        }
    }

    @ViewBuilder
    private func selectorTile(_ card: Card) -> some View {
        let isIncluded = included.contains(card.id)
        let isBigHit  = bigHits.contains(card.id)
        ZStack(alignment: .topTrailing) {
            BOBACardCell(card: card)
                .frame(width: 70, height: 98)
                .overlay(
                    RoundedRectangle(cornerRadius: BOBACardCell.cornerRadius)
                        .strokeBorder(
                            isBigHit ? Color(hex: "FFD700")
                                     : (isIncluded ? Design.Colors.bobaCyan : Color.white.opacity(0.1)),
                            lineWidth: isBigHit ? 2.5 : (isIncluded ? 2 : 1)
                        )
                )
                .overlay(
                    !isIncluded
                        ? RoundedRectangle(cornerRadius: BOBACardCell.cornerRadius)
                            .fill(Color.black.opacity(0.55))
                        : nil
                )
                .opacity(isIncluded ? 1 : 0.55)
            if isBigHit {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "FFD700"))
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .padding(4)
            } else if isIncluded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .background(Circle().fill(Design.Colors.nearBlack).padding(2))
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        // Single gesture chain: long-press FIRST (high priority) so
        // SwiftUI doesn't fire the brief tap-feedback "flash" the user
        // saw when both .onTapGesture and .onLongPressGesture were
        // racing on the same view. The tap gesture composes after via
        // .simultaneousGesture so a quick tap still toggles inclusion.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    if isBigHit {
                        bigHits.remove(card.id)
                    } else {
                        included.insert(card.id)
                        bigHits.insert(card.id)
                    }
                    Task { await compose() }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    if isIncluded {
                        included.remove(card.id)
                        bigHits.remove(card.id)
                    } else {
                        included.insert(card.id)
                    }
                    Task { await compose() }
                }
        )
        .accessibilityLabel(card.hero.isEmpty ? card.name : card.hero)
        .accessibilityValue(isBigHit ? "Highlighted on wall" : (isIncluded ? "Included on wall" : "Excluded"))
        .accessibilityAddTraits(isIncluded ? .isSelected : [])
    }

    // MARK: - Composition

    private func compose() async {
        // Honor the user's card selection — only included cards land
        // on the wall, big-hits get the gold/glow accent (same as
        // streamer ShowDetailView's wall flow).
        let chosen = cards.filter { included.contains($0.id) }
        guard !chosen.isEmpty else { wallImage = nil; return }
        isComposing = true
        let opts = ShowWallOptions(
            includeBranding: includeBranding,
            includeTitle: !title.isEmpty,
            customText: title,
            includePrices: includePrices
        )
        let bigHitFlags = chosen.map { bigHits.contains($0.id) }
        let img = await ShowWallComposer.compose(
            cards: chosen,
            bigHits: bigHitFlags,
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
