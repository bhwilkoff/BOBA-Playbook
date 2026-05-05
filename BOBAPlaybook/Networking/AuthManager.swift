import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - AuthManager
// Manages auth state: Sign in with Apple, Discord OAuth, or email/password.
// Session is persisted in Keychain via SupabaseClient.
// Sign in with Apple is driven by SignInWithAppleButton in SignInView —
// the view extracts the idToken from the completion handler and calls signInWithApple(idToken:).
// Discord uses ASWebAuthenticationSession with PKCE flow.

@Observable
@MainActor
final class AuthManager {

    // MARK: Published state
    private(set) var isAuthenticated = false
    private(set) var userId: UUID?
    private(set) var email: String?
    private(set) var role: String = "user"
    private(set) var hasPendingModRequest = false
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var confirmationEmailSent = false

    // Profile-sheet fields, populated by loadProfile() after sign-in.
    /// The user's public handle. Nil until the user picks one
    /// (auto-derived on first profile open from email/Discord
    /// username; ProfileView writes the derived value back).
    private(set) var username: String?
    /// Toggles the public bobaplaybook.com/u/{username} surface.
    private(set) var publicCollectionEnabled = false
    /// Persisted Discord avatar URL — survives across sessions so
    /// the profile header doesn't have to re-call Discord on every
    /// open. Refreshed when the user (re)connects via DiscordService.
    private(set) var discordAvatarURL: String?
    private(set) var discordUserId:    String?
    /// Notification toggles. Backend dispatch is deferred (see
    /// DECISIONS.md) — these store user opt-in for when the
    /// match-alerts pipeline ships.
    private(set) var notificationsEnabled = true
    private(set) var matchAlertsEnabled   = false
    /// Pending role request — 'moderator' or 'streamer' or nil.
    /// Generalized from the original hasPendingModRequest so the
    /// UI can show "Streamer request pending" too.
    private(set) var pendingRoleRequest: String?
    /// Provider used to create the current session — "apple",
    /// "discord", or "email". Drives the sign-in method pill on
    /// the Profile header so the user can see which identity they
    /// signed in with (matters for "how do I disconnect Apple?"-
    /// style questions).
    private(set) var signInProvider: String?

    var isMod: Bool { role == "moderator" || role == "admin" }
    var isAdmin: Bool { role == "admin" }
    /// Streamers get the Shows feature (Collection > My Shows, card-detail
    /// "To Show" add option, Show Mode scanner). Admins are implicitly
    /// streamers so the admin account can exercise the flow end-to-end
    /// without promoting itself.
    var isStreamer: Bool { role == "streamer" || role == "admin" }
    var canRequestMod: Bool {
        isAuthenticated && !isMod && pendingRoleRequest != "moderator"
    }
    var canRequestStreamer: Bool {
        isAuthenticated && !isStreamer && pendingRoleRequest != "streamer"
    }

    private let client = SupabaseClient.shared

    // Holds active ASWebAuthenticationSession to prevent deallocation during OAuth flow
    private var _oauthSession: ASWebAuthenticationSession?

    init() {
        // Restore session from Keychain
        if let session = client.session {
            isAuthenticated = true
            userId = session.userId
            email = session.email
            Task { await fetchRole() }
        }
    }

    func fetchRole() async {
        guard isAuthenticated else { return }
        do {
            role = try await client.fetchUserRole()
        } catch {
            role = "user"
        }
        await loadProfile()
        await loadAuthMetadata()
    }

    /// Fetches the Supabase auth user record (provider + OAuth
    /// metadata) and surfaces the provider. Called after every
    /// sign-in so the Profile header's sign-in method pill is
    /// always accurate. Best-effort: failures fall back to nil
    /// rather than blocking the UI.
    func loadAuthMetadata() async {
        guard isAuthenticated else { return }
        guard let auth = try? await client.fetchAuthUser() else { return }
        signInProvider = auth.app_metadata?.provider
    }

    /// After a Discord OAuth sign-in, lift the avatar URL +
    /// Discord user ID out of the Supabase user_metadata and
    /// persist them to user_profiles via setDiscordIdentity. This
    /// way Discord-OAuth-signed-up users have their avatar AND
    /// trade-room handle populated without having to re-Connect
    /// through the Profile sheet.
    private func captureDiscordIdentityFromOAuth() async {
        guard isAuthenticated else { return }
        guard let auth = try? await client.fetchAuthUser() else { return }
        // Only fire when the most recent provider was Discord —
        // we don't want to overwrite a previously-set identity
        // with email-based metadata.
        guard auth.app_metadata?.provider == "discord" else { return }
        let meta = auth.user_metadata
        let discordId = meta?.provider_id ?? meta?.sub
        let avatarURL = meta?.avatar_url
        guard discordId != nil || avatarURL != nil else { return }
        await setDiscordIdentity(discordId: discordId, avatarUrl: avatarURL)
    }

