package com.bobaplaybook.app.auth

import android.content.Context
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.bobaplaybook.app.BuildConfig
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.status.SessionStatus
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Auth Manager — Google + Email/password + Discord OAuth.
 *
 * Three sign-in paths:
 *  1. Google via Credential Manager (Sign in with Google bottom sheet)
 *  2. Email + password (sign up + sign in via supabase-kt)
 *  3. Discord OAuth via supabase-kt + Custom Tabs (DECISIONS.md #049 —
 *     auth-only Discord usage; no bot, no server-side API calls)
 *
 * Each path surfaces a typed [SignInResult] so the UI can show the
 * actual failure reason. The old runCatching wrapper silently
 * swallowed exceptions which made every failure look identical
 * ("nothing happens when I tap Sign in").
 */
@Singleton
class AuthManager @Inject constructor(
    val client: SupabaseClient,
) {

    companion object {
        private const val TAG = "AuthManager"
    }

    private val _authState = MutableStateFlow<AuthState>(AuthState.Unknown)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    suspend fun observeSession() {
        client.auth.sessionStatus.collect { status ->
            _authState.value = when (status) {
                is SessionStatus.Authenticated -> {
                    val user = status.session.user
                    val appMeta = user?.appMetadata
                    val userMeta = user?.userMetadata
                    val provider = appMeta?.get("provider")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                        ?: appMeta?.get("providers")?.let { providers ->
                            (providers as? kotlinx.serialization.json.JsonArray)?.firstOrNull()
                                ?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                        }
                    val providerAvatarUrl = userMeta?.get("avatar_url")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                        ?: userMeta?.get("picture")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                    val providerUserId = userMeta?.get("provider_id")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                        ?: userMeta?.get("sub")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                    AuthState.SignedIn(
                        userId = user?.id.orEmpty(),
                        email = user?.email,
                        provider = provider,
                        providerAvatarUrl = providerAvatarUrl,
                        providerUserId = providerUserId,
                    )
                }
                is SessionStatus.NotAuthenticated -> AuthState.SignedOut
                is SessionStatus.RefreshFailure   -> AuthState.SignedOut
                is SessionStatus.Initializing     -> AuthState.Unknown
            }
        }
    }

    /**
     * Sign in with Google via Credential Manager.
     *
     * Returns a typed [SignInResult] — UI uses this to render a Snackbar
     * with the actual failure cause instead of generic "couldn't sign in."
     */
    suspend fun signInWithGoogle(activityContext: Context): SignInResult {
        // 1. Build the Credential Manager request
        val credentialManager = CredentialManager.create(activityContext)
        val googleIdOption = GetGoogleIdOption.Builder()
            .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)
            .setAutoSelectEnabled(false)  // explicit user choice each time
            .build()
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()

        // 2. Get the ID token via Credential Manager
        val credential = try {
            credentialManager.getCredential(activityContext, request).credential
        } catch (e: NoCredentialException) {
            Log.w(TAG, "No Google credentials available — user may not have a Google account on this device, or the OAuth client SHA-1 isn't registered.", e)
            return SignInResult.NoCredentialAvailable
        } catch (e: GetCredentialCancellationException) {
            Log.i(TAG, "User cancelled Google sign-in")
            return SignInResult.Cancelled
        } catch (e: GetCredentialException) {
            Log.e(TAG, "Credential Manager error during Google sign-in: ${e.type} — ${e.message}", e)
            return SignInResult.CredentialError(e.message ?: e.type)
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error during Credential Manager request", e)
            return SignInResult.UnknownError(e.message ?: "Unknown error")
        }

        // 3. Verify credential type + extract token
        if (credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            Log.e(TAG, "Got credential of unexpected type: ${credential.type}")
            return SignInResult.UnknownError("Unexpected credential type: ${credential.type}")
        }
        val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)

        // 4. Hand the ID token to Supabase
        return try {
            client.auth.signInWith(IDToken) {
                idToken = googleIdTokenCredential.idToken
                provider = Google
            }
            SignInResult.Success
        } catch (e: Exception) {
            Log.e(TAG, "Supabase signInWith(IDToken) failed", e)
            SignInResult.SupabaseError(e.message ?: "Supabase rejected the token")
        }
    }

    /**
     * Email/password sign-up. Creates a new Supabase user.
     */
    suspend fun signUpWithEmail(emailAddr: String, passwordValue: String): SignInResult {
        return try {
            client.auth.signUpWith(Email) {
                email = emailAddr
                password = passwordValue
            }
            SignInResult.Success
        } catch (e: Exception) {
            Log.e(TAG, "Email sign-up failed for $emailAddr", e)
            SignInResult.SupabaseError(e.message ?: "Sign-up failed")
        }
    }

    /**
     * Email/password sign-in. Signs in to an existing Supabase user.
     */
    suspend fun signInWithEmail(emailAddr: String, passwordValue: String): SignInResult {
        return try {
            client.auth.signInWith(Email) {
                email = emailAddr
                password = passwordValue
            }
            SignInResult.Success
        } catch (e: Exception) {
            Log.e(TAG, "Email sign-in failed for $emailAddr", e)
            SignInResult.SupabaseError(e.message ?: "Sign-in failed")
        }
    }

    /**
     * Discord OAuth sign-in. Launches a Custom Tab to Discord's auth
     * page (via Supabase as the OAuth broker); Discord redirects back
     * to bobaplaybook://auth-callback, which MainActivity.onNewIntent
     * routes to SupabaseClient.handleDeeplinks(intent) to import the
     * session.
     *
     * Per DECISIONS.md #049 — auth-only Discord usage (no bot, no
     * server-side API calls); the OAuth handshake is the entire
     * surface area until BoBA Discord moderators grant bot permission.
     */
    suspend fun signInWithDiscord(): SignInResult {
        return try {
            client.auth.signInWith(io.github.jan.supabase.auth.providers.Discord)
            // signInWith returns synchronously once the Custom Tab launches;
            // session import happens later via handleDeeplinks(). The UI
            // observes authState to know when the import lands.
            SignInResult.Success
        } catch (e: Exception) {
            Log.e(TAG, "Discord OAuth launch failed", e)
            SignInResult.SupabaseError(e.message ?: "Discord OAuth failed")
        }
    }

    /**
     * Email password-reset request. Sends a magic-link email; the user
     * clicks the link to set a new password.
     */
    suspend fun sendPasswordReset(emailAddr: String): SignInResult {
        return try {
            client.auth.resetPasswordForEmail(emailAddr)
            SignInResult.Success
        } catch (e: Exception) {
            Log.e(TAG, "Password reset failed for $emailAddr", e)
            SignInResult.SupabaseError(e.message ?: "Reset request failed")
        }
    }

    suspend fun signOut() {
        client.auth.signOut()
    }
}

