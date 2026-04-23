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

    var isMod: Bool { role == "moderator" || role == "admin" }
    var isAdmin: Bool { role == "admin" }
    /// Streamers get the Shows feature (Collection > My Shows, card-detail
    /// "To Show" add option, Show Mode scanner). Admins are implicitly
    /// streamers so the admin account can exercise the flow end-to-end
    /// without promoting itself. Promotion UI (a request-role flow
    /// analogous to mod-access) is not built yet — admins can set this
    /// directly in user_profiles.role for now.
    var isStreamer: Bool { role == "streamer" || role == "admin" }
    var canRequestMod: Bool { isAuthenticated && !isMod && !hasPendingModRequest }

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
        // Refresh pending-request flag alongside role so the Profile UI
        // reflects current state after sign-in and after admin review.
        hasPendingModRequest = (try? await client.hasPendingModRequest()) ?? false
    }

    /// Submits a mod-access request with the given reason and refreshes pending state.
    func submitModRequest(reason: String) async {
        guard isAuthenticated else { return }
        do {
            try await client.submitModRequest(reason: reason)
            hasPendingModRequest = true
        } catch {
            self.error = error.localizedDescription
        }
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
        isAuthenticated = false
        userId = nil
        email = nil
        isLoading = false
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
