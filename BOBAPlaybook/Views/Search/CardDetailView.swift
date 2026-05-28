import SwiftUI

struct CardDetailView: View {
    // The card passed on init; navigation within the sheet updates `card` via state.
    private let initialCard: Card
    // Optional list of cards to swipe through (e.g. the current search results).
    // Empty = no prev/next navigation shown.
    var navigationCards: [Card] = []
    /// True when presented as a sheet (sheet needs its own NavigationStack
    /// to render the toolbar). False when pushed via .navigationDestination
    /// of a parent NavigationStack — the parent provides the chrome and a
    /// nested NavigationStack creates back-button conflicts.
    var wrapInNavStack: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore
    @Environment(DeckBuilderStore.self) private var deckBuilder
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // The card currently being displayed — may change via prev/next navigation.
    @State private var card: Card

    // Tick 523 — true horizontal swipe animation between cards (replaces
    // the prior fade). +1 = swipe-left/next (new card slides in from
    // trailing); -1 = swipe-right/prev (slides in from leading). Set
    // BEFORE the withAnimation block in advanceCard so the transition
    // modifier picks up the correct edge.
    @State private var swipeDirection: Int = 1

    // Zoom state (reset on card change)
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0
    @State private var showingAddSheet = false
    @State private var showingAddToDeck = false
    @State private var showingAddToShow = false
    @State private var showingSignIn = false
    @State private var showingDBSInfo = false
    // Tick 382 — popover state for the print-run / SSP chip explainer
    // (Android tick 379 parity). Tap on the chip → present a short
    // popover that decodes /5 · /10 · /25 · /50 · SSP · Serial.
    @State private var showingPrintRunExplainer = false
    /// Non-nil while a "Added to {deck}" toast should be visible. Cleared
    /// automatically after a short delay by the overlay's task.
    @State private var addedToDeckName: String?
    /// Toast surface reused for the Show add flow — "Added to {show}".
    @State private var addedToShowName: String?
    @State private var showSealedEbay = false
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var isPreparingShare = false
    @State private var showingModEdit = false
    /// Per DESIGN.md §6.10 — first-time card-detail walkthrough.
    @State private var walkthrough: BOBAWalkthrough.Script? = nil

    init(card: Card, navigationCards: [Card] = [], wrapInNavStack: Bool = true) {
        self.initialCard = card
        self.navigationCards = navigationCards
        self.wrapInNavStack = wrapInNavStack
        _card = State(initialValue: card)
    }

    // Other card_numbers with the same hero (same pattern as CollectionCardDetailView)
    private var variations: [Card] {
        cardStore.displayCards
            .filter { $0.hero == card.hero && $0.cardNumber != card.cardNumber }
            .sorted {
                let lImg = $0.imageFile != nil && !$0.imageFile!.isEmpty
                let rImg = $1.imageFile != nil && !$1.imageFile!.isEmpty
                if lImg != rImg { return lImg }
                return ($0.set, $0.treatment ?? "") < ($1.set, $1.treatment ?? "")
            }
    }

    private var effectiveScale: CGFloat { (scale * pinchDelta).clamped(to: 1...6) }

    // Index of the current card in the navigation list (-1 if not navigable).
    // Uses `card.id` (the full bobaId) not just cardNumber+hero, since the same
    // hero at the same card number can have multiple treatments/variations.
    private var navIndex: Int {
        navigationCards.firstIndex { $0.id == card.id } ?? -1
    }