/** Auth state surface for the UI. */
sealed interface AuthState {
    data object Unknown   : AuthState
    data object SignedOut : AuthState
    data class  SignedIn(
        val userId: String,
        val email: String?,
        /** OAuth provider id from supabase auth metadata: "google" / "discord" / "apple" / "email". */
        val provider: String? = null,
        /** Provider-supplied avatar URL (Discord avatar / Google profile pic), when present. */
        val providerAvatarUrl: String? = null,
        /** Provider-specific external user id — Discord snowflake when provider==discord. */
        val providerUserId: String? = null,
    ) : AuthState
}

/**
 * Typed result of an auth attempt. UI matches on this to render
 * appropriate Snackbar / error UI instead of silently failing.
 */
sealed interface SignInResult {
    data object Success                       : SignInResult
    data object Cancelled                     : SignInResult
    data object NoCredentialAvailable         : SignInResult
    data class CredentialError(val msg: String) : SignInResult
    data class SupabaseError(val msg: String)   : SignInResult
    data class UnknownError(val msg: String)    : SignInResult

    val userMessage: String
        get() = when (this) {
            Success -> "Signed in"
            Cancelled -> "Sign-in cancelled"
            NoCredentialAvailable ->
                "No Google credential returned. Either (a) no Google account is on this device, or (b) the app's signing-key SHA-1 isn't registered with the Firebase / Google OAuth Android client for com.bobaplaybook.app. Add it in Firebase Console → Project settings → Android app → Add fingerprint."
            is CredentialError -> "Google sign-in error: $msg"
            is SupabaseError   -> "Server rejected sign-in: $msg"
            is UnknownError    -> "Sign-in failed: $msg"
        }
}
