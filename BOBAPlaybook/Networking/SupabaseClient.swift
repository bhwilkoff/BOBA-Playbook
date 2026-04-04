import Foundation
import Security

// MARK: - Supabase REST client
// All auth + data calls go through this singleton.
// No third-party packages — pure URLSession + Keychain.

final class SupabaseClient {

    static let shared = SupabaseClient()
    private init() { loadSession() }

    // MARK: Session state
    private(set) var session: SupabaseSession?

    var isAuthenticated: Bool { session != nil }
    var accessToken: String? { session?.accessToken }
    var userId: UUID? { session?.userId }

    // MARK: - Auth endpoints

    func signUp(email: String, password: String) async throws -> SignUpResult {
        let body = ["email": email, "password": password]
        let flexible: FlexibleSignUpResponse = try await postAuth(path: "/auth/v1/signup", body: body)
        // Shape A: immediate session (email confirmation disabled)
        if let accessToken = flexible.accessToken,
           let refreshToken = flexible.refreshToken,
           let expiresIn = flexible.expiresIn,
           let user = flexible.user {
            let s = SupabaseSession(
                accessToken: accessToken, refreshToken: refreshToken,
                userId: user.id, email: user.email,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            )
            storeSession(s)
            return .session(s)
        }
        // Shape B: user object at root — email confirmation required
        if flexible.id != nil || flexible.email != nil {
            return .confirmationRequired
        }
        throw APIError.invalidResponse
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let body = ["email": email, "password": password]
        let response: AuthResponse = try await postAuth(path: "/auth/v1/token?grant_type=password", body: body)
        let s = makeSession(from: response)
        storeSession(s)
        return s
    }

    /// Sign in with an Apple identity token (from ASAuthorizationAppleIDCredential).
    func signInWithApple(idToken: String) async throws -> SupabaseSession {
        let body: [String: String] = ["provider": "apple", "id_token": idToken]
        let response: AuthResponse = try await postAuth(path: "/auth/v1/token?grant_type=id_token", body: body)
        let s = makeSession(from: response)
        storeSession(s)
        return s
    }

    func signOut() async throws {
        guard session != nil else { return }
        try await voidPost(path: "/auth/v1/logout", authenticated: true)
        clearSession()
    }

    func signOutLocally() {
        clearSession()
    }

    func setSession(_ session: SupabaseSession) {
        storeSession(session)
    }

    // MARK: - user_cards CRUD

    func fetchUserCards() async throws -> [UserCard] {
        let url = try makeURL(path: "/rest/v1/user_cards?select=*&order=acquired_at.desc")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        return try await executeArray(request)
    }

    func addUserCard(_ card: NewUserCard) async throws -> UserCard {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/user_cards")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        // Inject user_id — required by Supabase RLS INSERT policy
        var dict = (try JSONSerialization.jsonObject(with: JSONEncoder().encode(card))) as! [String: Any]
        dict["user_id"] = uid.uuidString.lowercased()
        request.httpBody = try JSONSerialization.data(withJSONObject: dict)
        let results: [UserCard] = try await executeArray(request)
        guard let first = results.first else { throw APIError.invalidResponse }
        return first
    }

    func updateUserCard(id: UUID, fields: UpdateUserCard) async throws -> UserCard {
        let url = try makeURL(path: "/rest/v1/user_cards?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(fields)
        let results: [UserCard] = try await executeArray(request)
        guard let first = results.first else { throw APIError.invalidResponse }
        return first
    }

    func deleteUserCard(id: UUID) async throws {
        let url = try makeURL(path: "/rest/v1/user_cards?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(&request, authenticated: true)
        try await voidExecute(request)
    }

    // MARK: - HTTP helpers

    private func postAuth<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: false)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode(Response.self, from: data)
    }

    private func voidPost(path: String, authenticated: Bool) async throws {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: authenticated)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    private func executeArray<T: Decodable>(_ request: URLRequest) async throws -> [T] {
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([T].self, from: data)
    }

    private func voidExecute(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    private func checkStatus(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SupabaseErrorBody.self, from: data))?.message
                ?? "HTTP \(http.statusCode)"
            throw APIError.serverError(http.statusCode, message)
        }
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: SupabaseConfig.projectURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func addHeaders(_ request: inout URLRequest, authenticated: Bool) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Session helpers

    private func makeSession(from response: AuthResponse) -> SupabaseSession {
        SupabaseSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.user.id,
            email: response.user.email,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }
}

// MARK: - Keychain session persistence

extension SupabaseClient {
    private static let keychainKey = "com.bhwilkoff.BOBAPlaybook.session"

    private func storeSession(_ session: SupabaseSession) {
        self.session = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    Self.keychainKey,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadSession() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainKey,
            kSecReturnData as String:  true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = try? JSONDecoder().decode(SupabaseSession.self, from: data) else { return }
        session = s
    }

    private func clearSession() {
        session = nil
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Types

enum SignUpResult {
    case session(SupabaseSession)   // Confirmation disabled — signed in immediately
    case confirmationRequired       // Confirmation email sent, session pending
}

// Flexible decoder for /auth/v1/signup — two possible response shapes:
//
// Shape A (email confirmation disabled):
//   { "access_token": "...", "refresh_token": "...", "expires_in": 3600, "user": { "id": "...", "email": "..." } }
//
// Shape B (email confirmation enabled):
//   { "id": "...", "email": "...", "confirmation_sent_at": "..." }  ← user IS the root object, no session keys
//
private struct FlexibleSignUpResponse: Decodable {
    // Shape A fields
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseUser?
    // Shape B fields (user object at root)
    let id: UUID?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case user
        case id
        case email
    }
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: UUID
    let email: String?
    let expiresAt: Date
}

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case user
    }
}

struct SupabaseUser: Decodable {
    let id: UUID
    let email: String?
}

struct SupabaseErrorBody: Decodable {
    let message: String
}

struct UpdateUserCard: Encodable {
    var designation: UserCard.Designation?
    var condition: String?
    var grade: String?
    var gradingCompany: String?
    var purchasePrice: Decimal?
    var askingPrice: Decimal?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case designation
        case condition
        case grade
        case gradingCompany = "grading_company"
        case purchasePrice  = "purchase_price"
        case askingPrice    = "asking_price"
        case notes
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid URL"
        case .invalidResponse:          return "Invalid server response"
        case .serverError(_, let msg):  return msg
        }
    }
}
