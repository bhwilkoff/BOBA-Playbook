import SwiftUI

// MARK: - CustomRainbowEditorSheet
//
// Create + edit form for a user-defined rainbow. The form is one
// Section per filter dimension (heroes, sets, sub-sets, weapons,
// treatments, card types, releases, plus the Inspired-Ink toggle).
// Each row opens a multi-select sub-picker populated from the
// live catalog's distinct values so the user can only choose
// taxonomy that actually exists.
//
// Live preview at the top: "X cards match · Y of those owned." So
// the user can dial in their goal interactively without guessing.
//
// Init in either "create" mode (rainbow == nil) or "edit" mode
// (rainbow == existing row). Edit mode shows a destructive Delete
// button at the bottom.

struct CustomRainbowEditorSheet: View {
    @Environment(CardStore.self)            private var cardStore
    @Environment(CollectionStore.self)      private var collection
    @Environment(CustomRainbowStore.self)   private var rainbowStore
    @Environment(\.dismiss)                 private var dismiss

    /// nil = create mode; non-nil = edit mode for that rainbow.
    let existing: CustomRainbow?

    @State private var name:     String          = ""
    @State private var criteria: RainbowCriteria = .init()

    @State private var isSaving      = false
    @State private var saveError:    String?
    @State private var confirmDelete = false

    /// Sheet-presentation state for each sub-picker.
    private enum SubPicker: Identifiable {
        case heroes, sets, subSets, elements, treatments, cardTypes, releases
        var id: String { String(describing: self) }
        var title: String {
            switch self {
            case .heroes:     return "Heroes"
            case .sets:       return "Sets"
            case .subSets:    return "Sub-sets"
            case .elements:   return "Weapons"
            case .treatments: return "Treatments"
            case .cardTypes:  return "Card types"
            case .releases:   return "Releases"
            }
        }
    }
    @State private var presented: SubPicker?

