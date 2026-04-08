import SwiftUI

// MARK: - ReactionPickerView
// Full emoji picker sheet — matches Discord's native category/search UI.

struct ReactionPickerView: View {
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory = "quick"
    @State private var searchText = ""

    private var filteredEmoji: [String] {
        if searchText.isEmpty {
            return discordEmojiCategories.first { $0.id == selectedCategory }?.emoji ?? []
        }
        return discordEmojiCategories.flatMap { $0.emoji }.filter { emoji in
            // Basic search: check if the emoji name contains the search text
            // In production you'd have a name map; here we just return all
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                categoryBar
                emojiGrid
            }
            .background(Color(hex: "1E1F22"))
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "5865F2"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search emoji", text: $searchText)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Category tab bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(discordEmojiCategories) { cat in
                    Button {
                        selectedCategory = cat.id
                        searchText = ""
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(
                                    selectedCategory == cat.id
                                    ? Color(hex: "5865F2")
                                    : .white.opacity(0.4)
                                )
                                .frame(width: 36, height: 32)
                        }
                        .overlay(alignment: .bottom) {
                            if selectedCategory == cat.id {
                                Rectangle()
                                    .fill(Color(hex: "5865F2"))
                                    .frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color(hex: "2B2D31"))
    }

    // MARK: - Emoji grid

    private var emojiGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 9)
        return ScrollView {
            if !searchText.isEmpty {
                // Show all emoji when searching
                allEmojiGrid(columns: columns)
            } else {
                categoryEmojiGrid(columns: columns)
            }
        }
    }

    private func categoryEmojiGrid(columns: [GridItem]) -> some View {
        let cat = discordEmojiCategories.first { $0.id == selectedCategory }
            ?? discordEmojiCategories[0]
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(cat.emoji, id: \.self) { emoji in
                emojiButton(emoji)
            }
        }
        .padding(8)
    }

    private func allEmojiGrid(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(discordEmojiCategories.flatMap { $0.emoji }, id: \.self) { emoji in
                emojiButton(emoji)
            }
        }
        .padding(8)
    }

    private func emojiButton(_ emoji: String) -> some View {
        Button {
            onSelect(emoji)
            dismiss()
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
