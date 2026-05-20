@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalFoundationApi::class,
    androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi::class,
)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
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
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAWordmark
import com.bobaplaybook.core.ui.transitions.cardSharedBounds

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
    modifier: Modifier = Modifier,
) {
    if (isCompactWidth()) {
        DecksCompactScreen(
            onCardClick = onCardClick,
            onOpenManage = onOpenManage,
            onOpenRules = onOpenRules,
            onOpenLegality = onOpenLegality,
            modifier = modifier,
        )
    } else {
        DecksTabletScreen(
            onCardClick = onCardClick,
            onOpenManage = onOpenManage,
            onOpenRules = onOpenRules,
            onOpenLegality = onOpenLegality,
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
    modifier: Modifier = Modifier,
) {
    val findViewModel: FindViewModel = hiltViewModel()
    val findState by findViewModel.uiState.collectAsStateWithLifecycle()
    val deckViewModel: DecksViewModel = hiltViewModel()
    val draft by deckViewModel.draft.collectAsStateWithLifecycle()
    val hintsViewModel: HintsViewModel = hiltViewModel()
    val longPressHintDismissed by hintsViewModel
        .isDismissed(HintsStore.Ids.DECKS_LONG_PRESS_TO_ADD)
        .collectAsStateWithLifecycle(initialValue = true)
    var editorOpen by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var poolQuery by rememberSaveable { mutableStateOf("") }

    Scaffold(
        modifier = modifier,
        topBar = {
            CenterAlignedTopAppBar(
                title = { BOBAWordmark() },
                actions = {
                    IconButton(onClick = { editorOpen = true }) {
                        Icon(
                            imageVector = Icons.Default.Edit,
                            contentDescription = "Open deck editor",
                        )
                    }
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = "More",
                            )
                        }
                        DropdownMenu(
                            expanded = menuOpen,
                            onDismissRequest = { menuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Templates") },
                                leadingIcon = { Icon(Icons.Default.Lightbulb, contentDescription = null) },
                                onClick = { menuOpen = false /* M4 polish — template gallery */ },
                            )
                            DropdownMenuItem(
                                text = { Text("Saved decks") },
                                leadingIcon = { Icon(Icons.Default.Save, contentDescription = null) },
                                onClick = { menuOpen = false; onOpenManage() },
                            )
                            DropdownMenuItem(
                                text = { Text("Import (CSV)") },
                                leadingIcon = { Icon(Icons.Default.FileUpload, contentDescription = null) },
                                onClick = { menuOpen = false /* M4 polish — CSV import */ },
                            )
                            DropdownMenuItem(
                                text = { Text("Export (CSV)") },
                                leadingIcon = { Icon(Icons.Default.FileDownload, contentDescription = null) },
                                onClick = { menuOpen = false /* M4 polish — CSV export */ },
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
                            DropdownMenuItem(
                                text = { Text("Scan into deck") },
                                leadingIcon = { Icon(Icons.Default.QrCodeScanner, contentDescription = null) },
                                onClick = { menuOpen = false /* opens scan modal via parent */ },
                            )
                            androidx.compose.material3.HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("Clear draft") },
                                leadingIcon = { Icon(Icons.Default.Clear, contentDescription = null) },
                                onClick = { menuOpen = false; deckViewModel.clear() },
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
                    body = "Long-press any card in the pool to add it to your deck draft. Tap to see card detail instead.",
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
                onCardClick = onCardClick,
                onCardLongClick = deckViewModel::add,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }

    if (editorOpen) {
        DeckEditorSheet(
            draft = draft,
            onDismiss = { editorOpen = false },
            onRename = deckViewModel::rename,
            onRemove = deckViewModel::remove,
            onSave = {
                // M7 — Supabase write. v1 just closes the sheet.
                editorOpen = false
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
) {
    LazyVerticalGrid(
        modifier = modifier,
        columns = GridCells.Adaptive(minSize = 110.dp),
        contentPadding = PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(
            items = cards,
            key = { card -> card.bobaId },
            contentType = { "card" },
        ) { card ->
            BOBACardCell(
                imageFile = card.imageFile,
                contentDescription = card.displayName,
                modifier = Modifier
                    .cardSharedBounds(card.bobaId)
                    .combinedClickable(
                        onClick = { onCardClick(card.bobaId) },
                        onLongClick = { onCardLongClick(card) },
                    ),
            )
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
                Text(
                    draft.name,
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    "${draft.heroCount}/${draft.heroCap} H · ${draft.playCount + draft.bonusCount}/${draft.playCap} P · ${draft.bonusCount} BP · ${draft.totalHD}/${draft.hdCap} HD",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
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

// ─────────────────────────────────────────────────────────────────
// Tablet / Chromebook 3-pane: saved decks | pool | editor
// ─────────────────────────────────────────────────────────────────

@Composable
private fun DecksTabletScreen(
    onCardClick: (bobaId: String) -> Unit,
    onOpenManage: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val findViewModel: FindViewModel = hiltViewModel()
    val findState by findViewModel.uiState.collectAsStateWithLifecycle()
    val deckViewModel: DecksViewModel = hiltViewModel()
    val draft by deckViewModel.draft.collectAsStateWithLifecycle()

    Row(modifier = modifier.fillMaxSize()) {
        // Saved decks sidebar (placeholder until Supabase wires up in M7)
        Surface(
            modifier = Modifier
                .width(240.dp)
                .fillMaxSize(),
            color = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            Column(modifier = Modifier.padding(8.dp)) {
                BOBASectionHeader(title = "Saved decks")
                BOBAEmptyState(
                    icon = Icons.Default.Save,
                    headline = "No saved decks",
                    body = "Sign in to sync decks across iOS, web, and Android.",
                    actionLabel = "Manage",
                    onAction = onOpenManage,
                )
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
                onRename = deckViewModel::rename,
                onRemove = deckViewModel::remove,
                onSave = { /* M7 polish — Supabase write */ },
                onOpenRules = onOpenRules,
                onOpenLegality = onOpenLegality,
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
                            "Filter pool",
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
