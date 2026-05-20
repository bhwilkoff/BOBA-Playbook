package com.bobaplaybook.app.auth

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

/**
 * Compose-friendly adapter that exposes [AuthManager.authState] as a
 * Hilt-injected ViewModel. Used by composables that need to render
 * branch-on-auth content (Profile avatar in Find's TopAppBar, etc.)
 * without threading AuthManager through props.
 */
@HiltViewModel
class AuthViewModel @Inject constructor(
    authManager: AuthManager,
) : ViewModel() {
    val authState: StateFlow<AuthState> = authManager.authState
}
