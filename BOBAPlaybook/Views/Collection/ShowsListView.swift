import SwiftUI

// MARK: - ShowsListView
//
// Top-level list of a streamer's shows, rendered inside the Collection
// tab's "My Shows" mode. Each row opens ShowDetailView; swipe + menu
// actions handle rename and delete. Creating a new empty show is a
// manual path (usually coaches arrive here via Scanner Show Mode or
// card-detail "To Show"); "New Show" button is kept simple so the
// prep flow doesn't depend on any other surface.

struct ShowsListView: View {
    @Environment(ShowsStore.self) private var shows
    @State private var selectedShow: Show? = nil
    @State private var renameTarget: Show? = nil
    @State private var renameText: String = ""
    @State private var showNewShowSheet = false
    @State private var newShowName: String = ""
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Design.Spacing.sm) {
                // Primary action — new show. Kept at the top so a
                // streamer prepping at the start of a session lands on
                // it without scanning.
                Button {
                    newShowName = defaultShowName()
                    showNewShowSheet = true
                } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Design.Colors.nearBlack)
                        Text("Start New Show")
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.nearBlack)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Design.Colors.bobaOrange))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.md)

                if shows.shows.isEmpty {
                    emptyState
                } else {
                    ForEach(shows.shows) { show in
                        showRow(show)
                    }
                    .padding(.horizontal, Design.Spacing.lg)
                }
            }
            .padding(.bottom, Design.Spacing.xxl)
        }
        .refreshable { await shows.loadShows() }
        .task { if shows.shows.isEmpty { await shows.loadShows() } }
        .sheet(item: $selectedShow) { show in
            NavigationStack { ShowDetailView(show: show) }
        }
        // Rename + new-show sheets are action-shaped — popover on iPad
        // anchored to the trigger button (DESIGN.md §6.6).
        .sheet(item: $renameTarget) { target in
            renameSheet(for: target)
                .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: $showNewShowSheet) {
            newShowSheet
                .presentationCompactAdaptation(.popover)
        }
        .bobaItemAlert("Couldn't finish that", item: $actionError) { _ in
            Button("OK") { actionError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Row

    private func showRow(_ show: Show) -> some View {
        let cardCount = shows.cardsByShowId[show.id]?.count ?? 0
        return Button {
            selectedShow = show
        } label: {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: "tv.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Design.Colors.bobaOrange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(show.name)
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                    // Only show the cached count when we have it — otherwise
                    // the row would misleadingly say "0 cards" pre-fetch.
                    if shows.cardsByShowId[show.id] != nil {
                        Text("\(cardCount) card\(cardCount == 1 ? "" : "s")")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    } else {
                        Text("Tap to load cards")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                Spacer()
                Menu {
                    Button {
                        renameText = show.name
                        renameTarget = show
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        Task { await deleteShow(show) }
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(Design.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "tv")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No shows yet")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Start a new show here, or scan cards into a show from the scanner's Show Mode.")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.xxl)
    }

    // MARK: - Rename + new-show sheets

    private func renameSheet(for show: Show) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Show name", text: $renameText)
                        .font(Design.Fonts.mono(14))
                }
                .listRowBackground(Design.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Rename Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { renameTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !newName.isEmpty else { return }
                        Task {
                            do {
                                try await shows.rename(showId: show.id, to: newName)
                                renameTarget = nil
                            } catch {
                                actionError = error.localizedDescription
                            }
                        }
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.height(200)])
    }

    private var newShowSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Show name", text: $newShowName)
                        .font(Design.Fonts.mono(14))
                } footer: {
                    Text("You'll add cards from the scanner's Show Mode, the card detail screen, or the Find tab.")
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
                    Button("Cancel") { showNewShowSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newShowName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            do {
                                let show = try await shows.createShow(name: name)
                                showNewShowSheet = false
                                // Drop the user directly into the empty show
                                // so they can start adding cards right away.
                                selectedShow = show
                            } catch {
                                actionError = error.localizedDescription
                            }
                        }
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.height(240)])
    }

    // MARK: - Helpers

    private func deleteShow(_ show: Show) async {
        do { try await shows.delete(showId: show.id) }
        catch { actionError = error.localizedDescription }
    }

    /// Reasonable default name based on the current date so coaches
    /// don't have to type much to get started. "Whatnot 4/23" style.
    private func defaultShowName() -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "Show \(f.string(from: Date()))"
    }
}
