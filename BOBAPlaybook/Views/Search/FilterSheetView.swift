import SwiftUI

/// Sort options that only make sense in the Collection context
/// (date acquired, market value, paid price). Kept separate from
/// CardSortOrder so the Find tab's sort menu doesn't get cluttered
/// with options that depend on user-collection state.
enum CollectionSortOrder: String, CaseIterable, Identifiable {
    case nameAsc        = "name_asc"
    case nameDesc       = "name_desc"
    case dateAddedDesc  = "added_desc"
    case dateAddedAsc   = "added_asc"
    case priceDesc      = "price_desc"
    case priceAsc       = "price_asc"
    case paidDesc       = "paid_desc"
    case paidAsc        = "paid_asc"
    case numberAsc      = "number_asc"
    case numberDesc     = "number_desc"
    case powerDesc      = "power_desc"
    case powerAsc       = "power_asc"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAsc:       return "Name A → Z"
        case .nameDesc:      return "Name Z → A"
        case .dateAddedDesc: return "Recently Added"
        case .dateAddedAsc:  return "Oldest Added"
        case .priceDesc:     return "Market Value: High → Low"
        case .priceAsc:      return "Market Value: Low → High"
        case .paidDesc:      return "Paid: High → Low"
        case .paidAsc:       return "Paid: Low → High"
        case .numberAsc:     return "Card # Ascending"
        case .numberDesc:    return "Card # Descending"
        case .powerDesc:     return "Power: High → Low"
        case .powerAsc:      return "Power: Low → High"
        }
    }
}

struct FilterSheetView: View {
    @Bindable var store: CardStore
    /// Optional binding for the Collection-only sort axis. When non-nil,
    /// the sheet renders an additional sort section above the catalog
    /// sort. The Find tab passes nil, so collection-specific options
    /// (date added, paid, market value) stay scoped to Collection.
    var collectionSort: Binding<CollectionSortOrder>? = nil
    @Environment(\.dismiss) private var dismiss

    // Local power input strings — convert to Int? on commit
    @State private var powerMinText = ""
    @State private var powerMaxText = ""

