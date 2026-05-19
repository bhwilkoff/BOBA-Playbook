package com.bobaplaybook.app.auth

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.bobaplaybook.app.BuildConfig
import com.bobaplaybook.core.network.SupabaseConfig
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Auth Manager — M7.
 *
 * Owns the Supabase client + the Credential Manager flow for Sign in
 * with Google (ANDROID-DESIGN.md §6.5, DECISIONS.md #050).
 *
 * Flow on `signInWithGoogle(activityContext)`:
 *   1. Credential Manager bottom sheet appears (native one-tap UI)
 *   2. User selects an account; Google returns an ID token
 *   3. We hand the ID token to Supabase via `signInWith(IdToken)` —
 *      supabase-kt verifies the token signature against Google's JWKS
 *      and produces a Supabase session keyed by the user's Google sub
 *
 * Token storage uses supabase-kt's default SessionManager (DataStore-
 * backed since v3.0.x). Tink hardening per ANDROID-DEV.md §5.7 is a
 * post-M7 follow-up.
 *
 * Discord OAuth flow is wired separately (M7-followup) — same
 * supabase-kt client, different provider, launches via Auth Tab /
 * Custom Tabs instead of Credential Manager.
 */
@Singleton
class AuthManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    val client: SupabaseClient = createSupabaseClient(
        supabaseUrl = SupabaseConfig.URL,
        supabaseKey = SupabaseConfig.PUBLISHABLE_KEY,
    ) {
        install(Auth)
        install(Postgrest)
    }

    private val _authState = MutableStateFlow<AuthState>(AuthState.Unknown)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    /**
     * Mirror supabase-kt's session status into our own simpler model.
     * Caller observes [authState] in the UI layer.
     */
    suspend fun observeSession() {
        client.auth.sessionStatus.collect { status ->
            _authState.value = when (status) {
                is SessionStatus.Authenticated -> AuthState.SignedIn(
                    userId = status.session.user?.id.orEmpty(),
                    email = status.session.user?.email,
                )
                is SessionStatus.NotAuthenticated -> AuthState.SignedOut
                is SessionStatus.RefreshFailure   -> AuthState.SignedOut
                is SessionStatus.Initializing     -> AuthState.Unknown
            }
        }
    }

    /**
     * Launch the Google sign-in bottom sheet via Credential Manager,
     * then hand the resulting ID token to Supabase.
     *
     * Must be called with an Activity context (not an Application
     * context) because the bottom sheet is a system UI surface.
     */
    suspend fun signInWithGoogle(activityContext: Context): Result<Unit> = runCatching {
        val credentialManager = CredentialManager.create(activityContext)
        val googleIdOption = GetGoogleIdOption.Builder()
            .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)
            .build()
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()
        val response = credentialManager.getCredential(activityContext, request)
        val credential = response.credential
        if (credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
            client.auth.signInWith(IDToken) {
                idToken = googleIdTokenCredential.idToken
                provider = Google
            }
        }
    }

    suspend fun signOut() {
        client.auth.signOut()
    }
}

/** Lightweight auth state surface for the UI. */
sealed interface AuthState {
    data object Unknown   : AuthState
    data object SignedOut : AuthState
    data class  SignedIn(val userId: String, val email: String?) : AuthState
}
