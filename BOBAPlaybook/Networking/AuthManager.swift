import SwiftUI
import AuthenticationServices

// MARK: - AuthManager
// Manages auth state: Sign in with Apple + email/password.
// Session is persisted in Keychain via SupabaseClient.
// Sign in with Apple is driven by SignInWithAppleButton in SignInView —
// the view extracts the idToken from the completion handler and calls signInWithApple(idToken:).

@Observable
@MainActor
final class AuthManager {

    // MARK: Published state
    private(set) var isAuthenticated = false
    private(set) var userId: UUID?
    private(set) var email: String?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var confirmationEmailSent = false

    private let client = SupabaseClient.shared

    init() {
        // Restore session from Keychain
        if let session = client.session {
            isAuthenticated = true
            userId = session.userId
            email = session.email
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
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
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
