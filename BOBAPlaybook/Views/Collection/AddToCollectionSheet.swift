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
    @State private var serialNumber = ""
    @State private var grade = ""
    @State private var gradingCompany = ""
    @State private var purchasePriceText = ""
    @State private var askingPriceText = ""
    @State private var notes = ""

    @State private var isSaving = false
    @State private var saveError: String?

    // Pre-existing wishlist entry for this card
    private var existingWishlistEntry: UserCard? {
        collection.userCards.first {
            $0.cardNumber == card.cardNumber && !$0.designation.isOwned
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
                        serialRow
                    }
                    .listRowBackground(Design.Colors.surface)

                    Section("PRICING") {
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
            if existingWishlistEntry != nil, collection.entries(for: card.cardNumber).isEmpty {
                designation = existingWishlistEntry?.designation ?? .personal
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

    private var serialRow: some View {
        HStack {
            Text("Serial #")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            TextField("e.g. 42", text: $serialNumber)
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
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
        let serial        = Int(serialNumber)

        let new = NewUserCard(
            cardNumber:     card.cardNumber,
            designation:    designation,
            condition:      condition.isEmpty ? nil : condition,
            serialNumber:   serial,
            grade:          grade.isEmpty ? nil : grade,
            gradingCompany: gradingCompany.isEmpty ? nil : gradingCompany,
            purchasePrice:  purchasePrice,
            askingPrice:    askingPrice,
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
