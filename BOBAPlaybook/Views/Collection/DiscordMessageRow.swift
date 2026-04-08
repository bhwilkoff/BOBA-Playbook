import SwiftUI
import UIKit

// MARK: - DiscordMessageRow
// Renders a single Discord message in the trade-room channel.
// Supports grouped display (compact = no avatar/name when same author continues).

struct DiscordMessageRow: View {
    let message: DiscordMessage
    let isCompact: Bool                 // true = same author within 7 min, hide avatar+name
    let currentUserId: String?
    var onReact: (String) -> Void       = { _ in }
    var onRemoveReact: (String) -> Void = { _ in }
    var onReply: () -> Void             = { }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar column — always 36pt wide for consistent message indentation
            if isCompact {
                Color.clear.frame(width: 36)
            } else {
                DiscordAvatar(user: message.author, size: 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Reply preview
                if message.isReply, let ref = message.referencedMessage {
                    replyBar(ref: ref)
                }

                // Author + timestamp (omitted for compact rows)
                if !isCompact {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(message.author.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(authorColor(for: message.author.id))
                        if let date = message.parsedDate {
                            Text(formatTimestamp(date))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }

                // Content
                if !message.content.isEmpty {
                    DiscordMarkdown(text: message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                }

                // Image attachments
                ForEach(message.attachments?.filter { $0.isImage } ?? []) { att in
                    DiscordImageAttachment(attachment: att)
                }

                // Reactions
                if let reactions = message.reactions, !reactions.isEmpty {
                    reactionChips(reactions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCompact ? 1 : 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            Divider()
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Reply bar

    private func replyBar(ref: DiscordMessageRef) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
            Text(ref.author.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(authorColor(for: ref.author.id).opacity(0.8))
            Text(ref.content.isEmpty ? "*[attachment]*" : ref.content)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    // MARK: - Reaction chips

    private func reactionChips(_ reactions: [DiscordReaction]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(reactions.enumerated()), id: \.offset) { _, r in
                Button {
                    if r.me { onRemoveReact(r.emoji.display) }
                    else     { onReact(r.emoji.display) }
                } label: {
                    HStack(spacing: 4) {
                        Text(r.emoji.display)
                            .font(.system(size: 14))
                        Text("\(r.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(r.me ? Color(hex: "5865F2") : .white.opacity(0.8))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(r.me ? Color(hex: "5865F2").opacity(0.2) : Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(r.me ? Color(hex: "5865F2").opacity(0.5) : Color.white.opacity(0.12))
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // Add reaction button
            Button { onReact("picker") } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1)))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func authorColor(for userId: String) -> Color {
        // Cycle through Discord-like palette based on user id
        let palette: [Color] = [
            Color(hex: "F23F43"), Color(hex: "F0B232"), Color(hex: "23A55A"),
            Color(hex: "00B0F4"), Color(hex: "5865F2"), Color(hex: "EB459E"),
            Color(hex: "ED4245"), Color(hex: "3BA55D"), Color(hex: "FAA61A"),
        ]
        let hash = abs(userId.hashValue)
        return palette[hash % palette.count]
    }

    private func formatTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today at " + DateFormatter.discordTime.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at " + DateFormatter.discordTime.string(from: date)
        }
        return DateFormatter.discordFull.string(from: date)
    }
}

// MARK: - DiscordAvatar

struct DiscordAvatar: View {
    let user: DiscordUser
    let size: CGFloat

    var body: some View {
        Group {
            if let url = user.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:               defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color(hex: "36393F"))
            .overlay(
                Text(String(user.displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - DiscordMarkdown (basic Discord formatting)

struct DiscordMarkdown: View {
    let text: String

    var body: some View {
        Text(parse(text))
    }

    private func parse(_ raw: String) -> AttributedString {
        var s = raw
        var result = AttributedString()

        // Process in order: bold > italic > code > strikethrough
        // This is a simplified parser — handles the most common cases
        do {
            var attr = try AttributedString(markdown: discordToMarkdown(s),
                                            options: .init(interpretedSyntax: .inlinesOnlyPreservingWhitespace))
            return attr
        } catch {
            return AttributedString(s)
        }
    }

    /// Convert Discord markdown to standard Markdown for AttributedString
    private func discordToMarkdown(_ input: String) -> String {
        var s = input
        // **bold**  → already standard
        // *italic* or _italic_ → already standard
        // ~~strike~~ → already standard
        // `code` → already standard
        // ||spoiler|| → replace with ??? (can't hide in attributed string easily)
        s = s.replacingOccurrences(of: #"\|\|(.+?)\|\|"#,
                                   with: "▓▓▓",
                                   options: .regularExpression)
        // > quote → blockquote not supported inline, just strip >
        s = s.replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)
        return s
    }
}

// MARK: - DiscordImageAttachment

struct DiscordImageAttachment: View {
    let attachment: DiscordAttachment

    var body: some View {
        AsyncImage(url: URL(string: attachment.proxyUrl ?? attachment.url)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            case .failure:
                EmptyView()
            default:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 200, height: 100)
                    .overlay(ProgressView())
            }
        }
    }
}

// MARK: - FlowLayout (wrapping HStack for reactions)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0, +)
            + max(0, CGFloat(rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: .init(size))
                x += size.width + spacing
            }
            y += rowH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        let maxW = proposal.width ?? .infinity
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x + w > maxW && !rows.last!.isEmpty {
                rows.append([view])
                x = w + spacing
            } else {
                rows[rows.count - 1].append(view)
                x += w + spacing
            }
        }
        return rows
    }
}

// MARK: - Formatters

extension DateFormatter {
    static let discordTime: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static let discordFull: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"; return f
    }()
}

// Color(hex:) is defined in Design.swift — no duplicate needed here.
