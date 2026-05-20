@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import android.content.Intent
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.draw
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import kotlinx.coroutines.launch
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.format.formatUsdAmount
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASignInPrompt
import com.bobaplaybook.core.ui.components.BOBAWordmark
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.transitions.cardSharedBounds

/**
 * Collection tab — the owner (ANDROID-DESIGN.md §8.4).
 *
 * Anatomy:
 *  - LargeTopAppBar (Collection) with overflow Menu (display modes)
 *  - Designation `SingleChoiceSegmentedButtonRow` below the bar
 *  - Value summary header (total estimated value)
 *  - Card grid w/ designation badge overlay per cell, OR list view, OR
 *    Wall view (per DECISIONS.md #036 lifted from streamer-only)
 *  - Signed-out: inline BOBASignInPrompt
 */
@Composable
fun CollectionScreen(
    onCardClick: (bobaId: String) -> Unit,
    onProfileClick: () -> Unit,  // unused per feedback_profile_only_on_find; kept for nav signature symmetry
    onRainbowsClick: () -> Unit = {},
    onShowsClick: () -> Unit = {},
    onScanClick: () -> Unit = {},
    onSignInRequest: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val viewModel: CollectionViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    var designation by rememberSaveable { mutableStateOf(Designation.PERSONAL) }
    var menuOpen by remember { mutableStateOf(false) }
    var filterSheetOpen by rememberSaveable { mutableStateOf(false) }

    // Persistent display mode + sort order — iOS @AppStorage parity
    // via CollectionPrefsStore (DataStore<Preferences>). Stored as
    // enum.name() so the catalog can evolve without breaking saved
    // values. Unknown / missing values fall back to the default.
    val collectionPrefs: com.bobaplaybook.app.settings.CollectionPrefsViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val storedDisplayMode by collectionPrefs.displayMode.collectAsStateWithLifecycle(initialValue = null)
    val storedSortOrder by collectionPrefs.sortOrder.collectAsStateWithLifecycle(initialValue = null)
    val displayMode = remember(storedDisplayMode) {
        storedDisplayMode?.let { runCatching { DisplayMode.valueOf(it) }.getOrNull() }
            ?: DisplayMode.GRID
    }
    val collectionSort = remember(storedSortOrder) {
        storedSortOrder?.let { runCatching { CollectionSortOrder.valueOf(it) }.getOrNull() }
            ?: CollectionSortOrder.DATE_ADDED_DESC
    }
    var totalsMode by rememberSaveable { mutableStateOf(TotalsMode.COLLECTION) }
    // Collection-scoped search — iOS .searchable parity. Filters owned
    // cards by name/hero/cardNumber/set using the word-prefix matcher
    // (memory feedback_search_word_prefix). Empty = no filter.
    var collectionQuery by rememberSaveable { mutableStateOf("") }
    val findViewModel: com.bobaplaybook.app.feature.find.FindViewModel = hiltViewModel()
    val findState by findViewModel.uiState.collectAsStateWithLifecycle()
    // CenterAlignedTopAppBar w/ wordmark — pinned so the brand mark
    // stays visible during scroll (ANDROID-DESIGN.md §6.9).
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            CenterAlignedTopAppBar(
                title = { BOBAWordmark() },
                actions = {
                    val context = LocalContext.current
                    IconButton(onClick = onScanClick) {
                        Icon(
                            imageVector = Icons.Default.QrCodeScanner,
                            contentDescription = "Scan a card",
                        )
                    }
                    IconButton(onClick = { filterSheetOpen = true }) {
                        androidx.compose.material3.BadgedBox(
                            badge = {
                                if (findState.activeFilterCount > 0) {
                                    androidx.compose.material3.Badge { Text("${findState.activeFilterCount}") }
                                }
                            },
                        ) {
                            Icon(Icons.Default.Tune, contentDescription = "Filters")
                        }
                    }
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(
                            expanded = menuOpen,
                            onDismissRequest = { menuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Grid") },
                                leadingIcon = { Icon(Icons.Default.GridOn, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    collectionPrefs.setDisplayMode(DisplayMode.GRID.name)
                                },
                                trailingIcon = if (displayMode == DisplayMode.GRID) {
                                    { Icon(Icons.Default.GridOn, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                                } else null,
                            )
                            DropdownMenuItem(
                                text = { Text("List") },
                                leadingIcon = { Icon(Icons.AutoMirrored.Filled.ViewList, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    collectionPrefs.setDisplayMode(DisplayMode.LIST.name)
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Wall") },
                                leadingIcon = { Icon(Icons.Default.Wallpaper, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    collectionPrefs.setDisplayMode(DisplayMode.WALL.name)
                                },
                            )
                            androidx.compose.material3.HorizontalDivider()
                            // Sort sub-menu — peer-collection iOS parity (P1 #17).
                            // Material 3 doesn't have a built-in nested DropdownMenu;
                            // we expose the active sort label in this row and open a
                            // dedicated sort dialog when tapped.
                            var sortDialogOpen by remember { mutableStateOf(false) }
                            DropdownMenuItem(
                                text = { Text("Sort: ${collectionSort.label}") },
                                leadingIcon = { Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null) },
                                onClick = { menuOpen = false; sortDialogOpen = true },
                            )
                            if (sortDialogOpen) {
                                CollectionSortDialog(
                                    selected = collectionSort,
                                    onSelected = {
                                        collectionPrefs.setSortOrder(it.name)
                                        sortDialogOpen = false
                                    },
                                    onDismiss = { sortDialogOpen = false },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Rainbow Progress") },
                                leadingIcon = { Icon(Icons.Default.Palette, contentDescription = null) },
                                onClick = { menuOpen = false; onRainbowsClick() },
                            )
                            DropdownMenuItem(
                                text = { Text("My Shows") },
                                leadingIcon = { Icon(Icons.Default.LiveTv, contentDescription = null) },
                                onClick = { menuOpen = false; onShowsClick() },
                            )
                            androidx.compose.material3.HorizontalDivider()
                            // Share moved into the overflow menu — was a
                            // standalone toolbar action; per Ben's pref
                            // the toolbar is cleaner with just Filters +
                            // overflow.
                            DropdownMenuItem(
                                text = { Text("Share collection") },
                                leadingIcon = { Icon(Icons.Default.Share, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    shareCollection(context, designation, displayMode)
                                },
                            )
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            DesignationRow(
                selected = designation,
                onChange = { designation = it },
                counts = state.entriesByDesignation.mapValues { it.value.size },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            // Count summary — single line below the segmented row so
            // the chips themselves stay readable on compact widths.
            // Hide when 0 — the BOBAEmptyState / BOBASignInPrompt
            // below carries the "nothing here" message; a small
            // top-left "No personal" caption is redundant chrome.
            val currentCount = state.entriesByDesignation[designation]?.size ?: 0
            if (currentCount > 0) {
                Text(
                    text = "$currentCount ${designation.label.lowercase()} card${if (currentCount == 1) "" else "s"}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                )
            }

            // Totals — flip between the whole collection (default) and
            // just the active designation subset. Mirrors iOS
            // CollectionView's TotalsMode toggle (DESIGN.md §8.4 value
            // summary). Hidden when there's no value yet.
            val filterEntries = state.entriesByDesignation[designation].orEmpty()
            val filterValue = remember(filterEntries) {
                filterEntries.sumOf { it.userCard.estimatedValue ?: 0.0 }
            }
            val filterCount = filterEntries.size
            if (state.totalValueUsd > 0.0 || filterValue > 0.0) {
                ValueSummary(
                    mode = totalsMode,
                    onToggleMode = {
                        totalsMode = if (totalsMode == TotalsMode.COLLECTION)
                            TotalsMode.FILTER else TotalsMode.COLLECTION
                    },
                    collectionTotal = state.totalValueUsd,
                    collectionCount = state.entriesByDesignation.values.sumOf { it.size },
                    filterTotal = filterValue,
                    filterCount = filterCount,
                    designationLabel = designation.label,
                )
            }

            if (!state.isSignedIn) {
                BOBASignInPrompt(
                    title = "Sign in to see your collection",
                    body = "Your collection, decks, and wanted list sync across iOS, web, and Android.",
                    onAction = onSignInRequest,
                )
                return@Scaffold
            }

            // Collection-scoped search pill — iOS Collection has
            // .searchable over owned cards; we keep the pill compact and
            // single-line per DESIGN.md §5.3 small-multiples density.
            CollectionSearchPill(
                query = collectionQuery,
                onQueryChange = { collectionQuery = it },
            )

            val unsorted = state.entriesByDesignation[designation].orEmpty()
            val filtered = remember(unsorted, collectionQuery) {
                if (collectionQuery.isBlank()) unsorted
                else unsorted.filter { entry ->
                    com.bobaplaybook.core.domain.search.CardSearch.matchesFields(
                        query = collectionQuery,
                        fields = listOf(
                            entry.card.name,
                            entry.card.hero,
                            entry.card.cardNumber,
                            entry.card.set,
                            entry.card.treatment,
                        ),
                    )
                }
            }
            val entries = remember(filtered, collectionSort) { applySort(filtered, collectionSort) }
            if (entries.isEmpty()) {
                if (collectionQuery.isNotBlank()) {
                    BOBAEmptyState(
                        icon = Icons.Default.Inventory2,
                        headline = "No matches",
                        body = "Nothing in your ${designation.label.lowercase()} cards matches \"$collectionQuery\".",
                        actionLabel = "Clear search",
                        onAction = { collectionQuery = "" },
                    )
                } else {
                    BOBAEmptyState(
                        icon = Icons.Default.Inventory2,
                        headline = "No ${designation.label.lowercase()} cards yet",
                        body = "Scan a card or browse Find to add your first one.",
                    )
                }
                return@Scaffold
            }

            // First-run hint: point new users at the display-mode
            // picker so they discover Grid / List / Wall (especially
            // Wall, which is a shareable surface per DECISIONS.md
            // #036 but lives one menu-tap away).
            val hintsVm: com.bobaplaybook.app.hints.HintsViewModel =
                androidx.hilt.navigation.compose.hiltViewModel()
            val modesHintDismissed by hintsVm
                .isDismissed(com.bobaplaybook.app.hints.HintsStore.Ids.COLLECTION_DISPLAY_MODES)
                .collectAsStateWithLifecycle(initialValue = true)
            if (!modesHintDismissed) {
                com.bobaplaybook.core.ui.components.BOBAHintBanner(
                    title = "Switch display modes",
                    body = "Tap the overflow menu to flip between Grid, List, and Wall. Wall turns your collection into a shareable image.",
                    onDismiss = {
                        hintsVm.dismiss(com.bobaplaybook.app.hints.HintsStore.Ids.COLLECTION_DISPLAY_MODES)
                    },
                )
            }

            // Pull-to-refresh re-pulls user_cards from Supabase via
            // CollectionRepository.refresh(). Wall-mode wraps the
            // same way; refreshing then re-renders with whatever the
            // server returned (e.g. picks up writes from another
            // device on the same account).
            var isRefreshing by remember { mutableStateOf(false) }
            androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    viewModel.refreshFromServer()
                    // The repo refresh is fire-and-forget against
                    // Flow; clear the indicator after a short tick.
                    scope.launch {
                        kotlinx.coroutines.delay(800)
                        isRefreshing = false
                    }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                when (displayMode) {
                    DisplayMode.GRID -> CollectionGrid(entries = entries, onCardClick = onCardClick)
                    DisplayMode.LIST -> CollectionList(entries = entries, onCardClick = onCardClick)
                    DisplayMode.WALL -> CollectionWall(
                        entries = entries,
                        onCardClick = onCardClick,
                        designationLabel = designation.label,
                    )
                }
            }
        }
    }

    if (filterSheetOpen) {
        com.bobaplaybook.app.feature.find.FilterSheet(
            state = findState,
            onEvent = findViewModel::onEvent,
            onDismiss = { filterSheetOpen = false },
        )
    }
}

@Composable
private fun DesignationRow(
    selected: Designation,
    onChange: (Designation) -> Unit,
    counts: Map<Designation, Int>,
    modifier: Modifier = Modifier,
) {
    val entries = remember { Designation.entries }
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        entries.forEachIndexed { index, designation ->
            SegmentedButton(
                selected = designation == selected,
                onClick = { onChange(designation) },
                shape = SegmentedButtonDefaults.itemShape(index, entries.size),
                // Drop the default checkmark icon — M3's selected-state
                // color change (secondaryContainer fill) is already the
                // affordance; the redundant ✓ visually crowds the pill
                // and shifts the label off-center on selection.
                icon = {},
            ) {
                Text(
                    designation.shortLabel,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * Two-mode totals readout. iOS CollectionView.valueSummary parity —
 * users can flip the value+count panel between the whole collection
 * (everything owned across designations) and the currently-active
 * designation subset.
 *
 * Tap anywhere on the row to flip modes; the chip on the right shows
 * which mode is active. Keeping the toggle inline avoids burying it
 * in a filter sheet the way iOS does — Android users haven't built
 * the habit of opening the filter to find a totals toggle.
 */
@Composable
private fun ValueSummary(
    mode: TotalsMode,
    onToggleMode: () -> Unit,
    collectionTotal: Double,
    collectionCount: Int,
    filterTotal: Double,
    filterCount: Int,
    designationLabel: String,
) {
    val isFilter = mode == TotalsMode.FILTER
    val total = if (isFilter) filterTotal else collectionTotal
    val count = if (isFilter) filterCount else collectionCount
    val valueLabel = if (isFilter) "${designationLabel.uppercase()} VALUE" else "EST. MARKET VALUE"
    val countLabel = if (isFilter) "CARDS IN FILTER" else "CARDS OWNED"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onToggleMode() }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = valueLabel,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = if (total > 0.0) "$${total.formatUsdAmount()}" else "—",
                style = MaterialTheme.typography.headlineSmall,
                color = if (total > 0.0) BobaBrand.Orange
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Bold,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = countLabel,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = "$count",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun CollectionGrid(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 110.dp),
        contentPadding = PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(
            items = entries,
            key = { it.userCard.id },
        ) { entry ->
            Box(modifier = Modifier.fillMaxWidth()) {
                BOBACardCell(
                    imageFile = entry.card.imageFile,
                    isSealed = entry.card.isSealed,
                    contentDescription = entry.card.displayName,
                    modifier = Modifier
                        .cardSharedBounds(entry.card.bobaId)
                        .clickable { onCardClick(entry.card.bobaId) },
                )
                DesignationBadge(
                    designation = entry.userCard.designation,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(6.dp),
                )
                if (entry.userCard.quantity > 1) {
                    QuantityBadge(
                        quantity = entry.userCard.quantity,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionList(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items = entries, key = { it.userCard.id }) { entry ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onCardClick(entry.card.bobaId) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(modifier = Modifier.width(40.dp).height(56.dp)) {
                    BOBACardCell(
                        imageFile = entry.card.imageFile,
                    isSealed = entry.card.isSealed,
                        contentDescription = entry.card.displayName,
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        entry.card.displayName,
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                    )
                    Text(
                        "${entry.card.cardNumber} · ${entry.card.element.lowercase().replaceFirstChar { it.uppercase() }}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
                entry.userCard.estimatedValue?.let {
                    Text(
                        "$${it.formatUsdAmount()}",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

@Composable
private fun CollectionWall(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
    designationLabel: String,
) {
    // Wall view = small multiples grid w/ no padding, near-black bg —
    // the shareable layout per DECISIONS.md #036.
    //
    // Capture-on-tap path: a GraphicsLayer records the rendered grid so
    // the share button can export a PNG to FileProvider + Intent.ACTION_SEND.
    val graphicsLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    // Price overlay — DESIGN.md §8.8 per-designation defaults. Sale +
    // Trade + Wanted default ON; Personal + Grails default OFF.
    val defaultOverlay = when (designationLabel.lowercase()) {
        "for sale", "for trade", "wanted" -> true
        else -> false
    }
    var includePrices by rememberSaveable(designationLabel) { mutableStateOf(defaultOverlay) }
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
        ) {
            androidx.compose.material3.FilterChip(
                selected = includePrices,
                onClick = { includePrices = !includePrices },
                label = { Text("Prices") },
                modifier = Modifier.padding(end = 8.dp),
            )
            androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
            // Compact share affordance — appears only in Wall view (DECISIONS.md
            // #036 calls Wall a sharing surface). Tap → capture → share PNG.
            // Pulls the current username via ProfileViewModel so the share-text
            // can deep-link to the user's public collection (when enabled).
            val profileVm: com.bobaplaybook.app.feature.profile.ProfileViewModel =
                androidx.hilt.navigation.compose.hiltViewModel()
            val profile by profileVm.profile.collectAsStateWithLifecycle(initialValue = null)
            LaunchedEffect(Unit) { profileVm.refreshProfile() }
            val username = profile?.takeIf { it.publicCollectionEnabled }?.username
            androidx.compose.material3.TextButton(
                onClick = {
                    scope.launch {
                        val img = graphicsLayer.toImageBitmap()
                        val bmp = img.asAndroidBitmap()
                        WallShareHelper.share(
                            context = context,
                            bitmap = bmp,
                            designationLabel = designationLabel,
                            username = username,
                        )
                    }
                },
            ) {
                Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.width(16.dp).height(16.dp))
                androidx.compose.foundation.layout.Spacer(modifier = Modifier.padding(end = 8.dp))
                Text("Share Wall as image")
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 90.dp),
            contentPadding = PaddingValues(2.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier
                .fillMaxSize()
                .clip(MaterialTheme.shapes.medium)
                .drawWithContent {
                    graphicsLayer.record { this@drawWithContent.drawContent() }
                    drawLayer(graphicsLayer)
                },
        ) {
            items(items = entries, key = { it.userCard.id }) { entry ->
                Box(
                    modifier = Modifier
                        .cardSharedBounds(entry.card.bobaId)
                        .clickable { onCardClick(entry.card.bobaId) },
                ) {
                    BOBACardCell(
                        imageFile = entry.card.imageFile,
                    isSealed = entry.card.isSealed,
                        contentDescription = entry.card.displayName,
                    )
                    if (includePrices) {
                        val price = entry.userCard.estimatedValue
                        if (price != null && price > 0.0) {
                            androidx.compose.material3.Surface(
                                shape = MaterialTheme.shapes.small,
                                color = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.7f),
                                modifier = Modifier
                                    .align(Alignment.BottomStart)
                                    .padding(4.dp),
                            ) {
                                Text(
                                    "$${"%.0f".format(price)}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = com.bobaplaybook.core.ui.theme.BobaBrand.Orange,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DesignationBadge(
    designation: Designation,
    modifier: Modifier = Modifier,
) {
    Surface(
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f),
        shape = MaterialTheme.shapes.small,
        modifier = modifier,
    ) {
        Text(
            text = designation.shortLabel,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

@Composable
private fun QuantityBadge(
    quantity: Int,
    modifier: Modifier = Modifier,
) {
    Surface(
        color = BobaBrand.Orange,
        shape = CircleShape,
        modifier = modifier,
    ) {
        Text(
            text = "x$quantity",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

/**
 * Collection-only sort orders. Mirrors iOS CollectionSortOrder
 * (FilterSheetView.swift). Adds date-added + market value + paid
 * dimensions that depend on user-collection state.
 */
/**
 * Apply the selected sort order to the entries list. Mirrors iOS
 * CollectionSortOrder semantics from CollectionView.swift.
 */
private fun applySort(
    entries: List<CollectionEntry>,
    order: CollectionSortOrder,
): List<CollectionEntry> {
    // Image-first as PRIMARY criterion per memory
    // `feedback_card_art_sort_priority` — image-pending placeholders
    // never lead a sort regardless of which secondary criterion the
    // user picked.
    val artFirst = compareByDescending<CollectionEntry> { !it.card.imageFile.isNullOrEmpty() }
    return when (order) {
        CollectionSortOrder.NAME_ASC -> entries.sortedWith(artFirst.thenBy { it.card.displayName.lowercase() })
        CollectionSortOrder.NAME_DESC -> entries.sortedWith(artFirst.thenByDescending { it.card.displayName.lowercase() })
        CollectionSortOrder.DATE_ADDED_DESC -> entries.sortedWith(artFirst)  // server-roughly date-added already
        CollectionSortOrder.DATE_ADDED_ASC -> entries.reversed().sortedWith(artFirst)
        CollectionSortOrder.PRICE_DESC -> entries.sortedWith(artFirst.thenByDescending { it.userCard.estimatedValue ?: 0.0 })
        CollectionSortOrder.PRICE_ASC -> entries.sortedWith(artFirst.thenBy { it.userCard.estimatedValue ?: Double.MAX_VALUE })
        CollectionSortOrder.PAID_DESC -> entries.sortedWith(artFirst.thenByDescending { it.userCard.purchasePrice ?: 0.0 })
        CollectionSortOrder.PAID_ASC -> entries.sortedWith(artFirst.thenBy { it.userCard.purchasePrice ?: Double.MAX_VALUE })
        CollectionSortOrder.NUMBER_ASC -> entries.sortedWith(artFirst.thenBy { it.card.cardNumber })
        CollectionSortOrder.NUMBER_DESC -> entries.sortedWith(artFirst.thenByDescending { it.card.cardNumber })
        CollectionSortOrder.POWER_DESC -> entries.sortedWith(artFirst.thenByDescending { it.card.power ?: 0 })
        CollectionSortOrder.POWER_ASC -> entries.sortedWith(artFirst.thenBy { it.card.power ?: Int.MAX_VALUE })
        CollectionSortOrder.COST_ASC -> entries.sortedWith(artFirst.thenBy { it.card.cost ?: Int.MAX_VALUE })
        CollectionSortOrder.COST_DESC -> entries.sortedWith(artFirst.thenByDescending { it.card.cost ?: 0 })
    }
}

@Composable
private fun CollectionSortDialog(
    selected: CollectionSortOrder,
    onSelected: (CollectionSortOrder) -> Unit,
    onDismiss: () -> Unit,
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Sort by") },
        text = {
            androidx.compose.foundation.lazy.LazyColumn {
                items(items = CollectionSortOrder.entries, key = { it.name }) { order ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelected(order) }
                            .padding(vertical = 8.dp),
                    ) {
                        androidx.compose.material3.RadioButton(
                            selected = order == selected,
                            onClick = { onSelected(order) },
                        )
                        Text(order.label, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text("Done") }
        },
    )
}

enum class CollectionSortOrder(val label: String) {
    NAME_ASC        ("Name A → Z"),
    NAME_DESC       ("Name Z → A"),
    DATE_ADDED_DESC ("Recently Added"),
    DATE_ADDED_ASC  ("Oldest Added"),
    PRICE_DESC      ("Market Value: High → Low"),
    PRICE_ASC       ("Market Value: Low → High"),
    PAID_DESC       ("Paid: High → Low"),
    PAID_ASC        ("Paid: Low → High"),
    NUMBER_ASC      ("Card # Ascending"),
    NUMBER_DESC     ("Card # Descending"),
    POWER_DESC      ("Power: High → Low"),
    POWER_ASC       ("Power: Low → High"),
    COST_ASC        ("Hot Dog Cost: Low → High"),
    COST_DESC       ("Hot Dog Cost: High → Low"),
}

/** Totals-mode segmented control state. iOS CollectionView.TotalsMode. */
enum class TotalsMode(val label: String) {
    COLLECTION ("Collection"),
    FILTER     ("Filter"),
}

private fun shareCollection(
    context: android.content.Context,
    designation: Designation,
    displayMode: DisplayMode,
) {
    // v1 share: text link to the public collection page (requires the
    // user to have toggled sharing ON in Profile). Full PNG export of
    // the Wall view via GraphicsLayer.toImageBitmap() is a follow-up —
    // needs FileProvider XML config + cache-cleanup policy.
    val text = "Check out my BOBA Playbook ${designation.label.lowercase()}!\n" +
               "https://bobaplaybook.com/u/your-handle"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "My BOBA ${designation.label}")
        putExtra(Intent.EXTRA_TEXT, text)
    }
    context.startActivity(Intent.createChooser(intent, "Share collection"))
}

/**
 * Compact single-line search pill scoped to the visible designation.
 * Mirrors iOS `.searchable` over Collection (CollectionView.swift).
 * Word-prefix match via CardSearch.matchesFields — "amon" finds
 * Amon-Ra but not Johnny Damon.
 */
@Composable
private fun CollectionSearchPill(
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
            androidx.compose.material3.Icon(
                imageVector = Icons.Default.Search,
                contentDescription = null,
                modifier = Modifier.width(20.dp).height(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            androidx.compose.foundation.layout.Spacer(modifier = Modifier.width(8.dp))
            androidx.compose.material3.TextField(
                value = query,
                onValueChange = onQueryChange,
                placeholder = { Text("Search your collection") },
                singleLine = true,
                modifier = Modifier.weight(1f),
                colors = androidx.compose.material3.TextFieldDefaults.colors(
                    focusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                    disabledContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                    focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                ),
            )
            if (query.isNotEmpty()) {
                androidx.compose.material3.IconButton(onClick = { onQueryChange("") }) {
                    androidx.compose.material3.Icon(
                        imageVector = Icons.Default.Clear,
                        contentDescription = "Clear search",
                    )
                }
            }
        }
    }
}
