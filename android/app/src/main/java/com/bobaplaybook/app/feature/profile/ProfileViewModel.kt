package com.bobaplaybook.app.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.core.network.ProfileService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
