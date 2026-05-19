@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.profile

import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.theme.BobaBrand
import kotlinx.coroutines.launch

/**
 * Profile sheet (ANDROID-DESIGN.md §6.5).
 *
 * Find-only entry. Bottom-sheet expanded to large by default. v1
 * sections:
 *  - Header (avatar / username / sign-in method pill)
 *  - Identity (username edit, Discord link)
 *  - Sharing (public collection toggle)
 *  - Notifications (match alerts toggle — gated until APNs/FCM
 *    dispatcher lands per DECISIONS.md #039)
 *  - Role request (mod / streamer)
 *  - Legal (Terms / Privacy)
 *  - Sign out / delete account
 */
@Composable
fun ProfileSheet(
    authManager: AuthManager,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val authState by authManager.authState.collectAsStateWithLifecycle(initialValue = AuthState.Unknown)
    LaunchedEffect(Unit) { authManager.observeSession() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = modifier,
    ) {
        when (val s = authState) {
            AuthState.Unknown -> LoadingState()
            AuthState.SignedOut -> SignedOutContent(authManager)
            is AuthState.SignedIn -> SignedInContent(authManager, s, onDismiss)
        }
    }
}

@Composable
private fun LoadingState() {
    Box(
        modifier = Modifier.fillMaxWidth().padding(48.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text("Loading…", style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun SignedOutContent(authManager: AuthManager) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Profile", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "Sign in to sync your collection, decks, and wanted list across iOS, web, and Android.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = { scope.launch { authManager.signInWithGoogle(context) } },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Sign in with Google")
        }
        OutlinedButton(
            onClick = { launchDiscordOAuth(context) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Default.Group, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("Sign in with Discord")
        }
        Spacer(Modifier.height(16.dp))
        LegalLinks(context)
    }
}

@Composable
private fun SignedInContent(
    authManager: AuthManager,
    authState: AuthState.SignedIn,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var publicCollection by rememberSaveable { mutableStateOf(false) }
    var matchAlerts by rememberSaveable { mutableStateOf(false) }
    var deleteConfirmOpen by rememberSaveable { mutableStateOf(false) }
    var username by rememberSaveable { mutableStateOf(deriveUsername(authState.email)) }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item("header") {
            ProfileHeader(
                username = username,
                email = authState.email,
                signInMethod = "Google",
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
            )
        }

        item("identity-header") { BOBASectionHeader(title = "Identity") }
        item("username") {
            OutlinedTextField(
                value = username,
                onValueChange = { username = it.lowercase().filter { c -> c.isLetterOrDigit() || c == '_' || c == '-' } },
                label = { Text("Username (your public handle)") },
                supportingText = { Text("bobaplaybook.com/u/$username") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 4.dp),
            )
        }
        item("discord-link") {
            ListItem(
                headlineContent = { Text("Link Discord") },
                supportingContent = { Text("Required to enable trading", style = MaterialTheme.typography.labelMedium) },
                leadingContent = { Icon(Icons.Default.Group, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                trailingContent = {
                    TextButton(onClick = { launchDiscordOAuth(context) }) {
                        Text("Link")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item("avatar") {
            ListItem(
                headlineContent = { Text("Profile picture") },
                supportingContent = { Text("Upload a custom avatar (≤2 MB)", style = MaterialTheme.typography.labelMedium) },
                leadingContent = { Icon(Icons.Default.Image, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                trailingContent = {
                    TextButton(onClick = { /* M7 polish — boba-avatar-upload Worker */ }) {
                        Text("Upload")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item("sharing-header") { BOBASectionHeader(title = "Sharing") }
        item("public-collection") {
            ToggleRow(
                title = "Public collection",
                subtitle = "Share at bobaplaybook.com/u/$username",
                icon = Icons.Default.Public,
                checked = publicCollection,
                onCheckedChange = { publicCollection = it },
            )
        }

        item("notify-header") { BOBASectionHeader(title = "Notifications") }
        item("match-alerts") {
            ToggleRow(
                title = "Match alerts",
                subtitle = "Coming soon — APNs/FCM dispatcher in development",
                icon = Icons.Default.Notifications,
                checked = matchAlerts,
                onCheckedChange = { matchAlerts = it },
            )
        }

        item("role-header") { BOBASectionHeader(title = "Role") }
        item("role-request") {
            ListItem(
                headlineContent = { Text("Request mod or streamer role") },
                supportingContent = { Text("Reviewed by Ben within 48h", style = MaterialTheme.typography.labelMedium) },
                leadingContent = { Icon(Icons.Default.Verified, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                trailingContent = {
                    TextButton(onClick = { /* M7 polish — request_role RPC */ }) {
                        Text("Request")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item("streamer-shows") {
            ListItem(
                headlineContent = { Text("My Shows") },
                supportingContent = { Text("Streamer role required", style = MaterialTheme.typography.labelMedium) },
                leadingContent = { Icon(Icons.Default.LiveTv, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                modifier = Modifier.fillMaxWidth().clickable(enabled = false) { },
            )
        }

        item("legal-header") { BOBASectionHeader(title = "Legal") }
        item("terms") {
            ListItem(
                headlineContent = { Text("Terms of Service") },
                leadingContent = { Icon(Icons.Default.PrivacyTip, contentDescription = null) },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        CustomTabsIntent.Builder().build().launchUrl(context, "https://bobaplaybook.com/terms/".toUri())
                    },
            )
        }
        item("privacy") {
            ListItem(
                headlineContent = { Text("Privacy Policy") },
                leadingContent = { Icon(Icons.Default.PrivacyTip, contentDescription = null) },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        CustomTabsIntent.Builder().build().launchUrl(context, "https://bobaplaybook.com/privacy/".toUri())
                    },
            )
        }

        item("divider") { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }

        item("signout") {
            OutlinedButton(
                onClick = {
                    scope.launch {
                        authManager.signOut()
                        onDismiss()
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 4.dp),
            ) {
                Icon(Icons.AutoMirrored.Filled.ExitToApp, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Sign out")
            }
        }
        item("delete") {
            TextButton(
                onClick = { deleteConfirmOpen = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 4.dp),
            ) {
                Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(8.dp))
                Text("Delete account", color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (deleteConfirmOpen) {
        AlertDialog(
            onDismissRequest = { deleteConfirmOpen = false },
            title = { Text("Delete account?") },
            text = {
                Text(
                    "This permanently removes your collection, decks, shows, and profile across iOS, web, and Android. Card corrections you've submitted stay archived without your name attached. This cannot be undone."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        deleteConfirmOpen = false
                        /* M7 polish — boba-account-delete Worker call */
                    },
                ) {
                    Text("Delete forever", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmOpen = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun ProfileHeader(
    username: String,
    email: String?,
    signInMethod: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Surface(
            shape = CircleShape,
            color = BobaBrand.Orange,
            modifier = Modifier.size(72.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = (username.firstOrNull()?.uppercase() ?: "B"),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                )
            }
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "@$username",
                style = MaterialTheme.typography.headlineSmall,
            )
            email?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            AssistChip(
                onClick = {},
                label = { Text("Signed in with $signInMethod", style = MaterialTheme.typography.labelSmall) },
                leadingIcon = {
                    Icon(
                        Icons.Default.Verified,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                    )
                },
                colors = AssistChipDefaults.assistChipColors(
                    labelColor = MaterialTheme.colorScheme.primary,
                ),
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

@Composable
private fun ToggleRow(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle, style = MaterialTheme.typography.labelMedium) },
        leadingContent = { Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
        trailingContent = {
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun LegalLinks(context: android.content.Context) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        TextButton(onClick = {
            CustomTabsIntent.Builder().build().launchUrl(context, "https://bobaplaybook.com/terms/".toUri())
        }) {
            Text("Terms", style = MaterialTheme.typography.labelMedium)
        }
        TextButton(onClick = {
            CustomTabsIntent.Builder().build().launchUrl(context, "https://bobaplaybook.com/privacy/".toUri())
        }) {
            Text("Privacy", style = MaterialTheme.typography.labelMedium)
        }
    }
}

/**
 * Launches Discord OAuth via Chrome Custom Tabs.
 * Real implementation goes through supabase-kt's Discord provider —
 * this is a v1 stub that opens the BoBA Discord server invite while
 * the full OAuth path is wired in M7 polish.
 */
private fun launchDiscordOAuth(context: android.content.Context) {
    // M7 polish: replace with supabase-kt OAuth(Discord) launching Auth Tab.
    // For v1 we open Discord directly so the user can join the community.
    val url = "https://discord.com/invite/bobattlearena".toUri()
    CustomTabsIntent.Builder().build().launchUrl(context, url)
}

private fun deriveUsername(email: String?): String {
    if (email == null) return "you"
    return email.substringBefore("@").lowercase().filter { it.isLetterOrDigit() || it == '_' || it == '-' }
}
