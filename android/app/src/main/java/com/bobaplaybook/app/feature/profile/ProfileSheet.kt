@file:OptIn(ExperimentalMaterial3Api::class, androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)

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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
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
    onPracticeUnlock: () -> Unit = {},
) {
    val authState by authManager.authState.collectAsStateWithLifecycle(initialValue = AuthState.Unknown)
    // observeSession() is started lifecycle-scoped from MainActivity so
    // every screen sees authState immediately, not only after Profile
    // has been opened.
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
                is AuthState.SignedIn -> SignedInContent(authManager, s, onBack, onPracticeUnlock)
            }
        }
    }
}

@Composable
private fun LoadingState() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        androidx.compose.material3.ContainedLoadingIndicator()
        Text(
            "Loading profile…",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
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
                BOBAIconTooltip(if (passwordVisible) "Hide password" else "Show password") {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            imageVector = if (passwordVisible) Icons.Default.VisibilityOff
                                          else Icons.Default.Visibility,
                            contentDescription = if (passwordVisible) "Hide password" else "Show password",
                        )
                    }
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
            onClick = { scope.launch { launchDiscordOAuth(authManager) } },
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
    onPracticeUnlock: () -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val vm: ProfileViewModel = androidx.hilt.navigation.compose.hiltViewModel()
    val hintsVm: com.bobaplaybook.app.hints.HintsViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    val hintsEnabled by hintsVm.globalEnabled.collectAsStateWithLifecycle(initialValue = true)
    val usernameStatus by vm.usernameStatus.collectAsStateWithLifecycle(initialValue = null)
    val profile by vm.profile.collectAsStateWithLifecycle(initialValue = null)

    // Pull the user's row once on sheet open so the header avatar +
    // public-collection + match-alerts toggles reflect server state
    // (not just the local defaults). Re-fetches happen automatically
    // when uploadAvatar succeeds.
    androidx.compose.runtime.LaunchedEffect(Unit) {
        vm.refreshProfile()
    }

    // When the user signed in with Discord, persist the discord_user_id +
    // avatar URL on user_profiles so future trade-matching can deep-link
    // to their Discord profile. DECISIONS.md #049 — we store the
    // identifier; we never call the Discord API ourselves.
    androidx.compose.runtime.LaunchedEffect(authState.provider, authState.providerUserId) {
        if (authState.provider == "discord" && !authState.providerUserId.isNullOrEmpty()) {
            vm.captureDiscordIdentity(authState.providerUserId, authState.providerAvatarUrl)
        }
    }
    // Tick 199 — seeded from server. Prior to this both toggles were
    // hardcoded `mutableStateOf(false)` with no LaunchedEffect to
    // hydrate, so an account with sharing/alerts already enabled would
    // see the switch in the OFF position on profile open. Classic
    // [[feedback_state_from_prop_antipattern]]. `togglesSeededFor`
    // matches the username-seed pattern at line 391: avoid clobbering
    // an in-flight optimistic update from the user.
    var publicCollection by rememberSaveable { mutableStateOf(false) }
    var matchAlerts by rememberSaveable { mutableStateOf(false) }
    var togglesSeededFor by rememberSaveable { mutableStateOf<String?>(null) }
    androidx.compose.runtime.LaunchedEffect(profile?.username,
        profile?.publicCollectionEnabled,
        profile?.matchAlertsEnabled) {
        val serverName = profile?.username
        if (!serverName.isNullOrBlank() && togglesSeededFor != serverName) {
            publicCollection = profile?.publicCollectionEnabled == true
            matchAlerts      = profile?.matchAlertsEnabled == true
            togglesSeededFor = serverName
        }
    }
    var deleteConfirmOpen by rememberSaveable { mutableStateOf(false) }
    /// Tick 169 — confirm before signing out. iOS uses .alert, web
    /// uses confirm(). Android was the only platform that signed
    /// out on the first tap.
    var signOutConfirmOpen by rememberSaveable { mutableStateOf(false) }
    var username by rememberSaveable { mutableStateOf(deriveUsername(authState.email)) }
    var roleRequestOpen by rememberSaveable { mutableStateOf(false) }

    // Seed the local username field from the server-side profile when it
    // arrives. Without this the field is permanently stuck on the
    // email-derived candidate even when the user already has a saved
    // handle — [[feedback_state_from_prop_antipattern]]. Uses
    // `serverSeededFor` to avoid clobbering edits the user is making
    // mid-stream; we only seed once per distinct server username.
    var serverSeededFor by rememberSaveable { mutableStateOf<String?>(null) }
    androidx.compose.runtime.LaunchedEffect(profile?.username) {
        val serverName = profile?.username
        if (!serverName.isNullOrBlank() && serverSeededFor != serverName) {
            username = serverName
            serverSeededFor = serverName
        }
    }

    // Tick 338 — LocalConfiguration.current is a @Composable getter
    // and must be read at the Composable scope, not inside
    // LazyListScope (which is a DSL builder, not @Composable).
    // Hoisted from inside LazyColumn so the cheat-sheet block can
    // close over the value without invoking a Composable from a
    // non-Composable context. Fixes tick 334 CI red.
    val isPhoneOnlyTouch = LocalConfiguration.current.keyboard ==
        android.content.res.Configuration.KEYBOARD_NOKEYS

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item("header") {
            ProfileHeader(
                username = profile?.username ?: username,
                email = authState.email,
                signInMethod = authState.provider,
                // Prefer the user-uploaded avatar on user_profiles; fall
                // back to provider-supplied (Google / Discord) avatar.
                avatarUrl = profile?.avatarUrl ?: profile?.discordAvatarUrl ?: authState.providerAvatarUrl,
                role = profile?.role,
                isAdmin = profile?.isAdmin == true,
                isMod = profile?.isMod == true,
                isStreamer = profile?.isStreamer == true,
                onPracticeUnlock = onPracticeUnlock,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
            )
        }

        item("identity-header") { BOBASectionHeader(title = "Identity") }
        item("username") {
            OutlinedTextField(
                value = username,
                onValueChange = { raw ->
                    val cleaned = raw.lowercase()
                        .filter { c -> c.isLetterOrDigit() || c == '_' || c == '-' }
                        .take(30)  // matches Supabase username column constraint
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
                    val dirty = username.isNotBlank() && username != profile?.username
                    val savable = dirty && (usernameStatus == "available" || usernameStatus == null)
                    if (dirty) {
                        TextButton(
                            enabled = savable && username.length >= 3,
                            onClick = {
                                vm.setUsername(username) { ok ->
                                    if (ok) scope.launch { appSnackbar?.showSnackbar("Username saved") }
                                }
                            },
                        ) {
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
            // Tick 211 — branch on linked-state so signed-in-with-Discord
            // users + users who already linked don't see "Link" pretending
            // they haven't. Mirrors iOS Profile/SignInMethodSection logic.
            val discordLinked = !profile?.discordUserId.isNullOrEmpty()
            ListItem(
                headlineContent = { Text("Discord") },
                supportingContent = {
                    Text(
                        if (discordLinked) "Linked — enables trading"
                        else "Link to enable trading",
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
                leadingContent = {
                    val avatarUrl = profile?.discordAvatarUrl
                    if (discordLinked && !avatarUrl.isNullOrEmpty()) {
                        coil3.compose.AsyncImage(
                            model = avatarUrl,
                            contentDescription = null,
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                            modifier = Modifier
                                .size(24.dp)
                                .clip(CircleShape),
                        )
                    } else {
                        Icon(
                            Icons.Default.Group,
                            contentDescription = null,
                            tint = if (discordLinked) androidx.compose.ui.graphics.Color(0xFF5865F2)
                                   else MaterialTheme.colorScheme.primary,
                        )
                    }
                },
                trailingContent = {
                    if (discordLinked) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = "Discord linked",
                            tint = androidx.compose.ui.graphics.Color(0xFF5865F2),
                        )
                    } else {
                        TextButton(onClick = {
                            scope.launch { launchDiscordOAuth(authManager) }
                        }) {
                            Text("Link")
                        }
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
                vm.uploadAvatar(bytes, mime) { url ->
                    // Pull the fresh user_profiles row so the header
                    // avatar updates immediately. Without this the new
                    // avatar didn't surface until next sign-in.
                    if (url != null) {
                        vm.refreshProfile()
                        scope.launch { appSnackbar?.showSnackbar("Profile picture updated") }
                    } else {
                        scope.launch { appSnackbar?.showSnackbar("Couldn't upload avatar. Try again.") }
                    }
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
        // Surface copy + share affordances only when the toggle is on.
        // iOS+web Profile both let the user immediately copy the link
        // when they enable sharing — WEB-DESIGN.md §14.4 codifies this
        // as binding ("Anyone toggling sharing on should immediately
        // see the URL with a copy button").
        if (publicCollection && username.isNotBlank()) {
            item("public-url-actions") {
                val publicUrl = "https://bobaplaybook.com/u/$username"
                ListItem(
                    headlineContent = {
                        Text(
                            "bobaplaybook.com/u/$username",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    },
                    supportingContent = {
                        Text(
                            "Public link to your collection",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                    leadingContent = {
                        Icon(Icons.Default.Public,
                             contentDescription = null,
                             tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    },
                    trailingContent = {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            BOBAIconTooltip("Copy public collection link") {
                                IconButton(onClick = {
                                    val cm = context.getSystemService(android.content.ClipboardManager::class.java)
                                    cm?.setPrimaryClip(
                                        android.content.ClipData.newPlainText("BOBA Playbook", publicUrl)
                                    )
                                    scope.launch { appSnackbar?.showSnackbar("Link copied") }
                                }) {
                                    Icon(Icons.Default.ContentCopy,
                                         contentDescription = "Copy link",
                                         tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            BOBAIconTooltip("Share public collection link") {
                                IconButton(onClick = {
                                    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(android.content.Intent.EXTRA_SUBJECT, "My BOBA collection")
                                        putExtra(android.content.Intent.EXTRA_TEXT, publicUrl)
                                    }
                                    context.startActivity(
                                        android.content.Intent.createChooser(intent, "Share collection link")
                                    )
                                }) {
                                    Icon(Icons.Default.Share,
                                         contentDescription = "Share link",
                                         tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        item("notify-header") { BOBASectionHeader(title = "Notifications") }
        // Two independent toggles — iOS Profile parity. Tick 121
        // un-bundled them; previously toggling match-alerts also
        // overwrote the general-push setting and vice-versa.
        item("push-toggle") {
            val pushChecked = profile?.notificationsEnabled ?: true
            var pushOptimistic by remember(pushChecked) { mutableStateOf(pushChecked) }
            ToggleRow(
                title = "Push notifications",
                subtitle = "App-wide push deliveries (deck shares, trade match alerts, BoBA announcements).",
                icon = Icons.Default.Notifications,
                checked = pushOptimistic,
                onCheckedChange = { enabled ->
                    pushOptimistic = enabled
                    vm.setNotifications(enabled) { ok ->
                        if (!ok) pushOptimistic = !enabled
                    }
                },
            )
        }
        item("match-alerts") {
            ToggleRow(
                title = "Match alerts",
                subtitle = "Opt in now — push delivery lands when the dispatcher ships.",
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
            // Surface pending-request state so users who submitted a
            // request earlier see "Pending: moderator" instead of
            // re-submitting blind. iOS Profile already shows this; the
            // Android gap meant the only feedback was the post-submit
            // Snackbar that disappeared after a few seconds.
            val pendingRole = profile?.requestedRole?.takeIf { it.isNotBlank() }
            ListItem(
                headlineContent = { Text("Request mod or streamer role") },
                supportingContent = {
                    if (pendingRole != null) {
                        Text(
                            "Pending: ${pendingRole.replaceFirstChar { it.uppercase() }} · Ben reviews within 48h",
                            style = MaterialTheme.typography.labelMedium,
                            color = BobaBrand.Cyan,
                        )
                    } else {
                        Text("Reviewed by Ben within 48h", style = MaterialTheme.typography.labelMedium)
                    }
                },
                leadingContent = { Icon(Icons.Default.Verified, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                trailingContent = {
                    TextButton(onClick = { roleRequestOpen = true }) {
                        Text(if (pendingRole != null) "Update" else "Request")
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

        item("hints-header") { BOBASectionHeader(title = "Hints") }
        item("hints-toggle") {
            ToggleRow(
                title = "Show first-run hints",
                subtitle = "Tips like \"long-press to add\" surface once per device",
                icon = Icons.Default.Lightbulb,
                checked = hintsEnabled,
                onCheckedChange = { hintsVm.setGlobalEnabled(it) },
            )
        }
        item("hints-reset") {
            ListItem(
                headlineContent = { Text("Reset hints") },
                supportingContent = {
                    Text(
                        "Make every hint banner re-appear",
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
                leadingContent = {
                    Icon(Icons.Default.Lightbulb, contentDescription = null,
                         tint = MaterialTheme.colorScheme.onSurfaceVariant)
                },
                trailingContent = {
                    TextButton(onClick = {
                        hintsVm.resetAll()
                        scope.launch { appSnackbar?.showSnackbar("Hints reset") }
                    }) {
                        Text("Reset")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
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
        // Change password — sends a password-reset email to the
        // signed-in user's address. iOS ProfileView.swift line 422
        // same flow (Supabase resetPasswordForEmail). Hidden for
        // OAuth-only users (Google / Discord) who don't have a
        // password to reset.
        val authEmail = authState.email
        if (!authEmail.isNullOrBlank() && authState.provider != "google" && authState.provider != "discord") {
            item("change-password") {
                ListItem(
                    headlineContent = { Text("Change password") },
                    supportingContent = {
                        Text(
                            "Email a reset link to $authEmail",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                    leadingContent = {
                        Icon(Icons.Default.Lock, contentDescription = null)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            scope.launch {
                                val result = authManager.sendPasswordReset(authEmail)
                                val msg = if (result is com.bobaplaybook.app.auth.SignInResult.Success)
                                    "Reset link sent to $authEmail"
                                else "Couldn't send reset link. Try again."
                                appSnackbar?.showSnackbar(msg)
                            }
                        },
                )
            }
        }

        // Send Feedback — opens a mailto: with subject pre-filled to
        // include the app version. iOS ProfileView.swift:798 same
        // pattern. Helps Ben triage bug reports without asking for
        // the build number.
        item("feedback") {
            ListItem(
                headlineContent = { Text("Send feedback") },
                supportingContent = {
                    Text(
                        "Email ben@bobaplaybook.com",
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
                leadingContent = {
                    Icon(Icons.Default.Email, contentDescription = null)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        val v = "${com.bobaplaybook.app.BuildConfig.VERSION_NAME} (${com.bobaplaybook.app.BuildConfig.VERSION_CODE})"
                        val subject = android.net.Uri.encode("BOBA Playbook feedback (v$v)")
                        // Tick 289 — port iOS v2.314 device+OS body
                        // pre-fill so Ben can triage faster. 3 blank
                        // lines for the user's message, then a "---"
                        // divider with App + Device + Android version.
                        val device = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
                        val body = android.net.Uri.encode(
                            "\n\n\n---\nApp: $v\nDevice: $device · Android ${android.os.Build.VERSION.RELEASE}"
                        )
                        val intent = android.content.Intent(
                            android.content.Intent.ACTION_VIEW,
                            android.net.Uri.parse("mailto:ben@bobaplaybook.com?subject=$subject&body=$body"),
                        )
                        // Tick 166 — was silently swallowed via
                        // runCatching{...}. If no email app is installed
                        // (Pixels often ship without one), the user taps
                        // and sees nothing. Fall back to a Snackbar with
                        // the canonical email + a Copy-email affordance
                        // so they can at least reach out via another
                        // client (Gmail web, etc.).
                        runCatching { context.startActivity(intent) }
                            .onFailure {
                                val cm = context.getSystemService(android.content.ClipboardManager::class.java)
                                cm?.setPrimaryClip(
                                    android.content.ClipData.newPlainText("BOBA feedback email", "ben@bobaplaybook.com")
                                )
                                scope.launch {
                                    appSnackbar?.showSnackbar(
                                        "No email app — copied ben@bobaplaybook.com to clipboard",
                                    )
                                }
                            }
                    },
            )
        }
        // App version — iOS Profile shows this under About per
        // DESIGN.md §8.5 spec. Helps Ben triage bug reports
        // ("which version is this?") when users email feedback.
        item("version") {
            ListItem(
                headlineContent = { Text("Version") },
                supportingContent = {
                    Text(
                        "${com.bobaplaybook.app.BuildConfig.VERSION_NAME} " +
                            "(${com.bobaplaybook.app.BuildConfig.VERSION_CODE})",
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
                leadingContent = {
                    Icon(Icons.Default.Info, contentDescription = null,
                         tint = MaterialTheme.colorScheme.onSurfaceVariant)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        // Tap-to-copy the version string — useful for
                        // including in bug reports.
                        // Tick 294 — confirm haptic (TextHandleMove) so
                        // tap feels like it did something even when the
                        // Snackbar is animating in. Matches the iOS
                        // success-haptic on the same row.
                        haptic.performHapticFeedback(
                            androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove
                        )
                        val v = "${com.bobaplaybook.app.BuildConfig.VERSION_NAME} " +
                            "(${com.bobaplaybook.app.BuildConfig.VERSION_CODE})"
                        val cm = context.getSystemService(android.content.ClipboardManager::class.java)
                        cm?.setPrimaryClip(android.content.ClipData.newPlainText("BOBA Playbook version", v))
                        scope.launch { appSnackbar?.showSnackbar("Version copied: $v") }
                    },
            )
        }

        // Tick 334 — Keyboard shortcuts cheat sheet (web tick 333 parity).
        // Useful on Chromebook + tablets with paired keyboard. Hidden
        // when no hardware keyboard via the hoisted isPhoneOnlyTouch
        // flag (LocalConfiguration must be read at Composable scope,
        // not inside LazyListScope — tick 338 fix).
        if (!isPhoneOnlyTouch) {
            item("shortcuts-header") {
                BOBASectionHeader(title = "Keyboard shortcuts")
            }
            val shortcuts = listOf(
                "Ctrl+1..5" to "Switch tabs",
                "/" to "Focus search (Find)",
                "R" to "Surprise me · random card (Find)",
                "N" to "Clear deck draft (Decks)",
                "Ctrl+S" to "Save deck (Decks)",
                "Ctrl+← / Ctrl+→" to "Prev / next card (Card detail)",
            )
            shortcuts.forEach { (combo, desc) ->
                item("shortcut-$combo") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainerHigh,
                            shape = MaterialTheme.shapes.small,
                        ) {
                            Text(
                                combo,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                            )
                        }
                        Text(
                            desc,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        item("divider") { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }

        item("signout") {
            OutlinedButton(
                // Tick 169 — confirm sign-out (iOS + web parity). Without
                // the dialog, a stray tap immediately kicks the user out
                // of every personal surface (Collection / Decks / Custom
                // Rainbows / Shows). Sync layer is durable so no data is
                // lost, but the re-sign-in friction warrants a confirm.
                onClick = { signOutConfirmOpen = true },
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
        // Pre-fill the radio with the user's current pending role (if
        // any) so "Update" reads the existing state instead of always
        // defaulting to "moderator." Keyed on profile?.requestedRole so
        // opening for a different profile resets correctly.
        val initialRole = profile?.requestedRole?.takeIf { it.isNotBlank() } ?: "moderator"
        var requestedRole by remember(initialRole) { mutableStateOf(initialRole) }
        var reason by remember { mutableStateOf("") }
        val isUpdate = profile?.requestedRole?.isNotBlank() == true
        AlertDialog(
            onDismissRequest = { roleRequestOpen = false },
            title = { Text(if (isUpdate) "Update role request" else "Request role") },
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
                        val role = requestedRole
                        vm.requestRole(role, reason) { ok ->
                            scope.launch {
                                val msg = if (ok) "Role request submitted — Ben reviews within 48h."
                                          else "Couldn't submit role request. Try again later."
                                appSnackbar?.showSnackbar(msg)
                            }
                        }
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

    if (signOutConfirmOpen) {
        AlertDialog(
            onDismissRequest = { signOutConfirmOpen = false },
            title = { Text("Sign out?") },
            text = {
                Text(
                    "Your collection, decks, and wanted list stay synced to the cloud. Sign back in any time to bring them back."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    signOutConfirmOpen = false
                    scope.launch {
                        authManager.signOut()
                        onDismiss()
                    }
                }) {
                    Text("Sign out")
                }
            },
            dismissButton = {
                TextButton(onClick = { signOutConfirmOpen = false }) { Text("Cancel") }
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
    signInMethod: String?,
    avatarUrl: String? = null,
    role: String? = null,
    isAdmin: Boolean = false,
    isMod: Boolean = false,
    isStreamer: Boolean = false,
    onPracticeUnlock: () -> Unit = {},
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
            if (avatarUrl != null) {
                coil3.compose.AsyncImage(
                    model = avatarUrl,
                    contentDescription = "Avatar",
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
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
            // Role + provider badge row. iOS DESIGN.md §6.5 — role
            // badge primary, provider pill secondary. Admin row gets
            // a bolt-icon button that unlocks the Practice executor
            // (M5.5 — admin-only per DECISIONS.md #033 / #048).
            Row(
                modifier = Modifier.padding(top = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val (roleLabel, roleColor) = when {
                    isAdmin -> "ADMIN" to BobaBrand.Orange
                    isMod -> "MOD" to BobaBrand.Cyan
                    else -> "MEMBER" to MaterialTheme.colorScheme.onSurfaceVariant
                }
                RoleBadgePill(label = roleLabel, color = roleColor)
                if (isStreamer && !isAdmin) {
                    RoleBadgePill(label = "STREAMER", color = BobaBrand.Cyan)
                }
                // Tick 206 — provider-specific pill styling (iOS parity).
                // Google + Discord get brand colors; Email/null falls to
                // the unmarked default (no pill) so the absence-of-pill
                // also signals "this is a password account."
                ProviderPill(provider = signInMethod)
                if (isAdmin) {
                    androidx.compose.material3.IconButton(
                        onClick = onPracticeUnlock,
                        modifier = Modifier.size(28.dp),
                    ) {
                        Icon(
                            Icons.Default.Bolt,
                            contentDescription = "Practice (admin only)",
                            tint = BobaBrand.Orange,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ProviderPill(provider: String?) {
    // Email / null / unknown → unmarked default (no pill). The absence
    // is a positive signal: "this account has a password to reset."
    val p = provider?.lowercase() ?: return
    val (label, bg, fg) = when (p) {
        "google"  -> Triple("GOOGLE",  androidx.compose.ui.graphics.Color(0xFF4285F4), Color.White)
        "discord" -> Triple("DISCORD", androidx.compose.ui.graphics.Color(0xFF5865F2), Color.White)
        "apple"   -> Triple("APPLE",   Color.Black, Color.White)
        else      -> return
    }
    androidx.compose.material3.Surface(
        shape = MaterialTheme.shapes.extraSmall,
        color = bg,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                fontWeight = FontWeight.Bold,
                fontSize = 9.sp,
                letterSpacing = 1.sp,
            ),
            color = fg,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

@Composable
private fun RoleBadgePill(label: String, color: androidx.compose.ui.graphics.Color) {
    androidx.compose.material3.Surface(
        shape = MaterialTheme.shapes.extraSmall,
        color = color,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                fontWeight = FontWeight.Bold,
                fontSize = 9.sp,
                letterSpacing = 1.sp,
            ),
            color = BobaBrand.NearBlack,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
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
 * Launches Discord OAuth via supabase-kt's Discord provider.
 *
 * Supabase opens a Custom Tab to Discord's auth page; Discord redirects
 * back to bobaplaybook://auth-callback which MainActivity.onNewIntent
 * passes to SupabaseClient.handleDeeplinks(intent) to import the
 * session. Per DECISIONS.md #049 the OAuth handshake is the entire
 * Discord surface — no bot, no server-side API calls, no message reads.
 *
 * Requires Discord to be added as a provider in the Supabase project
 * dashboard with redirect URL `bobaplaybook://auth-callback` allowed.
 */
private suspend fun launchDiscordOAuth(authManager: AuthManager) {
    authManager.signInWithDiscord()
}

private fun deriveUsername(email: String?): String {
    if (email == null) return "you"
    return email.substringBefore("@").lowercase().filter { it.isLetterOrDigit() || it == '_' || it == '-' }
}
