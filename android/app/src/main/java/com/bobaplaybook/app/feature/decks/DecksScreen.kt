@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalFoundationApi::class,
    androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi::class,
)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as lazyItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.feature.find.FindEvent
import com.bobaplaybook.app.feature.find.FindViewModel
import com.bobaplaybook.app.hints.HintsStore
import com.bobaplaybook.app.hints.HintsViewModel
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.adaptive.isCompactWidth
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAHintBanner
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAWordmark
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.transitions.cardSharedBounds
import kotlinx.coroutines.launch

/**
 * Decks tab — the builder (ANDROID-DESIGN.md §8.3).
 *
 * Anatomy:
 *  - Pool grid (full screen background) with FilterChip filter row +
 *    Find's catalog source
 *  - DeckSummaryBar pinned via Scaffold bottomBar (always visible)
 *  - Tap summary → opens ModalBottomSheet editor (M4-polish lands the
 *    full editor; M4 ships the summary + add-to-draft on long-press)
 *  - Long-press a pool card → adds to current draft (canonical mobile
 *    add gesture per ANDROID-DESIGN.md §8.3)
 *  - Tap a pool card → push to card detail (with container transform)
 */
@Composable
fun DecksScreen(
    onCardClick: (bobaId: String) -> Unit,
    onOpenManage: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
    onSignInRequest: () -> Unit = {},
    onScanClick: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    if (isCompactWidth()) {
        DecksCompactScreen(
            onCardClick = onCardClick,
            onOpenManage = onOpenManage,
            onOpenRules = onOpenRules,
            onOpenLegality = onOpenLegality,
            onSignInRequest = onSignInRequest,
            onScanClick = onScanClick,
            modifier = modifier,
        )
    } else {
        DecksTabletScreen(
            onCardClick = onCardClick,
            onOpenManage = onOpenManage,
            onOpenRules = onOpenRules,
            onOpenLegality = onOpenLegality,
            onSignInRequest = onSignInRequest,
            modifier = modifier,
        )
    }
}