    var body: some View {
        NavigationStack {
            Form {
                Section("NAME") {
                    TextField("e.g. Cupid Griffey Chase, Glow Hunt…", text: $name)
                        .font(Design.Fonts.mono(15, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .listRowBackground(Design.Colors.surface)

                Section("PROGRESS PREVIEW") {
                    let total = matchingCardsCount
                    let owned = ownedMatchingCount
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(total) cards match")
                                .font(Design.Fonts.mono(13, weight: .bold))
                                .foregroundStyle(Design.Colors.bobaCyan)
                            Text("\(owned) of those owned (\(percentLabel(owned: owned, total: total)))")
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Design.Colors.surface)

                Section("FILTERS") {
                    pickerRow(.heroes,     selected: criteria.heroes,     options: catalogValues(.heroes))
                    pickerRow(.sets,       selected: criteria.sets,       options: catalogValues(.sets))
                    pickerRow(.subSets,    selected: criteria.subSets,    options: catalogValues(.subSets))
                    pickerRow(.elements,   selected: criteria.elements,   options: catalogValues(.elements))
                    pickerRow(.treatments, selected: criteria.treatments, options: catalogValues(.treatments))
                    pickerRow(.cardTypes,  selected: criteria.cardTypes,  options: catalogValues(.cardTypes))
                    pickerRow(.releases,   selected: criteria.releases,   options: catalogValues(.releases))
                    Toggle("Inspired Ink only", isOn: $criteria.inspiredInkOnly)
                        .font(Design.Fonts.mono(14))
                        .tint(Design.Colors.bobaOrange)
                }
                .listRowBackground(Design.Colors.surface)

                if let error = saveError {
                    Section {
                        Text(error)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Design.Colors.surface)
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete rainbow", systemImage: "trash")
                                .font(Design.Fonts.mono(14, weight: .bold))
                        }
                    }
                    .listRowBackground(Design.Colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle(existing == nil ? "New rainbow" : "Edit rainbow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Design.Colors.bobaOrange)
                    } else {
                        Button("Save") { save() }
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .disabled(!canSave)
                    }
                }
            }
            .sheet(item: $presented) { kind in
                MultiSelectPicker(
                    title:    kind.title,
                    options:  catalogValues(kind),
                    selected: binding(for: kind)
                )
            }
            .confirmationDialog("Delete this rainbow?",
                                isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .onAppear { hydrateFromExistingIfNeeded() }
        }
    }

    // MARK: - Picker row

    @ViewBuilder
    private func pickerRow(_ kind: SubPicker, selected: [String], options: [String]) -> some View {
        Button {
            presented = kind
        } label: {
            HStack {
                Text(kind.title)
                    .font(Design.Fonts.mono(13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                Text(selected.isEmpty ? "Any" : selected.prefix(3).joined(separator: ", ")
                     + (selected.count > 3 ? " +\(selected.count - 3)" : ""))
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(selected.isEmpty ? Design.Colors.textMuted : Design.Colors.bobaCyan)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
    }

    private func binding(for kind: SubPicker) -> Binding<[String]> {
        switch kind {
        case .heroes:     return Binding(get: { criteria.heroes     }, set: { criteria.heroes     = $0 })
        case .sets:       return Binding(get: { criteria.sets       }, set: { criteria.sets       = $0 })
        case .subSets:    return Binding(get: { criteria.subSets    }, set: { criteria.subSets    = $0 })
        case .elements:   return Binding(get: { criteria.elements   }, set: { criteria.elements   = $0 })
        case .treatments: return Binding(get: { criteria.treatments }, set: { criteria.treatments = $0 })
        case .cardTypes:  return Binding(get: { criteria.cardTypes  }, set: { criteria.cardTypes  = $0 })
        case .releases:   return Binding(get: { criteria.releases   }, set: { criteria.releases   = $0 })
        }
    }

    // MARK: - Catalog projections

    /// All distinct, non-empty values for a given dimension across
    /// the live catalog. Sorted alphabetically; the picker's own
    /// search field handles narrowing.
    private func catalogValues(_ kind: SubPicker) -> [String] {
        let cards = cardStore.displayCards
        let raw: [String]
        switch kind {
        case .heroes:     raw = cards.map(\.hero)
        case .sets:       raw = cards.map(\.set)
        case .subSets:    raw = cards.compactMap { $0.subSet }
        case .elements:   raw = cards.map(\.element)
        case .treatments: raw = cards.compactMap { $0.treatment }
        case .cardTypes:  raw = cards.map(\.cardType)
        case .releases:   raw = cards.map(\.release)
        }
        return Array(Set(raw.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var matchingCards: [Card] {
        cardStore.displayCards.filter { criteria.matches($0) }
    }
    private var matchingCardsCount: Int { matchingCards.count }
    private var ownedMatchingCount: Int {
        let owned = Set(collection.userCards
                            .filter { $0.designation.isOwned }
                            .compactMap { $0.bobaId })
        return matchingCards.filter { owned.contains($0.id) }.count
    }
    private func percentLabel(owned: Int, total: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int(((Double(owned) / Double(total)) * 100).rounded()))%"
    }

    // MARK: - State helpers

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !criteria.isEmpty
    }

    private func hydrateFromExistingIfNeeded() {
        guard let r = existing else { return }
        if name.isEmpty { name = r.name }
        if criteria.isEmpty { criteria = r.criteria }
    }

    private func save() {
        isSaving  = true
        saveError = nil
        Task {
            do {
                if let r = existing {
                    try await rainbowStore.update(r, name: name, criteria: criteria)
                } else {
                    _ = try await rainbowStore.create(name: name, criteria: criteria)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func performDelete() {
        guard let r = existing else { return }
        isSaving = true
        Task {
            do {
                try await rainbowStore.delete(r)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - MultiSelectPicker
//
// Generic sub-sheet for a single criterion dimension: a searchable
// list of options with check-mark toggles. Bound to the parent's
// `[String]` selection list; tapping a row adds/removes that
// option in place.

private struct MultiSelectPicker: View {
    let title:   String
    let options: [String]
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [String] {
        guard !query.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section("SELECTED") {
                        ForEach(selected, id: \.self) { value in
                            Button { toggle(value) } label: {
                                row(value, isSelected: true)
                            }
                        }
                        Button(role: .destructive) {
                            selected.removeAll()
                        } label: {
                            Text("Clear all")
                                .font(Design.Fonts.mono(13, weight: .semibold))
                        }
                    }
                    .listRowBackground(Design.Colors.surface)
                }
                Section("ALL \(title.uppercased())") {
                    ForEach(filtered, id: \.self) { value in
                        Button { toggle(value) } label: {
                            row(value, isSelected: selected.contains(value))
                        }
                    }
                }
                .listRowBackground(Design.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .searchable(text: $query)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
        }
    }

    private func row(_ value: String, isSelected: Bool) -> some View {
        HStack {
            Text(value)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
        }
    }

    private func toggle(_ value: String) {
        if let idx = selected.firstIndex(of: value) {
            selected.remove(at: idx)
        } else {
            selected.append(value)
        }
    }
}
