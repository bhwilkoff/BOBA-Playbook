package com.bobaplaybook.core.network

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Outcome of a Tier 3 community-comp submission, mapped from the
 * `submit_community_comp` RPC's success (uuid) / RAISE (rate-limit or
 * validation) so the UI can show specific copy. (PRICING_PLAYBOOK §5.)
 */
enum class CommunityCompResult { SUCCESS, RATE_LIMITED, ALREADY_THIS_WEEK, ERROR }

/**
 * Profile-side RPCs + Worker calls.
 *
 * Mirrors iOS SupabaseClient.swift lines 200-300 (set_username,
 * set_public_collection_enabled, set_notification_prefs, request_role)
 * + the iOS account-delete Worker call.
 *
 * Returns string status codes verbatim from the Supabase RPCs so the UI
 * can branch on "available" / "taken" / "banned" / etc.
 */
@Singleton
class ProfileService @Inject constructor(
    private val supabase: SupabaseClient,
    private val httpClient: HttpClient,
) {

    companion object { private const val TAG = "ProfileService" }

    /**
     * One-shot fetch of every user_profiles field that drives the
     * Profile sheet. Filters by the current user_id explicitly —
     * "RLS scopes to own-row" is NOT enough because the
     * "admins read all profiles" PERMISSIVE policy lets the admin
     * role read every row in the table. With no explicit filter and
     * `limit(1)`, an admin sees an arbitrary OTHER user's profile
     * (Ben hit this on 2026-05-25 — his admin account showed
     * `bsullivan322`'s username instead of his own `bhwilkoff`).
     *
     * Mirrors iOS SupabaseClient.swift fetchProfile() shape.
     */
    suspend fun fetchUserProfile(): UserProfile? =
        runCatching {
            val userId = supabase.auth.currentUserOrNull()?.id
                ?: return@runCatching null
            val rows = supabase.postgrest.from("user_profiles")
                .select(io.github.jan.supabase.postgrest.query.Columns.list(
                    "username", "public_collection_enabled", "notifications_enabled",
                    "match_alerts_enabled", "discord_user_id", "discord_avatar_url",
                    "avatar_url", "requested_role", "requested_role_at",
                    "role",
                )) {
                    filter { eq("user_id", userId) }
                    limit(1)
                }
                .decodeList<UserProfileRow>()
            rows.firstOrNull()?.toDomain()
        }.onFailure { Log.e(TAG, "fetchUserProfile failed", it) }
            .getOrNull()

    /** Returns "available", "taken", "invalid_chars", "reserved", "banned", "too_short", "too_long". */
    suspend fun checkUsername(candidate: String): String =
        runCatching {
            supabase.postgrest.rpc(
                "check_username",
                buildJsonObject { put("candidate", candidate) },
            ).data.trim('"')
        }.onFailure { Log.e(TAG, "check_username failed", it) }
            .getOrDefault("invalid_chars")

    /** Atomic validate-and-write. Returns same codes as [checkUsername]; "available" = success. */
    suspend fun setUsername(newUsername: String): String =
        runCatching {
            supabase.postgrest.rpc(
                "set_username",
                buildJsonObject { put("new_username", newUsername) },
            ).data.trim('"')
        }.onFailure { Log.e(TAG, "set_username failed", it) }
            .getOrDefault("invalid_chars")

    suspend fun setPublicCollectionEnabled(enabled: Boolean): Boolean =
        runCatching {
            supabase.postgrest.rpc(
                "set_public_collection_enabled",
                buildJsonObject { put("enabled", enabled) },
            )
            true
        }.onFailure { Log.e(TAG, "set_public_collection_enabled failed", it) }
            .getOrDefault(false)

    suspend fun setNotificationPrefs(notifications: Boolean, matchAlerts: Boolean): Boolean =
        runCatching {
            supabase.postgrest.rpc(
                "set_notification_prefs",
                buildJsonObject {
                    put("notifications", notifications)
                    put("match_alerts", matchAlerts)
                },
            )
            true
        }.onFailure { Log.e(TAG, "set_notification_prefs failed", it) }
            .getOrDefault(false)

    /**
     * Persist Discord identity to user_profiles after a successful
     * Discord OAuth flow. DECISIONS.md #049 — auth-only use; this
     * just stores the discord_user_id + avatar URL for future
     * trade-match deep-link construction.
     */
    suspend fun setDiscordIdentity(discordId: String?, avatarUrl: String?): Boolean =
        runCatching {
            supabase.postgrest.rpc(
                "set_discord_identity",
                buildJsonObject {
                    put("discord_id", discordId?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: kotlinx.serialization.json.JsonNull)
                    put("avatar_url", avatarUrl?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: kotlinx.serialization.json.JsonNull)
                },
            )
            true
        }.onFailure { Log.e(TAG, "set_discord_identity failed", it) }
            .getOrDefault(false)

    suspend fun requestRole(role: String, reason: String): Boolean =
        runCatching {
            supabase.postgrest.rpc(
                "request_role",
                buildJsonObject {
                    put("target_role", role)
                    put("reason", reason)
                },
            )
            true
        }.onFailure { Log.e(TAG, "request_role failed", it) }
            .getOrDefault(false)

    /**
     * Tier 3 community-comp submission (PRICING_PLAYBOOK §5). Calls the
     * `submit_community_comp` SECURITY DEFINER RPC, which enforces the
     * rate limits server-side (5/day, 1/card/week) and inserts a pending
     * row for moderator review. Mirrors iOS
     * SupabaseClient.submitCommunityComp + web API.submitCommunityComp.
     *
     * @param soldAtIso the sold date as "yyyy-MM-dd" (UTC).
     */
    suspend fun submitCommunityComp(
        bobaId: String,
        priceUsd: Double,
        soldAtIso: String,
        platform: String,
        notes: String?,
    ): CommunityCompResult =
        runCatching {
            supabase.postgrest.rpc(
                "submit_community_comp",
                buildJsonObject {
                    put("p_boba_id", bobaId)
                    put("p_price", priceUsd)
                    put("p_sold_at", soldAtIso)
                    put("p_platform", platform)
                    put("p_photo_url", kotlinx.serialization.json.JsonNull)
                    put("p_notes", notes?.takeIf { it.isNotBlank() }
                        ?.let { kotlinx.serialization.json.JsonPrimitive(it) }
                        ?: kotlinx.serialization.json.JsonNull)
                },
            )
            CommunityCompResult.SUCCESS
        }.getOrElse { e ->
            val msg = e.message?.lowercase().orEmpty()
            Log.e(TAG, "submit_community_comp failed: $msg", e)
            when {
                "this week" in msg || "already submitted" in msg -> CommunityCompResult.ALREADY_THIS_WEEK
                "limit" in msg || "5/day" in msg -> CommunityCompResult.RATE_LIMITED
                else -> CommunityCompResult.ERROR
            }
        }

    /**
     * Account deletion — POST to the boba-account-delete Worker with
     * a Bearer JWT. Worker verifies vs Supabase /auth/v1/user then
     * forwards to the admin /auth/v1/admin/users/{id} endpoint with
     * the service-role key. Returns true on 200 OK.
     *
     * The Worker is the only path that can call admin auth (the
     * service-role key never reaches the client).
     */
    /**
     * Upload an avatar image (jpeg/png/webp) to the boba-avatar-upload
     * Worker. Worker writes R2 + returns `{url, version}`. We then call
     * `set_avatar_url` so the column points at the new R2 object.
     *
     * Caller is responsible for bounding bytes to ≤2 MB (Worker rejects
     * anything larger). Returns the public R2 URL on success, null on
     * failure.
     */
    suspend fun uploadAvatar(bytes: ByteArray, mimeType: String): String? {
        val accessToken = supabase.auth.currentSessionOrNull()?.accessToken
        if (accessToken.isNullOrEmpty()) return null
        if (bytes.size > 2 * 1024 * 1024) {
            Log.w(TAG, "uploadAvatar: payload ${bytes.size} bytes exceeds 2 MB cap")
            return null
        }
        return runCatching {
            val response = httpClient.post("${WorkerConfig.AVATAR_UPLOAD}/avatar") {
                headers { append(HttpHeaders.Authorization, "Bearer $accessToken") }
                contentType(ContentType.parse(mimeType))
                setBody(bytes)
            }
            if (response.status.value !in 200..299) {
                Log.e(TAG, "uploadAvatar failed: HTTP ${response.status.value}")
                return@runCatching null
            }
            val responseText = response.body<String>()
            val payload = Json.decodeFromString<AvatarUploadResponse>(responseText)
            // Persist to user_profiles via the SECURITY DEFINER RPC. The
            // RPC verifies the URL is an R2 avatars/ path before writing.
            supabase.postgrest.rpc(
                "set_avatar_url",
                kotlinx.serialization.json.buildJsonObject {
                    put("new_url", kotlinx.serialization.json.JsonPrimitive(payload.url))
                },
            )
            payload.url
        }.onFailure { e ->
            Log.e(TAG, "uploadAvatar failed", e)
        }.getOrNull()
    }

    @Serializable
    private data class AvatarUploadResponse(val url: String, val version: String? = null)

    @Serializable
    private data class UserProfileRow(
        val username: String? = null,
        @kotlinx.serialization.SerialName("public_collection_enabled") val publicCollectionEnabled: Boolean = false,
        @kotlinx.serialization.SerialName("notifications_enabled") val notificationsEnabled: Boolean = false,
        @kotlinx.serialization.SerialName("match_alerts_enabled") val matchAlertsEnabled: Boolean = false,
        @kotlinx.serialization.SerialName("discord_user_id") val discordUserId: String? = null,
        @kotlinx.serialization.SerialName("discord_avatar_url") val discordAvatarUrl: String? = null,
        @kotlinx.serialization.SerialName("avatar_url") val avatarUrl: String? = null,
        @kotlinx.serialization.SerialName("requested_role") val requestedRole: String? = null,
        @kotlinx.serialization.SerialName("requested_role_at") val requestedRoleAt: String? = null,
        val role: String? = null,
    ) {
        fun toDomain() = UserProfile(
            username = username,
            publicCollectionEnabled = publicCollectionEnabled,
            notificationsEnabled = notificationsEnabled,
            matchAlertsEnabled = matchAlertsEnabled,
            discordUserId = discordUserId,
            discordAvatarUrl = discordAvatarUrl,
            avatarUrl = avatarUrl,
            requestedRole = requestedRole,
            requestedRoleAt = requestedRoleAt,
            role = role,
        )
    }

    suspend fun deleteAccount(): Boolean {
        val accessToken = supabase.auth.currentSessionOrNull()?.accessToken
        if (accessToken.isNullOrEmpty()) {
            Log.w(TAG, "deleteAccount called without an access token")
            return false
        }
        return runCatching {
            val response = httpClient.post("${WorkerConfig.ACCOUNT_DELETE}/account/delete") {
                headers { append(HttpHeaders.Authorization, "Bearer $accessToken") }
            }
            response.status.value in 200..299
        }.onFailure { Log.e(TAG, "deleteAccount failed", it) }
            .getOrDefault(false)
    }
}

/** Domain shape of the user_profiles row — drives the Profile sheet. */
data class UserProfile(
    val username: String?,
    val publicCollectionEnabled: Boolean,
    val notificationsEnabled: Boolean,
    val matchAlertsEnabled: Boolean,
    val discordUserId: String?,
    val discordAvatarUrl: String?,
    val avatarUrl: String?,
    val requestedRole: String?,
    val requestedRoleAt: String?,
    /**
     * One of: "user" (default), "moderator", "streamer", "admin".
     * Drives the role badge + admin-only practice unlock per iOS
     * DECISIONS.md #033. RLS lets every user read their own row.
     */
    val role: String? = null,
) {
    val isAdmin: Boolean get() = role.equals("admin", ignoreCase = true)
    val isMod: Boolean get() = role.equals("moderator", ignoreCase = true) || isAdmin
    val isStreamer: Boolean get() = role.equals("streamer", ignoreCase = true) || isAdmin
}