    /// Move to the next/previous card in `navigationCards`. Negative
    /// `delta` goes backward, positive forward. Wraps around at the
    /// ends so left-swiping at the first card jumps to the last and
    /// right-swiping at the last jumps to the first — matches the
    /// Photos.app expectation.
    private func advanceCard(by delta: Int) {
        guard !navigationCards.isEmpty else { return }
        let n = navigationCards.count
        let i = navIndex
        guard i >= 0 else { return }
        let next = ((i + delta) % n + n) % n
        guard next != i else { return }
        // Tick 312 — light haptic on every successful card swap (Android
        // tick 291 TextHandleMove parity). Subtle confirmation that the
        // swipe / Cmd-arrow registered without competing with button-tap
        // haptics. selectionChanged is the closest "stepped through a
        // list" feedback iOS exposes.
        UISelectionFeedbackGenerator().selectionChanged()
        swipeDirection = delta
        // Tick 523 — spring-curve slide (Photos.app feel). The
        // `.transition(.asymmetric(.move...))` on the inner stack
        // does the actual horizontal slide; this animation just
        // drives the timing.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            card = navigationCards[next]
            // Reset zoom state on every nav so the new card starts at
            // its natural size with no leftover pan.
            scale = 1.0
            offset = .zero
        }
    }

    private var collectionStatusIcon: String? {
        if collection.isOwned(bobaId: card.id) { return "checkmark.circle.fill" }
        if collection.isWanted(bobaId: card.id) { return "star.fill" }
        return nil
    }

    // Shareable web URL — opens card modal on the web app.
    // element is included to disambiguate weapon-variant pairs that
    // share cardNumber+hero+treatment after the bobaId v3 migration
    // (DECISIONS.md #057). Web cardFromURLParams + the iOS / Android
    // inbound handlers all consume the element param when present.
    private var cardShareURL: URL? {
        var components = URLComponents(string: "https://bobaplaybook.com/")!
        var items = [URLQueryItem(name: "card", value: card.cardNumber)]
        if !card.hero.isEmpty { items.append(URLQueryItem(name: "hero", value: card.hero)) }
        if let treatment = card.treatment { items.append(URLQueryItem(name: "treatment", value: treatment)) }
        if !card.element.isEmpty { items.append(URLQueryItem(name: "element", value: card.element)) }
        components.queryItems = items
        return components.url
    }

    private func prepareAndShare() async {
        guard let shareURL = cardShareURL else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        // Fetch card image for sharing.
        var image: UIImage? = nil
        if let imageURL = CDN.fullURL(for: card),
           let (data, _) = try? await URLSession.shared.data(from: imageURL) {
            image = UIImage(data: data)
        }

        // CardShareItemSource returns different data per activity type:
        // - Messages (.message): text string so URL appears in message body
        // - Notes, Mail, AirDrop, etc.: URL object so apps embed a tappable link
        let source = CardShareItemSource(card: card, url: shareURL, image: image)
        shareItems = image != nil ? [image!, source] : [source]
        showingShare = true
    }

    /// v2.280 — refresh the local @State `card` from the live
    /// CardStore entry. Used on appear and whenever the runtime
    /// override map changes, so an admin's just-uploaded image
    /// appears in the open detail view without re-navigation.
    private func syncFromCardStore() {
        guard let live = cardStore.displayCards.first(where: { $0.id == card.id })
        else { return }
        if live.imageFile != card.imageFile {
            card.imageFile = live.imageFile
        }
    }

    @ViewBuilder
    private func navStackIfNeeded<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if wrapInNavStack {
            NavigationStack { content() }
        } else {
            content()
        }
    }

    var body: some View {
        navStackIfNeeded {
            ScrollView {
                VStack(spacing: 0) {
                    artPanel
                    infoPanel
                }
                // Tick 523 — true horizontal swipe transition. `.id(card.id)`
                // gives each card a fresh identity, so the OUTGOING content
                // slides off and the INCOMING slides in from the opposite
                // edge (asymmetric .move) instead of cross-fading.
                .id(card.id)
                .transition(.asymmetric(
                    insertion: .move(edge: swipeDirection > 0 ? .trailing : .leading),
                    removal:   .move(edge: swipeDirection > 0 ? .leading  : .trailing)
                ))
            }
            // Horizontal-swipe nav between cards. Only fires when:
            //   - we have a navigation list (navigationCards non-empty)
            //   - the art image isn't pinch-zoomed (scale == 1) — the art
            //     panel's in-zoom drag pans the image; swiping at rest
            //     navigates instead.
            //   - the swipe is mostly horizontal (|dx| > 60, |dy| < 40)
            //     so vertical scroll-flick wins as expected.
            // Restored per beta feedback 2026-05-20; replaces the
            // removed prev/next chevron buttons (DESIGN.md §8.6 anti-
            // patterns called those "noisy" — gesture is the iOS-native
            // answer).
            .simultaneousGesture(
                DragGesture(minimumDistance: 60)
                    .onEnded { value in
                        guard !navigationCards.isEmpty, scale == 1 else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 60, abs(dy) < 40 else { return }
                        if dx < 0 { advanceCard(by:  1) }
                        else      { advanceCard(by: -1) }
                    }
            )
            .scrollEdgeEffectStyle(.soft, for: .top)  // §5.6 reading content
            .background(Design.Colors.nearBlack)
            // Tick 287 — iPad / hardware-keyboard arrow shortcuts for
            // prev/next card. Matches the swipe gesture above. Hidden
            // zero-size Buttons register in the responder chain so the
            // shortcuts fire even when the action Menu isn't open. Web
            // already has ArrowLeft/Right keys per PARITY row.
            .background(
                Group {
                    Button { advanceCard(by: 1) } label: { EmptyView() }
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                    Button { advanceCard(by: -1) } label: { EmptyView() }
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if wrapInNavStack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(card.name)
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Action bar (toolbar Menu form for now; sticky bottom
                    // glass bar per DESIGN.md §8.6 is a follow-up). Walkthrough
                    // anchor lives here so the cardDetail.actionBar step
                    // points at the actual action surface.
                    Group {
                        if auth.isAuthenticated {
                            Menu {
                                Section("Add \(card.name)") {
                                    Button {
                                        showingAddSheet = true
                                    } label: {
                                        Label("To Collection", systemImage: "folder.badge.plus")
                                    }
                                    if card.isHero || card.isPlay || card.isHotDog {
                                        Button {
                                            showingAddToDeck = true
                                        } label: {
                                            Label("To Custom Deck", systemImage: "rectangle.stack.badge.plus")
                                        }
                                    }
                                    // Streamers get a third add destination: a
                                    // Whatnot/live-show prep list.
                                    if auth.isStreamer {
                                        Button {
                                            showingAddToShow = true
                                        } label: {
                                            Label("To Show", systemImage: "dot.radiowaves.up.forward")
                                        }
                                    }
                                }
                            } label: {
                                addIconLabel
                            }
                        } else {
                            Button { showingSignIn = true } label: { addIconLabel }
                        }
                    }
                    .walkthroughAnchor("cardDetail.actionBar")
                }
                if auth.isMod {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingModEdit = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await prepareAndShare() }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                                .tint(Design.Colors.bobaCyan)
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Design.Colors.bobaCyan)
                        }
                    }
                    .disabled(isPreparingShare)
                }
                // Prev/Next navigation removed per user feedback —
                // they cluttered the simple card-detail surface. The
                // user navigates back to the grid (via dismiss) and
                // taps another card.
            }
            // Hide nav bar background — the artPanel's gradient becomes
            // the visual top surface; nav bar items float over it.
            // Music's "Now Playing" pattern. Same modifier on Decks and
            // Collection card details for consistency.
            .toolbarBackground(.hidden, for: .navigationBar)
            // Action-shaped sheets adapt to popover on iPad per
            // DESIGN.md §6.6 — anchored to the toolbar Add menu's
            // chosen item. Compact width keeps sheet behavior.
            .sheet(isPresented: $showingAddSheet) {
                AddToCollectionSheet(card: card) { designationLabel in
                    showAddedToDeckToast("Added to \(designationLabel)")
                }
                    .presentationCompactAdaptation(.popover)
            }
            .sheet(isPresented: $showingAddToDeck) {
                AddToDeckSheet(card: card) { deckName in
                    showAddedToDeckToast(deckName)
                }
                .environment(cardStore)
                .presentationCompactAdaptation(.popover)
            }
            .sheet(isPresented: $showingAddToShow) {
                AddToShowSheet(card: card) { showName in
                    showAddedToShowToast(showName)
                }
                .presentationCompactAdaptation(.popover)
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView()
            }
            .sheet(isPresented: $showingShare) {
                ActivityShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showSealedEbay) {
                if let url = sealedEbayURL { SafariView(url: url) }
            }
            .sheet(isPresented: $showingModEdit) {
                ModCardEditSheet(card: card)
            }
            .sheet(isPresented: $showingDBSInfo) {
                // Tick 187 — Discord backlog #5: pass active draft's DBS
                // context. Sheet falls back to static explainer when the
                // format doesn't enforce DBS or the card isn't a Play.
                let showContext = deckBuilder.effectiveEnforceDBS && card.isPlay && card.dbs != nil
                DBSInfoSheet(
                    cardDBS:        showContext ? card.dbs : nil,
                    currentDeckDBS: showContext ? deckBuilder.totalDBS : nil,
                    dbsBudget:      showContext ? deckBuilder.effectiveDBSBudget : nil,
                )
            }
            // Confirmation toast for "Added to {deck}". Rendered inside the
            // NavigationStack so it floats above the card art and info panel.
            .overlay(alignment: .top) {
                if let name = addedToDeckName {
                    confirmationToast(text: "Added to \(name)")
                } else if let showName = addedToShowName {
                    confirmationToast(text: "Added to \(showName)")
                }
            }
            // First-visit walkthrough per DESIGN.md §6.10.1 cardDetail
            // catalog. Anchors land on the canonical-6 stats grid, the
            // pricing panels, and the toolbar add-action bar.
            .walkthroughOverlay($walkthrough)
            .onAppear {
                // First-visit teaches CardDetail surface anatomy.
                // The pricingPanels walkthrough fires from inside
                // PricingSection.onAppear instead of here — that way
                // the user has actually scrolled to pricing before the
                // walkthrough anchors at it (no off-screen text).
                if WalkthroughsManager.shared.shouldShow(.cardDetail) {
                    walkthrough = .cardDetail
                }
                // v2.280 — re-resolve the live card on appear. The
                // @State capture freezes whatever copy was passed in,
                // so a card opened before applyRuntimeImageOverrides
                // runs (e.g. signed-out launch) shows the stale
                // imageFile until manually refreshed. Pull the live
                // version from cardStore.displayCards.
                syncFromCardStore()
                // AddToCollectionIntent (DESIGN.md §7) hint — when the
                // user invoked the intent from Spotlight/Siri/Shortcuts
                // and we landed on this card, auto-present the add
                // sheet. Auth-gated via the existing showingSignIn
                // route (sheet falls through to BOBASignInPrompt when
                // unauthenticated).
                if cardStore.pendingCardAction == "addToCollection" {
                    cardStore.pendingCardAction = nil
                    if auth.isAuthenticated {
                        showingAddSheet = true
                    } else {
                        showingSignIn = true
                    }
                }
            }
            // v2.280 — when an admin saves a new image while this
            // detail surface is open, setAppliedOverride mutates the
            // displayCards entry and bumps the override map. Watch
            // the map so the artPanel re-renders without a re-push.
            .onChange(of: cardStore.appliedImageOverridesByBobaId) {
                syncFromCardStore()
            }
            .onChange(of: cardStore.appliedImageOverridesByCardNumber) {
                syncFromCardStore()
            }
        }
    }

    private var addIconLabel: some View {
        Image(systemName: collectionStatusIcon ?? "plus.circle.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(
                collectionStatusIcon != nil
                    ? (collection.isOwned(bobaId: card.id) ? Color.green : Design.Colors.bobaOrange)
                    : Design.Colors.bobaOrange
            )
    }

    private func showAddedToDeckToast(_ name: String) {
        withAnimation(.easeOut(duration: 0.25)) { addedToDeckName = name }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { addedToDeckName = nil }
        }
    }

    private func showAddedToShowToast(_ name: String) {
        withAnimation(.easeOut(duration: 0.25)) { addedToShowName = name }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { addedToShowName = nil }
        }
    }

    private func confirmationToast(text: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "4CAF50"))
            Text(text)
                .font(Design.Fonts.mono(12, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "4CAF50").opacity(0.4), lineWidth: 1))
        .padding(.top, Design.Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Format restrictions block
    //
    // Renders only when a card has a real per-card format restriction
    // — a Spec-ineligible hero, a Bonus Play or HTD Play that some
    // events toggle off, or a Trainer card banned in Elite. A plain
    // base-set hero under Power 160 produces no restrictions and this
    // block doesn't appear at all. Deck-building rules (DBS budget,
    // count limits) still live in the Decks tab's legality audit.
    @ViewBuilder
    // Tick 207 — Discord backlog #4 iOS port. 4-chip strip showing
    // positive legality across Spec / Spec+ / Brawl / Checklist. Most
    // cards render 4 green chips (the at-a-glance reassurance is the
    // point). Hero-power-gated cards show amber (constrained) or red
    // (illegal) chips with a help-cursor tooltip explaining the cause.
    private func formatLegalityStrip(_ chips: [FormatLegality]) -> some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                let (dotColor, textColor): (Color, Color) = {
                    switch chip.status {
                    case .legal:       return (Color(red: 0.49, green: 0.80, blue: 0.51), Design.Colors.textSecondary)
                    case .constrained: return (Color(red: 1.00, green: 0.84, blue: 0.00), Design.Colors.textPrimary)
                    case .illegal:     return (Color(red: 0.75, green: 0.23, blue: 0.14), Design.Colors.textMuted)
                    }
                }()
                HStack(spacing: 5) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                    Text(chip.format)
                        .font(Design.Fonts.mono(11, weight: .semibold))
                        .foregroundStyle(textColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Design.Colors.surface)
                        .overlay(Capsule().strokeBorder(Design.Colors.glassBorder, lineWidth: 0.5))
                )
                .help(chip.reason ?? "\(chip.format): legal")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func formatRestrictionsBlock(_ notes: [CardRestriction]) -> some View {
        let amber = Design.Colors.bobaOrange
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("FORMAT RESTRICTIONS")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            VStack(spacing: 1) {
                ForEach(notes) { n in
                    HStack(alignment: .top, spacing: Design.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(amber)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.label)
                                .font(Design.Fonts.mono(12, weight: .bold))
                                .foregroundStyle(amber)
                            Text(n.detail)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                .strokeBorder(amber.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: - Art panel
    //
    // Standardized layout shared by Find / Decks / Collection per user
    // request — same gradient height, same image height, same rounded
    // corners, same shadow, same horizontal padding. Differences
    // between the three card-detail surfaces should be in the BODY
    // BELOW this panel, never in the panel itself.
    private var artPanel: some View {
        ZStack {
            // Element gradient background (orange accent for sealed products)
            LinearGradient(
                colors: [
                    (card.isSealed ? Design.Colors.bobaOrange : Design.Colors.element(card.element)).opacity(0.25),
                    Design.Colors.nearBlack
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Design.CardDetailMetrics.panelHeight(for: horizontalSizeClass))

            CardImageView(card: card, size: .full)
                .id(card.id)  // force view recreation on card change so loadedImage resets
                .aspectRatio(5.0/7.0, contentMode: .fit)
                .frame(height: Design.CardDetailMetrics.imageHeight(for: horizontalSizeClass))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Design.Colors.element(card.element).opacity(0.4), radius: 16, y: 6)
                .scaleEffect(effectiveScale)
                .offset(
                    x: offset.width + (scale > 1 ? dragDelta.width : 0),
                    y: offset.height + (scale > 1 ? dragDelta.height : 0)
                )
                .clipped()
                .gesture(
                    MagnificationGesture()
                        .updating($pinchDelta) { value, state, _ in state = value }
                        .onEnded { value in
                            scale = (scale * value).clamped(to: 1...6)
                            if scale == 1 { offset = .zero }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragDelta) { value, state, _ in
                            if scale > 1 { state = value.translation }
                        }
                        .onEnded { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width:  offset.width  + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1 { scale = 1.0; offset = .zero }
                        else         { scale = 2.5 }
                    }
                }

        }
    }

    // MARK: - Info panel (branches on card type)
    private var infoPanel: some View {
        Group {
            if card.isSealed {
                sealedInfoPanel
            } else {
                cardInfoPanel
            }
        }
    }

    // MARK: - Regular card info panel
    private var cardInfoPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {

            // Name + primary stat row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text(card.displayName)
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(Design.Colors.textPrimary)
                    if let variation = card.variation, !variation.isEmpty, variation != card.displayName {
                        Text(variation)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                    } else if card.isHero, card.hero != card.name {
                        Text(card.hero)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                }
                Spacer()
                // Power — Hero cards only (power 0 on Play/HotDog is meaningless)
                if card.isHero, let power = card.power, power > 0 {
                    VStack(spacing: 0) {
                        Text("\(power)")
                            .font(Design.Fonts.arena(36))
                            .foregroundStyle(Design.Colors.element(card.element))
                        Text("POWER")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                    }
                } else if card.isPlay, let cost = card.playCost {
                    VStack(spacing: 0) {
                        Text(cost == 0 ? "FREE" : "\(cost)")
                            .font(Design.Fonts.arena(36))
                            .foregroundStyle(cost == 0 ? Color(hex: "7ecb82") : Design.Colors.bobaCyan)
                        Text(cost == 0 ? "COST" : "HOT DOG\(cost == 1 ? "" : "S")")
                            .font(Design.Fonts.mono(9))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                    }
                }
            }

            // Badge row
            HStack(spacing: Design.Spacing.sm) {
                if card.isHero {
                    elementBadge
                } else if card.isPlay {
                    playTypeBadge
                } else if card.isHotDog {
                    hotDogBadge
                }
                if let treatment = card.treatment, !treatment.isEmpty {
                    treatmentBadge(treatment)
                }
                setBadge
            }

            Divider().background(Design.Colors.glassBorder)

            // Stats grid — fixed 6-cell layout per the BoBA-expert
            // taxonomy spec. Reading order with [flex, flex] columns
            // is left-to-right then top-to-bottom, so the sequence
            // below produces:
            //
            //   Card #     │ Type
            //   Treatment  │ Weapon
            //   Set        │ Sub-set
            //
            // Heroes show their printed weapon in the right-middle
            // slot; non-heroes leave it blank ("—") rather than
            // collapsing the row, which would shift everything
            // beneath and break the visual grid the user expects.
            // Cost + DBS for plays render below the standard 6-cell
            // block so the canonical taxonomy is never disrupted.
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Design.Spacing.sm
            ) {
                statCell(label: "Card #",   value: card.cardNumber)
                statCell(label: "Type",     value: card.cardType)

                // "Treatment" is the print variant (Base Set, Battlefoil,
                // Superfoil, Inspired Ink, etc.) — the field that used
                // to render as "Rarity" in this slot. Per the expert
                // feedback, "Rarity" is reserved for the rarity-by-
                // weapon-type discussion in the Learn tab; everywhere
                // else this field is "Treatment."
                if !card.isSealed {
                    statCell(label: "Treatment",
                             value: card.treatment?.isEmpty == false ? card.treatment! : (card.rarityLabel == "Paper" ? "Base Set" : card.rarityLabel))
                }
                if card.isHero || (card.element != "NONE" && !card.element.isEmpty) {
                    statCell(label: "Weapon",
                             value: card.element,
                             color: Design.Colors.element(card.element))
                } else if !card.isSealed {
                    statCell(label: "Weapon", value: "—", color: Design.Colors.textMuted)
                }

                statCell(label: "Set",      value: card.set)
                if let sub = card.subSet, !sub.isEmpty {
                    statCell(label: "Sub-set", value: sub)
                } else {
                    statCell(label: "Sub-set", value: "—", color: Design.Colors.textMuted)
                }

                // Play-only fields — cost + DBS appear in row 4+
                // beneath the canonical six.
                if card.isPlay, let cost = card.playCost {
                    statCell(label: "Cost",
                             value: cost == 0 ? "FREE" : "\(cost) Hot Dog\(cost == 1 ? "" : "s")",
                             color: cost == 0 ? Color(hex: "7ecb82") : Design.Colors.bobaCyan)
                }
                if card.isPlay, let dbs = card.dbs {
                    dbsStatCell(dbs: dbs, tier: card.dbsTier)
                }
            }
            .walkthroughAnchor("cardDetail.statsGrid")

            // Tick 207 — Discord backlog #4 iOS port (Android tick 179
            // + web tick 203 closes the trio). At-a-glance positive-
            // legality answer for Spec / Spec+ / Brawl / Checklist.
            if !card.isSealed {
                let chips = CardFormatEligibility.legalFormats(for: card)
                if !chips.isEmpty {
                    formatLegalityStrip(chips)
                }
            }

            // Per-card format restrictions — only renders when the card
            // actually has one (Spec-ineligible hero, Bonus Play / HTD
            // toggled-off in some events, Trainer banned in Elite).
            // Most cards render nothing here, which is the point.
            if !card.isSealed {
                let notes = CardFormatEligibility.restrictions(for: card)
                if !notes.isEmpty {
                    formatRestrictionsBlock(notes)
                }
            }

            // Play ability
            if let ability = card.playAbility, !ability.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("PLAY ABILITY")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    Text(ability)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.glass)
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                )
            }

            // Athlete inspiration
            if let athlete = card.athleteInspiration, !athlete.isEmpty {
                HStack(spacing: Design.Spacing.sm) {
                    Rectangle()
                        .fill(Design.Colors.element(card.element))
                        .frame(width: 3)
                        .cornerRadius(2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INSPIRED BY")
                            .font(Design.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.5)
                        Text(athlete)
                            .font(Design.Fonts.display(15))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    if card.isInspiredInk {
                        Spacer()
                        Text("INSPIRED INK")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaViolet)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Design.Colors.bobaViolet.opacity(0.15))
                                .overlay(Capsule().strokeBorder(Design.Colors.bobaViolet.opacity(0.4), lineWidth: 0.5)))
                    }
                    // Tick 197 — Discord backlog #7: print-run / SSP chip.
                    // SSP=orange, numbered=cyan. nil for typical cards.
                    // Tick 382 — Android tick 379 parity. Tap → popover
                    // explainer of what /5 · /10 · /25 · /50 · SSP · Serial
                    // each mean (DECISIONS.md #028 weapon-tied print runs).
                    // Casual users don't auto-know the BoBA Inspired Ink
                    // convention; the popover carries the spec inline.
                    if let label = card.printRunLabel {
                        if !card.isInspiredInk { Spacer() }
                        let accent = label == "SSP" ? Design.Colors.bobaOrange : Design.Colors.bobaCyan
                        let explanation: String = {
                            switch label {
                            case "SSP":    return "Superfoil — Super-Short-Print, BoBA's rarest non-numbered treatment."
                            case "/5":     return "Inspired Ink Hex — limited run of 5 copies (BoBA's rarest serialized treatment)."
                            case "/10":    return "Inspired Ink Glow — limited run of 10 copies."
                            case "/25":    return "Inspired Ink Fire — limited run of 25 copies."
                            case "/50":    return "Inspired Ink Ice — limited run of 50 copies."
                            case "Serial": return "Inspired Ink — serialized run; print number not publicly disclosed."
                            default:       return "\(label) print run."
                            }
                        }()
                        Button {
                            showingPrintRunExplainer = true
                        } label: {
                            Text(label)
                                .font(Design.Fonts.mono(9, weight: .bold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accent.opacity(0.15))
                                    .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 0.5)))
                        }
                        .buttonStyle(.plain)
                        .help(explanation)
                        .accessibilityHint(explanation)
                        .popover(isPresented: $showingPrintRunExplainer, arrowEdge: .top) {
                            Text(explanation)
                                .font(Design.Fonts.mono(13))
                                .foregroundStyle(Design.Colors.textPrimary)
                                .padding(16)
                                .frame(maxWidth: 280)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }

            // "In your collection" summary — same shape as
            // CollectionCardDetailView (tick 107 parity). Lets users
            // tapping a card from Find see whether they already own a
            // copy + at which designation, without switching tabs.
            let ownedEntries = collection.entries(forBobaId: card.id)
            if !ownedEntries.isEmpty {
                Divider().background(Design.Colors.glassBorder)
                let byDesig = Dictionary(grouping: ownedEntries, by: { $0.designation })
                    .mapValues { $0.count }
                let summary = byDesig
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { (d, n) in n > 1 ? "\(d.displayName) ×\(n)" : d.displayName }
                    .joined(separator: " · ")
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("IN YOUR COLLECTION (\(ownedEntries.count))")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    Text(summary)
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
            }

            Divider().background(Design.Colors.glassBorder)

            PricingSection(card: card)
                .walkthroughAnchor("cardDetail.pricing")
                .onAppear {
                    // Pricing walkthrough fires here, after the user
                    // has actually scrolled to (or auto-rendered) the
                    // pricing panels — guarantees the buyNow / sold
                    // anchors are on-screen at trigger time. The
                    // cardDetail walkthrough must be dismissed first
                    // (one walkthrough per surface, per §6.10).
                    if walkthrough == nil,
                       WalkthroughsManager.shared.shouldShow(.pricingPanels) {
                        walkthrough = .pricingPanels
                    }
                }

            if !variations.isEmpty {
                variationsSection
            }
        }
        .padding(Design.Spacing.lg)
    }

    // MARK: - Other Versions section

    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("OTHER VERSIONS (\(variations.count))")
                .font(Design.Fonts.mono(9, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.md) {
                    // ID is .id (bobaId) not .cardNumber — multiple
                    // variants can share a cardNumber (e.g., themed
                    // foils + Inspired Ink at one number). Non-unique
                    // ForEach IDs corrupt SwiftUI identity tracking
                    // and was the cause of the "Other Versions tap
                    // bounces back to Find" bug. Value-based
                    // NavigationLink routes via the parent
                    // NavigationStack's path + navigationDestination
                    // (for: Card.self) handler — pushing
                    // CardDetailView via the destination init that
                    // already handles wrapInNavStack correctly.
                    // Mixing value-less .destination: with path-
                    // driven NavigationStack causes state desync.
                    ForEach(variations, id: \.id) { variant in
                        NavigationLink(value: variant) {
                            VStack(spacing: Design.Spacing.xs) {
                                // No overlays on the card art per DECISIONS.md
                                // #061; treatment label below the thumb carries
                                // the disambiguation.
                                CardImageView(card: variant, size: .thumb)
                                    .frame(width: 80, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))

                                Text(variant.treatment ?? variant.set)
                                    .font(Design.Fonts.mono(9))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .lineLimit(1)
                                    .frame(width: 80)

                                let owned = collection.isOwned(bobaId: variant.id)
                                let wanted = collection.isWanted(bobaId: variant.id)
                                if owned || wanted {
                                    Image(systemName: owned ? "checkmark.circle.fill" : "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(owned ? .green : Design.Colors.bobaOrange)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sealed product info panel
    private var sealedInfoPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {

            // Name + product type
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(card.name)
                    .font(Design.Fonts.display(22))
                    .foregroundStyle(Design.Colors.textPrimary)
                if let pt = card.productType {
                    Text(pt.replacingOccurrences(of: "-", with: " ").uppercased())
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                        .tracking(1)
                }
            }

            // Badge row
            HStack(spacing: Design.Spacing.sm) {
                Text(card.set.uppercased())
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaOrange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
                    )
                Text("SEALED PRODUCT")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.glass)
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                    )
            }

            Divider().background(Design.Colors.glassBorder)

            // Product stats grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Design.Spacing.sm
            ) {
                if let packs = card.packsPerBox {
                    statCell(label: "Packs/Box", value: "\(packs)")
                }
                if let cpp = card.cardsPerPack {
                    statCell(label: "Cards/Pack", value: "\(cpp)")
                }
                if let total = card.totalCards {
                    statCell(label: "Total Cards", value: "\(total)")
                }
                if let msrp = card.msrp {
                    statCell(label: "MSRP", value: Decimal(msrp).formatted(.currency(code: "USD")))
                }
                if let upc = card.upc {
                    statCell(label: "UPC", value: upc)
                }
            }

            // Highlights
            if let highlights = card.highlights, !highlights.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("WHAT'S INSIDE")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(highlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                                Text("·")
                                    .font(Design.Fonts.mono(13, weight: .bold))
                                    .foregroundStyle(Design.Colors.bobaOrange)
                                Text(highlight)
                                    .font(Design.Fonts.mono(12))
                                    .foregroundStyle(Design.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.glass)
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                )
            }

            // External links row
            HStack(spacing: Design.Spacing.sm) {
                // eBay sold listings
                if card.ebaySearchQuery != nil {
                    Button { showSealedEbay = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 11))
                            Text("eBay Sales")
                                .font(Design.Fonts.mono(12))
                        }
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
                }

                // Per Radish (2026-05-23): ordinary user-facing link only,
                // opens external browser. Uses the legacy catalog
                // `radishUrl` field when present; falls back to the
                // Radish homepage when null.
                Link(destination: card.radishDisplayURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("View on Radish")
                            .font(Design.Fonts.mono(12))
                    }
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaCyan.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                    )
                }
            }
        }
        .padding(Design.Spacing.lg)
    }

    private var sealedEbayURL: URL? {
        guard let query = card.ebaySearchQuery else { return nil }
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")!
        components.queryItems = [
            URLQueryItem(name: "_nkw",        value: query),
            URLQueryItem(name: "LH_Sold",     value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "_sacat",      value: "0"),
        ]
        return components.url
    }

    // MARK: - Sub-components
    private var elementBadge: some View {
        Text(card.element)
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.element(card.element))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.element(card.element).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.element(card.element).opacity(0.45), lineWidth: 1))
            )
    }

    private var playTypeBadge: some View {
        let isBonus = card.isBonusPlay == true
        let color = isBonus ? Design.Colors.bobaCyan : Design.Colors.bobaViolet
        return Text(isBonus ? "BONUS PLAY" : "PLAY CARD")
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(color.opacity(0.35), lineWidth: 1))
            )
    }

    private var hotDogBadge: some View {
        Text("HOT DOG")
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Color(hex: "7ecb82"))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Color(hex: "4CAF50").opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Color(hex: "4CAF50").opacity(0.35), lineWidth: 1))
            )
    }

    private var setBadge: some View {
        Text(card.set.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.glass)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            )
    }

    private func treatmentBadge(_ treatment: String) -> some View {
        Text(treatment.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.bobaOrange.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
            )
    }

    private func statCell(label: String, value: String, color: Color = Design.Colors.textSecondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.2)
            Text(value)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(Design.Colors.surface2)
        )
    }

    // DBS cell — same shape as statCell but tappable (opens explainer
    // modal). Color-coded by tier so coaches can scan at a glance.
    private func dbsStatCell(dbs: Int, tier: String?) -> some View {
        Button {
            showingDBSInfo = true
        } label: {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("DBS")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.2)
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(dbs)")
                            .font(Design.Fonts.mono(13, weight: .bold))
                            .foregroundStyle(dbsColor(for: tier))
                        if let t = tier, !t.isEmpty {
                            Text(t.uppercased())
                                .font(Design.Fonts.mono(9, weight: .bold))
                                .foregroundStyle(dbsColor(for: tier).opacity(0.85))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(dbsColor(for: tier).opacity(0.15)))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.surface2)
            )
        }
        .buttonStyle(.plain)
    }

    private func dbsColor(for tier: String?) -> Color {
        switch tier?.lowercased() {
        case "low":       return Color(hex: "7ecb82")
        case "medium":    return Design.Colors.bobaCyan
        case "high":      return .yellow
        case "very high": return Design.Colors.bobaOrange
        default:          return Design.Colors.textSecondary
        }
    }
}

