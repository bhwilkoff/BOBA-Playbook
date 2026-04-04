import SwiftUI

// MARK: - CollectionView
// Main Collection tab. Shows cards grouped by designation with a value summary.
// One row per unique card_number — multiple physical copies are shown on the detail page.

struct CollectionView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(CardStore.self) private var cardStore

    @State private var selectedDesignation: UserCard.Designation = .personal
    @State private var selectedCard: CardNumberWrapper?
    @State private var showingSignIn = false

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
            CollectionCardDetailView(cardNumber: wrapper.id)
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
        VStack(spacing: 0) {
            valueSummary
            designationPicker
            cardList
        }
        .background(Design.Colors.nearBlack)
        .refreshable {
            await collection.loadCollection()
        }
    }

    // MARK: - Value summary

    private var valueSummary: some View {
        let total = collection.totalPurchaseValue
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PORTFOLIO VALUE")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Text(total == 0 ? "—" : formatCurrency(total))
                    .font(Design.Fonts.arena(28))
                    .foregroundStyle(total == 0 ? Design.Colors.textMuted : Design.Colors.bobaOrange)
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
                    let count = collection.uniqueCardNumbers(for: d).count
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
        let cardNumbers = collection.uniqueCardNumbers(for: selectedDesignation)

        return Group {
            if collection.isLoading {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cardNumbers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Design.Spacing.sm) {
                        ForEach(cardNumbers, id: \.self) { cardNumber in
                            collectionRow(cardNumber: cardNumber)
                                .onTapGesture { selectedCard = CardNumberWrapper(id: cardNumber) }
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

    private func collectionRow(cardNumber: String) -> some View {
        let catalog = cardStore.displayCards.first { $0.cardNumber == cardNumber }
        let copies = collection.entries(for: cardNumber).filter { $0.designation == selectedDesignation }
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
                Text(catalog?.name ?? cardNumber)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Design.Spacing.xs) {
                    if let element = catalog?.element {
                        Text(element)
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.element(element))
                    }
                    Text(cardNumber)
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

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - CardNumberWrapper
// Identifiable wrapper so we can use sheet(item:) with a String.
private struct CardNumberWrapper: Identifiable {
    let id: String
}

