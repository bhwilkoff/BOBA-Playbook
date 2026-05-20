package com.bobaplaybook.app.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.network.ProfileService
import com.bobaplaybook.core.network.UserProfile
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.launch

/**
 * Profile screen view-model — bridges UI events to [ProfileService].
 *
 * Username persistence is a two-step:
 *   1. Inline `checkUsername(...)` on every keystroke (debounce-friendly,
 *      the RPC is SECURITY DEFINER + STABLE so cheap to spam)
 *   2. On commit / blur: `setUsername(...)` does the atomic write
 *
 * Toggle persistence (public collection / match alerts) writes inline
 * on change; optimistic UI updates happen at the screen level.
 *
 * Account deletion routes through the boba-account-delete Worker.
 */
@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val service: ProfileService,
    private val authManager: AuthManager,
) : ViewModel() {

    /** Last status from check_username / set_username — drives the UX pill. */
    private val _usernameStatus = MutableStateFlow<String?>(null)
    val usernameStatus: StateFlow<String?> = _usernameStatus.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    /** Current user_profiles snapshot — avatar, prefs, requested role. */
    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    init {
        // Reactive sign-out / sign-in handling. When the auth state
        // drops to SignedOut (or sign-in switches to a different user
        // id), wipe the cached profile so the next refreshProfile
        // pulls the new row instead of leaking the old user's avatar
        // / username / role into the new session.
        viewModelScope.launch {
            var lastUserId: String? = null
            authManager.authState.collect { state ->
                val current = (state as? AuthState.SignedIn)?.userId
                if (current != lastUserId) {
                    _profile.value = null
                    _usernameStatus.value = null
                    lastUserId = current
                }
            }
        }
    }

    fun refreshProfile() {
        viewModelScope.launch {
            _profile.value = service.fetchUserProfile()
        }
    }

    fun checkUsername(candidate: String) {
        viewModelScope.launch {
            val status = service.checkUsername(candidate)
            _usernameStatus.value = status
        }
    }

    /** Commits the username; returns true on success ("available"). */
    fun setUsername(newUsername: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            _busy.value = true
            val status = service.setUsername(newUsername)
            _usernameStatus.value = status
            _busy.value = false
            onResult(status == "available")
        }
    }

    fun setPublicCollection(enabled: Boolean, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val ok = service.setPublicCollectionEnabled(enabled)
            onResult(ok)
        }
    }

    fun setMatchAlerts(enabled: Boolean, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val ok = service.setNotificationPrefs(notifications = enabled, matchAlerts = enabled)
            onResult(ok)
        }
    }

    fun captureDiscordIdentity(discordId: String, avatarUrl: String?) {
        viewModelScope.launch {
            service.setDiscordIdentity(discordId, avatarUrl)
        }
    }

    fun requestRole(role: String, reason: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val ok = service.requestRole(role, reason)
            onResult(ok)
        }
    }

    /**
     * Hard delete. Worker call destroys the auth user; FK CASCADE removes
     * user_cards / decks / shows / user_profiles. Caller should sign out
     * the local session afterwards so cached UI stops trying to read the
     * now-gone account.
     */
    fun uploadAvatar(bytes: ByteArray, mimeType: String, onResult: (String?) -> Unit) {
        viewModelScope.launch {
            _busy.value = true
            val url = service.uploadAvatar(bytes, mimeType)
            _busy.value = false
            // After a successful upload, refresh the profile so the
            // header reads the new avatar URL.
            if (url != null) _profile.value = service.fetchUserProfile()
            onResult(url)
        }
    }

    fun deleteAccount(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            _busy.value = true
            val ok = service.deleteAccount()
            if (ok) authManager.signOut()
            _busy.value = false
            onResult(ok)
        }
    }
}
