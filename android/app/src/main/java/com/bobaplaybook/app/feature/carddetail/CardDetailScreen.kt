@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)

package com.bobaplaybook.app.feature.carddetail

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Share
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ContainedLoadingIndicator
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
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
import com.bobaplaybook.core.domain.model.CardFormatEligibility
import com.bobaplaybook.core.network.CDN
import com.bobaplaybook.core.network.PricingListing
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
import com.bobaplaybook.core.ui.components.BOBAPriceTile
import com.bobaplaybook.core.ui.format.formatUsdAmount
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
    // ─── Swipe-nav between sibling cards (parity w/ iOS CardDetailView.swift) ───
    // Find / Decks / Collection populate CardNavigationStore.set(visibleIds)
    // before pushing. We seed `currentBobaId` with the incoming route arg
    // and let horizontal swipes advance the index in-place — no re-push.
    // If the store is empty (deep link, hero-zoom from somewhere we
    // haven't wired yet) swipes are no-ops and the row collapses to a
    // plain detail view.
    val navStore: CardNavigationStore = hiltViewModel<CardNavigationHolderViewModel>().store
    val siblingIds by navStore.bobaIds.collectAsStateWithLifecycle()
    var currentBobaId by remember(bobaId) { mutableStateOf(bobaId) }
    // Tick 329 — Ctrl+→ / Ctrl+← keyboard shortcut nav (iPad iOS
    // Cmd+arrow tick 287 + web ArrowLeft/Right parity). BOBAApp root
    // emits +1/-1; this LaunchedEffect walks the index with the same
    // wrap-around math as the swipe gesture below.
    LaunchedEffect(Unit) {
        navStore.requestAdvance.collect { delta ->
            val ids = siblingIds
            if (ids.size <= 1) return@collect
            val idx = ids.indexOf(currentBobaId)
            if (idx < 0) return@collect
            val n = ids.size
            currentBobaId = ids[((idx + delta) % n + n) % n]
        }
    }
    // Tick 331 — flag for the root keyboard handler so Ctrl+arrow only
    // consumes the keystroke when this screen is in the composition.
    // Otherwise typing Ctrl+→ in Find's search field would silently
    // lose the "next-word" behavior to a no-op nav request.
    DisposableEffect(Unit) {
        navStore.setOnDetail(true)
        onDispose { navStore.setOnDetail(false) }
    }
    val state by remember(currentBobaId) { viewModel.uiStateFor(currentBobaId) }
        .collectAsStateWithLifecycle()
    val decksViewModel: com.bobaplaybook.app.feature.decks.DecksViewModel = hiltViewModel()
    val profileViewModel: com.bobaplaybook.app.feature.profile.ProfileViewModel = hiltViewModel()
    val profile by profileViewModel.profile.collectAsStateWithLifecycle(initialValue = null)
    LaunchedEffect(Unit) { profileViewModel.refreshProfile() }
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
                    // Tick 400 — BOBAIconTooltip helper.
                    BOBAIconTooltip("Share card") {
                        IconButton(onClick = {
                            state.card?.let { c ->
                                scope.launch { CardShareHelper.share(context, c) }
                            }
                        }) {
                            Icon(Icons.Default.Share, contentDescription = "Share")
                        }
                    }
                    Box {
                        BOBAIconTooltip("Add to Collection, Deck, or Show") {
                            IconButton(onClick = { addMenuOpen = true }) {
                                Icon(Icons.Default.Add, contentDescription = "Add")
                            }
                        }
                        DropdownMenu(
                            expanded = addMenuOpen,
                            onDismissRequest = { addMenuOpen = false },
                        ) {
                            // Tick 474 — leading icons on each menu item, iOS
                            // CardDetailView parity (Label("To Collection",
                            // systemImage: "folder.badge.plus")). LibraryAdd
                            // for collection, PlaylistAdd for deck, LiveTv
                            // for streamer-only show.
                            DropdownMenuItem(
                                text = { Text("Add to Collection") },
                                leadingIcon = {
                                    Icon(Icons.Default.LibraryAdd, contentDescription = null)
                                },
                                onClick = {
                                    addMenuOpen = false
                                    addToCollectionOpen = true
                                },
                            )
                            // Tick 481 — gate "Add to Deck" on deckable card
                            // types (iOS + web parity). Sealed Products aren't
                            // playable cards, so the option just leads to a
                            // confused "you can't add this" state.
                            val cardForGate = state.card
                            val isDeckable = cardForGate != null &&
                                (cardForGate.isHero || cardForGate.isPlay || cardForGate.isHotDog)
                            if (isDeckable) {
                                DropdownMenuItem(
                                    text = { Text("Add to Deck") },
                                    leadingIcon = {
                                        Icon(Icons.Default.PlaylistAdd, contentDescription = null)
                                    },
                                    onClick = {
                                        addMenuOpen = false
                                        addToDeckOpen = true
                                    },
                                )
                            }
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
                                    leadingIcon = {
                                        Icon(Icons.Default.LiveTv, contentDescription = null)
                                    },
                                    onClick = {
                                        addMenuOpen = false
                                        scope.launch {
                                            snackbarHostState.showSnackbar(
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
                body = "Couldn't find a card with bobaId `$currentBobaId`.",
                actionLabel = "Back",
                onAction = onBack,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
            return@Scaffold
        }
        // Horizontal-drag gesture advances the index in [siblingIds].
        // `detectHorizontalDragGestures` uses horizontal touch slop so
        // a vertical-mostly drag never starts the recognizer — the
        // body's vertical scroll wins. Only fires when there's at
        // least one sibling to navigate to. Mirrors iOS
        // CardDetailView.swift simultaneousGesture with ±60pt threshold.
        // Tick 291 — TextHandleMove haptic on every successful card swap
        // gives a subtle tactile "stuck" feel that confirms the swipe
        // registered without competing with the existing button-tap
        // haptics. Same idiom as Find long-press add (tick 249).
        val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
        val swipeMod = if (siblingIds.size > 1) {
            Modifier.pointerInput(siblingIds, currentBobaId) {
                var totalDx = 0f
                val threshold = 80.dp.toPx()
                detectHorizontalDragGestures(
                    onDragStart = { totalDx = 0f },
                    onDragEnd = {
                        if (kotlin.math.abs(totalDx) < threshold) return@detectHorizontalDragGestures
                        val idx = siblingIds.indexOf(currentBobaId)
                        if (idx < 0) return@detectHorizontalDragGestures
                        val n = siblingIds.size
                        val delta = if (totalDx < 0) 1 else -1
                        // Wrap — matches iOS (`(index + delta + n) % n`).
                        currentBobaId = siblingIds[((idx + delta) % n + n) % n]
                        haptic.performHapticFeedback(
                            androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove
                        )
                    },
                ) { _, dragAmount ->
                    totalDx += dragAmount
                }
            }
        } else Modifier
        CardDetailBody(
            card = card,
            state = state,
            onOpenOtherVersion = onOpenOtherVersion,
            onRefreshPricing = { viewModel.refreshPricing(card.bobaId) },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .then(swipeMod),
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
                    // Pass through the full form input (tick 99). Previously
                    // quantity / purchasePrice / askingPrice / condition /
                    // notes were silently discarded — user filled out the
                    // form expecting it to save and only the bobaId +
                    // designation actually landed.
                    collectionViewModel.add(
                        cardBobaId    = input.cardBobaId,
                        designation   = input.designation,
                        quantity      = input.quantity,
                        purchasePrice = input.purchasePriceUsd,
                        askingPrice   = input.askingPriceUsd,
                        condition     = input.condition,
                        notes         = input.notes,
                    )
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
    onRefreshPricing: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Re-resolve the app-scoped snackbar host + coroutine scope so the
    // "Decks with this card" tap-to-load (tick 149) can fire Snackbar
    // feedback from inside this sub-Composable. The outer
    // CardDetailScreen declares its own copies; redeclaring here keeps
    // CardDetailBody's signature stable.
    val snackbarHostState = LocalAppSnackbar.current
        ?: remember { androidx.compose.material3.SnackbarHostState() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
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

        // Format-legality chip strip (Discord-mined backlog #4, tick 179).
        // 4 chips at-a-glance: Spec · Spec+ · Brawl · Checklist. Most
        // cards show all 4 green. Sealed products hide entirely.
        FormatLegalityStrip(card = card)

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

        // In-your-collection summary — iOS card detail surfaces this
        // so the user always knows whether they already own the card
        // they're looking at + which designation(s) it sits under.
        val collectionVm: com.bobaplaybook.app.feature.collection.CollectionViewModel =
            androidx.hilt.navigation.compose.hiltViewModel()
        val collectionState by collectionVm.uiState.collectAsStateWithLifecycle()
        val ownedEntries = remember(collectionState, card.bobaId) {
            collectionState.entriesByDesignation.values.flatten()
                .filter { it.card.bobaId == card.bobaId }
        }
        if (ownedEntries.isNotEmpty()) {
            // Tick 434 — locale-format the count (web tick 433 parity).
            // Grail farmers can hit 4-digit copies of a Maverick.
            BOBASectionHeader(
                title = "In your collection (${java.text.NumberFormat.getInstance(java.util.Locale.US).format(ownedEntries.size)})",
            )
            val byDesignation = ownedEntries.groupingBy { it.userCard.designation }.eachCount()
            Text(
                text = byDesignation.entries.joinToString(" · ") { (d, n) ->
                    if (n > 1) "${d.label} ×$n" else d.label
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }

        // Pricing
        PricingPanels(state = state, onRefresh = onRefreshPricing)

        // Decks with this card — iOS CollectionCardDetailView parity.
        // Tap a row → loadSaved swaps the current draft to the saved
        // deck. Snackbar confirms (the load triggers a Flow update that
        // re-renders all Decks surfaces, but a confirmation toast
        // anchors the cause-and-effect for the user).
        val decksVmHere: com.bobaplaybook.app.feature.decks.DecksViewModel =
            androidx.hilt.navigation.compose.hiltViewModel()
        val savedDecksForCard by decksVmHere.savedDecks.collectAsStateWithLifecycle(initialValue = emptyList())
        // Pre-load draft state — used to warn the user (with Undo) when
        // tapping a "Decks with this card" row would overwrite a non-
        // empty in-progress draft. Tick 149 — parallels tick 144's
        // DeckManageScreen fix.
        val draftForOverwriteCheck by decksVmHere.draft.collectAsStateWithLifecycle()
        val decksContaining = remember(savedDecksForCard, card) {
            savedDecksForCard.filter { sd ->
                sd.cards.any { it.cardNumber == card.cardNumber }
            }
        }
        if (decksContaining.isNotEmpty()) {
            HorizontalDivider(
                modifier = Modifier.padding(vertical = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            BOBASectionHeader(title = "Decks with this card (${decksContaining.size})")
            // For tap-to-load — needs the full catalog so DeckStore
            // can resolve cardNumbers back to Card objects.
            val catalogForDeckLoad: com.bobaplaybook.core.data.catalog.CardRepository =
                remember { com.bobaplaybook.app.feature.scan.ScanModuleAccess.cardRepository }
            val catalog by catalogForDeckLoad.cards.collectAsStateWithLifecycle()
            decksContaining.forEach { deck ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            val captured = if (draftForOverwriteCheck.cards.isNotEmpty())
                                draftForOverwriteCheck else null
                            decksVmHere.loadSaved(deck, catalog)
                            scope.launch {
                                if (captured != null) {
                                    val result = snackbarHostState.showSnackbar(
                                        message = "Loaded \"${deck.name}\" — your previous draft was replaced.",
                                        actionLabel = "Undo",
                                        duration = androidx.compose.material3.SnackbarDuration.Short,
                                    )
                                    if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                                        decksVmHere.restoreDraft(captured)
                                    }
                                } else {
                                    snackbarHostState.showSnackbar("Loaded \"${deck.name}\" into the Decks editor")
                                }
                            }
                        }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(deck.name, style = MaterialTheme.typography.titleSmall)
                        deck.archetype?.takeIf { it.isNotBlank() }?.let { arch ->
                            Text(
                                arch,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    val qty = deck.cards.firstOrNull { it.cardNumber == card.cardNumber }?.quantity ?: 0
                    if (qty > 1) {
                        Text(
                            "×$qty",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    // Trailing chevron — signals the row is tappable
                    // (without it the row reads as a list display).
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // Other versions (same hero, different treatments)
        if (state.otherVersions.isNotEmpty()) {
            HorizontalDivider(
                modifier = Modifier.padding(vertical = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            BOBASectionHeader(title = "Other versions of ${card.displayName}")
            // Pre-compute the bobaIds the user owns / wants so the per-
            // row lookup is O(1) instead of re-walking entriesByDesignation
            // on every item recompose. iOS CardDetailView::variationsSection
            // does the same (the per-tile indicator helps users see at a
            // glance "I already have 2 of these treatments").
            val ownedBobaIds = remember(collectionState) {
                collectionState.entriesByDesignation.values.flatten()
                    .filter { it.userCard.designation in setOf(
                        com.bobaplaybook.core.domain.model.Designation.PERSONAL,
                        com.bobaplaybook.core.domain.model.Designation.FOR_SALE,
                        com.bobaplaybook.core.domain.model.Designation.FOR_TRADE,
                    ) }
                    .map { it.card.bobaId }.toSet()
            }
            val wantedBobaIds = remember(collectionState) {
                collectionState.entriesByDesignation.values.flatten()
                    .filter { it.userCard.designation in setOf(
                        com.bobaplaybook.core.domain.model.Designation.WANTED,
                        com.bobaplaybook.core.domain.model.Designation.GRAILS,
                    ) }
                    .map { it.card.bobaId }.toSet()
            }
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(items = state.otherVersions, key = { it.bobaId }) { other ->
                    Column(
                        modifier = Modifier.width(80.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Box {
                            BOBACardCell(
                                imageFile = other.imageFile,
                                contentDescription = other.displayName,
                                isSealed = other.isSealed,
                                modifier = Modifier.clickable {
                                    onOpenOtherVersion(other.bobaId)
                                },
                            )
                            // Owned/Wanted indicator overlay — iOS parity.
                            // Owned wins when both flags fire (a user could
                            // theoretically have both a Personal copy AND
                            // a Wanted entry for the same bobaId).
                            val isOwned = other.bobaId in ownedBobaIds
                            val isWanted = other.bobaId in wantedBobaIds
                            if (isOwned || isWanted) {
                                Icon(
                                    imageVector = if (isOwned) Icons.Default.CheckCircle else Icons.Default.Star,
                                    contentDescription = if (isOwned) "Owned" else "Wanted",
                                    // 0xFF4CAF50 = the same Material success-
                                    // green iOS uses (Color(hex:"4CAF50")) so
                                    // owned/wanted indicators feel identical
                                    // across platforms.
                                    tint = if (isOwned) androidx.compose.ui.graphics.Color(0xFF4CAF50)
                                           else BobaBrand.Orange,
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .padding(4.dp)
                                        .size(16.dp),
                                )
                            }
                        }
                        // Treatment / set label — iOS CardDetailView
                        // variationsSection renders this under the
                        // thumb so the user can tell base from
                        // Battlefoil from Inspired Ink at a glance.
                        val label = other.treatment?.takeIf { it.isNotBlank() } ?: other.set
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
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
        // Tick 189 — Discord backlog #7: print-run / SSP / "/N" badge
        // for serialized + super-short-print cards. Null for the typical
        // Base Set / Battlefoil card.
        // Tick 379 — wrap in TooltipBox so tapping the chip explains
        // what /5 / /10 / /25 / /50 / SSP / Serial each mean. Casual
        // users don't auto-know the BoBA Inspired Ink convention; the
        // tooltip carries the DECISIONS.md #028 spec inline. Matches
        // the FormatLegalityChip pattern above.
        card.printRunLabel?.let { label ->
            val accent = if (label == "SSP")
                com.bobaplaybook.core.ui.theme.BobaBrand.Orange
            else com.bobaplaybook.core.ui.theme.BobaBrand.Cyan
            val tooltipState = androidx.compose.material3.rememberTooltipState()
            val tooltipScope = androidx.compose.runtime.rememberCoroutineScope()
            val explanation = when (label) {
                "SSP"    -> "Superfoil — Super-Short-Print, BoBA's rarest non-numbered treatment."
                "/5"     -> "Inspired Ink Hex — limited run of 5 copies (BoBA's rarest serialized treatment)."
                "/10"    -> "Inspired Ink Glow — limited run of 10 copies."
                "/25"    -> "Inspired Ink Fire — limited run of 25 copies."
                "/50"    -> "Inspired Ink Ice — limited run of 50 copies."
                "Serial" -> "Inspired Ink — serialized run; print number not publicly disclosed."
                else     -> "$label print run."
            }
            androidx.compose.material3.TooltipBox(
                positionProvider = androidx.compose.material3.TooltipDefaults
                    .rememberTooltipPositionProvider(
                        androidx.compose.material3.TooltipAnchorPosition.Above
                    ),
                tooltip = { PlainTooltip { Text(explanation) } },
                state = tooltipState,
            ) {
                androidx.compose.material3.Surface(
                    shape = MaterialTheme.shapes.small,
                    color = accent.copy(alpha = 0.18f),
                    border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.45f)),
                    modifier = Modifier.clickable {
                        tooltipScope.launch { tooltipState.show() }
                    },
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelSmall,
                        color = accent,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
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
        CardFormatEligibility.restrictions(card)
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
                            imageVector = Icons.Default.Bolt,
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
 * Format-legality chip strip (Discord-mined backlog #4, tick 179).
 *
 * Discord §11 finding: ~30-35% of rules Qs are "is this legal in Spec /
 * Spec+ / Brawl / Checklist?" 4 chips, at-a-glance, dot-coded:
 * green = legal, amber = constrained, red = illegal. Long-press a chip
 * for the reason (TooltipBox).
 *
 * Sealed products hide entirely (no format semantics).
 */
@Composable
private fun FormatLegalityStrip(card: Card) {
    val chips = remember(card.bobaId) {
        CardFormatEligibility.legalFormats(card)
    }
    if (chips.isEmpty()) return
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        chips.forEach { chip ->
            FormatLegalityChip(chip)
        }
    }
}

@Composable
private fun FormatLegalityChip(chip: com.bobaplaybook.core.domain.model.FormatLegality) {
    val color = when (chip.status) {
        com.bobaplaybook.core.domain.model.FormatStatus.LEGAL ->
            androidx.compose.ui.graphics.Color(0xFF4CAF50)
        com.bobaplaybook.core.domain.model.FormatStatus.CONSTRAINED ->
            com.bobaplaybook.core.ui.theme.BobaBrand.Orange
        com.bobaplaybook.core.domain.model.FormatStatus.ILLEGAL ->
            androidx.compose.ui.graphics.Color(0xFFE53935)
    }
    val tooltipState = androidx.compose.material3.rememberTooltipState()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    // `PlainTooltip` is a TooltipScope extension — must be called from
    // inside `tooltip = { ... }` whose receiver is TooltipScope. The
    // fully-qualified path doesn't resolve the extension dispatch.
    // Local val for `reason` works around the cross-module smart-cast
    // limitation (FormatLegality lives in :core:domain).
    val reason = chip.reason
    androidx.compose.material3.TooltipBox(
        positionProvider = androidx.compose.material3.TooltipDefaults
            .rememberTooltipPositionProvider(
                androidx.compose.material3.TooltipAnchorPosition.Above
            ),
        tooltip = {
            PlainTooltip { Text(reason ?: "${chip.format}: legal") }
        },
        state = tooltipState,
    ) {
        androidx.compose.material3.AssistChip(
            onClick = { scope.launch { tooltipState.show() } },
            label = { Text(chip.format, style = MaterialTheme.typography.labelMedium) },
            leadingIcon = {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .background(color, shape = androidx.compose.foundation.shape.CircleShape),
                )
            },
        )
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
        // Tick 186 — Discord backlog #5: pass active draft's DBS context
        // so the sheet can show the per-card "what does adding this do?"
        // line. Draft state lives in the screen-scoped DecksViewModel as
        // a top-level `draft: StateFlow<DeckDraft>` — collect it
        // directly. Falls back to static explainer when format doesn't
        // enforce DBS.
        val decksVm: com.bobaplaybook.app.feature.decks.DecksViewModel =
            androidx.hilt.navigation.compose.hiltViewModel()
        val draft by decksVm.draft.collectAsStateWithLifecycle()
        val showContext = draft.enforcesDBS
        DBSInfoSheet(
            onDismiss = { dbsInfoOpen = false },
            cardDBS    = card.dbs.takeIf { showContext },
            currentDeckDBS = draft.totalDBS.takeIf { showContext },
            dbsBudget  = draft.dbsBudget.takeIf { showContext },
        )
    }
}

/**
 * What-is-DBS explainer. Triggered from the DBS stat cell on Plays.
 * Copy ported from iOS DBSInfoSheet (BOBAPlaybook/Views/Search/
 * CardDetailView.swift) so iOS+Android stay in sync. Sourced from
 * the 2026-04-22 Discord terminology handoff §4.1.
 */
/// Made `internal` (was private) so the Decks editor's DBS chip
/// (tick 134) can route to the same explainer instead of duplicating
/// the copy. Stays in this file because Card detail's DBS chip is
/// still the primary trigger; promote to a shared module if a 3rd
/// caller needs it.
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun DBSInfoSheet(
    onDismiss: () -> Unit,
    /** This card's DBS cost — surfaces the contextual line if set. */
    cardDBS: Int? = null,
    /** Active deck-builder draft's current total DBS, if a draft exists. */
    currentDeckDBS: Int? = null,
    /** Active draft's DBS budget (1000 for Nationals formats). */
    dbsBudget: Int? = null,
) {
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
            // Tick 186 — Discord backlog #5: contextual line at top
            // when card detail opens the sheet and a deck draft exists.
            // Tells coaches "this card is +N DBS; your deck is X/Y;
            // adding it gets you to (X+N)/Y" — replaces the mental math.
            if (cardDBS != null && currentDeckDBS != null && dbsBudget != null) {
                val projected = currentDeckDBS + cardDBS
                val overCap = projected > dbsBudget
                androidx.compose.material3.Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = if (overCap)
                        MaterialTheme.colorScheme.errorContainer
                    else MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            "This card costs +$cardDBS DBS",
                            style = MaterialTheme.typography.titleSmall,
                            color = if (overCap)
                                MaterialTheme.colorScheme.onErrorContainer
                            else MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            "Your deck has $currentDeckDBS / $dbsBudget DBS used.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            if (overCap)
                                "Adding it puts you at $projected / $dbsBudget — over budget."
                            else
                                "Adding it brings you to $projected / $dbsBudget.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (overCap)
                                MaterialTheme.colorScheme.onErrorContainer
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
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
    // Centroid-aware variant — `_` ignores rotation + centroid since
    // we only react to zoom + pan. The 3-arg overload is deprecated;
    // the new centroid-aware signature takes the lambda in the order
    // (centroid: Offset, zoomChange: Float, panChange: Offset,
    // rotationChange: Float) — centroid FIRST, then zoom/pan/rotation.
    // We discard centroid + rotation; keep zoom + pan.
    val transformState = androidx.compose.foundation.gestures.rememberTransformableState { _, zoomChange, panChange, _ ->
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
        // Card-aware so sealed products hit /sealed/optimized/.
        val fullUrl = remember(card.bobaId, card.imageFile) { CDN.fullUrl(card) }
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
private fun PricingPanels(state: CardDetailUiState, onRefresh: () -> Unit) {
    if (state.isLoadingPricing) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp),
            contentAlignment = Alignment.Center,
        ) {
            ContainedLoadingIndicator()
        }
        return
    }

    // Market estimate header — paired with a small refresh affordance
    // so the user can force a fresh Worker fetch (active listings are
    // cached for the lifetime of the screen otherwise).
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = "MARKET ESTIMATE",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp).weight(1f),
        )
        BOBAIconTooltip("Refresh pricing") {
            IconButton(onClick = onRefresh) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = "Refresh pricing",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
    state.marketEstimateUsd?.let { est ->
        Text(
            text = "~$${est.formatUsdAmount()}",
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
        // First-run hint above the first non-empty tile row —
        // teaches that price tiles tap-through to the buyer site
        // (eBay / Radish). Dismissible per HintsStore.
        val hintsVm: com.bobaplaybook.app.hints.HintsViewModel =
            androidx.hilt.navigation.compose.hiltViewModel()
        val tapHintDismissed by hintsVm
            .isDismissed(com.bobaplaybook.app.hints.HintsStore.Ids.CARD_DETAIL_TAP_PRICE)
            .collectAsStateWithLifecycle(initialValue = true)
        if (!tapHintDismissed) {
            com.bobaplaybook.core.ui.components.BOBAHintBanner(
                title = "Tap a price to open",
                body = "Each tile links straight to the listing — eBay for actives + sold comps, Radish when available.",
                onDismiss = {
                    hintsVm.dismiss(com.bobaplaybook.app.hints.HintsStore.Ids.CARD_DETAIL_TAP_PRICE)
                },
            )
        }
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
                date = listing.date,
                onClick = {
                    if (listing.url.isNotBlank()) {
                        // Custom Tab keeps the BOBA back-arrow context
                        // — user taps Back and lands on the card detail
                        // instead of leaving the app entirely. eBay /
                        // Radish handle Custom Tab fine; if the user has
                        // the eBay app installed it still routes there
                        // via the Custom Tab app-handoff.
                        runCatching {
                            androidx.browser.customtabs.CustomTabsIntent.Builder()
                                .build()
                                .launchUrl(context, listing.url.toUri())
                        }.onFailure {
                            // Fallback for devices without a Custom Tabs
                            // provider (rare; AOSP / older Chrome).
                            runCatching {
                                context.startActivity(Intent(Intent.ACTION_VIEW, listing.url.toUri()))
                            }
                        }
                    }
                },
            )
        }
    }
}