@Composable
private fun DecksCompactScreen(
    onCardClick: (bobaId: String) -> Unit,
    onOpenManage: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
    onSignInRequest: () -> Unit,
    onScanClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val findViewModel: FindViewModel = hiltViewModel()
    val findState by findViewModel.uiState.collectAsStateWithLifecycle()
    val deckViewModel: DecksViewModel = hiltViewModel()
    val draft by deckViewModel.draft.collectAsStateWithLifecycle()
    val authState by deckViewModel.authState.collectAsStateWithLifecycle()
    val isSignedIn = authState is com.bobaplaybook.app.auth.AuthState.SignedIn
    // Card-detail swipe-nav siblings — populate the store whenever the
    // pool's filtered list changes so a tap → detail → swipe walks
    // the visible pool. Parity with iOS Decks browser.
    val navHolder: com.bobaplaybook.app.feature.carddetail.CardNavigationHolderViewModel = hiltViewModel()
    LaunchedEffect(findState.results) {
        navHolder.store.set(findState.results.map { it.bobaId })
    }
    val hintsViewModel: HintsViewModel = hiltViewModel()
    val longPressHintDismissed by hintsViewModel
        .isDismissed(HintsStore.Ids.DECKS_LONG_PRESS_TO_ADD)
        .collectAsStateWithLifecycle(initialValue = true)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current
    // Per-tab grid density — was registered in GridDensityStore.Target.DECKS
    // but the pool grid hardcoded Adaptive(minSize=110.dp). iOS DesksView
    // exposes a 1/2/3 column picker via @AppStorage("bp_decksGridColumns_v1");
    // this brings Android to parity.
    val gridDensityVm: com.bobaplaybook.app.settings.GridDensityViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val storedPoolColumns by gridDensityVm
        .columnsFor(com.bobaplaybook.app.settings.GridDensityStore.Target.DECKS)
        .collectAsStateWithLifecycle(initialValue = 0)
    var editorOpen by remember { mutableStateOf(false) }
    var wallOpen by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var templatesOpen by remember { mutableStateOf(false) }
    var clearConfirmOpen by remember { mutableStateOf(false) }
    var poolQuery by rememberSaveable { mutableStateOf("") }

    // Tick 309 — extracted save closure so both the SAVE-pill onSave
    // and the Ctrl+S keyboard listener (BOBAApp root → DecksActions
    // singleton bus) call the same path.
    val saveDeckAction: () -> Unit = {
        deckViewModel.save { errorMessage: String? ->
            if (errorMessage == null) {
                editorOpen = false
                scope.launch {
                    appSnackbar?.showSnackbar("Saved \"${draft.name}\"")
                }
            } else {
                scope.launch {
                    appSnackbar?.showSnackbar(errorMessage)
                }
            }
        }
    }
    // Collect Ctrl+S from the root-level keyboard handler. Only acts
    // when the editor is open + signed in + deck has cards (matches
    // iOS .disabled() rule on SAVE pill).
    val decksActionsVm: DecksActionsHolderViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    LaunchedEffect(Unit) {
        decksActionsVm.bus.savePressed.collect {
            if (editorOpen && isSignedIn && (draft.cards.isNotEmpty())) {
                saveDeckAction()
            }
        }
    }
    // Tick 324 — `n` from root → surface the clear-deck confirm
    // dialog (or no-op if draft is already empty). Matches the
    // existing Clear-button tap behavior at line 326-327.
    LaunchedEffect(Unit) {
        decksActionsVm.bus.clearPressed.collect {
            if (draft.cards.isNotEmpty()) {
                clearConfirmOpen = true
            }
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            CenterAlignedTopAppBar(
                title = { BOBAWordmark() },
                actions = {
                    // Tick 400 — BOBAIconTooltip helper.
                    BOBAIconTooltip("Scan into current deck") {
                        IconButton(onClick = onScanClick) {
                            Icon(
                                imageVector = Icons.Default.QrCodeScanner,
                                contentDescription = "Scan a card",
                            )
                        }
                    }
                    // Editor opens via the bottom DeckSummaryBar drawer.
                    // The duplicate top-bar Edit button was confusing —
                    // there's now exactly one way to open the editor.
                    Box {
                        BOBAIconTooltip("Templates, manage, rules, legality…") {
                            IconButton(onClick = { menuOpen = true }) {
                                Icon(
                                    imageVector = Icons.Default.MoreVert,
                                    contentDescription = "More",
                                )
                            }
                        }
                        DropdownMenu(
                            expanded = menuOpen,
                            onDismissRequest = { menuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Templates") },
                                leadingIcon = { Icon(Icons.Default.Lightbulb, contentDescription = null) },
                                onClick = { menuOpen = false; templatesOpen = true },
                            )
                            DropdownMenuItem(
                                text = { Text("Saved decks") },
                                leadingIcon = { Icon(Icons.Default.Save, contentDescription = null) },
                                onClick = { menuOpen = false; onOpenManage() },
                            )
                            val catalogVm: com.bobaplaybook.app.feature.collection.RainbowCatalogViewModel = hiltViewModel()
                            val catalog by catalogVm.cards.collectAsStateWithLifecycle()
                            val csvPicker = androidx.activity.compose.rememberLauncherForActivityResult(
                                androidx.activity.result.contract.ActivityResultContracts.OpenDocument(),
                            ) { uri ->
                                if (uri == null) return@rememberLauncherForActivityResult
                                importDraftFromCsv(context, uri, catalog, deckViewModel)
                            }
                            DropdownMenuItem(
                                text = { Text("Import (CSV)") },
                                leadingIcon = { Icon(Icons.Default.FileUpload, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    csvPicker.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*"))
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Export (CSV)") },
                                leadingIcon = { Icon(Icons.Default.FileDownload, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    exportDraftAsCsv(context, draft)
                                },
                            )
                            androidx.compose.material3.HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("Deck rules") },
                                leadingIcon = { Icon(Icons.Default.Build, contentDescription = null) },
                                onClick = { menuOpen = false; onOpenRules() },
                            )
                            DropdownMenuItem(
                                text = { Text("Legality") },
                                leadingIcon = { Icon(Icons.Default.Verified, contentDescription = null) },
                                onClick = { menuOpen = false; onOpenLegality() },
                            )
                            // (Tick 391 — dropped duplicate "Scan into deck"
                            // overflow item that was a no-op stub. The top-bar
                            // Scan icon at line 229 is the canonical entry
                            // point — same one-way-in pattern as the editor.)
                            androidx.compose.material3.HorizontalDivider()
                            // Grid density picker — iOS DesksView parity.
                            // Sub-menu would clutter; render the 3 options
                            // inline (iOS pattern). Active row shows a
                            // checkmark via DropdownMenuItem's leadingIcon
                            // slot when matching the current density.
                            Text(
                                "Pool columns",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp),
                            )
                            listOf(1, 2, 3).forEach { col ->
                                DropdownMenuItem(
                                    text = { Text("$col column${if (col > 1) "s" else ""}") },
                                    leadingIcon = {
                                        if (storedPoolColumns == col) {
                                            Icon(Icons.Default.Check, contentDescription = "Active")
                                        } else {
                                            Spacer(modifier = Modifier.width(24.dp))
                                        }
                                    },
                                    onClick = {
                                        menuOpen = false
                                        scope.launch {
                                            gridDensityVm.setColumns(
                                                com.bobaplaybook.app.settings.GridDensityStore.Target.DECKS,
                                                col,
                                            )
                                        }
                                    },
                                )
                            }
                            androidx.compose.material3.HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("Clear draft") },
                                leadingIcon = { Icon(Icons.Default.Clear, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    // Confirm only when there's actual work to lose —
                                    // an empty draft clears silently.
                                    if (draft.cards.isNotEmpty()) clearConfirmOpen = true
                                    else deckViewModel.clear()
                                },
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
        bottomBar = {
            DeckSummaryBar(
                draft = draft,
                onTap = { editorOpen = true },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            if (!longPressHintDismissed) {
                BOBAHintBanner(
                    title = "Long-press to add",
                    body = "Long-press any card to add it to your deck draft. Tap to see card detail instead.",
                    onDismiss = { hintsViewModel.dismiss(HintsStore.Ids.DECKS_LONG_PRESS_TO_ADD) },
                )
            }
            // Pool search — slim single-line filter pill. Matches dense
            // M3 chip aesthetics (no oversized OutlinedTextField label
            // floating above the field).
            DecksPoolSearchPill(
                query = poolQuery,
                onQueryChange = { q ->
                    poolQuery = q
                    findViewModel.onEvent(com.bobaplaybook.app.feature.find.FindEvent.QueryChanged(q))
                },
            )
            CardPoolGrid(
                cards = findState.results,
                searchQuery = poolQuery,
                onClearSearch = {
                    poolQuery = ""
                    findViewModel.onEvent(com.bobaplaybook.app.feature.find.FindEvent.QueryChanged(""))
                },
                columns = storedPoolColumns,
                inDeckBobaIds = remember(draft.cards) { draft.cards.map { it.bobaId }.toSet() },
                onCardClick = onCardClick,
                onCardLongClick = { card ->
                    // Snackbar branches on the actual add outcome
                    // (tick 114 — store enforces caps + dup-checks now).
                    // If the store rejected the add (duplicate / hard
                    // cap), we surface "X — reason" instead of pretending
                    // it landed. iOS tick 112 + web tick 113 use the
                    // same outcome-shape.
                    val result = deckViewModel.add(card)
                    val msg = when (result) {
                        is com.bobaplaybook.app.feature.decks.DeckStore.AddResult.Added -> {
                            // Soft-cap (HD / DBS) warnings still fire on
                            // a successful add — they're not hard rejects,
                            // just legality concerns the user should see
                            // before they tab-switch to the editor.
                            val newHD = draft.totalHD + (card.hd ?: 0)
                            val newDBS = draft.totalDBS + (card.dbs ?: 0)
                            val warn = when {
                                newHD > draft.hdCap -> " — over HD cap"
                                draft.enforcesDBS && newDBS > draft.dbsBudget -> " — over DBS budget"
                                else -> ""
                            }
                            "Added ${card.displayName}$warn"
                        }
                        is com.bobaplaybook.app.feature.decks.DeckStore.AddResult.Skipped ->
                            "${card.displayName} — ${result.reason}"
                    }
                    scope.launch { appSnackbar?.showSnackbar(msg) }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }

    if (editorOpen) {
        DeckEditorSheet(
            draft = draft,
            isSignedIn = isSignedIn,
            onDismiss = { editorOpen = false },
            onRename = deckViewModel::rename,
            onRemove = { bobaId ->
                // Capture the card so an Undo action can re-add it
                // without re-walking the catalog. iOS card-tap-remove
                // also offers undo via the toast.
                val removed = draft.cards.firstOrNull { it.bobaId == bobaId }
                deckViewModel.remove(bobaId)
                if (removed != null) {
                    scope.launch {
                        val result = appSnackbar?.showSnackbar(
                            message = "Removed ${removed.displayName}",
                            actionLabel = "Undo",
                            duration = androidx.compose.material3.SnackbarDuration.Short,
                        )
                        if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                            deckViewModel.add(removed)
                        }
                    }
                }
            },
            onSave = saveDeckAction,
            onSignInRequest = {
                editorOpen = false
                onSignInRequest()
            },
            onGenerateWall = { wallOpen = true },
        )
    }

    if (wallOpen) {
        DeckWallSheet(draft = draft, onDismiss = { wallOpen = false })
    }

    if (templatesOpen) {
        TemplateGallerySheet(onDismiss = { templatesOpen = false })
    }

    if (clearConfirmOpen) {
        // BackHandler-style guard against losing 30 cards to a stray
        // tap. iOS shows an action sheet for the same path. Empty
        // drafts skip the dialog (gated at the menu callback).
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { clearConfirmOpen = false },
            title = { Text("Clear deck draft?") },
            text = {
                Text(
                    "Remove all ${draft.cards.size} cards from the draft. " +
                        "This doesn't affect any saved decks.",
                )
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    // Snapshot the draft BEFORE clearing so the Undo
                    // Snackbar can restore it. Tick 139 — Clear-deck
                    // is a 30-card destructive action; a brief recovery
                    // window matches the Manage Decks delete pattern
                    // shipped in tick 124.
                    val captured = draft
                    deckViewModel.clear()
                    clearConfirmOpen = false
                    scope.launch {
                        val result = appSnackbar?.showSnackbar(
                            message = "Draft cleared",
                            actionLabel = "Undo",
                            duration = androidx.compose.material3.SnackbarDuration.Short,
                        )
                        if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                            deckViewModel.restoreDraft(captured)
                        }
                    }
                }) {
                    Text("Clear", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { clearConfirmOpen = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}

@Composable
private fun CardPoolGrid(
    cards: List<Card>,
    onCardClick: (bobaId: String) -> Unit,
    onCardLongClick: (Card) -> Unit,
    modifier: Modifier = Modifier,
    searchQuery: String = "",
    onClearSearch: (() -> Unit)? = null,
    /**
     * Fixed column count (1/2/3) from the user's per-tab grid-density
     * preference. `0` uses the adaptive minSize default (iOS parity:
     * defaults to ~3 cols on a typical phone, 5-7 on tablet).
     */
    columns: Int = 0,
    /**
     * Bobaids of cards currently in the draft — iOS DeckBuilderView
     * parity (tick 161). Pool cells that are already in the draft get a
     * cyan border + checkmark badge so coaches see at a glance which
     * cards they've already picked.
     */
    inDeckBobaIds: Set<String> = emptySet(),
) {
    if (cards.isEmpty()) {
        // Disambiguate: search-driven empty vs filter-driven empty.
        // When the user typed a query we can offer a one-tap Clear;
        // when no query is active the catalog is being filtered by
        // Find tab state (which the user can't manipulate from here
        // without context-switching) so we just point them there.
        if (searchQuery.isNotBlank()) {
            BOBAEmptyState(
                icon = Icons.Default.SearchOff,
                headline = "No cards match",
                body = "Nothing in the catalog matches \"$searchQuery\". Try a different term or clear the search.",
                actionLabel = onClearSearch?.let { "Clear search" },
                onAction = onClearSearch,
                modifier = modifier,
            )
        } else {
            BOBAEmptyState(
                icon = Icons.Default.SearchOff,
                headline = "No cards in scope",
                body = "Filters set on the Find tab are constraining the catalog. Open Find → Filters and widen or clear them.",
                modifier = modifier,
            )
        }
        return
    }
    // Tick 249 — haptic on long-press → add (parity with Find tab).
    // Pulled outside LazyVerticalGrid since LazyGridScope is non-composable.
    val haptic = LocalHapticFeedback.current
    LazyVerticalGrid(
        modifier = modifier,
        // Sentinel 0 → adaptive (the M3 default that flows with width
        // size class). Non-zero → fixed-count for the user's explicit
        // density choice. iOS DesksView per-tab grid density parity.
        columns = if (columns > 0) GridCells.Fixed(columns)
                  else GridCells.Adaptive(minSize = 110.dp),
        contentPadding = PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(
            items = cards,
            key = { card -> card.bobaId },
            contentType = { "card" },
        ) { card ->
            val isInDeck = card.bobaId in inDeckBobaIds
            Box(
                modifier = Modifier
                    .cardSharedBounds(card.bobaId)
                    .combinedClickable(
                        onClick = { onCardClick(card.bobaId) },
                        onLongClick = {
                            haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                            onCardLongClick(card)
                        },
                    ),
            ) {
                BOBACardCell(
                    imageFile = card.imageFile,
                    isSealed = card.isSealed,
                    contentDescription = card.displayName,
                    printRunLabel = card.printRunLabel,
                    formatLegalityHint = com.bobaplaybook.core.domain.model.CardFormatEligibility.restrictedLegalAbbrev(card),
                )
                // Tick 161 — iOS DeckBuilderView parity. Cards already in
                // the draft get a cyan border + checkmark badge so coaches
                // see at a glance which pool cards they've already picked.
                if (isInDeck) {
                    androidx.compose.foundation.Canvas(
                        modifier = Modifier.matchParentSize(),
                    ) {
                        drawRoundRect(
                            color = BobaBrand.Cyan,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(width = 4.dp.toPx()),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(12.dp.toPx()),
                        )
                    }
                    androidx.compose.foundation.layout.Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(4.dp)
                            .size(20.dp)
                            .background(BobaBrand.Cyan, shape = CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Default.Check,
                            contentDescription = "Already in deck",
                            tint = BobaBrand.NearBlack,
                            modifier = Modifier.size(14.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * Persistent draft summary bar. Pinned at the bottom via Scaffold's
 * bottomBar slot. Tap → opens editor. Per ANDROID-DESIGN.md §8.3
 * the pill is NOT draggable (drag-from-bottom is iOS's anti-pattern).
 */
@Composable
private fun DeckSummaryBar(
    draft: DeckDraft,
    onTap: () -> Unit,
) {
    // Tick 356 — iOS DeckSummaryPill empty-state parity
    // (DecksView.swift:1648 + 1691). When the draft is brand-new
    // (zero cards AND default name), show "Build a deck / Tap to
    // open the editor" + suppress the counts, format pill, and
    // Legal chip. Before this, an empty draft showed
    // "New Deck · 0/8 H · 0/30 P · 0 BP · 0/10 HD · STANDARD · Legal",
    // which buried the call-to-action.
    val hasDraft = draft.cards.isNotEmpty() || draft.name != "New Deck"
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onTap() },
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Edit,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Column(modifier = Modifier.weight(1f)) {
                if (hasDraft) {
                    Text(
                        draft.name,
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "${draft.heroCount}/${draft.heroCap} H · ${draft.playCount + draft.bonusCount}/${draft.playCap} P · ${draft.bonusCount} BP · ${draft.totalHD}/${draft.hdCap} HD",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    Text(
                        "Build a deck",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "Tap to open the editor",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (hasDraft) {
                // Tick 221 — format-name pill (iOS DeckSummaryPill
                // parity, DecksView.swift:1685). Hidden on empty draft
                // per iOS pattern (the pill only renders when hasDraft).
                Text(
                    text = draft.playMode.label,
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 9.sp,
                        letterSpacing = 0.8.sp,
                    ),
                    color = com.bobaplaybook.core.ui.theme.BobaBrand.Orange,
                    modifier = Modifier
                        .background(
                            color = com.bobaplaybook.core.ui.theme.BobaBrand.Orange.copy(alpha = 0.12f),
                            shape = MaterialTheme.shapes.extraSmall,
                        )
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
                if (draft.isStandardLegal) {
                    AssistChip(
                        onClick = onTap,
                        label = { Text("Legal") },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Verified,
                                contentDescription = null,
                                modifier = Modifier.width(16.dp).height(16.dp),
                            )
                        },
                    )
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// Tablet / Chromebook 3-pane: saved decks | pool | editor
// ─────────────────────────────────────────────────────────────────

@Composable
private fun DecksTabletScreen(
    onCardClick: (bobaId: String) -> Unit,
    onOpenManage: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
    onSignInRequest: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val findViewModel: FindViewModel = hiltViewModel()
    val findState by findViewModel.uiState.collectAsStateWithLifecycle()
    val deckViewModel: DecksViewModel = hiltViewModel()
    val draft by deckViewModel.draft.collectAsStateWithLifecycle()
    val authState by deckViewModel.authState.collectAsStateWithLifecycle()
    val isSignedIn = authState is com.bobaplaybook.app.auth.AuthState.SignedIn
    val scope = rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current
    var wallOpen by remember { mutableStateOf(false) }

    if (wallOpen) {
        DeckWallSheet(draft = draft, onDismiss = { wallOpen = false })
    }

    Row(modifier = modifier.fillMaxSize()) {
        // Saved decks sidebar — Supabase-backed via DecksViewModel.savedDecks
        val savedDecks by deckViewModel.savedDecks.collectAsStateWithLifecycle()
        Surface(
            modifier = Modifier
                .width(240.dp)
                .fillMaxSize(),
            color = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            Column(modifier = Modifier.padding(8.dp)) {
                BOBASectionHeader(title = "Saved decks")
                if (savedDecks.isEmpty()) {
                    BOBAEmptyState(
                        icon = Icons.Default.Save,
                        headline = "No saved decks",
                        body = "Sign in + tap Save in the editor to sync decks across iOS, web, and Android.",
                        actionLabel = "Manage",
                        onAction = onOpenManage,
                    )
                } else {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        lazyItems(items = savedDecks, key = { it.id }) { deck ->
                            androidx.compose.material3.ListItem(
                                headlineContent = { Text(deck.name) },
                                supportingContent = {
                                    val total = deck.cards.sumOf { it.quantity }
                                    Text("$total cards", style = MaterialTheme.typography.labelMedium)
                                },
                                modifier = Modifier.clickable { onOpenManage() },
                            )
                        }
                    }
                }
            }
        }

        androidx.compose.material3.VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        // Pool middle column
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxSize(),
        ) {
            // Pool TopAppBar
            TopAppBar(
                title = { BOBAWordmark() },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
            CardPoolGrid(
                cards = findState.results,
                onCardClick = onCardClick,
                onCardLongClick = deckViewModel::add,
                inDeckBobaIds = remember(draft.cards) { draft.cards.map { it.bobaId }.toSet() },
                modifier = Modifier.fillMaxSize(),
            )
        }

        androidx.compose.material3.VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        // Editor pane (always visible on tablet — no sheet needed)
        Surface(
            modifier = Modifier
                .width(380.dp)
                .fillMaxSize(),
            color = MaterialTheme.colorScheme.surface,
        ) {
            // Reuse the editor body content directly (without the sheet
            // wrapper) so it lives in the pane.
            DeckEditorContentInline(
                draft = draft,
                isSignedIn = isSignedIn,
                onRename = deckViewModel::rename,
                onRemove = { bobaId ->
                    // Snackbar + Undo on remove — tablet parity with
                    // the compact-pane flow (DecksScreen.kt:374).
                    // Without this the tablet user lost the cap-restore
                    // signal compact users had.
                    val removed = draft.cards.firstOrNull { it.bobaId == bobaId }
                    deckViewModel.remove(bobaId)
                    if (removed != null) {
                        scope.launch {
                            val result = appSnackbar?.showSnackbar(
                                message = "Removed ${removed.displayName}",
                                actionLabel = "Undo",
                                duration = androidx.compose.material3.SnackbarDuration.Short,
                            )
                            if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                                deckViewModel.add(removed)
                            }
                        }
                    }
                },
                onSave = {
                    // Snackbar feedback — symmetric with the compact
                    // path (line 391). Tablet pane stays open after
                    // save (no editor-sheet to dismiss), but the user
                    // still needs a signal that the save persisted.
                    // Tick 154 — was firing fire-and-forget save with
                    // no UI feedback, so users couldn't tell if the
                    // server write actually landed.
                    deckViewModel.save { errorMessage: String? ->
                        scope.launch {
                            appSnackbar?.showSnackbar(
                                errorMessage ?: "Saved \"${draft.name}\""
                            )
                        }
                    }
                },
                onSignInRequest = onSignInRequest,
                onOpenRules = onOpenRules,
                onOpenLegality = onOpenLegality,
                onGenerateWall = { wallOpen = true },
            )
        }
    }
}

/**
 * Dense single-line search pill — Surface + Row + TextField on one
 * baseline. No floating label, no border. Sized to match M3 dense
 * filter-row guidance (44dp content area, 8dp side padding).
 */
@Composable
private fun DecksPoolSearchPill(
    query: String,
    onQueryChange: (String) -> Unit,
) {
    androidx.compose.material3.Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.extraLarge,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.Search,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = 8.dp),
            )
            androidx.compose.foundation.text.BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(
                    color = MaterialTheme.colorScheme.onSurface,
                ),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                modifier = Modifier
                    .weight(1f)
                    .padding(vertical = 12.dp),
                decorationBox = { inner ->
                    if (query.isEmpty()) {
                        Text(
                            "Search cards…",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    inner()
                },
            )
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(Icons.Default.Clear, contentDescription = "Clear", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/**
 * Export the current draft as CSV in the canonical v2 shape
 * (DECISIONS.md #033 part b). Fires the Android share sheet with the
 * CSV body as text — receivers like Google Drive / Gmail / Files
 * accept text directly. v1 bobaleagues-compat legacy format is
 * deferred (the v2 format is what roundtrips correctly).
 *
 * CSV columns: id,name,type,release,number,cost,dbs,ability,bonus
 */
private fun exportDraftAsCsv(context: android.content.Context, draft: DeckDraft) {
    val header = "id,name,type,release,number,cost,dbs,ability,bonus"
    val rows = draft.cards.map { c ->
        listOf(
            c.bobaId,
            c.displayName.csvEscape(),
            c.cardType.csvEscape(),
            c.set.csvEscape(),
            c.cardNumber.csvEscape(),
            c.cost?.toString().orEmpty(),
            c.dbs?.toString().orEmpty(),
            "",  // ability — not in catalog model today
            (c.hd ?: 0).toString(),
        ).joinToString(",")
    }
    val csv = (listOf(header) + rows).joinToString("\n")
    val filename = "${draft.name.replace(' ', '_').lowercase().take(40)}.csv"

    // Write to FileProvider-shared cache so the share sheet
    // attaches a real file (not just EXTRA_TEXT, which most chat
    // apps render as a wall-of-text snippet). Cleanup is OS-managed
    // — same lifecycle as the wall PNG (WallShareHelper).
    val dir = java.io.File(context.cacheDir, "deck-csv").apply { mkdirs() }
    val file = java.io.File(dir, filename)
    file.writeText(csv)
    val uri = androidx.core.content.FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file,
    )
    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
        type = "text/csv"
        putExtra(android.content.Intent.EXTRA_SUBJECT, "BOBA deck: ${draft.name}")
        putExtra(android.content.Intent.EXTRA_TITLE, filename)
        putExtra(android.content.Intent.EXTRA_STREAM, uri)
        putExtra(android.content.Intent.EXTRA_TEXT, "${draft.cards.size}-card BOBA Playbook deck (CSV attached).")
        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(android.content.Intent.createChooser(intent, "Share deck CSV"))
}

/** Escape a CSV field if it contains comma / quote / newline. */
private fun String.csvEscape(): String =
    if (any { it == ',' || it == '"' || it == '\n' }) "\"${replace("\"", "\"\"")}\"" else this

/**
 * Import a CSV file produced by [exportDraftAsCsv] (or any system
 * matching the v2 shape — DECISIONS.md #033b). Replaces the current
 * draft. Unknown card_numbers are silently skipped; partial decks
 * still load with the cards we recognize so a user with a slightly
 * stale catalog isn't blocked.
 *
 * Header detection is column-based: we look for `number` (the
 * card_number column) and `name` to set the draft name. Other
 * columns are advisory; the catalog is the source of truth for
 * everything except `number`.
 */
private fun importDraftFromCsv(
    context: android.content.Context,
    uri: android.net.Uri,
    catalog: List<com.bobaplaybook.core.domain.model.Card>,
    deckViewModel: DecksViewModel,
) {
    val text = runCatching {
        context.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() }
    }.getOrNull() ?: return
    val lines = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
    if (lines.isEmpty()) return
    val header = lines.first().lowercase().split(',').map { it.trim() }
    val numberIdx = header.indexOf("number").takeIf { it >= 0 }
        ?: header.indexOf("card#").takeIf { it >= 0 }
        ?: header.indexOf("cardnumber").takeIf { it >= 0 }
        ?: return
    val nameIdx = header.indexOf("name")
    val byCardNumber = catalog.associateBy { it.cardNumber }

    // First non-header row's name field becomes the deck name (if any).
    val cardRows = lines.drop(1)
    if (cardRows.isEmpty()) return

    deckViewModel.clear()
    cardRows.forEach { row ->
        val cols = parseCsvRow(row)
        val number = cols.getOrNull(numberIdx) ?: return@forEach
        val card = byCardNumber[number] ?: return@forEach
        deckViewModel.add(card)
    }
    if (nameIdx >= 0) {
        // Use the deck's name from the first row's name column? In iOS the
        // CSV stores the deck name separately. For now keep "Imported deck"
        // and let the user rename in the editor.
        deckViewModel.rename("Imported deck")
    }
    android.widget.Toast.makeText(context, "Imported ${cardRows.size} rows", android.widget.Toast.LENGTH_SHORT).show()
}

/** Minimal CSV row parser — handles quoted fields with embedded commas + escaped quotes. */
private fun parseCsvRow(line: String): List<String> {
    val out = mutableListOf<String>()
    val sb = StringBuilder()
    var inQuotes = false
    var i = 0
    while (i < line.length) {
        val c = line[i]
        when {
            c == '"' && inQuotes && i + 1 < line.length && line[i + 1] == '"' -> {
                sb.append('"'); i += 2
            }
            c == '"' -> { inQuotes = !inQuotes; i++ }
            c == ',' && !inQuotes -> { out.add(sb.toString()); sb.setLength(0); i++ }
            else -> { sb.append(c); i++ }
        }
    }
    out.add(sb.toString())
    return out
}