    var body: some View {
        NavigationStack {
            List {

                // MARK: Collection sort (only when invoked from Collection)
                if let collectionSort = collectionSort {
                    Section {
                        Picker("Sort", selection: collectionSort) {
                            ForEach(CollectionSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                    } header: {
                        sectionHeader("Sort Collection")
                    } footer: {
                        Text("Date added and price sorts are scoped to your collection.")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    .listRowBackground(Design.Colors.surface2)
                } else {
                    // MARK: Sort (catalog)
                    Section {
                        Picker("Sort", selection: $store.sortOrder) {
                            ForEach(CardSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                    } header: {
                        sectionHeader("Sort Order")
                    }
                    .listRowBackground(Design.Colors.surface2)
                }

                // MARK: Card Type
                Section {
                    cardPurposeRow
                } header: {
                    sectionHeader("Card Type")
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Showcase — curated subsets (WOBA + sports for now;
                // team / city / custom showcases planned).
                Section {
                    showcaseRow
                } header: {
                    sectionHeader("Showcase")
                } footer: {
                    Text("Curated subsets of the catalog. More showcases (teams, cities, custom) are planned.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Weapons (renamed from Element 2026-04-23 — every
                // community reference calls them weapons, not elements;
                // the catalog field name `element` stays as-is).
                Section {
                    elementGrid
                } header: {
                    sectionHeader("Weapon")
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Has Image
                Section {
                    Toggle(isOn: $store.hasImageOnly) {
                        Text("Has Image Only")
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    .tint(Design.Colors.bobaOrange)
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Set
                Section {
                    Picker("Set", selection: $store.selectedSet) {
                        Text("All Sets").tag(String?.none)
                        ForEach(store.sets, id: \.self) { s in
                            Text(s).tag(Optional(s))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                } header: {
                    sectionHeader("Set")
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Treatment
                Section {
                    Picker("Treatment", selection: $store.selectedTreatment) {
                        Text("All Treatments").tag(String?.none)
                        ForEach(store.treatments, id: \.self) { t in
                            Text(t).tag(Optional(t))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                } header: {
                    sectionHeader("Treatment")
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Release
                Section {
                    Picker("Release", selection: $store.selectedRelease) {
                        Text("All Releases").tag(String?.none)
                        ForEach(store.releases, id: \.self) { r in
                            Text(r).tag(Optional(r))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)
                } header: {
                    sectionHeader("Release")
                }
                .listRowBackground(Design.Colors.surface2)

                // MARK: Power range
                Section {
                    HStack(spacing: Design.Spacing.sm) {
                        powerField(placeholder: "Min", text: $powerMinText)
                            .onChange(of: powerMinText) { _, new in
                                store.powerMin = Int(new)
                            }
                        Text("–")
                            .foregroundStyle(Design.Colors.textMuted)
                        powerField(placeholder: "Max", text: $powerMaxText)
                            .onChange(of: powerMaxText) { _, new in
                                store.powerMax = Int(new)
                            }
                    }
                    // Power presets
                    presetRow
                } header: {
                    sectionHeader("Power Range")
                }
                .listRowBackground(Design.Colors.surface2)
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        store.clearAllFilters()
                        powerMinText = ""
                        powerMaxText = ""
                    }
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textMuted)
                    .disabled(store.activeFilterCount == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            // Sync text fields with current store state
            powerMinText = store.powerMin.map(String.init) ?? ""
            powerMaxText = store.powerMax.map(String.init) ?? ""
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Showcase row (WOBA / sport filters / future custom)
    //
    // Chip-style picker mirroring the card-purpose row but bound to
    // store.selectedShowcaseId. Tap an active chip again to clear it,
    // matching the behavior of the Learn > Browse tab's chips where
    // these showcases originally lived.
    private var showcaseRow: some View {
        FlowLayout(spacing: Design.Spacing.sm) {
            ForEach(Showcases.all) { showcase in
                let selected = store.selectedShowcaseId == showcase.id
                Button {
                    store.selectedShowcaseId = selected ? nil : showcase.id
                } label: {
                    Text(showcase.name)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(selected ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs + 2)
                        .background(
                            Capsule()
                                .fill(selected ? Design.Colors.bobaCyan : Design.Colors.glass)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    // MARK: - Card purpose row (Heroes / Plays / Hot Dogs / Sealed)
    //
    // Moved into the filter sheet (2026-04-22) to live alongside the rest
    // of the filters instead of as a separate chip row on SearchView.
    private var cardPurposeRow: some View {
        FlowLayout(spacing: Design.Spacing.sm) {
            ForEach(CardPurpose.allCases) { purpose in
                let selected = store.cardPurpose == purpose
                Button {
                    store.cardPurpose = purpose
                } label: {
                    Text(purpose.rawValue)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(selected ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs + 2)
                        .background(
                            Capsule()
                                .fill(selected ? Design.Colors.bobaOrange : Design.Colors.glass)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    // MARK: - Element grid
    private var elementGrid: some View {
        FlowLayout(spacing: Design.Spacing.sm) {
            ForEach(store.elements, id: \.self) { element in
                let selected = store.selectedElements.contains(element)
                Button {
                    if selected { store.selectedElements.remove(element) }
                    else        { store.selectedElements.insert(element) }
                } label: {
                    Text(element)
                        .font(Design.Fonts.mono(12, weight: .bold))
                        .foregroundStyle(selected ? .white : Design.Colors.element(element))
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs + 2)
                        .background(
                            Capsule()
                                .fill(selected
                                    ? Design.Colors.element(element)
                                    : Design.Colors.element(element).opacity(0.12))
                                .overlay(Capsule().strokeBorder(
                                    Design.Colors.element(element).opacity(selected ? 0 : 0.4),
                                    lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    // MARK: - Power preset row
    private var presetRow: some View {
        let presets: [(label: String, min: Int?, max: Int?)] = [
            ("Any",   nil,  nil),
            ("Low",   nil,  114),
            ("Mid",   115,  139),
            ("High",  140,  164),
            ("Elite", 165,  nil),
        ]
        return HStack(spacing: Design.Spacing.xs) {
            ForEach(presets, id: \.label) { p in
                let active = store.powerMin == p.min && store.powerMax == p.max
                Button {
                    store.powerMin = p.min
                    store.powerMax = p.max
                    powerMinText = p.min.map(String.init) ?? ""
                    powerMaxText = p.max.map(String.init) ?? ""
                } label: {
                    Text(p.label)
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(active ? .white : Design.Colors.textSecondary)
                        .padding(.horizontal, Design.Spacing.sm)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .fill(active ? Design.Colors.bobaOrange : Design.Colors.glass)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.textMuted)
            .tracking(1.5)
    }

    private func powerField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .font(Design.Fonts.mono(14))
            .foregroundStyle(Design.Colors.textPrimary)
            .padding(Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .fill(Design.Colors.glass)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                        .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            )
    }
}

// MARK: - Simple flow layout (iOS 16+)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, maxH: CGFloat = 0, rowH: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowH + spacing; x = 0; rowH = 0
            }
            rowH = max(rowH, size.height)
            maxH = max(maxH, y + rowH)
            x += size.width + spacing
        }
        return CGSize(width: width, height: maxH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + spacing; x = bounds.minX; rowH = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}