    /// Hydrates every Profile-sheet field from user_profiles in one
    /// network round-trip. Called after sign-in and on every Profile
    /// open (so admin actions like role review surface immediately).
    func loadProfile() async {
        guard isAuthenticated else { return }
        guard let profile = try? await client.fetchProfile() else { return }
        username                = profile.username
        publicCollectionEnabled = profile.public_collection_enabled
        notificationsEnabled    = profile.notifications_enabled
        matchAlertsEnabled      = profile.match_alerts_enabled
        discordAvatarURL        = profile.discord_avatar_url
        discordUserId           = profile.discord_user_id
        pendingRoleRequest      = profile.requested_role
        // Keep the legacy hasPendingModRequest flag in sync so any
        // remaining call sites (AdminPanelView) keep working.
        hasPendingModRequest    = profile.requested_role == "moderator"
    }

    /// Persists a username via the validate-and-write RPC. Returns the
    /// status code ("available" on success; one of taken/banned/etc.
    /// on failure) so the UI can render a precise inline message.
    @discardableResult
    func setUsername(_ candidate: String) async -> String {
        guard isAuthenticated else { return "invalid_chars" }
        do {
            let result = try await client.setUsername(candidate)
            if result == "available" {
                username = candidate.lowercased()
            }
            return result
        } catch {
            self.error = error.localizedDescription
            return "invalid_chars"
        }
    }

    /// Debounced uniqueness/banned-words check used by the inline
    /// TextField. Cheaper than setUsername — read-only, no write.
    func checkUsername(_ candidate: String) async -> String {
        guard isAuthenticated else { return "invalid_chars" }
        return (try? await client.checkUsername(candidate)) ?? "invalid_chars"
    }

    /// Public-collection-sharing toggle. Persists to user_profiles
    /// AND mirrors locally so the SwiftUI binding doesn't snap back.
    func setPublicCollectionEnabled(_ enabled: Bool) async {
        guard isAuthenticated else { return }
        publicCollectionEnabled = enabled  // optimistic
        do {
            try await client.setPublicCollectionEnabled(enabled)
        } catch {
            publicCollectionEnabled = !enabled
            self.error = error.localizedDescription
        }
    }

    /// Both notification toggles in one call so the UI can flip
    /// either toggle without spawning two race-prone PATCHes.
    func setNotificationPrefs(notifications: Bool, matchAlerts: Bool) async {
        guard isAuthenticated else { return }
        let oldN = notificationsEnabled
        let oldM = matchAlertsEnabled
        notificationsEnabled = notifications
        matchAlertsEnabled   = matchAlerts
        do {
            try await client.setNotificationPrefs(
                notifications: notifications, matchAlerts: matchAlerts)
        } catch {
            notificationsEnabled = oldN
            matchAlertsEnabled   = oldM
            self.error = error.localizedDescription
        }
    }