// MARK: - DBS Info Sheet
// Presented from the DBS stat cell on Plays. Explains the scoring system
// and its role in Nationals-style formats. Copy sourced from the
// 2026-04-22 Discord terminology handoff §4.1.

struct DBSInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Tick 187 — Discord backlog #5 (Android tick 186 parity).
    /// Optional per-card contextual line. When all three are provided,
    /// renders a header block ABOVE the static explainer:
    /// "This card costs +N DBS. Your deck has X/Y. Adding it brings
    /// you to (X+N)/Y." Switches to error red when over budget.
    var cardDBS:        Int? = nil
    var currentDeckDBS: Int? = nil
    var dbsBudget:      Int? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    if let cardDBS, let currentDeckDBS, let dbsBudget {
                        contextBlock(card: cardDBS, used: currentDeckDBS, budget: dbsBudget)
                    }
                    Text("What is DBS?")
                        .font(Design.Fonts.display(22))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("The **Deck Balancing System** is a scoring system used in Nationals-style formats to keep high-powered plays from crowding out the rest of a deck.")
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textSecondary)
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        bullet("Every Play card has a DBS score.")
                        bullet("Your deck's total DBS across all 30 Plays must be ≤ **1,000** in formats that enforce it.")
                        bullet("High-DBS plays are individually powerful but force you to fill the rest of the deck with low-DBS plays to stay under budget.")
                        bullet("Non-Nationals formats (Rookie, Substitution, Playmaker) ignore DBS entirely — it's only a constraint when a format opts in.")
                    }
                    Text("DBS tiers").font(Design.Fonts.display(16)).foregroundStyle(Design.Colors.textPrimary).padding(.top, Design.Spacing.sm)
                    VStack(spacing: 1) {
                        tierRow("Low",       "1–20",  Color(hex: "7ecb82"))
                        tierRow("Medium",    "21–40", Design.Colors.bobaCyan)
                        tierRow("High",      "41–60", .yellow)
                        tierRow("Very High", "67+",   Design.Colors.bobaOrange)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                    Text("The deck builder shows a running DBS total and warns you when you cross the budget — no mental math required.")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                        .padding(.top, Design.Spacing.xs)
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    /// Tick 187 — contextual DBS block surfacing the active draft's
    /// current load vs. what adding this card would do. Mirrors
    /// Android tick 186's DBSInfoSheet header. Red treatment when
    /// projected total exceeds budget.
    @ViewBuilder
    private func contextBlock(card: Int, used: Int, budget: Int) -> some View {
        let projected = used + card
        let overCap   = projected > budget
        let surface   = overCap ? Color.red.opacity(0.18) : Design.Colors.surface
        let stroke    = overCap ? Color.red.opacity(0.55) : Design.Colors.glassBorder
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("This card costs +\(card) DBS")
                .font(Design.Fonts.display(15))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Your deck has \(used) / \(budget) DBS used.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
            Text(overCap
                 ? "Adding it puts you at \(projected) / \(budget) — over budget."
                 : "Adding it brings you to \(projected) / \(budget).")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(overCap ? Color.red : Design.Colors.textSecondary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md).strokeBorder(stroke, lineWidth: 1))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Text("•")
                .font(Design.Fonts.mono(14, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text(.init(text))
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierRow(_ label: String, _ range: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(color)
            Spacer()
            Text(range)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface)
    }
}

// MARK: - Comparable clamp
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Activity sheet wrapper
import UIKit

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Per-app share item source
// Notes and similar apps handle URL objects as tappable embedded links.
// Messages requires a plain String so the URL appears in the message body.
final class CardShareItemSource: NSObject, UIActivityItemSource {
    private let card: Card
    private let url: URL
    private let image: UIImage?

    init(card: Card, url: URL, image: UIImage?) {
        self.card = card
        self.url = url
        self.image = image
    }

    // Placeholder tells the system what kind of item this is (URL).
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // Messages needs a String — URL objects get dropped when paired with an image.
        if activityType == .message {
            return "\(card.name) — BOBA Playbook\n\(url.absoluteString)"
        }
        // Notes, Mail, AirDrop, Copy, etc. all handle URL objects correctly.
        return url
    }

    // Subject line for Mail and Notes.
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        return "\(card.name) — BOBA Playbook"
    }
}
