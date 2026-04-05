import SwiftUI

struct ScanQueueView: View {
    @Environment(ScanStore.self)       private var scanStore
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(AuthManager.self)     private var auth
    @Environment(\.dismiss)           private var dismiss

    @State private var selectedCard: Card?
    @State private var isSavingAll    = false
    @State private var saveError:     String?
    @State private var saveSuccess    = false

    var body: some View {
        NavigationStack {
            Group {
                if scanStore.queuedCards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Scan Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .background(Design.Colors.nearBlack)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
    }

    // MARK: - Card list

    private var cardList: some View {
        List {
            ForEach(scanStore.queuedCards) { queued in
                Button { selectedCard = queued.card } label: {
                    HStack(spacing: Design.Spacing.md) {
                        CardImageView(card: queued.card, size: .thumb)
                            .frame(width: 44, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))

                        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                            Text(queued.card.name)
                                .font(Design.Fonts.display(15))
                                .foregroundStyle(Design.Colors.textPrimary)
                                .lineLimit(1)
                            Text(queued.card.cardNumber)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(Design.Colors.bobaOrange)
                            if let power = queued.card.power {
                                Text("PWR \(power)  ·  \(queued.card.element)")
                                    .font(Design.Fonts.mono(10))
                                    .foregroundStyle(Design.Colors.element(queued.card.element))
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                    .padding(.vertical, Design.Spacing.xs)
                }
                .buttonStyle(.plain)
                .listRowBackground(Design.Colors.surface)
            }
            .onDelete { scanStore.removeFromQueue(at: $0) }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            if auth.isAuthenticated {
                saveAllButton
                    .padding(Design.Spacing.lg)
            }
        }
    }

    // MARK: - Save all button

    private var saveAllButton: some View {
        VStack(spacing: Design.Spacing.sm) {
            if let error = saveError {
                Text(error)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(.red)
            }
            if saveSuccess {
                Label("All cards saved to Collection", systemImage: "checkmark.circle.fill")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(.green)
            }

            Button {
                Task { await saveAll() }
            } label: {
                HStack {
                    if isSavingAll {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                    }
                    Text(isSavingAll ? "Saving…" : "Save All to Collection")
                        .font(Design.Fonts.display(15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.bobaOrange)
                )
                .foregroundStyle(.white)
            }
            .disabled(isSavingAll || saveSuccess)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Queue Empty")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Enable Multi mode on the scanner and detected cards will appear here.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !scanStore.queuedCards.isEmpty {
                Button("Clear All") {
                    withAnimation { scanStore.clearQueue() }
                }
                .foregroundStyle(Design.Colors.textMuted)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
                .foregroundStyle(Design.Colors.bobaOrange)
        }
    }

    // MARK: - Save all

    private func saveAll() async {
        isSavingAll = true
        saveError   = nil
        var firstError: String?

        for queued in scanStore.queuedCards {
            let entry = NewUserCard(
                cardNumber: queued.card.cardNumber,
                designation: .personal
            )
            do {
                try await collectionStore.addCard(entry)
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        isSavingAll = false
        if let err = firstError {
            saveError = err
        } else {
            saveSuccess = true
            scanStore.clearQueue()
        }
    }
}
