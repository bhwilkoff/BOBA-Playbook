import Foundation

// MARK: - Discord data models (in-memory only — never persisted to disk)

struct DiscordUser: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?
    let discriminator: String?

    var displayName: String { globalName?.isEmpty == false ? globalName! : username }

    var avatarURL: URL? {
        guard let avatar else {
            // Default avatar based on user id mod 5
            guard let uid = UInt64(id) else { return nil }
            return URL(string: "https://cdn.discordapp.com/embed/avatars/\(uid % 5).png")
        }
        let ext = avatar.hasPrefix("a_") ? "gif" : "webp"
        return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).\(ext)?size=64")
    }

    enum CodingKeys: String, CodingKey {
        case id, username, avatar, discriminator
        case globalName = "global_name"
    }
}

struct DiscordEmoji: Codable, Equatable {
    let id: String?
    let name: String?

    /// String used in the PUT/DELETE reaction endpoint path
    var reactionKey: String {
        if let id, let name { return "\(name):\(id)" }
        return name ?? "❓"
    }

    /// String shown in the UI
    var display: String { name ?? "❓" }
}

struct DiscordReaction: Codable, Equatable {
    let emoji: DiscordEmoji
    var count: Int
    var me: Bool
}

struct DiscordAttachment: Codable, Identifiable {
    let id: String
    let filename: String
    let url: String
    let proxyUrl: String?
    let contentType: String?
    let width: Int?
    let height: Int?

    var isImage: Bool {
        guard let ct = contentType else {
            let lower = filename.lowercased()
            return lower.hasSuffix(".png") || lower.hasSuffix(".jpg")
                || lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif")
                || lower.hasSuffix(".webp")
        }
        return ct.hasPrefix("image/")
    }

    enum CodingKeys: String, CodingKey {
        case id, filename, url, width, height
        case proxyUrl    = "proxy_url"
        case contentType = "content_type"
    }
}

/// Lightweight reply preview — avoids recursive struct.
struct DiscordMessageRef: Codable, Equatable {
    let id: String
    let content: String
    let author: DiscordUser

    enum CodingKeys: String, CodingKey { case id, content, author }
}

struct DiscordMessage: Codable, Identifiable {
    let id: String
    let content: String
    let author: DiscordUser
    let timestamp: String
    var reactions: [DiscordReaction]?
    let attachments: [DiscordAttachment]?
    let referencedMessage: DiscordMessageRef?
    let type: Int

    /// Discord message type 0 = DEFAULT, 19 = REPLY. Skip system messages.
    var isUserMessage: Bool { type == 0 || type == 19 }
    var isReply: Bool { type == 19 }

    var parsedDate: Date? {
        ISO8601DateFormatter.discord.date(from: timestamp)
            ?? ISO8601DateFormatter().date(from: timestamp)
    }

    enum CodingKeys: String, CodingKey {
        case id, content, author, timestamp, reactions, attachments, type
        case referencedMessage = "referenced_message"
    }
}

extension ISO8601DateFormatter {
    static let discord: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Token response

struct DiscordTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }
}

// MARK: - Emoji data for picker

struct EmojiCategory: Identifiable {
    let id: String
    let label: String
    let icon: String
    let emoji: [String]
}

let discordEmojiCategories: [EmojiCategory] = [
    EmojiCategory(id: "quick", label: "Frequently Used", icon: "clock", emoji: [
        "👍","❤️","🔥","😂","😮","😢","🎉","💯","🙏","👀","💪","✅"
    ]),
    EmojiCategory(id: "smileys", label: "Smileys & Emotion", icon: "face.smiling", emoji: [
        "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊",
        "😇","🥰","😍","😘","😗","😚","😋","😛","😝","😜","🤪","🤨",
        "🧐","🤓","😎","🥸","🤩","🥳","😏","😒","😞","😔","😟","😕",
        "🙁","😣","😖","😫","😩","🥺","😢","😭","😤","😠","😡","🤬",
        "🤯","😳","🥵","🥶","😱","😨","😰","😥","😓","🤗","🤔","🫠",
        "🤭","🤫","🤥","😶","😐","😑","😬","🙄","😯","😦","😧","😮",
        "😲","🥱","😴","🤤","😪","😵","🤐","🥴","🤢","🤮","🤧","😷",
        "🤒","🤕","🤑","🤠","😈","👿","👹","👺","🤡","💩","👻","💀"
    ]),
    EmojiCategory(id: "people", label: "People & Body", icon: "person.fill", emoji: [
        "👋","🤚","🖐️","✋","🖖","👌","🤌","🤏","✌️","🤞","🫰","🤙",
        "👈","👉","👆","👇","☝️","👍","👎","✊","👊","🤛","🤜","👏",
        "🙌","🤲","🤝","🙏","💪","🦾","🦿","🦵","🦶","👂","🦻","👃",
        "👁️","👅","🫀","🫁","🧠","🦷","🦴","👀","🗣️","👤","👥"
    ]),
    EmojiCategory(id: "animals", label: "Animals & Nature", icon: "pawprint.fill", emoji: [
        "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮",
        "🐷","🐸","🐵","🐔","🐧","🐦","🦅","🦆","🦉","🦋","🐝","🐛",
        "🐢","🐍","🦎","🦕","🦖","🐊","🦈","🐋","🐳","🦭","🦓","🦒",
        "🐘","🦏","🦛","🐆","🐅","🦊","🐺","🦝","🦨","🦡","🦦","🐿️"
    ]),
    EmojiCategory(id: "food", label: "Food & Drink", icon: "fork.knife", emoji: [
        "🍕","🍔","🍟","🌭","🍿","🧂","🥓","🥚","🍳","🧇","🥞","🧈",
        "🥗","🥘","🍜","🍱","🍣","🍤","🍙","🍚","🍛","🍝","🍠","🧆",
        "🌮","🌯","🫔","🥙","🧁","🍰","🎂","🍩","🍪","🍫","🍬","🍭",
        "🍦","🍧","🍨","☕","🫖","🧃","🧉","🥤","🍺","🍻","🥂","🍾"
    ]),
    EmojiCategory(id: "activities", label: "Activities", icon: "sportscourt.fill", emoji: [
        "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🎱","🏓","🏸","🥊",
        "🥋","🎿","🛷","🛹","🛼","🎮","🕹️","🎲","🎯","🎳","🎻","🎸",
        "🎺","🥁","🎤","🎧","🎼","🏆","🥇","🥈","🥉","🎖️","🏅","🎗️"
    ]),
    EmojiCategory(id: "objects", label: "Objects", icon: "cube.fill", emoji: [
        "💎","💰","💵","💳","🔑","🗝️","🔒","🔓","📱","💻","🖥️","⌨️",
        "📷","📸","🎵","🎶","🎙️","📚","📖","✏️","📝","🗒️","📋","📦",
        "🛒","🔍","🔎","💡","🔦","🕯️","💊","🧪","🧫","🧬","🔬","🔭",
        "⚗️","🪄","🎩","👑","💍","👓","🕶️","🥽","🧳","☂️","☔","⚡"
    ]),
    EmojiCategory(id: "symbols", label: "Symbols", icon: "number", emoji: [
        "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕",
        "💞","💓","💗","💖","💘","💝","✨","⭐","🌟","💫","🔥","💥",
        "❄️","🌊","🌈","☀️","🌙","⚡","🌪️","✅","❌","⭕","❗","❓",
        "💯","🔝","🆕","🆒","🆓","🆙","🔄","⬆️","⬇️","⬅️","➡️","🔀"
    ]),
]
