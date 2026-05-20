@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.carddetail

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Share
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material.icons.filled.Style
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.app.R
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.network.CDN
import com.bobaplaybook.core.network.PricingListing
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAPriceTile
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAStatsGrid
import com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaElements
import com.bobaplaybook.core.ui.transitions.cardSharedBounds
import kotlinx.collections.immutable.ImmutableList

/**
 * Card detail surface — ANDROID-DESIGN.md §8.6.
 *
 * Anatomy (top → bottom):
 *  1. LargeTopAppBar w/ X close, Add overflow menu, Share action
 *  2. Element-gradient art panel (full-res Coil image, sharedBounds key)
 *  3. Canonical 6-cell BOBAStatsGrid (DECISIONS.md #029)
 *  4. Cost/DBS/Power (Plays only) BELOW the canonical six
 *  5. Pricing panels — Buy Now (eBay active) + Sold (Radish + eBay)
 *  6. Add to Collection / Deck / Show CTAs at bottom
 */
@Composable
fun CardDetailScreen(
    bobaId: String,
    onBack: () -> Unit,
    onOpenOtherVersion: (bobaId: String) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val viewModel: CardDetailViewModel = hiltViewModel()
    val state by viewModel.uiStateFor(bobaId).collectAsStateWithLifecycle()
    val decksViewModel: com.bobaplaybook.app.feature.decks.DecksViewModel = hiltViewModel()
    val profileViewModel: com.bobaplaybook.app.feature.profile.ProfileViewModel = hiltViewModel()
    val profile by profileViewModel.profile.collectAsStateWithLifecycle(initialValue = null)
    androidx.compose.runtime.LaunchedEffect(Unit) { profileViewModel.refreshProfile() }
    val isStreamer = profile?.role?.contains("streamer", ignoreCase = true) == true ||
        profile?.role?.contains("admin", ignoreCase = true) == true
    // Plain TopAppBar — Large variant was overscaled for a short card
    // title and ate vertical space above the art panel.
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior(rememberTopAppBarState())
    val context = LocalContext.current
    // App-scoped Snackbar host (LocalAppSnackbar) — provided at the
    // BOBAApp root. No local fallback: tests render this through the
    // theme which provides the local; previews don't show Snackbars.
    val snackbarHostState = LocalAppSnackbar.current
        ?: remember { androidx.compose.material3.SnackbarHostState() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    var addMenuOpen by remember { mutableStateOf(false) }
    var addToCollectionOpen by remember { mutableStateOf(false) }
    var addToDeckOpen by remember { mutableStateOf(false) }

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        // Snackbar host omitted — app-scoped via LocalAppSnackbar covers
        // the cross-tab case; per-screen Scaffold doesn't double-paint.
        topBar = {
            TopAppBar(
                title = { Text(state.card?.displayName ?: "Card", maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.action_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = {
                        state.card?.let { c ->
                            scope.launch { CardShareHelper.share(context, c) }
                        }
                    }) {
                        Icon(Icons.Default.Share, contentDescription = "Share")
                    }
                    Box {
                        IconButton(onClick = { addMenuOpen = true }) {
                            Icon(Icons.Default.Add, contentDescription = "Add")
                        }
                        DropdownMenu(
                            expanded = addMenuOpen,
                            onDismissRequest = { addMenuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Add to Collection") },
                                onClick = {
                                    addMenuOpen = false
                                    addToCollectionOpen = true
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Add to Deck") },
                                onClick = {
                                    addMenuOpen = false
                                    addToDeckOpen = true
                                },
                            )
                            // "Add to Show" only renders for users with the
                            // streamer/admin role — non-streamers never see
                            // the option (ANDROID-DESIGN.md §3.7 "show
                            // features users can use, hide features they
                            // can't"). Backed by the user_profiles.role
                            // lookup. When the user IS a streamer, this
                            // still no-ops because the full Whatnot show
                            // management UI is deferred per the conversation
                            // summary's "deferred follow-ups" list.
                            if (isStreamer) {
                                DropdownMenuItem(
                                    text = { Text("Add to Show") },
                                    onClick = {
                                        addMenuOpen = false
                                        scope.launch {
                                            snackbarHostState?.showSnackbar(
                                                "Show management ships in M2 polish",
                                            )
                                        }
                                    },
                                )
                            }
                        }
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        val card = state.card
        if (card == null) {
            BOBAEmptyState(
                headline = "Card not found",
                body = "Couldn't find a card with bobaId `$bobaId`.",
                actionLabel = "Back",
                onAction = onBack,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
            return@Scaffold
        }
        CardDetailBody(
            card = card,
            state = state,
            onOpenOtherVersion = onOpenOtherVersion,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        )
    }

    if (addToCollectionOpen) {
        state.card?.let { card ->
            val collectionViewModel: com.bobaplaybook.app.feature.collection.CollectionViewModel = hiltViewModel()
            com.bobaplaybook.app.feature.collection.AddToCollectionSheet(
                card = card,
                onDismiss = { addToCollectionOpen = false },
                onSubmit = { input ->
                    addToCollectionOpen = false
                    collectionViewModel.add(input.cardBobaId, input.designation)
                    scope.launch {
                        snackbarHostState.showSnackbar("Added ${card.displayName} to ${input.designation.label}")
                    }
                },
            )
        }
    }

    if (addToDeckOpen) {
        state.card?.let { card ->
            com.bobaplaybook.app.feature.decks.AddToDeckSheet(
                card = card,
                onDismiss = { addToDeckOpen = false },
            )
        }
    }
}

@Composable
private fun CardDetailBody(
    card: Card,
    state: CardDetailUiState,
    onOpenOtherVersion: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()),
    ) {
        ArtPanel(card)

        // Badge row — weapon / treatment / set. iOS DESIGN.md §8.6
        // renders these above the stats grid as a quick scan affordance.
        BadgeRow(card = card)

        // Athlete inspiration — when present, surfaced as a one-line
        // "Inspired by {athlete}" with an element-tinted accent rail.
        card.athleteInspiration?.takeIf { it.isNotBlank() }?.let { athlete ->
            AthleteInspirationRow(athlete = athlete, card = card)
        }

        BOBAStatsGrid(
            cardNumber = card.cardNumber,
            cardType   = card.cardType,
            treatment  = card.treatment,
            weapon     = card.element.takeIf { !card.isSealed }?.lowercase()?.replaceFirstChar { it.uppercase() },
            set        = card.set,
            subSet     = card.subSet,
        )

        // Power + cost + DBS — big arena-font hero stat. iOS DESIGN.md
        // §8.6 (Card detail) renders the primary number large + element-
        // tinted so coaches read it at a glance.
        HeroStatRow(card = card)

        // Format restrictions — only renders when the card has at least
        // one. iOS CardDetailView.formatRestrictionsBlock. Empty for the
        // typical sub-160 Hero / base-Set Play.
        FormatRestrictionsBlock(card = card)

        // Ability/Bonus text when present
        card.abilityText?.takeIf { it.isNotBlank() }?.let { text ->
            BOBASectionHeader(title = "Ability")
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        card.bonusText?.takeIf { it.isNotBlank() }?.let { text ->
            BOBASectionHeader(title = "Bonus")
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }

        HorizontalDivider(
            modifier = Modifier.padding(vertical = 16.dp),
            color = MaterialTheme.colorScheme.outlineVariant,
        )

        // Pricing
        PricingPanels(state = state)

        // Other versions (same hero, different treatments)
        if (state.otherVersions.isNotEmpty()) {
            HorizontalDivider(
                modifier = Modifier.padding(vertical = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            BOBASectionHeader(title = "Other versions of ${card.displayName}")
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(items = state.otherVersions, key = { it.bobaId }) { other ->
                    Box(modifier = Modifier.width(80.dp)) {
                        BOBACardCell(
                            imageFile = other.imageFile,
                            contentDescription = other.displayName,
                            modifier = Modifier.clickable {
                                onOpenOtherVersion(other.bobaId)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun BadgeRow(card: Card) {
    val element = card.element.takeIf { !card.isSealed }?.lowercase()?.replaceFirstChar { it.uppercase() }
    val treatment = card.treatment?.takeIf { it.isNotBlank() }
    val setName = card.set.takeIf { it.isNotBlank() }
    if (element == null && treatment == null && setName == null) return
    androidx.compose.foundation.layout.FlowRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (element != null) {
            val accent = com.bobaplaybook.core.ui.theme.BobaElements.forElement(card.element)
            androidx.compose.material3.AssistChip(
                onClick = {},
                label = { Text(element) },
                leadingIcon = {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .background(accent, androidx.compose.foundation.shape.CircleShape),
                    )
                },
            )
        }
        treatment?.let {
            androidx.compose.material3.AssistChip(onClick = {}, label = { Text(it) })
        }
        setName?.let {
            androidx.compose.material3.AssistChip(onClick = {}, label = { Text(it) })
        }
        // "INSPIRED INK" capsule for serialized variants
        if (card.treatment?.lowercase()?.contains("inspired ink") == true) {
            androidx.compose.material3.Surface(
                shape = MaterialTheme.shapes.small,
                color = com.bobaplaybook.core.ui.theme.BobaBrand.Violet.copy(alpha = 0.18f),
            ) {
                Text(
                    text = "INSPIRED INK",
                    style = MaterialTheme.typography.labelSmall,
                    color = com.bobaplaybook.core.ui.theme.BobaBrand.Violet,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }
    }
}

/**
 * Format restrictions block. iOS CardDetailView.formatRestrictionsBlock —
 * surfaces ONLY when a card has at least one per-card format
 * restriction (Spec-ineligible Heroes, Bonus Plays, HTD Plays,
 * Trainers). 99% of cards render nothing here.
 *
 * Deck-level legality (DBS budget, count caps) stays in the Decks tab.
 */
@Composable
private fun FormatRestrictionsBlock(card: Card) {
    val notes = remember(card.bobaId) {
        com.bobaplaybook.core.domain.model.CardFormatEligibility.restrictions(card)
    }
    if (notes.isEmpty()) return
    val amber = com.bobaplaybook.core.ui.theme.BobaBrand.Orange
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            "FORMAT RESTRICTIONS",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold,
        )
        androidx.compose.material3.Surface(
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.surfaceContainer,
            border = androidx.compose.foundation.BorderStroke(
                1.dp,
                amber.copy(alpha = 0.35f),
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(vertical = 4.dp),
            ) {
                notes.forEach { note ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = androidx.compose.material.icons.Icons.Default.Bolt,
                            contentDescription = null,
                            tint = amber,
                            modifier = Modifier.size(16.dp),
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                note.label,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                color = amber,
                            )
                            Text(
                                note.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Hero-stat row. iOS CardDetailView's title-row trailing slot renders
 * the primary stat at arena-font 36pt, element-tinted: Power for
 * Heroes, Hot Dog cost for Plays. Android translates that to its own
 * top-of-body stat block.
 *
 * Nothing renders when the card has no meaningful stat (Sealed
 * Products, hero-only Coach cards w/ no power).
 */
@Composable
private fun HeroStatRow(card: Card) {
    // Decide what's primary based on card type.
    data class Stat(val number: String, val label: String, val color: androidx.compose.ui.graphics.Color)
    val primary: Stat? = when {
        card.cardType.equals("Hero", ignoreCase = true) -> {
            val power = card.power
            if (power != null && power > 0) {
                Stat(
                    number = "$power",
                    label = "POWER",
                    color = com.bobaplaybook.core.ui.theme.BobaElements.forElement(card.element),
                )
            } else null
        }
        card.cardType.contains("Play", ignoreCase = true) -> {
            val cost = card.cost
            if (cost != null) {
                if (cost == 0) {
                    Stat(
                        number = "FREE",
                        label = "COST",
                        color = androidx.compose.ui.graphics.Color(0xFF7ECB82),
                    )
                } else {
                    Stat(
                        number = "$cost",
                        label = if (cost == 1) "HOT DOG" else "HOT DOGS",
                        color = com.bobaplaybook.core.ui.theme.BobaBrand.Cyan,
                    )
                }
            } else null
        }
        else -> null
    }
    if (primary == null && card.dbs == null) return
    var dbsInfoOpen by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (primary != null) {
            Column(horizontalAlignment = androidx.compose.ui.Alignment.Start) {
                Text(
                    text = primary.number,
                    style = MaterialTheme.typography.displaySmall,
                    color = primary.color,
                )
                Text(
                    text = primary.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        // DBS — Play-card-specific secondary stat. Tap opens an
        // explainer sheet (iOS parity: ProfileView.swift DBSInfoSheet).
        card.dbs?.let { dbs ->
            Column(
                horizontalAlignment = androidx.compose.ui.Alignment.Start,
                modifier = Modifier
                    .clip(MaterialTheme.shapes.small)
                    .clickable { dbsInfoOpen = true }
                    .padding(4.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "+$dbs",
                        style = MaterialTheme.typography.headlineMedium,
                        color = com.bobaplaybook.core.ui.theme.BobaBrand.Violet,
                    )
                    Spacer(Modifier.width(4.dp))
                    Icon(
                        imageVector = Icons.Default.Info,
                        contentDescription = "What is DBS?",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(14.dp),
                    )
                }
                Text(
                    text = "DBS",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
    if (dbsInfoOpen) {
        DBSInfoSheet(onDismiss = { dbsInfoOpen = false })
    }
}

/**
 * What-is-DBS explainer. Triggered from the DBS stat cell on Plays.
 * Copy ported from iOS DBSInfoSheet (BOBAPlaybook/Views/Search/
 * CardDetailView.swift) so iOS+Android stay in sync. Sourced from
 * the 2026-04-22 Discord terminology handoff §4.1.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun DBSInfoSheet(onDismiss: () -> Unit) {
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                "What is DBS?",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                "The Deck Balancing System is a scoring system used in " +
                    "Nationals-style formats to keep high-powered plays " +
                    "from crowding out the rest of a deck.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            listOf(
                "Every Play card has a DBS score.",
                "Your deck's total DBS across all 30 Plays must be ≤ 1,000 in formats that enforce it.",
                "High-DBS plays are individually powerful but force you to fill the rest of the deck with low-DBS plays to stay under budget.",
                "Non-Nationals formats (Rookie, Substitution, Playmaker) ignore DBS entirely — it's only a constraint when a format opts in.",
            ).forEach { bullet ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "•",
                        color = com.bobaplaybook.core.ui.theme.BobaBrand.Orange,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        bullet,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                "DBS tiers",
                style = MaterialTheme.typography.titleSmall,
            )
            androidx.compose.material3.Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column {
                    DbsTierRow("Low", "1–20",
                        androidx.compose.ui.graphics.Color(0xFF7ECB82))
                    DbsTierRow("Medium", "21–40",
                        com.bobaplaybook.core.ui.theme.BobaBrand.Cyan)
                    DbsTierRow("High", "41–60",
                        androidx.compose.ui.graphics.Color(0xFFFFD700))
                    DbsTierRow("Very High", "67+",
                        com.bobaplaybook.core.ui.theme.BobaBrand.Orange)
                }
            }
            Text(
                "The deck builder shows a running DBS total and warns " +
                    "you when you cross the budget — no mental math required.",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun DbsTierRow(label: String, range: String, color: androidx.compose.ui.graphics.Color) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = color,
             fontWeight = FontWeight.Bold)
        Text(range, style = MaterialTheme.typography.labelMedium,
             color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun AthleteInspirationRow(athlete: String, card: Card) {
    val accent = com.bobaplaybook.core.ui.theme.BobaElements.forElement(card.element)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(36.dp)
                .background(accent),
        )
        Column(modifier = Modifier.padding(start = 12.dp)) {
            Text(
                text = "INSPIRED BY",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = athlete,
                style = MaterialTheme.typography.titleMedium,
            )
        }
    }
}

@Composable
private fun ArtPanel(card: Card) {
    val context = LocalContext.current
    val accent = if (card.isSealed) BobaBrand.Orange else BobaElements.forElement(card.element)
    // Pinch-to-zoom + double-tap-to-reset. iOS CardDetailView.swift
    // lines 461-490 use the same pattern (MagnificationGesture + drag
    // when scale > 1 + double-tap to reset). M3 equivalent uses
    // transformable + pointerInput for the double-tap reset.
    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    val transformState = androidx.compose.foundation.gestures.rememberTransformableState { zoomChange, panChange, _ ->
        scale = (scale * zoomChange).coerceIn(1f, 6f)
        if (scale > 1f) {
            offset += panChange
        } else {
            offset = androidx.compose.ui.geometry.Offset.Zero
        }
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(420.dp)
            .background(
                Brush.verticalGradient(
                    colors = listOf(accent.copy(alpha = 0.25f), BobaBrand.NearBlack),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        val fullUrl = remember(card.imageFile) { CDN.fullUrl(card.imageFile) }
        if (fullUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(fullUrl)
                    .crossfade(200)
                    .build(),
                contentDescription = card.displayName,
                modifier = Modifier
                    .aspectRatio(5f / 7f)
                    .clip(MaterialTheme.shapes.large)
                    .cardSharedBounds(card.bobaId)
                    .graphicsLayer(
                        scaleX = scale,
                        scaleY = scale,
                        translationX = offset.x,
                        translationY = offset.y,
                    )
                    .transformable(state = transformState)
                    .pointerInput(card.bobaId) {
                        detectTapGestures(
                            onDoubleTap = {
                                scale = if (scale > 1f) 1f else 2.5f
                                offset = androidx.compose.ui.geometry.Offset.Zero
                            },
                        )
                    },
            )
        } else {
            Text(
                text = card.displayName,
                style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.cardSharedBounds(card.bobaId),
            )
        }
    }
}

@Composable
private fun PricingPanels(state: CardDetailUiState) {
    if (state.isLoadingPricing) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
        return
    }

    // Market estimate header
    state.marketEstimateUsd?.let { est ->
        BOBASectionHeader(title = "Market estimate")
        Text(
            text = "~$${"%.2f".format(est)}",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp),
        )
        state.marketEstimateBasis?.let { basis ->
            Text(
                text = basis,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
    }

    BOBASectionHeader(title = "Buy Now")
    if (state.ebayActive.isEmpty()) {
        Text(
            text = "No active listings",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
    } else {
        ListingsRow(listings = state.ebayActive)
    }

    BOBASectionHeader(title = "Sold history")
    val sold = state.ebaySold.distinctBy { it.url }
    if (sold.isEmpty()) {
        Text(
            text = "No sold-comp data yet",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
    } else {
        ListingsRow(listings = kotlinx.collections.immutable.persistentListOf<PricingListing>().addAll(sold))
    }
}

@Composable
private fun ListingsRow(listings: ImmutableList<PricingListing>) {
    val context = LocalContext.current
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(items = listings, key = { it.url }) { listing ->
            BOBAPriceTile(
                priceUsd = listing.priceUsd,
                title = listing.title,
                thumbUrl = listing.thumbUrl,
                source = listing.source.name.lowercase().replaceFirstChar { it.uppercase() },
                onClick = {
                    if (listing.url.isNotBlank()) {
                        val intent = Intent(Intent.ACTION_VIEW, listing.url.toUri())
                        context.startActivity(intent)
                    }
                },
            )
        }
    }
}

