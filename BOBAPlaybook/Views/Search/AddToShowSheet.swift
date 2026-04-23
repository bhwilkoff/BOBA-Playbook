import SwiftUI

// MARK: - AddToShowSheet
//
// Streamer-only add destination from the card detail view. Mirrors
// AddToDeckSheet's shape: list existing Shows + a top-of-view
// "Start New Show" button, taps add the current card and dismiss.
// The parent posts a confirmation toast via `onAdded`.

struct AddToShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShowsStore.self) private var shows

    /// Single-card convenience init used from CardDetailView /
    /// CollectionCardDetailView. Wraps the single card in the bulk
    /// array so both call sites land in the same add path.
    init(card: Card, onAdded: @escaping (String) -> Void) {
        self.cards = [card]
        self.titleDescription = card.name
        self.onAdded = onAdded
    }

    /// Bulk-add init used from the scanner Show Mode queue.
    init(cards: [Card], title: String, onAdded: @escaping (String) -> Void) {
        self.cards = cards
        self.titleDescription = title
        self.onAdded = onAdded
    }

    let cards: [Card]
    let titleDescription: String
    /// Called with the name of the show the cards landed in. Parent
    /// animates "Added to {show}" / "Saved N cards to {show}".
    var onAdded: (String) -> Void

    @State private var isLoading = true
    @State private var busyShowId: UUID? = nil
    @State private var isCreatingNew = false
    @State private var newShowText: String = ""
    @State private var showNewSheet = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    savedShowsSection
                    newShowButton
                    if let err = errorMessage {
                        Text(err)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.vertical, Design.Spacing.lg)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("Add to Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                ToolbarItem(placement: .principal) {
                    Text(cards.count == 1 ? "Add \(titleDescription)" : titleDescription)
                        .font(Design.Fonts.display(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await refresh() }
        .sheet(isPresented: $showNewSheet) { newShowSheet }
    }

    // MARK: - Sections

    private var savedShowsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("MY SHOWS")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .padding(.horizontal, Design.Spacing.lg)

            if isLoading {
                ProgressView("Loading shows…")
                    .tint(Design.Colors.bobaCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.xl)
            } else if shows.shows.isEmpty {
                Text("No shows yet — start a new one below.")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.vertical, Design.Spacing.md)
            } else {
                VStack(spacing: Design.Spacing.xs) {
                    ForEach(shows.shows) { show in
                        showRow(show)
                    }
                }
                .padding(.horizontal, Design.Spacing.sm)
            }
        }
    }

    private func showRow(_ show: Show) -> some View {
        let count = shows.cardsByShowId[show.id]?.count
        return Button {
            Task { await add(to: show) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(show.name)
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textPrimary)
                    if let count {
                        Text("\(count) card\(count == 1 ? "" : "s")")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                Spacer()
                if busyShowId == show.id {
                    ProgressView().tint(Design.Colors.bobaCyan)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .padding(.vertical, Design.Spacing.sm)
            .padding(.horizontal, Design.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface))
        }
        .buttonStyle(.plain)
        .disabled(busyShowId != nil || isCreatingNew)
    }

    private var newShowButton: some View {
        Button {
            newShowText = defaultShowName()
            showNewSheet = true
        } label: {
            HStack {
                if isCreatingNew {
                    ProgressView().tint(Design.Colors.nearBlack)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Design.Colors.nearBlack)
                }
                Text("Start New Show")
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(Design.Colors.nearBlack)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaOrange))
        }
        .buttonStyle(.plain)
        .disabled(busyShowId != nil || isCreatingNew)
        .padding(.horizontal, Design.Spacing.lg)
    }

    private var newShowSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Show name", text: $newShowText)
                        .font(Design.Fonts.mono(14))
                } footer: {
                    Text(cards.count == 1
                         ? "We'll create the show and drop \(titleDescription) into it."
                         : "We'll create the show and drop all \(cards.count) cards into it.")
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .listRowBackground(Design.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("New Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newShowText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task { await createAndAdd(name: name) }
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.height(240)])
    }

    // MARK: - Actions

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await shows.loadShows()
    }

    private func add(to show: Show) async {
        busyShowId = show.id
        errorMessage = nil
        defer { busyShowId = nil }
        do {
            try await shows.addCards(showId: show.id, bobaIds: cards.map(\.id))
            onAdded(show.name)
            dismiss()
        } catch {
            errorMessage = "Couldn't add to \(show.name)"
        }
    }

    private func createAndAdd(name: String) async {
        isCreatingNew = true
        errorMessage = nil
        defer { isCreatingNew = false }
        do {
            let show = try await shows.createShow(name: name, initialCardBobaIds: cards.map(\.id))
            onAdded(show.name)
            showNewSheet = false
            dismiss()
        } catch {
            errorMessage = "Couldn't create show"
        }
    }

    private func defaultShowName() -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "Show \(f.string(from: Date()))"
    }
}
