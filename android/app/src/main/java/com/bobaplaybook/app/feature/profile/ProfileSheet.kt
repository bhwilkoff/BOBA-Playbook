@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import kotlinx.coroutines.launch

/**
 * Profile sheet (ANDROID-DESIGN.md §6.5).
 *
 * Find-only entry point — top-leading icon in FindScreen's TopAppBar
 * opens this sheet. Other tabs never expose Profile (per
 * `feedback_profile_only_on_find`).
 *
 * M7 ships the sign-in flow + signed-in state. Username editing,
 * sharing toggle, role request, avatar upload, etc. are M7-polish
 * follow-ups (iOS ProfileView is ~600 lines; the framework is here,
 * sections plug in as they get ported).
 */
@Composable
fun ProfileSheet(
    authManager: AuthManager,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val authState by authManager.authState.collectAsStateWithLifecycle(initialValue = AuthState.Unknown)

    LaunchedEffect(Unit) { authManager.observeSession() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Profile", style = MaterialTheme.typography.headlineSmall)

            when (val s = authState) {
                AuthState.Unknown   -> Text("Loading…", style = MaterialTheme.typography.bodyMedium)
                AuthState.SignedOut -> {
                    Text(
                        text = "Sign in to sync your collection, decks, and wanted list across iOS, web, and Android.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(
                        onClick = {
                            scope.launch { authManager.signInWithGoogle(context) }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Sign in with Google")
                    }
                }
                is AuthState.SignedIn -> {
                    Text("Signed in", style = MaterialTheme.typography.titleMedium)
                    s.email?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    OutlinedButton(
                        onClick = {
                            scope.launch { authManager.signOut() }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Sign out")
                    }
                }
            }
        }
    }
}
