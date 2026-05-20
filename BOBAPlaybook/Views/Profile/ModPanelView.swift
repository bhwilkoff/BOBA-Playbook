import SwiftUI

// MARK: - ModPanelView
// Entry point for moderator/admin tools. Accessible from ProfileView when isMod == true.

struct ModPanelView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CardStore.self) private var cardStore
    @State private var searchText = ""
    @State private var selectedCard: Card?
    @State private var showingAddCard = false

    var body: some View {
        List {
            Section {
                Label("Logged in as \(auth.isAdmin ? "Admin" : "Moderator")", systemImage: "shield.lefthalf.filled")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(auth.isAdmin ? Design.Colors.bobaOrange : Design.Colors.bobaCyan)
            }
            .listRowBackground(Design.Colors.surface)

            Section("ADD A NEW CARD") {
                Button {
                    showingAddCard = true
                } label: {
                    Label("Add a card to the catalog", systemImage: "plus.rectangle.on.rectangle")
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                Text("For cards that aren't in the catalog yet — Promos, Top 8, anything missing. Admin reviews before it ships to everyone.")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Design.Colors.surface)

            Section("CARD INFO CORRECTIONS") {
                Text("Search for a card to submit a correction or flag an image issue.")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(Design.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                // Inline search field — the section text used to say
                // "search below" but the only searchable surface was the
                // nav bar at the top. Users hit a dead-end looking for
                // a field here. Added per beta feedback 2026-05-20 so
                // the search lives where the copy points.
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Design.Colors.textMuted)
                    TextField("Card # or hero name", text: $searchText)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Design.Colors.surface)

            if !searchText.isEmpty {
                // CardSearch.matches mirrors the word-prefix behavior
                // of Find / Decks so a query like "amon" finds Amon-Ra
                // but not Johnny Damon (per
                // feedback_search_word_prefix memory).
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let results = cardStore.displayCards.filter { card in
                    CardSearch.matches(query: q, fields: [card.name, card.cardNumber, card.hero])
                }.prefix(50)

                if results.isEmpty {
                    Section {
                        Text("No cards found for \"\(searchText)\"")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    .listRowBackground(Design.Colors.surface)
                } else {
                    Section("RESULTS") {
                        // id: \.id (bobaId) — cardNumber is non-unique
                        // when a hero has multiple variants at one
                        // number; using it here would collide and
                        // corrupt SwiftUI identity tracking.
                        ForEach(Array(results), id: \.id) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.hero.isEmpty ? card.cardNumber : card.hero)
                                        .font(Design.Fonts.display(14))
                                        .foregroundStyle(Design.Colors.textPrimary)
                                    Text(card.cardNumber)
                                        .font(Design.Fonts.mono(11))
                                        .foregroundStyle(Design.Colors.textMuted)
                                }
                            }
                        }
                    }
                    .listRowBackground(Design.Colors.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Design.Colors.nearBlack)
        .navigationTitle("Mod Panel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search by card # or hero name")
        .sheet(item: $selectedCard) { card in
            ModCardEditSheet(card: card)
        }
        .sheet(isPresented: $showingAddCard) {
            ModAddCardSheet()
        }
    }
}
