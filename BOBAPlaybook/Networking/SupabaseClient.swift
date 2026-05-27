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

    /// Refresh the access token if it's missing OR within 60 seconds
    /// of expiring. Cheap guard for paths that hit Supabase Storage /
    /// other non-PostgREST surfaces directly (Storage doesn't go through
    /// voidExecute's 401-retry pattern). Returns the current access token.
    @discardableResult
    func refreshIfNeeded() async throws -> String {
        let now = Date()
        let skew: TimeInterval = 60   // refresh if within a minute of expiry
        if let s = session, s.expiresAt.timeIntervalSince(now) <= skew {
            try await refreshSession()
        }
        guard let t = accessToken else {
            throw APIError.serverError(401, "No access token after refreshIfNeeded")
        }
        return t
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

    // MARK: - Auth user (provider + OAuth metadata)

    /// Fetches the Supabase auth user record for the current session,
    /// surfacing the OAuth provider used to sign in plus any
    /// provider-supplied metadata (Discord avatar, username, etc.).
    /// Used by AuthManager to (a) auto-persist Discord identity on
    /// Discord OAuth sign-in and (b) render the sign-in method pill
    /// on the Profile header.
    struct AuthUser: Decodable {
        struct AppMetadata: Decodable {
            let provider:  String?
            let providers: [String]?
        }
        struct UserMetadata: Decodable {
            // Discord-supplied (also Apple/email-supplied — keys vary).
            let avatar_url:  String?
            let full_name:   String?
            let user_name:   String?
            let name:        String?
            let provider_id: String?
            let sub:         String?  // Discord user ID under PKCE
        }
        let id:            String
        let email:         String?
        let app_metadata:  AppMetadata?
        let user_metadata: UserMetadata?
    }

    func fetchAuthUser() async throws -> AuthUser? {
        guard accessToken != nil else { return nil }
        let url = try makeURL(path: "/auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    // MARK: - Full profile (username, sharing, notifications, Discord)

    /// One-shot fetch of every user_profiles field that drives the
    /// Profile sheet — username, public sharing toggle, notification
    /// prefs, persisted Discord identity, and any pending role
    /// request. Returns nil if no profile row exists yet (the
    /// handle_new_user trigger should always create one, but the
    /// nil-safe path matters during the first session after sign-up
    /// when the trigger and our fetch race).
    struct UserProfileRow: Decodable {
        let username:                  String?
        let public_collection_enabled: Bool
        let notifications_enabled:     Bool
        let match_alerts_enabled:      Bool
        let discord_user_id:           String?
        let discord_avatar_url:        String?
        let avatar_url:                String?
        let requested_role:            String?
        let requested_role_at:         String?
    }
    func fetchProfile() async throws -> UserProfileRow? {
        guard let uid = userId else { return nil }
        let select = "username,public_collection_enabled,notifications_enabled," +
                     "match_alerts_enabled,discord_user_id,discord_avatar_url," +
                     "avatar_url,requested_role,requested_role_at"
        let url = try makeURL(path:
            "/rest/v1/user_profiles?select=\(select)&user_id=eq.\(uid.uuidString.lowercased())&limit=1")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let rows: [UserProfileRow] = try await executeArray(request)
        return rows.first
    }

    /// Calls the check_username RPC. Returns one of: "available",
    /// "taken", "invalid_chars", "reserved", "banned", "too_short",
    /// "too_long". Used by the inline username TextField for
    /// debounced validation. The RPC is SECURITY DEFINER + STABLE,
    /// safe to call on every keystroke.
    func checkUsername(_ candidate: String) async throws -> String {
        let url = try makeURL(path: "/rest/v1/rpc/check_username")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["candidate": candidate])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        // RPC returns a bare JSON string like "available"
        return (try? JSONDecoder().decode(String.self, from: data)) ?? "invalid_chars"
    }

    /// Atomic validate-and-write. Returns the same code set as
    /// checkUsername; only "available" means the write succeeded.
    func setUsername(_ newUsername: String) async throws -> String {
        let url = try makeURL(path: "/rest/v1/rpc/set_username")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["new_username": newUsername])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return (try? JSONDecoder().decode(String.self, from: data)) ?? "invalid_chars"
    }

    /// Toggles the public-collection-sharing flag. Web app's
    /// /u/{username} route reads the same column and refuses to
    /// render when false.
    func setPublicCollectionEnabled(_ enabled: Bool) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/set_public_collection_enabled")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Both notification toggles in one round-trip — the iOS surface
    /// always knows the full state, so two toggles == one RPC.
    func setNotificationPrefs(notifications: Bool, matchAlerts: Bool) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/set_notification_prefs")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "notifications": notifications,
            "match_alerts":  matchAlerts
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Persists Discord identity to user_profiles after the user
    /// connects via DiscordService. Pass nils to clear.
    func setDiscordIdentity(discordId: String?, avatarUrl: String?) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/set_discord_identity")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "discord_id": discordId as Any,
            "avatar_url": avatarUrl as Any
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Generalized role request — accepts 'moderator' or 'streamer'.
    /// SQL function `request_role` writes both the new
    /// `requested_role` column AND the legacy `mod_request_*` columns
    /// (compat shim) so older clients still surface pending status.
    func requestRole(_ role: String, reason: String) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/request_role")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "target_role": role,
            "reason":      reason
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Submit a community sold-comp (Tier 3, PRICING_PLAYBOOK.md §5). The SQL
    /// function `submit_community_comp` is SECURITY DEFINER and enforces the
    /// rate limits (5/user/day, 1/bobaId/user/week) + validation server-side,
    /// raising (→ non-2xx) on violation. `soldAt` is sent as a `yyyy-MM-dd`
    /// date string for the Postgres `date` column.
    func submitCommunityComp(bobaId: String, price: Decimal, soldAt: Date,
                             platform: String, notes: String?) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/submit_community_comp")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        var body: [String: Any] = [
            "p_boba_id":   bobaId,
            "p_price":     NSDecimalNumber(decimal: price),
            "p_sold_at":   fmt.string(from: soldAt),
            "p_platform":  platform,
            "p_photo_url": NSNull()
        ]
        body["p_notes"] = (notes?.isEmpty == false) ? notes! : NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Triggers Supabase's native password reset email. Recipient
    /// gets a deep link back into bobaplaybook:// with a recovery
    /// token; AuthManager.handleDeepLink already routes those.
    func requestPasswordReset(email: String) async throws {
        let url = try makeURL(path: "/auth/v1/recover")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: false)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Calls the boba-account-delete Worker to permanently delete the
    /// current user's auth row. Postgres FKs cascade through every
    /// user-data table (user_cards, decks, deck_cards, shows, show_cards,
    /// user_profiles). Mod-submitted records (card_corrections,
    /// card_image_overrides) preserve their content with NULL author.
    ///
    /// On success the caller MUST sign out locally — the JWT is
    /// already invalidated server-side, but the local session needs
    /// clearing so AuthManager doesn't try to use the stale token.
    func deleteAccount() async throws {
        // v2.279 — refreshIfNeeded() ensures the Bearer JWT we hand
        // the Worker isn't already expired (Workers verify via
        // Supabase /auth/v1/user; an expired JWT yields 401).
        let token = try await refreshIfNeeded()
        guard let url = URL(string: WorkerConfig.accountDeleteURL + "/account/delete") else {
            throw APIError.serverError(0, "Invalid Worker URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    // MARK: - Avatar upload

    struct AvatarUploadResponse: Decodable {
        let url:     String
        let version: Int64
    }

    /// Upload pre-cropped image data to the boba-avatar-upload Worker.
    /// Caller is responsible for cropping to a square + downscaling to
    /// ≤512px before passing the bytes (Worker rejects >2 MB).
    /// `mimeType` must be one of: image/jpeg, image/png, image/webp.
    /// Returns the public CDN URL + a version token for cache-busting.
    func uploadAvatar(data imageData: Data, mimeType: String) async throws -> AvatarUploadResponse {
        let token = try await refreshIfNeeded()
        guard let url = URL(string: WorkerConfig.avatarUploadURL + "/avatar") else {
            throw APIError.serverError(0, "Invalid Worker URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType,           forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try JSONDecoder().decode(AvatarUploadResponse.self, from: data)
    }

    /// Remove the current avatar from R2. Caller is responsible for
    /// also calling `setAvatarUrl(nil)` so the resolver falls back to
    /// the Discord avatar (or default silhouette).
    func deleteAvatar() async throws {
        let token = try await refreshIfNeeded()
        guard let url = URL(string: WorkerConfig.avatarUploadURL + "/avatar") else {
            throw APIError.serverError(0, "Invalid Worker URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    /// Persist the avatar URL on user_profiles via the set_avatar_url
    /// RPC. Pass nil to clear (resolver falls back to Discord/default).
    /// The RPC enforces that non-nil URLs match the BOBA R2 avatars
    /// prefix — defense against arbitrary-host avatar pointers.
    func setAvatarUrl(_ newUrl: String?) async throws {
        let url = try makeURL(path: "/rest/v1/rpc/set_avatar_url")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["new_url": newUrl as Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
    }

    // MARK: - Mod promotion requests

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

    /// Submits a NEW-CARD ADDITION via the same card_corrections table
    /// (kind='addition'). The `cardSpec` dict carries the FULL card
    /// record (every field from CLAUDE.md "One ID per Card" — see
    /// scripts/import_new_cards.py NewCardSpec for the shape).
    ///
    /// `imageStoragePath` is the Supabase Storage path returned by an
    /// upload to the `mod-card-images` bucket. May be nil if the
    /// moderator submitted the card without an image — the auto-
    /// pipeline (Stage A→B→C) will hunt for art separately.
    ///
    /// `bobaId` is the canonical 4-field ID computed client-side
    /// (cardNumber-hero-treatment-variation). The merge worker
    /// re-validates against the catalog before committing.
    func submitCardAddition(
        cardSpec:          [String: Any],
        bobaId:            String,
        notes:             String?,
        imageStoragePath:  String?,
        status:            String = "pending"
    ) async throws {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/card_corrections")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        let cardNumber = (cardSpec["cardNumber"] as? String) ?? ""
        let cardHero   = (cardSpec["hero"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                         ?? (cardSpec["name"] as? String) ?? ""
        let cardElement = (cardSpec["element"] as? String) ?? "NONE"
        var body: [String: Any] = [
            "kind":          "addition",
            "card_number":   cardNumber,
            "corrections":   cardSpec,      // full spec lives in the jsonb
            "notes":         notes as Any,
            "submitted_by":  uid.uuidString.lowercased(),
            "status":        status,
            "card_hero":     cardHero,
            "card_element":  cardElement,
            "boba_id":       bobaId,
        ]
        if let power = cardSpec["power"] as? Int    { body["card_power"]     = power }
        if let treat = cardSpec["treatment"] as? String, !treat.isEmpty {
            body["card_treatment"] = treat
        }
        if let path = imageStoragePath              { body["image_storage_path"] = path }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await voidExecute(request)
    }

    // MARK: - Custom Rainbows
    //
    // User-defined collecting goals — see Models/CustomRainbow.swift.
    // RLS policies (migration 2026_05_15_user_custom_rainbows.sql)
    // restrict each user to their own rows.

    /// Wire-shape of a user_custom_rainbows row. PostgREST sends
    /// snake_case columns; we map to the camel-case CustomRainbow
    /// struct via custom Codable.
    private struct CustomRainbowRow: Codable {
        let id: UUID
        let userId: UUID
        let name: String
        let criteria: RainbowCriteria
        let createdAt: Date
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, name, criteria
            case userId    = "user_id"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        var asModel: CustomRainbow {
            CustomRainbow(id: id, name: name, criteria: criteria,
                          createdAt: createdAt, updatedAt: updatedAt)
        }
    }

    func fetchCustomRainbows() async throws -> [CustomRainbow] {
        guard userId != nil else { return [] }
        let url = try makeURL(path: "/rest/v1/user_custom_rainbows?order=created_at.desc&select=id,user_id,name,criteria,created_at,updated_at")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        let rows = try makeDecoder().decode([CustomRainbowRow].self, from: data)
        return rows.map(\.asModel)
    }

    /// Returns the new rainbow's UUID so the client can drop it
    /// into the local store without re-fetching.
    @discardableResult
    func createCustomRainbow(name: String, criteria: RainbowCriteria) async throws -> CustomRainbow {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        let url = try makeURL(path: "/rest/v1/user_custom_rainbows?select=id,user_id,name,criteria,created_at,updated_at")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        // Prefer header asks PostgREST to return the inserted row(s).
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "user_id":  uid.uuidString.lowercased(),
            "name":     name,
            "criteria": criteriaJSON(criteria),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        let rows = try makeDecoder().decode([CustomRainbowRow].self, from: data)
        guard let row = rows.first else {
            throw APIError.serverError(0, "Create returned no row")
        }
        return row.asModel
    }

    func updateCustomRainbow(id: UUID, name: String, criteria: RainbowCriteria) async throws {
        let url = try makeURL(path: "/rest/v1/user_custom_rainbows?id=eq.\(id.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        let body: [String: Any] = [
            "name":     name,
            "criteria": criteriaJSON(criteria),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await voidExecute(request)
    }

    func deleteCustomRainbow(id: UUID) async throws {
        let url = try makeURL(path: "/rest/v1/user_custom_rainbows?id=eq.\(id.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(&request, authenticated: true)
        try await voidExecute(request)
    }

    /// Convert a RainbowCriteria to a JSON-serializable dict for
    /// PostgREST. The criteria column is jsonb so we just nest the
    /// dict directly inside the request body.
    private func criteriaJSON(_ c: RainbowCriteria) -> [String: Any] {
        [
            "heroes":          c.heroes,
            "sets":            c.sets,
            "subSets":         c.subSets,
            "elements":        c.elements,
            "treatments":      c.treatments,
            "cardTypes":       c.cardTypes,
            "releases":        c.releases,
            "inspiredInkOnly": c.inspiredInkOnly,
        ]
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
    /// Returns the upserted row's id so callers can chain to applyImageOverride().
    @discardableResult
    func submitImageOverride(cardNumber: String, action: String, storagePath: String?, status: String = "pending", bobaId: String? = nil) async throws -> String? {
        guard let uid = userId else { throw APIError.serverError(401, "Not authenticated") }
        // v2.277 — `?on_conflict=card_number` tells PostgREST exactly
        // which UNIQUE constraint to use for ON CONFLICT. Without it,
        // PostgREST can't infer the target on tables with multiple
        // unique constraints (pkey + card_number_key here) and falls
        // back to plain INSERT, which fails when a row for this
        // card_number already exists — exactly the duplicate-key
        // violation the beta tester + admin both hit on retry.
        let url = try makeURL(path: "/rest/v1/card_image_overrides?on_conflict=card_number")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(&request, authenticated: true)
        // ON CONFLICT (card_number) DO UPDATE + return the row so we can
        // chain a merge call without a second round-trip.
        request.setValue("resolution=merge-duplicates,return=representation",
                          forHTTPHeaderField: "Prefer")
        var body: [String: Any] = [
            "card_number":   cardNumber,
            "action":        action,
            "submitted_by":  uid.uuidString.lowercased(),
            "status":        status
        ]
        if let path = storagePath { body["storage_path"] = path }
        if let id = bobaId        { body["boba_id"]      = id }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        struct UpsertedRow: Decodable { let id: String }
        let rows = (try? makeDecoder().decode([UpsertedRow].self, from: data)) ?? []
        return rows.first?.id
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

    // MARK: - Mod merge (boba-mod-merge worker)

    /// Trigger the boba-mod-merge Cloudflare Worker to apply an approved
    /// image override IMMEDIATELY: downloads the JPEG from Supabase
    /// Storage, writes to R2 (full/ + thumbs/), purges CF cache, marks
    /// the override row status='applied' with applied_image_file set.
    /// iOS reads applied overrides on sign-in into a runtime map so the
    /// new image appears in the app without waiting for the daily merge
    /// cron + git deploy.
    /// Only admins succeed (Worker checks role); other callers get 403.
    @discardableResult
    func applyImageOverride(id: String) async throws -> AppliedImageOverride {
        let token = try await refreshIfNeeded()
        guard let url = URL(string: WorkerConfig.modMergeURL + "/merge") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["overrideId": id])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let trimmed = body.prefix(240)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.serverError(code, "Merge worker failed (HTTP \(code)) — \(trimmed.isEmpty ? "no body" : String(trimmed))")
        }
        return try makeDecoder().decode(AppliedImageOverride.self, from: data)
    }

    struct AppliedImageOverride: Decodable {
        let ok: Bool
        let imageFile: String?
        let urls: [String]?
    }

    /// Applied-override rows used by the runtime image-override map.
    /// CardStore loads these on sign-in via fetchAppliedImageOverrides
    /// and resolves card_number / boba_id → applied_image_file at
    /// render time, replacing cards.json's imageFile when present.
    struct AppliedOverride: Decodable {
        let cardNumber: String
        let bobaId: String?
        let appliedImageFile: String

        enum CodingKeys: String, CodingKey {
            case cardNumber       = "card_number"
            case bobaId           = "boba_id"
            case appliedImageFile = "applied_image_file"
        }
    }

    func fetchAppliedImageOverrides() async throws -> [AppliedOverride] {
        let url = try makeURL(path: "/rest/v1/card_image_overrides?status=eq.applied&applied_image_file=not.is.null&select=card_number,boba_id,applied_image_file")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try makeDecoder().decode([AppliedOverride].self, from: data)
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

    /// Returns every deck (id + name + format) that contains a card with
    /// the given `bobaId`. Postgrest's resource embedding joins the
    /// `decks` table through the `deck_cards` foreign key, so this is
    /// one round trip rather than the old fetch-all + per-deck walk.
    func decksContaining(bobaId: String) async throws -> [SavedDeck] {
        // deck_cards?boba_id=eq.{id}&select=decks(id,name,format,created_at)
        // Postgrest returns `{ decks: {...} }` rows; we flatten to [SavedDeck].
        let encoded = bobaId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bobaId
        let url = try makeURL(path: "/rest/v1/deck_cards?boba_id=eq.\(encoded)&select=decks(id,name,format,created_at)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request, authenticated: true)
        struct Wrapper: Decodable { let decks: SavedDeck? }
        let wrapped: [Wrapper] = try await executeArray(request)
        // Dedupe — the same deck can have the same bobaId in multiple
        // roles (e.g. a Play in both Playbook and Sideboard rows).
        var seen = Set<UUID>()
        var out: [SavedDeck] = []
        for w in wrapped {
            if let d = w.decks, !seen.contains(d.id) {
                seen.insert(d.id)
                out.append(d)
            }
        }
        return out
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

    /// Append cards to an existing deck without rewriting the rest of
    /// the deck — used by the scanner-from-deck-builder flow where
    /// scanned cards should join saved decks the user multi-selects in
    /// the queue. Computes the next sort_order from the current
    /// deck_cards count so newly appended rows land at the bottom.
    /// Role per card is inferred from cardType: Hero/Play/HotDog with
    /// `bonus_play` carved out from Play when isBonusPlay is set.
    func appendCardsToDeck(deckId: UUID, cards: [Card]) async throws {
        guard !cards.isEmpty else { return }
        let existing = try await fetchDeckCards(deckId: deckId)
        let baseOrder = existing.count
        var rows: [[String: Any]] = []
        for (i, card) in cards.enumerated() {
            let role: String
            switch card.cardType {
            case "Hero":  role = "hero"
            case "HotDog": role = "hot_dog"
            case "Play":  role = card.isBonusPlay == true ? "bonus_play" : "play"
            default:      role = "play"   // safe default for sealed/unknown
            }
            rows.append([
                "deck_id": deckId.uuidString.lowercased(),
                "boba_id": card.id,
                "card_type": role,
                "sort_order": baseOrder + i
            ])
        }
        let url = try makeURL(path: "/rest/v1/deck_cards")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addHeaders(&req, authenticated: true)
        req.httpBody = try JSONSerialization.data(withJSONObject: rows)
        try await voidExecute(req)
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
            "/rest/v1/show_cards?show_id=eq.\(showId)&select=id,show_id,boba_id,sort_order,excluded_from_total,is_big_hit,added_at&order=sort_order.asc")
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

    /// Flip the big-hit flag on a single show_cards row. Used by the
    /// star/flame button in the show detail view; the wall composer
    /// reads the resulting flag to render a much larger tile for the
    /// flagged card.
    func setShowCardBigHit(id: UUID, isBigHit: Bool) async throws {
        let url = try makeURL(path: "/rest/v1/show_cards?id=eq.\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        addHeaders(&request, authenticated: true)
        let body: [String: Any] = ["is_big_hit": isBigHit]
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
