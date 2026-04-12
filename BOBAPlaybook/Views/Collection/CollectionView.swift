import SwiftUI

// MARK: - CollectionView
// Main Collection tab. Shows cards grouped by designation with a value summary.
// One row per unique card_number — multiple physical copies are shown on the detail page.

struct CollectionView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore

    @State private var selectedDesignation: UserCard.Designation = .personal
    @State private var selectedCard: BobaIdWrapper?
    @State private var showingSignIn    = false
    @State private var showTradeRoom    = false
    @State private var discord          = DiscordService()

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isAuthenticated {
                    unauthenticatedView
                } else {
                    authenticatedView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(item: $selectedCard) { wrapper in
            CollectionCardDetailView(bobaId: wrapper.id)
        }
        .task {
            if auth.isAuthenticated {
                await collection.loadCollection()
            }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task { await collection.loadCollection() }
            } else {
                collection.clearCollection()
            }
        }
    }

    // MARK: - Unauthenticated state

    private var unauthenticatedView: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Design.Colors.textMuted)
            Text("My Collection")
                .font(Design.Fonts.display(22))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Sign in to track owned cards,\nwishlist, and portfolio value.")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
            Button {
                showingSignIn = true
            } label: {
                Text("Sign In")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .frame(maxWidth: 200)
                    .frame(height: 50)
                    .background(Design.Colors.bobaOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Authenticated state

    private var authenticatedView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                valueSummary
                designationPicker
                cardList
            }
            .background(Design.Colors.nearBlack)
            .refreshable {
                await collection.loadCollection()
            }

            // tradeRoomFAB — hidden until Discord bot is added to server
        }
        .sheet(isPresented: $showTradeRoom) {
            TradeRoomSheet(discord: discord)
        }
    }

    // MARK: - Value summary

    private var valueSummary: some View {
        let estimated = collection.totalEstimatedValue
        let purchased = collection.totalPurchaseValue
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(estimated > 0 ? "EST. MARKET VALUE" : "COST BASIS")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                let displayValue = estimated > 0 ? estimated : purchased
                Text(displayValue == 0 ? "—" : formatCurrency(displayValue))
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(displayValue == 0 ? Design.Colors.textMuted : Design.Colors.bobaOrange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("CARDS OWNED")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text("\(collection.userCards.filter { $0.designation.isOwned }.count)")
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .background(Design.Colors.surface)
    }

    // MARK: - Designation picker

    private var designationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.sm) {
                ForEach(UserCard.Designation.allCases) { d in
                    let count = collection.uniqueBobaIds(for: d).count
                    Button {
                        selectedDesignation = d
                    } label: {
                        HStack(spacing: Design.Spacing.xs) {
                            Image(systemName: d.icon)
                                .font(.system(size: 11))
                            Text(d.displayName)
                                .font(Design.Fonts.mono(12, weight: selectedDesignation == d ? .bold : .regular))
                            if count > 0 {
                                Text("\(count)")
                                    .font(Design.Fonts.mono(10))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(selectedDesignation == d ? Design.Colors.nearBlack.opacity(0.3) : Design.Colors.glass))
                            }
                        }
                        .foregroundStyle(selectedDesignation == d ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                        .padding(.horizontal, Design.Spacing.md)
                        .frame(height: 34)
                        .background(selectedDesignation == d ? Design.Colors.bobaOrange : Design.Colors.glass)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
        }
        .background(Design.Colors.surface)
    }

    // MARK: - Card list

    private var cardList: some View {
        let identifiers = collection.uniqueBobaIds(for: selectedDesignation)

        return Group {
            if collection.isLoading {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if identifiers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Design.Spacing.sm) {
                        ForEach(identifiers, id: \.self) { identifier in
                            collectionRow(identifier: identifier)
                                .onTapGesture { selectedCard = BobaIdWrapper(id: identifier) }
                        }
                    }
                    .padding(Design.Spacing.lg)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer()
            Image(systemName: selectedDesignation.icon)
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No \(selectedDesignation.displayName) cards")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Add cards from any card detail view.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func collectionRow(identifier: String) -> some View {
        // identifier is a bobaId (e.g. "BOJ-123-BoJax-Base") for new entries,
        // or a plain cardNumber for legacy entries without a bobaId stored.
        let catalog = cardStore.displayCards.first { $0.id == identifier }
                   ?? cardStore.displayCards.first { $0.cardNumber == identifier }
        let copies = collection.entries(forBobaId: identifier).filter { $0.designation == selectedDesignation }
        let totalPaid = copies.compactMap { $0.purchasePrice }.reduce(Decimal(0), +)

        return HStack(spacing: Design.Spacing.md) {
            // Thumbnail
            if let card = catalog {
                CardImageView(card: card, size: .thumb)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
            } else {
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.surface2)
                    .frame(width: 44, height: 62)
            }

            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(catalog?.name ?? catalog?.cardNumber ?? identifier)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Design.Spacing.xs) {
                    if let element = catalog?.element {
                        Text(element)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.element(element))
                    }
                    Text(catalog?.cardNumber ?? identifier)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                if copies.count > 1 {
                    Text("\(copies.count) copies")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if totalPaid > 0 {
                    Text(formatCurrency(totalPaid))
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("PAID")
                        .font(Design.Fonts.mono(8))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1)
                } else {
                    Text("$—")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(Design.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .fill(Design.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Trade Room FAB

    private var tradeRoomFAB: some View {
        Button {
            showTradeRoom = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: "5865F2"))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                // Unread badge
                if discord.unreadCount > 0 {
                    Text(discord.unreadCount > 99 ? "99+" : "\(discord.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color(hex: "F23F43"))
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - BobaIdWrapper
// Identifiable wrapper so we can use sheet(item:) with a bobaId or legacy cardNumber string.
private struct BobaIdWrapper: Identifiable {
    let id: String
}

