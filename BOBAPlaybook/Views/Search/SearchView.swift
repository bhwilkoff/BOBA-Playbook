import SwiftUI

struct SearchView: View {
    @Environment(CardStore.self) private var store
    @Environment(CollectionStore.self) private var collection
    @Environment(AuthManager.self) private var auth
    @State private var showFilters = false
    @State private var selectedCard: Card?
    @State private var showScan = false
    @State private var showProfile = false
    /// When true, tapping a grid card adds it to the user's Collection
    /// (as .personal) instead of opening the card detail sheet. Parallels
    /// the deck builder's Quick Add toggle. Sits on a pill next to the
    /// results count under the search bar.
    @State private var quickAdd = false
    @State private var quickAddToast: String? = nil
    @State private var quickAddError: String? = nil
    /// Drives the keyboard-toolbar Done button. SwiftUI's only built-in
    /// way to dismiss the keyboard from the field is via a focus binding,
    /// so the search field needs its own @FocusState even though we don't
    /// otherwise route focus into it.
    @FocusState private var searchFocused: Bool
    /// Mirror of the Settings → App Icon choice. The profile icon's tint
    /// follows this so the accent stays consistent with the user's chosen
    /// icon color.
    @AppStorage("selectedIconName") private var selectedIconName: String = "default"

