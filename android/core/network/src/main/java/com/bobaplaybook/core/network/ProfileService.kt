package com.bobaplaybook.core.network

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.ktor.client.HttpClient
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.http.HttpHeaders
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

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
     * Account deletion — POST to the boba-account-delete Worker with
     * a Bearer JWT. Worker verifies vs Supabase /auth/v1/user then
     * forwards to the admin /auth/v1/admin/users/{id} endpoint with
     * the service-role key. Returns true on 200 OK.
     *
     * The Worker is the only path that can call admin auth (the
     * service-role key never reaches the client).
     */
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