    /// Persists Discord identity post-OAuth so the avatar survives
    /// across sessions without re-calling Discord on every Profile
    /// open. Pass nils to clear (used by Disconnect).
    func setDiscordIdentity(discordId: String?, avatarUrl: String?) async {
        guard isAuthenticated else { return }
        do {
            try await client.setDiscordIdentity(discordId: discordId, avatarUrl: avatarUrl)
            discordUserId    = discordId
            discordAvatarURL = avatarUrl
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Generalized role request — accepts 'moderator' or 'streamer'.
    /// Replaces submitModRequest. Old code paths still work because
    /// the SQL layer keeps a compat shim.
    func requestRole(_ targetRole: String, reason: String) async {
        guard isAuthenticated else { return }
        do {
            try await client.requestRole(targetRole, reason: reason)
            pendingRoleRequest = targetRole
            if targetRole == "moderator" { hasPendingModRequest = true }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Triggers Supabase's password-reset email flow. The recipient
    /// gets a deep link back into bobaplaybook:// — handleDeepLink
    /// already restores the session from those tokens.
    func requestPasswordReset() async -> Bool {
        guard let address = email else { return false }
        do {
            try await client.requestPasswordReset(email: address)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Permanently delete the current user's account via the
    /// boba-account-delete Worker. On success the local session is
    /// cleared so the next launch lands the user signed-out. On
    /// failure the user stays signed in and `self.error` carries the
    /// message — caller should surface it without dismissing the
    /// confirmation dialog.
    func deleteAccount() async -> Bool {
        do {
            try await client.deleteAccount()
            await signOut()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Submits a mod-access request with the given reason. Kept for
    /// existing call sites; new code should call requestRole.
    func submitModRequest(reason: String) async {
        await requestRole("moderator", reason: reason)
    }

    // MARK: - Sign up (email/password)

    func signUp(email: String, password: String) async {
        isLoading = true
        error = nil
        confirmationEmailSent = false
        do {
            switch try await client.signUp(email: email, password: password) {
            case .session(let session):
                isAuthenticated = true
                userId = session.userId
                self.email = session.email
            case .confirmationRequired:
                confirmationEmailSent = true
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in (email/password)

    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        do {
            let session = try await client.signIn(email: email, password: password)
            isAuthenticated = true
            userId = session.userId
            self.email = session.email
            await fetchRole()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in with Apple
    // Called from SignInView's SignInWithAppleButton onCompletion handler.

    func signInWithApple(idToken: String) async {
        isLoading = true
        error = nil
        do {
            let session = try await client.signInWithApple(idToken: idToken)
            isAuthenticated = true
            userId = session.userId
            self.email = session.email
            await fetchRole()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in with Discord (OAuth + PKCE via ASWebAuthenticationSession)

    func signInWithDiscord() async {
        isLoading = true
        error = nil
        do {
            let session = try await startOAuthFlow(provider: "discord")
            client.setSession(session)
            isAuthenticated = true
            userId = session.userId
            email  = session.email
            await fetchRole()
            // fetchRole already loads auth metadata; lift the Discord
            // avatar + ID into user_profiles so the avatar surface
            // doesn't need a separate DiscordService.authorize() round.
            await captureDiscordIdentityFromOAuth()
        } catch is CancellationError {
            // User dismissed the auth sheet — not an error
        } catch {
            self.error = error.localizedDescription
        }
        _oauthSession = nil
        isLoading = false
    }

    private func startOAuthFlow(provider: String) async throws -> SupabaseSession {
        let codeVerifier  = makeCodeVerifier()
        let codeChallenge = makeCodeChallenge(from: codeVerifier)
        let redirectURI   = "bobaplaybook://oauth"

        guard let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let authURL = URL(string:
                "\(SupabaseConfig.projectURL)/auth/v1/authorize" +
                "?provider=\(provider)" +
                "&redirect_to=\(encodedRedirect)" +
                "&code_challenge=\(codeChallenge)" +
                "&code_challenge_method=S256")
        else { throw APIError.invalidURL }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let ws = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "bobaplaybook") { url, err in
                if let nsErr = err as? ASWebAuthenticationSessionError,
                   nsErr.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: err ?? APIError.invalidResponse)
                }
            }
            ws.prefersEphemeralWebBrowserSession = false
            ws.presentationContextProvider = OAuthContextProvider.shared
            _oauthSession = ws
            ws.start()
        }

        // Implicit flow: tokens arrive in the URL fragment
        if let fragment = callbackURL.fragment {
            var comps = URLComponents()
            comps.query = fragment
            let p = queryDict(comps.queryItems ?? [])
            if let access = p["access_token"],
               let refresh = p["refresh_token"],
               let exp = p["expires_in"].flatMap(Int.init),
               let (uid, addr) = decodeJWTPayload(access) {
                return SupabaseSession(
                    accessToken: access, refreshToken: refresh,
                    userId: uid, email: addr,
                    expiresAt: Date().addingTimeInterval(TimeInterval(exp)))
            }
        }

        // PKCE flow: authorization code arrives as a query parameter
        let qp = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        guard let code = qp?.first(where: { $0.name == "code" })?.value
        else { throw APIError.invalidResponse }

        return try await client.exchangeOAuthCode(code, codeVerifier: codeVerifier)
    }

    // MARK: - PKCE helpers

    private func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeCodeChallenge(from verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func queryDict(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    // MARK: - Sign out

    func signOut() async {
        isLoading = true
        do {
            try await client.signOut()
        } catch {
            client.signOutLocally()
        }
        isAuthenticated         = false
        userId                  = nil
        email                   = nil
        role                    = "user"
        username                = nil
        publicCollectionEnabled = false
        notificationsEnabled    = true
        matchAlertsEnabled      = false
        discordAvatarURL        = nil
        discordUserId           = nil
        pendingRoleRequest      = nil
        hasPendingModRequest    = false
        signInProvider          = nil
        isLoading               = false
    }

    func clearError() { error = nil }

    // MARK: - Deep link handling
    // Handles bobaplaybook:// URLs from Supabase email confirmation and magic links.
    // Supabase redirects to: bobaplaybook://#access_token=...&refresh_token=...&type=signup

    func handleDeepLink(_ url: URL) {
        // Supabase puts tokens in the URL fragment, not the query string
        guard let fragment = url.fragment else { return }

        // Parse the fragment as if it were a query string
        var components = URLComponents()
        components.query = fragment
        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        guard let accessToken  = params["access_token"],
              let refreshToken = params["refresh_token"],
              let expiresIn    = params["expires_in"].flatMap(Int.init),
              let (userId, email) = decodeJWTPayload(accessToken)
        else { return }

        let session = SupabaseSession(
            accessToken:  accessToken,
            refreshToken: refreshToken,
            userId:       userId,
            email:        email,
            expiresAt:    Date().addingTimeInterval(TimeInterval(expiresIn))
        )
        client.setSession(session)
        isAuthenticated = true
        self.userId = userId
        self.email  = email
        confirmationEmailSent = false
    }

    // MARK: - JWT decode

    // Decode the JWT middle segment to extract sub (userId) and email without a network call
    private func decodeJWTPayload(_ jwt: String) -> (UUID, String?)? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        struct Payload: Decodable { let sub: String; let email: String? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let userId  = UUID(uuidString: payload.sub) else { return nil }
        return (userId, payload.email)
    }
}

// MARK: - OAuth presentation context

/// Provides the presentation anchor for ASWebAuthenticationSession OAuth flows.
private final class OAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = OAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // This is only called while the app is foregrounded — a scene always exists
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first!
        return scene.keyWindow ?? UIWindow(windowScene: scene)
    }
}
