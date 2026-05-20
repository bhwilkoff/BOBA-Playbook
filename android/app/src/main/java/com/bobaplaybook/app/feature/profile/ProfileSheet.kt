@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.profile

import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.clickable
import androidx.compose.ui.input.nestedscroll.nestedScroll
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
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
import androidx.compose.material3.SegmentedButton
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
 * Profile — full-screen destination (M3 guidance for settings + multi-
 * field auth surfaces). Was ModalBottomSheet; converted because
 * (a) signed-out state has >2 form fields (email + password + sign-in
 * options), (b) signed-in state drills into avatar upload / role request
 * sub-sections, and (c) predictive back on a ModalBottomSheet collapses
 * the sheet, not the nested push.
 *
 * Sections (signed in):
 *  - Header (avatar / username / sign-in method label)
 *  - Identity (username edit, Discord link, avatar upload)
 *  - Sharing (public collection toggle)
 *  - Notifications (match alerts toggle — gated per DECISIONS.md #039)
 *  - Role request
 *  - Legal (Terms / Privacy)
 *  - Sign out / delete account
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    authManager: AuthManager,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val authState by authManager.authState.collectAsStateWithLifecycle(initialValue = AuthState.Unknown)
    LaunchedEffect(Unit) { authManager.observeSession() }
    val scrollBehavior = androidx.compose.material3.TopAppBarDefaults.exitUntilCollapsedScrollBehavior(
        androidx.compose.material3.rememberTopAppBarState(),
    )

    androidx.compose.material3.Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            androidx.compose.material3.LargeTopAppBar(
                title = { Text("Profile") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        Box(modifier = Modifier.fillMaxWidth().padding(padding)) {
            when (val s = authState) {
                AuthState.Unknown -> LoadingState()
                AuthState.SignedOut -> SignedOutContent(authManager)
                is AuthState.SignedIn -> SignedInContent(authManager, s, onBack)
            }
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
    var mode by rememberSaveable { mutableStateOf(AuthMode.SIGN_IN) }
    var emailText by rememberSaveable { mutableStateOf("") }
    var passwordText by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var feedbackIsError by remember { mutableStateOf(true) }
    var submitting by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // LargeTopAppBar above already shows "Profile" — no second header here.
        Text(
            text = "Sign in to sync your collection, decks, and wanted list across iOS, web, and Android.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // M3 mode segmented switch — Sign in / Sign up
        androidx.compose.material3.SingleChoiceSegmentedButtonRow(
            modifier = Modifier.fillMaxWidth(),
        ) {
            AuthMode.entries.forEachIndexed { index, m ->
                SegmentedButton(
                    selected = mode == m,
                    onClick = { mode = m; feedback = null },
                    shape = androidx.compose.material3.SegmentedButtonDefaults.itemShape(index, AuthMode.entries.size),
                ) {
                    Text(m.label, style = MaterialTheme.typography.labelMedium)
                }
            }
        }

        OutlinedTextField(
            value = emailText,
            onValueChange = { emailText = it; feedback = null },
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                keyboardType = androidx.compose.ui.text.input.KeyboardType.Email,
                imeAction = androidx.compose.ui.text.input.ImeAction.Next,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = passwordText,
            onValueChange = { passwordText = it; feedback = null },
            label = { Text("Password") },
            singleLine = true,
            visualTransformation = if (passwordVisible)
                androidx.compose.ui.text.input.VisualTransformation.None
            else
                androidx.compose.ui.text.input.PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                    Icon(
                        imageVector = if (passwordVisible) Icons.Default.VisibilityOff
                                      else Icons.Default.Visibility,
                        contentDescription = if (passwordVisible) "Hide password" else "Show password",
                    )
                }
            },
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                keyboardType = androidx.compose.ui.text.input.KeyboardType.Password,
                imeAction = androidx.compose.ui.text.input.ImeAction.Done,
            ),
            modifier = Modifier.fillMaxWidth(),
        )

        if (feedback != null) {
            Text(
                text = feedback!!,
                style = MaterialTheme.typography.bodySmall,
                color = if (feedbackIsError) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.primary,
            )
        }

        Button(
            onClick = {
                if (emailText.isBlank() || passwordText.length < 6) {
                    feedback = "Enter a valid email and a password of at least 6 characters."
                    feedbackIsError = true
                    return@Button
                }
                submitting = true
                feedback = null
                scope.launch {
                    val result = when (mode) {
                        AuthMode.SIGN_IN -> authManager.signInWithEmail(emailText.trim(), passwordText)
                        AuthMode.SIGN_UP -> authManager.signUpWithEmail(emailText.trim(), passwordText)
                    }
                    submitting = false
                    when (result) {
                        com.bobaplaybook.app.auth.SignInResult.Success -> {
                            if (mode == AuthMode.SIGN_UP) {
                                feedback = "Account created — check your email to verify, then sign in."
                                feedbackIsError = false
                            }
                        }
                        else -> {
                            feedback = result.userMessage
                            feedbackIsError = true
                        }
                    }
                }
            },
            enabled = !submitting,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (mode == AuthMode.SIGN_IN) "Sign in" else "Create account")
        }

        if (mode == AuthMode.SIGN_IN) {
            TextButton(
                onClick = {
                    if (emailText.isBlank()) {
                        feedback = "Enter your email to receive a reset link."
                        feedbackIsError = true
                        return@TextButton
                    }
                    scope.launch {
                        val result = authManager.sendPasswordReset(emailText.trim())
                        feedback = when (result) {
                            com.bobaplaybook.app.auth.SignInResult.Success -> "Reset link sent to $emailText"
                            else -> result.userMessage
                        }
                        feedbackIsError = result !is com.bobaplaybook.app.auth.SignInResult.Success
                    }
                },
                modifier = Modifier.align(Alignment.End),
            ) {
                Text("Forgot password?", style = MaterialTheme.typography.labelLarge)
            }
        }

        androidx.compose.material3.HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
        Text(
            text = "Or continue with",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )

        OutlinedButton(
            onClick = {
                scope.launch {
                    val result = authManager.signInWithGoogle(context)
                    if (result !is com.bobaplaybook.app.auth.SignInResult.Success && result !is com.bobaplaybook.app.auth.SignInResult.Cancelled) {
                        feedback = result.userMessage
                        feedbackIsError = true
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Google")
        }
        OutlinedButton(
            onClick = { launchDiscordOAuth(context) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Default.Group, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("Discord")
        }
        Spacer(Modifier.height(8.dp))
        LegalLinks(context)
    }
}

private enum class AuthMode(val label: String) {
    SIGN_IN("Sign in"),
    SIGN_UP("Create account"),
}

@Composable
private fun SignedInContent(
    authManager: AuthManager,
    authState: AuthState.SignedIn,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val vm: ProfileViewModel = androidx.hilt.navigation.compose.hiltViewModel()
    val usernameStatus by vm.usernameStatus.collectAsStateWithLifecycle(initialValue = null)
    var publicCollection by rememberSaveable { mutableStateOf(false) }
    var matchAlerts by rememberSaveable { mutableStateOf(false) }
    var deleteConfirmOpen by rememberSaveable { mutableStateOf(false) }
    var username by rememberSaveable { mutableStateOf(deriveUsername(authState.email)) }
    var roleRequestOpen by rememberSaveable { mutableStateOf(false) }

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
                onValueChange = { raw ->
                    val cleaned = raw.lowercase().filter { c -> c.isLetterOrDigit() || c == '_' || c == '-' }
                    username = cleaned
                    if (cleaned.length >= 3) vm.checkUsername(cleaned)
                },
                label = { Text("Username (your public handle)") },
                supportingText = {
                    val statusMsg = when (usernameStatus) {
                        "available"     -> "✓ available — bobaplaybook.com/u/$username"
                        "taken"         -> "✗ taken — try ${username}2"
                        "banned"        -> "✗ not allowed"
                        "reserved"      -> "✗ reserved"
                        "invalid_chars" -> "letters, digits, _ or - only"
                        "too_short"     -> "at least 3 characters"
                        "too_long"      -> "at most 30 characters"
                        else            -> "bobaplaybook.com/u/$username"
                    }
                    Text(statusMsg)
                },
                trailingIcon = {
                    if (usernameStatus == "available") {
                        TextButton(onClick = { vm.setUsername(username) { /* no-op */ } }) {
                            Text("Save")
                        }
                    }
                },
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
            val avatarPicker = androidx.activity.compose.rememberLauncherForActivityResult(
                androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
            ) { uri ->
                if (uri == null) return@rememberLauncherForActivityResult
                val resolver = context.contentResolver
                val mime = resolver.getType(uri) ?: "image/jpeg"
                val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null) return@rememberLauncherForActivityResult
                vm.uploadAvatar(bytes, mime) { _ ->
                    // Success path: the URL is persisted via set_avatar_url
                    // RPC by the service. The next sign-in / profile refresh
                    // pulls the new column. (A user-visible avatar refresh
                    // would need a getUserProfile() pull -- defer.)
                }
            }
            ListItem(
                headlineContent = { Text("Profile picture") },
                supportingContent = { Text("Upload a custom avatar (≤2 MB)", style = MaterialTheme.typography.labelMedium) },
                leadingContent = { Icon(Icons.Default.Image, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                trailingContent = {
                    TextButton(
                        onClick = {
                            avatarPicker.launch(
                                androidx.activity.result.PickVisualMediaRequest(
                                    androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly,
                                ),
                            )
                        },
                    ) { Text("Upload") }
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
                onCheckedChange = { enabled ->
                    publicCollection = enabled  // optimistic
                    vm.setPublicCollection(enabled) { ok ->
                        if (!ok) publicCollection = !enabled  // revert on failure
                    }
                },
            )
        }

        item("notify-header") { BOBASectionHeader(title = "Notifications") }
        item("match-alerts") {
            ToggleRow(
                title = "Match alerts",
                subtitle = "Opt in now — push delivery lands when the dispatcher ships",
                icon = Icons.Default.Notifications,
                checked = matchAlerts,
                onCheckedChange = { enabled ->
                    matchAlerts = enabled  // optimistic
                    vm.setMatchAlerts(enabled) { ok ->
                        if (!ok) matchAlerts = !enabled
                    }
                },
            )
        }

        item("role-header") { BOBASectionHeader(title = "Role") }
        item("role-request") {
            ListItem(
                headlineContent = { Text("Request mod or streamer role") },
                supportingContent = { Text("Reviewed by Ben within 48h", style = MaterialTheme.typography.labelMedium) },
                leadingContent = { Icon(Icons.Default.Verified, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                trailingContent = {
                    TextButton(onClick = { roleRequestOpen = true }) {
                        Text("Request")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        // Role-gated entries — hidden until M7 wires user_profiles.role.
        // Always-disabled rows teach users a feature exists they can't
        // access (M3 anti-pattern). When role state lands, render the
        // matching entry only for users who have that role.
        //
        // ```
        // item("streamer-shows") {
        //     ListItem(headlineContent = { Text("My Shows") }, ...)
        // } onlyIf userRole.includes(streamer)
        //
        // item("mod-panel") { ... } onlyIf userRole.includes(moderator)
        // item("admin-panel") { ... } onlyIf userRole == admin
        // ```

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

    if (roleRequestOpen) {
        var requestedRole by remember { mutableStateOf("moderator") }
        var reason by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { roleRequestOpen = false },
            title = { Text("Request role") },
            text = {
                Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                    Text("Which role?", style = MaterialTheme.typography.bodyMedium)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.material3.RadioButton(
                            selected = requestedRole == "moderator",
                            onClick = { requestedRole = "moderator" },
                        )
                        Text("Moderator — review card corrections")
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.material3.RadioButton(
                            selected = requestedRole == "streamer",
                            onClick = { requestedRole = "streamer" },
                        )
                        Text("Streamer — manage Whatnot shows")
                    }
                    OutlinedTextField(
                        value = reason,
                        onValueChange = { reason = it },
                        label = { Text("Why?") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        vm.requestRole(requestedRole, reason) { /* Snackbar — M7 polish */ }
                        roleRequestOpen = false
                    },
                    enabled = reason.isNotBlank(),
                ) { Text("Submit") }
            },
            dismissButton = {
                TextButton(onClick = { roleRequestOpen = false }) { Text("Cancel") }
            },
        )
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
                        vm.deleteAccount { ok ->
                            if (ok) onDismiss()
                            // On failure, the account stays; UI keeps the user signed in.
                        }
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
                    fontWeight = FontWeight.Bold,
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
            // Status label — not interactive. M3 spec: small Surface +
            // Text, not a no-op Chip (which teaches users it's tappable).
            androidx.compose.material3.Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondaryContainer,
                modifier = Modifier.padding(top = 4.dp),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        Icons.Default.Verified,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Text(
                        "Signed in with $signInMethod",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }
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
