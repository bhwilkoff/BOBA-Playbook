import Foundation
import AuthenticationServices
import CryptoKit
import Security

// MARK: - DiscordService
// Manages Discord OAuth2 (PKCE), channel polling, send, and reactions.
// All message data is in-memory only — nothing written to disk except
// auth tokens (Keychain) and last-seen message ID (UserDefaults).

@Observable
@MainActor
final class DiscordService: NSObject {

    // MARK: - Public state

    var isAuthorized   = false
    var isMember       = false
    var memberChecked  = false
    var currentUser: DiscordUser?
    var messages: [DiscordMessage] = []
    var isLoading      = false
    var hasMoreHistory = true
    var errorMessage: String?

    var unreadCount: Int {
        guard let last = UserDefaults.standard.string(forKey: "discord_last_seen_id")
        else { return min(messages.count, 99) }
        // Discord snowflake IDs are lexicographically ordered (larger = newer)
        return messages.filter { $0.id > last }.count
    }

    // MARK: - Private state

    private var newestId: String?
    private var oldestId: String?
    private var pollTask: Task<Void, Never>?

    // PKCE one-time use — cleared after exchange
    private var pkceVerifier: String?
    private var pkceState: String?

    // MARK: - Keychain helpers

    private func store(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    key,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:      kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private var accessToken: String? {
        get { load(key: "discord_access_token") }
        set { newValue == nil ? delete(key: "discord_access_token") : store(newValue!, key: "discord_access_token") }
    }
    private var refreshToken: String? {
        get { load(key: "discord_refresh_token") }
        set { newValue == nil ? delete(key: "discord_refresh_token") : store(newValue!, key: "discord_refresh_token") }
    }
    private var tokenExpiresAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "discord_token_expires")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let v = newValue { UserDefaults.standard.set(v.timeIntervalSince1970, forKey: "discord_token_expires") }
            else { UserDefaults.standard.removeObject(forKey: "discord_token_expires") }
        }
    }

    // MARK: - Init

    override init() {
        super.init()
        isAuthorized = accessToken != nil
    }

    // MARK: - OAuth2 PKCE Authorization

    func authorize() async {
        let verifier = makeVerifier()
        let challenge = makeChallenge(verifier)
        let state = UUID().uuidString
        pkceVerifier = verifier
        pkceState = state

        var comps = URLComponents(string: "https://discord.com/oauth2/authorize")!
        comps.queryItems = [
            .init(name: "client_id",             value: DiscordConfig.clientId),
            .init(name: "response_type",          value: "code"),
            .init(name: "redirect_uri",           value: DiscordConfig.redirectURI),
            .init(name: "scope",                  value: "identify guilds"),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "code_challenge_method",  value: "S256"),
            .init(name: "state",                  value: state),
        ]
        guard let authURL = comps.url else { return }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "bobaplaybook"
                ) { url, err in
                    if let err { cont.resume(throwing: err); return }
                    guard let url else { cont.resume(throwing: URLError(.badURL)); return }
                    cont.resume(returning: url)
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            let parts = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            guard
                let code = parts?.queryItems?.first(where: { $0.name == "code" })?.value,
                let retState = parts?.queryItems?.first(where: { $0.name == "state" })?.value,
                retState == pkceState,
                let ver = pkceVerifier
            else {
                errorMessage = "Authorization failed — unexpected response."
                return
            }
            pkceVerifier = nil; pkceState = nil

            try await exchangeCode(code, verifier: ver)
            isAuthorized = accessToken != nil
            if isAuthorized {
                await fetchCurrentUser()
                await checkMembership()
            }
        } catch let err as ASWebAuthenticationSessionError where err.code == .canceledLogin {
            // User cancelled — no error to show
        } catch {
            errorMessage = "Authorization error: \(error.localizedDescription)"
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id",      value: DiscordConfig.clientId),
            .init(name: "grant_type",     value: "authorization_code"),
            .init(name: "code",           value: code),
            .init(name: "redirect_uri",   value: DiscordConfig.redirectURI),
            .init(name: "code_verifier",  value: verifier),
        ]
        req.httpBody = body.query?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let tokens = try JSONDecoder().decode(DiscordTokenResponse.self, from: data)
        storeTokens(tokens)
    }

    private func storeTokens(_ t: DiscordTokenResponse) {
        accessToken    = t.accessToken
        refreshToken   = t.refreshToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(t.expiresIn) - 60)
    }

    // MARK: - Token refresh (via Worker — holds client_secret)

    @discardableResult
    func refreshIfNeeded() async -> Bool {
        guard let expires = tokenExpiresAt, Date() >= expires else { return true }
        return await silentRefresh()
    }

    @discardableResult
    private func silentRefresh() async -> Bool {
        guard let rt = refreshToken else { disconnect(); return false }
        do {
            var req = URLRequest(url: URL(string: DiscordConfig.refreshURL)!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["refresh_token": rt])
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let tokens = try JSONDecoder().decode(DiscordTokenResponse.self, from: data)
            storeTokens(tokens)
            return true
        } catch {
            errorMessage = "Session expired — please reconnect Discord."
            disconnect()
            return false
        }
    }

    // MARK: - User + membership

    func fetchCurrentUser() async {
        guard let token = accessToken, await refreshIfNeeded() else { return }
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/users/@me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
        currentUser = try? JSONDecoder().decode(DiscordUser.self, from: data)
    }

    func checkMembership() async {
        guard let token = accessToken, await refreshIfNeeded() else { return }
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/users/@me/guilds")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
        struct PartialGuild: Decodable { let id: String }
        guard let guilds = try? JSONDecoder().decode([PartialGuild].self, from: data) else { return }
        isMember      = guilds.contains { $0.id == DiscordConfig.guildId }
        memberChecked = true
    }

    // MARK: - Messages

    func loadInitialMessages() async {
        guard let token = accessToken, await refreshIfNeeded() else { return }
        isLoading = true
        defer { isLoading = false }

        var comps = URLComponents(string: "https://discord.com/api/v10/channels/\(DiscordConfig.channelId)/messages")!
        comps.queryItems = [.init(name: "limit", value: "50")]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Discord] loadInitialMessages failed \(status): \(body)")
            errorMessage = "Failed to load messages (\(status))"
            return
        }
        guard let fetched = try? JSONDecoder().decode([DiscordMessage].self, from: data) else {
            print("[Discord] loadInitialMessages decode failed — raw: \(String(data: data, encoding: .utf8) ?? "")")
            return
        }

        let valid = fetched.filter { $0.isUserMessage }.reversed() as [DiscordMessage]
        messages      = valid
        newestId      = valid.last?.id
        oldestId      = valid.first?.id
        hasMoreHistory = fetched.count == 50
    }

    func loadOlderMessages() async {
        guard let token = accessToken, let oldest = oldestId, hasMoreHistory,
              await refreshIfNeeded() else { return }

        var comps = URLComponents(string: "https://discord.com/api/v10/channels/\(DiscordConfig.channelId)/messages")!
        comps.queryItems = [
            .init(name: "before", value: oldest),
            .init(name: "limit",  value: "50"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let fetched = try? JSONDecoder().decode([DiscordMessage].self, from: data)
        else { return }

        let valid = fetched.filter { $0.isUserMessage }.reversed() as [DiscordMessage]
        messages.insert(contentsOf: valid, at: 0)
        oldestId       = valid.first?.id
        hasMoreHistory = fetched.count == 50
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { break }
                await self?.pollNewMessages()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollNewMessages() async {
        guard let token = accessToken, let newest = newestId else { return }
        guard await refreshIfNeeded() else { return }

        var comps = URLComponents(string: "https://discord.com/api/v10/channels/\(DiscordConfig.channelId)/messages")!
        comps.queryItems = [
            .init(name: "after", value: newest),
            .init(name: "limit", value: "50"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let fetched = try? JSONDecoder().decode([DiscordMessage].self, from: data)
        else { return }

        let newMsgs = fetched.filter { $0.isUserMessage }.sorted { $0.id < $1.id }
        if !newMsgs.isEmpty {
            messages.append(contentsOf: newMsgs)
            newestId = newMsgs.last?.id
        }
    }

    // MARK: - Send

    @discardableResult
    func send(_ content: String, replyTo replyId: String? = nil) async -> Bool {
        guard let token = accessToken, await refreshIfNeeded() else { return false }

        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(DiscordConfig.channelId)/messages")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["content": content]
        if let replyId { payload["message_reference"] = ["message_id": replyId] }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        req.httpBody = body

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let msg = try? JSONDecoder().decode(DiscordMessage.self, from: data),
              msg.isUserMessage
        else { return false }

        messages.append(msg)
        newestId = msg.id
        return true
    }

    // MARK: - Reactions

    func addReaction(to messageId: String, emoji: String) async {
        guard let token = accessToken, await refreshIfNeeded() else { return }
        let enc = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? emoji
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(DiscordConfig.channelId)/messages/\(messageId)/reactions/\(enc)/@me")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
        applyLocalReaction(messageId: messageId, emoji: emoji, adding: true)
    }

    func removeReaction(from messageId: String, emoji: String) async {
        guard let token = accessToken, await refreshIfNeeded() else { return }
        let enc = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? emoji
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(DiscordConfig.channelId)/messages/\(messageId)/reactions/\(enc)/@me")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
        applyLocalReaction(messageId: messageId, emoji: emoji, adding: false)
    }

    private func applyLocalReaction(messageId: String, emoji: String, adding: Bool) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        var reactions = messages[idx].reactions ?? []
        if let ri = reactions.firstIndex(where: { $0.emoji.display == emoji }) {
            let r = reactions[ri]
            let newCount = r.count + (adding ? 1 : -1)
            if newCount <= 0 { reactions.remove(at: ri) }
            else { reactions[ri] = DiscordReaction(emoji: r.emoji, count: newCount, me: adding) }
        } else if adding {
            reactions.append(DiscordReaction(emoji: DiscordEmoji(id: nil, name: emoji), count: 1, me: true))
        }
        messages[idx].reactions = reactions
    }

    // MARK: - Read tracking

    func markRead() {
        guard let id = newestId ?? messages.last?.id else { return }
        UserDefaults.standard.set(id, forKey: "discord_last_seen_id")
    }

    // MARK: - Disconnect

    func disconnect() {
        stopPolling()
        accessToken    = nil
        refreshToken   = nil
        tokenExpiresAt = nil
        currentUser    = nil
        messages       = []
        isAuthorized   = false
        isMember       = false
        memberChecked  = false
        newestId       = nil
        oldestId       = nil
        errorMessage   = nil
        UserDefaults.standard.removeObject(forKey: "discord_token_expires")
    }

    // MARK: - PKCE

    private func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeChallenge(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationSession presentation context

extension DiscordService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            fatalError("No UIWindowScene available — app is not in a valid state for authentication")
        }
        return scene.windows.first(where: { $0.isKeyWindow })
            ?? scene.windows.first
            ?? UIWindow(windowScene: scene)
    }
}
