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

    /// Exchange a PKCE authorization code for a session. Used by OAuth flows (e.g. Discord).
    func exchangeOAuthCode(_ code: String, codeVerifier: String) async throws -> SupabaseSession {
        let body: [String: String] = ["auth_code": code, "code_verifier": codeVerifier]
        let response: AuthResponse = try await postAuth(path: "/auth/v1/token?grant_type=pkce", body: body)
        let s = makeSession(from: response)
        storeSession(s)
        return s
    }

    @discardableResult
    func refreshSession() async throws -> SupabaseSession {
        guard let rt = session?.refreshToken else {
            throw APIError.serverError(401, "No refresh token")
        }
        let body = ["refresh_token": rt]
        let response: AuthResponse = try await postAuth(
            path: "/auth/v1/token?grant_type=refresh_token", body: body)
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

    // MARK: - User profile / roles

    /// Fetches the current user's role from user_profiles. Returns "user" if no row exists yet.
    /// Uses executeArray so a stale/expired access token is automatically refreshed via the
    /// stored refresh token — prevents the role from silently dropping to "user" on cold launch.
    func fetchUserRole() async throws -> String {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/user_profiles?select=role&user_id=eq.\(uid.uuidString.lowercased())&limit=1")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        struct RoleRow: Decodable { let role: String }
        let rows: [RoleRow] = try await executeArray(request)
        return rows.first?.role ?? "user"
    }

    // MARK: - Mod promotion requests

    /// Returns true if the current user has an outstanding mod-access request.
    func hasPendingModRequest() async throws -> Bool {
        guard let uid = userId else { return false }
        let url = try makeURL(path: "/rest/v1/user_profiles?select=mod_request_at&user_id=eq.\(uid.uuidString.lowercased())&limit=1")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        struct Row: Decodable { let mod_request_at: String? }
        let rows: [Row] = try await executeArray(request)
        return rows.first?.mod_request_at != nil
    }

    /// Submits a mod-access request for the current user. Writes reason +
    /// timestamp to their own row (self-update, allowed by RLS).
    func submitModRequest(reason: String) async throws {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/user_profiles?user_id=eq.\(uid.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        let iso = ISO8601DateFormatter().string(from: Date())
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "mod_request_reason": reason,
            "mod_request_at": iso
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Admin-only: fetches all pending mod requests. Returns empty array for non-admins
    /// (RPC raises, which executeArray catches → empty result).
    struct PendingModRequest: Decodable, Identifiable {
        let user_id: UUID
        let email: String?
        let reason: String?
        let requested_at: String?
        var id: UUID { user_id }
    }
    func fetchPendingModRequests() async throws -> [PendingModRequest] {
        let url = try makeURL(path: "/rest/v1/rpc/get_pending_mod_requests")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "{}".data(using: .utf8)
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([PendingModRequest].self, from: data)
    }

    /// Admin-only: approve (promote to moderator) or deny (clear request) a pending mod request.
    func reviewModRequest(userId: UUID, approve: Bool) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/review_mod_request")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "target_user_id": userId.uuidString.lowercased(),
            "approve": approve
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    // MARK: - Admin methods

    /// Fetches full user stats via RPC. Admin-only (enforced server-side).
    /// Includes last sign-in, display name, collection count and estimated value.
    func fetchAllUserProfiles() async throws -> [AdminUserProfile] {
        let url = try makeURL(path: "/rest/v1/rpc/get_admin_user_stats")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "{}".data(using: .utf8)
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([AdminUserProfile].self, from: data)
    }

    /// Updates a user's role. Only succeeds for admin accounts (RLS enforced).
    func updateUserRole(userId: UUID, role: String) async throws {
        let url = try makeURL(path: "/rest/v1/user_profiles?user_id=eq.\(userId.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": role])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Fetches aggregate counts for the admin dashboard.
    func fetchAdminMetrics() async throws -> AdminMetrics {
        let totalUsers         = (try? await fetchTableCount(path: "/rest/v1/user_profiles?select=user_id")) ?? 0
        let pendingCorrections = (try? await fetchTableCount(path: "/rest/v1/card_corrections?status=eq.pending&select=id")) ?? 0
        let pendingImages      = (try? await fetchTableCount(path: "/rest/v1/card_image_overrides?status=eq.pending&select=id")) ?? 0
        return AdminMetrics(
            totalUsers: totalUsers,
            pendingCorrections: pendingCorrections,
            pendingImageOverrides: pendingImages
        )
    }

    private func fetchTableCount(path: String) async throws -> Int {
        let url = try makeURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.setValue("count=exact", forHTTPHeaderField: "Prefer")
        addHeaders(&req, authenticated: true)
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        // Content-Range: 0-9/42 or */42 → split on "/" → take last → parse as Int
        let countStr = http?.value(forHTTPHeaderField: "content-range")?
            .split(separator: "/").last.map(String.init) ?? "0"
        return Int(countStr) ?? 0
    }

    /// Submits a card correction. Only succeeds for moderator/admin accounts.
    /// Pass status "approved" for admin direct-saves; defaults to "pending" for mod review.
    /// card_hero/element/power/treatment are stored as context to uniquely identify the card
    /// in the apply_corrections.py pipeline (card_number alone is not always unique).
    func submitCardCorrection(
        cardNumber:   String,
        corrections:  [String: String],
        notes:        String?,
        status:       String = "pending",
        cardHero:     String,
        cardElement:  String,
        cardPower:    Int?,
        cardTreatment: String?,
        bobaId:       String? = nil
    ) async throws {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/card_corrections")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        var body: [String: Any] = [
            "card_number":    cardNumber,
            "corrections":    corrections,
            "notes":          notes as Any,
            "submitted_by":   uid.uuidString.lowercased(),
            "status":         status,
            "card_hero":      cardHero,
            "card_element":   cardElement,
        ]
        if let power = cardPower     { body["card_power"]     = power }
        if let treat = cardTreatment { body["card_treatment"]  = treat }
        if let id = bobaId           { body["boba_id"]         = id }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Route through voidExecute so an expired access token is
        // auto-refreshed and the POST retried. Direct URLSession calls
        // 401 silently and the mod's save looks broken.
        try await voidExecute(request)
    }

    // MARK: - Admin: corrections review

    struct PendingCorrection: Identifiable, Decodable {
        let id: String   // uuid
        let cardNumber: String
        let corrections: [String: String]
        let notes: String?
        let submittedBy: String
        let createdAt: Date
        let status: String

        enum CodingKeys: String, CodingKey {
            case id, corrections, notes, status
            case cardNumber  = "card_number"
            case submittedBy = "submitted_by"
            case createdAt   = "created_at"
        }
    }

    func fetchPendingCorrections() async throws -> [PendingCorrection] {
        let url = try makeURL(path: "/rest/v1/card_corrections?status=eq.pending&order=created_at.asc&select=id,card_number,corrections,notes,submitted_by,created_at,status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([PendingCorrection].self, from: data)
    }

    func fetchRecentCorrections(limit: Int = 10) async throws -> [PendingCorrection] {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let path = "/rest/v1/card_corrections?submitted_by=eq.\(uid.uuidString.lowercased())&order=created_at.desc&limit=\(limit)&select=id,card_number,corrections,notes,submitted_by,created_at,status"
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([PendingCorrection].self, from: data)
    }

    func approveCorrection(id: String) async throws {
        let url = try makeURL(path: "/rest/v1/card_corrections?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "approved"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    func rejectCorrection(id: String) async throws {
        let url = try makeURL(path: "/rest/v1/card_corrections?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "rejected"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Returns card numbers that have an active image removal override (pending or approved, not rejected).
    func fetchImageRemovals() async throws -> [String] {
        let url = try makeURL(path: "/rest/v1/card_image_overrides?action=eq.remove&status=neq.rejected&select=card_number")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        struct Row: Decodable {
            let cardNumber: String
            enum CodingKeys: String, CodingKey { case cardNumber = "card_number" }
        }
        return try makeDecoder().decode([Row].self, from: data).map(\.cardNumber)
    }

    /// Submits an image override (replace or remove). Only succeeds for moderator/admin accounts.
    /// Uses upsert on card_number so repeated submissions update the existing row, not add duplicates.
    /// Pass status="approved" for admin users so the removal is immediately active on all platforms.
    func submitImageOverride(cardNumber: String, action: String, storagePath: String?, status: String = "pending", bobaId: String? = nil) async throws {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/card_image_overrides")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        // resolution=merge-duplicates: ON CONFLICT (card_number) DO UPDATE
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = [
            "card_number":   cardNumber,
            "action":        action,
            "submitted_by":  uid.uuidString.lowercased(),
            "status":        status
        ]
        if let path = storagePath { body["storage_path"] = path }
        if let id = bobaId        { body["boba_id"]      = id }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Same as submitCardCorrection: go through voidExecute so a stale
        // access token refreshes + retries instead of failing silently.
        try await voidExecute(request)
    }

    // MARK: - Admin: image override management

    struct ImageOverride: Identifiable, Decodable {
        let id: String   // uuid
        let cardNumber: String
        let action: String
        let status: String
        let submittedBy: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, action, status
            case cardNumber  = "card_number"
            case submittedBy = "submitted_by"
            case createdAt   = "created_at"
        }
    }

    func fetchPendingImageOverrides() async throws -> [ImageOverride] {
        let url = try makeURL(path: "/rest/v1/card_image_overrides?status=eq.pending&order=created_at.asc&select=id,card_number,action,status,submitted_by,created_at")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([ImageOverride].self, from: data)
    }

    func approveImageOverride(id: String) async throws {
        let url = try makeURL(path: "/rest/v1/card_image_overrides?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "approved"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    func rejectImageOverride(id: String) async throws {
        let url = try makeURL(path: "/rest/v1/card_image_overrides?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "rejected"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
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
        let insertEncoder = JSONEncoder()
        insertEncoder.dateEncodingStrategy = .iso8601
        var dict = (try JSONSerialization.jsonObject(with: insertEncoder.encode(card))) as! [String: Any]
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
        let updateEncoder = JSONEncoder()
        updateEncoder.dateEncodingStrategy = .iso8601
        request.httpBody = try updateEncoder.encode(fields)
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

    // MARK: - Deck CRUD

    func fetchDecks() async throws -> [SavedDeck] {
        let url = try makeURL(path: "/rest/v1/decks?select=id,name,format,created_at&order=created_at.desc")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        return try await executeArray(request)
    }

    func saveDeck(_ store: DeckBuilderStore) async throws {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let existingId = store.currentDeckId {
            // Update existing deck name + format
            let url = try makeURL(path: "/rest/v1/decks?id=eq.\(existingId)")
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            addHeaders(&request, authenticated: true)
            let body = ["name": store.deckName, "format": store.format.supabaseValue]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            try await voidExecute(request)
            try await replaceDeckCards(deckId: existingId, store: store)
        } else {
            // Create new deck
            let url = try makeURL(path: "/rest/v1/decks")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            addHeaders(&request, authenticated: true)
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            let body: [String: Any] = [
                "user_id": uid.uuidString.lowercased(),
                "name": store.deckName,
                "format": store.format.supabaseValue
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            struct DeckRow: Decodable { let id: UUID }
            let rows: [DeckRow] = try await executeArray(request)
            guard let deckId = rows.first?.id else { throw APIError.invalidResponse }
            store.currentDeckId = deckId
            try await replaceDeckCards(deckId: deckId, store: store)
        }
    }

    func deleteDeck(deckId: UUID) async throws {
        // Delete deck_cards first (FK constraint)
        let cardsURL = try makeURL(path: "/rest/v1/deck_cards?deck_id=eq.\(deckId)")
        var cardsReq = URLRequest(url: cardsURL)
        cardsReq.httpMethod = "DELETE"
        addHeaders(&cardsReq, authenticated: true)
        try await voidExecute(cardsReq)

        // Delete the deck row
        let deckURL = try makeURL(path: "/rest/v1/decks?id=eq.\(deckId)")
        var deckReq = URLRequest(url: deckURL)
        deckReq.httpMethod = "DELETE"
        addHeaders(&deckReq, authenticated: true)
        try await voidExecute(deckReq)
    }

    func fetchDeckCards(deckId: UUID) async throws -> [(bobaId: String, cardType: String)] {
        let url = try makeURL(path: "/rest/v1/deck_cards?deck_id=eq.\(deckId)&select=boba_id,card_type&order=sort_order.asc")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        // Explicit CodingKeys: the project doesn't apply .convertFromSnakeCase
        // globally, so without these the decoder silently throws keyNotFound
        // and load-deck / resolve-saved-deck both fail before any state change
        // lands in the UI (the spinner just spins and nothing appears).
        struct Row: Decodable {
            let bobaId: String
            let cardType: String
            enum CodingKeys: String, CodingKey {
                case bobaId = "boba_id"
                case cardType = "card_type"
            }
        }
        let rows: [Row] = try await executeArray(request)
        return rows.map { (bobaId: $0.bobaId, cardType: $0.cardType) }
    }

    private func replaceDeckCards(deckId: UUID, store: DeckBuilderStore) async throws {
        // Delete existing cards
        let deleteURL = try makeURL(path: "/rest/v1/deck_cards?deck_id=eq.\(deckId)")
        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.httpMethod = "DELETE"
        addHeaders(&deleteRequest, authenticated: true)
        try await voidExecute(deleteRequest)

        // Build new rows
        var rows: [[String: Any]] = []
        func append(_ card: Card, role: String, index: Int) {
            rows.append([
                "deck_id": deckId.uuidString.lowercased(),
                "boba_id": card.id,
                "card_type": role,
                "sort_order": index
            ])
        }
        for (i, c) in store.heroes.enumerated()     { append(c, role: "hero", index: i) }
        for (i, c) in store.plays.enumerated()      { append(c, role: "play", index: i) }
        for (i, c) in store.bonusPlays.enumerated() { append(c, role: "bonus_play", index: i) }
        for (i, c) in store.hotDogs.enumerated()    { append(c, role: "hot_dog", index: i) }
        for (i, c) in store.sideboard.enumerated()  { append(c, role: "sideboard", index: i) }

        guard !rows.isEmpty else { return }
        let insertURL = try makeURL(path: "/rest/v1/deck_cards")
        var insertRequest = URLRequest(url: insertURL)
        insertRequest.httpMethod = "POST"
        addHeaders(&insertRequest, authenticated: true)
        insertRequest.httpBody = try JSONSerialization.data(withJSONObject: rows)
        try await voidExecute(insertRequest)
    }

    // MARK: - Shows (Streamer feature)
    //
    // A streamer assembles a "show" — an arbitrary list of cards curated
    // for a live broadcast. Cards in a show are distinct from cards in
    // the collection; they don't contribute to collection value.
    // Persisted in `shows` + `show_cards` (see supabase_schema.sql).

    func fetchShows() async throws -> [Show] {
        let url = try makeURL(path: "/rest/v1/shows?select=id,name,created_at,updated_at&order=updated_at.desc")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        return try await executeArray(request)
    }

    /// Creates an empty show and returns it. Caller typically follows
    /// with `addCardsToShow` for the initial card batch.
    func createShow(name: String) async throws -> Show {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/shows")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "user_id": uid.uuidString.lowercased(),
            "name":    name,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let rows: [Show] = try await executeArray(request)
        guard let show = rows.first else { throw APIError.invalidResponse }
        return show
    }

    /// Rename an existing show. Uses PATCH so other fields (created_at,
    /// etc.) stay untouched; the updated_at trigger bumps that column.
    func renameShow(id: UUID, name: String) async throws {
        let url = try makeURL(path: "/rest/v1/shows?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        let body = ["name": name]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await voidExecute(request)
    }

    func deleteShow(id: UUID) async throws {
        // show_cards cascade via FK; no need to delete them separately.
        let url = try makeURL(path: "/rest/v1/shows?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(&request, authenticated: true)
        try await voidExecute(request)
    }

    /// All cards in a given show, ordered by the streamer's sort_order.
    func fetchShowCards(showId: UUID) async throws -> [ShowCard] {
        let url = try makeURL(path:
            "/rest/v1/show_cards?show_id=eq.\(showId)&select=id,show_id,boba_id,sort_order,excluded_from_total,added_at&order=sort_order.asc")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        return try await executeArray(request)
    }

    /// Bulk-append cards to a show. Duplicate bobaIds are allowed (a
    /// streamer might want two copies of the same card in a show for
    /// different giveaway slots). sort_order starts from the current
    /// tail so the inserted batch lands in append-order.
    func addCardsToShow(showId: UUID, bobaIds: [String]) async throws {
        guard !bobaIds.isEmpty else { return }
        // Find the current max sort_order so appended rows land last.
        let maxURL = try makeURL(path:
            "/rest/v1/show_cards?show_id=eq.\(showId)&select=sort_order&order=sort_order.desc&limit=1")
        var maxReq = URLRequest(url: maxURL)
        maxReq.httpMethod = "GET"
        addHeaders(&maxReq, authenticated: true)
        struct SortRow: Decodable { let sortOrder: Int; enum CodingKeys: String, CodingKey { case sortOrder = "sort_order" } }
        let existing: [SortRow] = (try? await executeArray(maxReq)) ?? []
        let base = (existing.first?.sortOrder ?? -1) + 1

        var rows: [[String: Any]] = []
        for (i, bobaId) in bobaIds.enumerated() {
            rows.append([
                "show_id":    showId.uuidString.lowercased(),
                "boba_id":    bobaId,
                "sort_order": base + i,
            ])
        }
        let insertURL = try makeURL(path: "/rest/v1/show_cards")
        var insertReq = URLRequest(url: insertURL)
        insertReq.httpMethod = "POST"
        addHeaders(&insertReq, authenticated: true)
        insertReq.httpBody = try JSONSerialization.data(withJSONObject: rows)
        try await voidExecute(insertReq)
    }

    /// Flip the exclude-from-total flag for a single show_cards row.
    /// Used by the check-marks UI on the show detail view.
    func setShowCardExcluded(id: UUID, excluded: Bool) async throws {
        let url = try makeURL(path: "/rest/v1/show_cards?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        let body: [String: Any] = ["excluded_from_total": excluded]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await voidExecute(request)
    }

    func deleteShowCard(id: UUID) async throws {
        let url = try makeURL(path: "/rest/v1/show_cards?id=eq.\(id)")
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
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await refreshSession()
            var retried = request
            if let token = accessToken {
                retried.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data2, response2) = try await URLSession.shared.data(for: retried)
            try checkStatus(data: data2, response: response2)
            return try makeDecoder().decode([T].self, from: data2)
        }
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([T].self, from: data)
    }

    private func voidExecute(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await refreshSession()
            var retried = request
            if let token = accessToken {
                retried.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data2, response2) = try await URLSession.shared.data(for: retried)
            try checkStatus(data: data2, response: response2)
            return
        }
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
        // Supabase returns timestamps with fractional seconds (e.g. "2026-04-07T16:15:37.481611+00:00")
        // from database-generated columns. Swift's built-in .iso8601 strategy rejects fractional seconds,
        // so we use a custom decoder that tries fractional first, then falls back to whole seconds.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: str) { return date }
            if let date = ISO8601DateFormatter.withoutFractionalSeconds.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot parse date: \(str)")
        }
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
    var estimatedValue: Decimal?
    var lastPriceCheck: Date?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case designation
        case condition
        case grade
        case gradingCompany = "grading_company"
        case purchasePrice  = "purchase_price"
        case askingPrice    = "asking_price"
        case estimatedValue = "estimated_value"
        case lastPriceCheck = "last_price_check"
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

// MARK: - ISO8601DateFormatter helpers

private extension ISO8601DateFormatter {
    /// Handles Supabase database timestamps: "2026-04-07T16:15:37.481611+00:00"
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Handles app-written timestamps: "2026-04-07T16:15:37Z"
    static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
