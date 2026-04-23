import SwiftUI

// MARK: - AddToCollectionSheet
// Sheet presented from CardDetailView to add a card to the collection.
// If the user already has a wishlist entry (wanted/grails), offers to "acquire" it
// (converts to personal and lets them fill in details).

struct AddToCollectionSheet: View {
    let card: Card

    @Environment(AuthManager.self) private var auth
    @Environment(CollectionStore.self) private var collection
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var designation: UserCard.Designation = .personal
    @State private var condition = ""
    @State private var grade = ""
    @State private var gradingCompany = ""
    @State private var purchasePriceText = ""
    @State private var askingPriceText = ""
    @State private var notes = ""

    @State private var isSaving = false
    @State private var saveError: String?

    // Live market pricing fetched on appear
    @State private var marketAverage: Decimal? = nil
    @State private var isFetchingPrice = false

    // Pre-existing wishlist entry for this exact card (matched by bobaId, not just cardNumber)
    private var existingWishlistEntry: UserCard? {
        collection.userCards.first {
            ($0.bobaId == card.id || ($0.bobaId == nil && $0.cardNumber == card.cardNumber))
            && !$0.designation.isOwned
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    cardHeader
                }
                .listRowBackground(Design.Colors.surface)

                Section("DESIGNATION") {
                    designationPicker
                }
                .listRowBackground(Design.Colors.surface)

                if designation.isOwned {
                    Section("CONDITION") {
                        conditionRow
                        gradingRows
                    }
                    .listRowBackground(Design.Colors.surface)

                    Section("PRICING") {
                        // Market average (read-only, fetched from worker on appear)
                        HStack {
                            Text("Market Avg")
                                .font(Design.Fonts.mono(14))
                                .foregroundStyle(Design.Colors.textPrimary)
                            Spacer()
                            if isFetchingPrice {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(Design.Colors.bobaOrange)
                            } else if let avg = marketAverage {
                                Text(avg, format: .currency(code: "USD"))
                                    .font(Design.Fonts.mono(14, weight: .bold))
                                    .foregroundStyle(Design.Colors.bobaOrange)
                            } else {
                                Text("—")
                                    .font(Design.Fonts.mono(14))
                                    .foregroundStyle(Design.Colors.textMuted)
                            }
                        }
                        priceRow(label: "Purchase Price", text: $purchasePriceText)
                        if designation == .for_sale {
                            priceRow(label: "Asking Price", text: $askingPriceText)
                        }
                    }
                    .listRowBackground(Design.Colors.surface)
                }

                Section("NOTES") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(3...6)
                }
                .listRowBackground(Design.Colors.surface)

                if let err = saveError {
                    Section {
                        Text(err)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Design.Colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView().tint(Design.Colors.bobaOrange)
                        } else {
                            Text("Save")
                                .font(Design.Fonts.mono(14, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            // Default to "personal" but if only wishlist exists, start there
            if existingWishlistEntry != nil, collection.entries(forBobaId: card.id).isEmpty {
                designation = existingWishlistEntry?.designation ?? .personal
            }
            // Fetch current market price in background
            Task {
                isFetchingPrice = true
                if let pricing = try? await PricingService.shared.pricing(
                    for: card.cardNumber,
                    hero: card.hero,
                    set: card.set,
                    element: card.element,
                    power: card.power,
                    radishUrl: card.resolvedRadishUrlString,
                    days: 30,
                    treatment: card.treatment
                ) {
                    marketAverage = pricing.average
                }
                isFetchingPrice = false
            }
        }
    }

    // MARK: - Card header

    private var cardHeader: some View {
        HStack(spacing: Design.Spacing.md) {
            CardImageView(card: card, size: .thumb)
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(card.name)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(card.cardNumber)
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                if let power = card.power {
                    Text("\(card.element) · \(power)")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.element(card.element))
                }
            }
            Spacer()
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    // MARK: - Form rows

    private var designationPicker: some View {
        Picker("Designation", selection: $designation) {
            ForEach(UserCard.Designation.allCases) { d in
                Label(d.displayName, systemImage: d.icon)
                    .tag(d)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 120)
        .tint(Design.Colors.bobaOrange)
    }

    private var conditionRow: some View {
        HStack {
            Text("Condition")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Picker("", selection: $condition) {
                Text("—").tag("")
                ForEach(["Near Mint", "Lightly Played", "Moderately Played", "Heavily Played", "Damaged"], id: \.self) { c in
                    Text(c).tag(c)
                }
            }
            .font(Design.Fonts.mono(13))
            .tint(Design.Colors.bobaOrange)
        }
    }

    private var gradingRows: some View {
        Group {
            HStack {
                Text("Grade")
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                TextField("e.g. 9.5", text: $grade)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
            HStack {
                Text("Grading Co.")
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                TextField("e.g. PSA, BGS", text: $gradingCompany)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func priceRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            HStack(spacing: 2) {
                Text("$")
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textMuted)
                TextField("0.00", text: text)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
            }
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        saveError = nil

        let purchasePrice = Decimal(string: purchasePriceText.isEmpty ? "0" : purchasePriceText)
        let askingPrice   = Decimal(string: askingPriceText)

        let now = Date()
        let new = NewUserCard(
            cardNumber:     card.cardNumber,
            bobaId:         card.id,
            designation:    designation,
            condition:      condition.isEmpty ? nil : condition,
            serialNumber:   nil,
            grade:          grade.isEmpty ? nil : grade,
            gradingCompany: gradingCompany.isEmpty ? nil : gradingCompany,
            purchasePrice:  purchasePrice,
            askingPrice:    askingPrice,
            estimatedValue: marketAverage,
            lastPriceCheck: marketAverage != nil ? now : nil,
            notes:          notes.isEmpty ? nil : notes
        )

        Task {
            do {
                try await collection.addCard(new)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