    // Grid: 2 columns with minimum size
    private let columns = [
        GridItem(.flexible(), spacing: Design.Spacing.sm),
        GridItem(.flexible(), spacing: Design.Spacing.sm),
    ]

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 0) {
                // Custom search bar — typing area on the left, scan shortcut
                // on the right. Replaces the old `.searchable` so we can pack
                // a scan trigger into the same row per the nav-refactor ask.
                searchBar
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, Design.Spacing.sm)
                    .padding(.bottom, Design.Spacing.xs)

                Group {
                    if store.isLoading {
                        loadingView
                    } else if let error = store.loadError {
                        errorView(error)
                    } else {
                        contentView
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Profile moved off the tab bar into the Find-tab header so
                // the bottom bar stays focused on content modes.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(AppIconOption.currentColor(for: selectedIconName))
                    }
                    .accessibilityLabel("Profile")
                }
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterButton
                }
                // "Done" key on the keyboard accessory bar — gives an
                // out for the case where the user taps the search field
                // by mistake and doesn't want to commit a search just to
                // dismiss the keyboard.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay(alignment: .top) {
                if let toast = quickAddToast {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "4CAF50"))
                        Text(toast)
                            .font(Design.Fonts.mono(12, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "4CAF50").opacity(0.4), lineWidth: 1))
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert("Couldn't add that card", isPresented: .init(
                get: { quickAddError != nil },
                set: { if !$0 { quickAddError = nil } }
            )) {
                Button("OK") { quickAddError = nil }
            } message: {
                Text(quickAddError ?? "")
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheetView(store: store)
        }
        // Scan as an immersive full-screen cover — camera needs the whole
        // viewport. A floating Close button handles dismissal since ScanView
        // has no nav bar of its own.
        .fullScreenCover(isPresented: $showScan) {
            ZStack(alignment: .topLeading) {
                ScanView()
                Button {
                    showScan = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .padding(Design.Spacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scanner")
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card, navigationCards: store.filteredCards)
        }
        // Deep-link: bobaplaybook://card/{number} sets store.pendingCardNumber.
        // Try to resolve it immediately (cards may already be loaded) and again
        // when the full catalog finishes loading.
        .onChange(of: store.pendingCardNumber) { _, cardNum in
            tryPresentPendingCard()
        }
        .onChange(of: store.isLoadingMore) { _, _ in
            tryPresentPendingCard()
        }
        // Deep-link: bobaplaybook://scan — present the scanner sheet.
        .onChange(of: store.pendingScan) { _, pending in
            if pending {
                showScan = true
                store.pendingScan = false
            }
        }
        .onAppear {
            // Reset filter state when the tab re-appears — moving
            // between Find ↔ Collection ↔ etc. starts with a clean
            // slate rather than dragging a forgotten element pill
            // along. Sheets / modals don't retrigger onAppear on the
            // presenter so in-tab navigation (open card → close) keeps
            // whatever was set.
            store.clearAllFilters()
            tryPresentPendingCard()
            if store.pendingScan {
                showScan = true
                store.pendingScan = false
            }
        }
    }

    // MARK: - Quick Add toggle
    //
    // Mirror of the DeckBuilder pill. When on, tapping a grid card
    // adds it to the user's Collection as .personal instead of opening
    // the card-detail sheet. A small confirmation toast flashes at
    // the top so the coach knows the add succeeded.
    private var quickAddToggle: some View {
        Button {
            quickAdd.toggle()
        } label: {
            Label(
                quickAdd ? "Quick Add" : "Tap to View",
                systemImage: quickAdd ? "plus.circle.fill" : "eye.fill"
            )
            .font(Design.Fonts.mono(11, weight: .bold))
            .foregroundStyle(quickAdd ? Design.Colors.bobaOrange : Design.Colors.textMuted)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(quickAdd ? Design.Colors.bobaOrange.opacity(0.15) : Design.Colors.glass)
            )
        }
        .buttonStyle(.plain)
    }

    /// Writes a fresh user_card row for this card at .personal
    /// designation, then animates a confirmation toast. Collisions
    /// (same bobaId already owned) are allowed — coaches often add
    /// multiple copies of the same hero from a pull.
    private func quickAddCard(_ card: Card) async {
        do {
            let entry = NewUserCard(
                cardNumber: card.cardNumber,
                bobaId: card.id,
                designation: .personal
            )
            try await collection.addCard(entry)
            withAnimation(.easeOut(duration: 0.25)) {
                quickAddToast = "Added \(card.name)"
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.3)) { quickAddToast = nil }
            }
        } catch {
            quickAddError = error.localizedDescription
        }
    }

    // MARK: - Search Bar (typing + scan shortcut)

    private var searchBar: some View {
        @Bindable var store = store
        return HStack(spacing: Design.Spacing.sm) {
            // Typing area
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.textMuted)
                TextField("Cards, heroes, numbers…", text: $store.searchText)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Design.Colors.glass))

            // Scan shortcut — tapping here opens the scanner instead of the keyboard.
            Button {
                showScan = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                    Text("SCAN")
                        .font(Design.Fonts.mono(9, weight: .bold))
                }
                .foregroundStyle(Design.Colors.bobaOrange)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Design.Colors.bobaOrange.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan a card")
        }
    }

    private func tryPresentPendingCard() {
        guard let cardNum = store.pendingCardNumber,
              !store.displayCards.isEmpty,
              let card = store.displayCards.first(where: { $0.cardNumber == cardNum }) else { return }
        selectedCard = card
        store.pendingCardNumber = nil
    }

    // MARK: - Content
    private var contentView: some View {
        ScrollView {
            // Results count + Quick Add toggle. Authenticated users get
            // the toggle; anonymous users just see the count. Mirrors
            // the deck builder's "Tap to View / Quick Add" pill pattern.
            HStack {
                Text("\(store.filteredCards.count) cards")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                Spacer()
                if auth.isAuthenticated {
                    quickAddToggle
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.sm)

            // Only show partial-catalog notice when user is actively searching/filtering
            if store.isLoadingMore && (!store.searchText.isEmpty || store.activeFilterCount > 0) {
                HStack(spacing: Design.Spacing.sm) {
                    ProgressView()
                        .tint(Design.Colors.bobaCyan)
                        .scaleEffect(0.7)
                    Text("Searching first 500 cards — full catalog loading…")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.xs)
            }

            if store.filteredCards.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Design.Spacing.sm) {
                    ForEach(store.filteredCards) { card in
                        CardGridItemView(card: card)
                            .aspectRatio(3/4, contentMode: .fit)
                            .onTapGesture {
                                if quickAdd {
                                    Task { await quickAddCard(card) }
                                } else {
                                    selectedCard = card
                                }
                            }
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)

                // Loading more indicator at bottom — only visible on scroll
                if store.isLoadingMore {
                    HStack(spacing: Design.Spacing.sm) {
                        ProgressView()
                            .tint(Design.Colors.bobaOrange)
                            .scaleEffect(0.8)
                        Text("Loading full catalog…")
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.lg)
                }

                Spacer().frame(height: Design.Spacing.xl)
            }
        }
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Filter button
    private var filterButton: some View {
        Button {
            showFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)
                if store.activeFilterCount > 0 {
                    Circle()
                        .fill(Design.Colors.bobaOrange)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: Design.Spacing.lg) {
            ProgressView()
                .tint(Design.Colors.bobaOrange)
                .scaleEffect(1.4)
            Text("Loading card catalog…")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Error
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Design.Colors.bobaOrange)
            Text("Could not load cards")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(message)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No cards match your search")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textSecondary)
            Button("Clear All Filters") {
                store.clearAllFilters()
            }
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
