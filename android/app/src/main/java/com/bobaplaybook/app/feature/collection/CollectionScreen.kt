@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.RadioButton
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import kotlinx.coroutines.launch
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.domain.model.CardFormatEligibility
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.format.formatUsdAmount
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
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
    onRainbowsClick: () -> Unit = {},
    onShowsClick: () -> Unit = {},
    onScanClick: () -> Unit = {},
    onSignInRequest: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val viewModel: CollectionViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var designation by rememberSaveable { mutableStateOf(Designation.PERSONAL) }
    var menuOpen by remember { mutableStateOf(false) }
    var filterSheetOpen by rememberSaveable { mutableStateOf(false) }
    // Sort dialog visibility hoisted OUT of the DropdownMenu content
    // lambda. When `menuOpen = false` closed the menu, the inline
    // `var sortDialogOpen by remember { ... }` was disposed before
    // the dialog could render — sort taps were silently dropping
    // the new value. Keeping it here keeps the dialog state alive
    // across the menu's dispose. iOS CollectionView surfaces the
    // same sort picker as a NavigationLink push so this scoping
    // problem doesn't surface there.
    var sortDialogOpen by remember { mutableStateOf(false) }

    // Streamer role gates My Shows in the overflow menu — iOS
    // CollectionView.collectionMenu has `if auth.isStreamer { ... }`
    // wrapping the Shows item. Without this gate Android non-streamers
    // saw the row + tapped it + landed on an empty list, no value.
    val profileViewModel: com.bobaplaybook.app.feature.profile.ProfileViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val profile by profileViewModel.profile.collectAsStateWithLifecycle(initialValue = null)
    LaunchedEffect(Unit) { profileViewModel.refreshProfile() }
    val isStreamer = profile?.role?.contains("streamer", ignoreCase = true) == true ||
        profile?.role?.contains("admin", ignoreCase = true) == true

    // Persistent display mode + sort order — iOS @AppStorage parity
    // via CollectionPrefsStore (DataStore<Preferences>). Stored as
    // enum.name() so the catalog can evolve without breaking saved
    // values. Unknown / missing values fall back to the default.
    val collectionPrefs: com.bobaplaybook.app.settings.CollectionPrefsViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val storedDisplayMode by collectionPrefs.displayMode.collectAsStateWithLifecycle(initialValue = null)
    val storedSortOrder by collectionPrefs.sortOrder.collectAsStateWithLifecycle(initialValue = null)
    // Per-tab grid density — Target.COLLECTION was registered in
    // GridDensityStore but unused until tick 104. iOS @AppStorage
    // ("bp_collectionGridColumns_v1") parity.
    val gridDensityVm: com.bobaplaybook.app.settings.GridDensityViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val storedGridColumns by gridDensityVm
        .columnsFor(com.bobaplaybook.app.settings.GridDensityStore.Target.COLLECTION)
        .collectAsStateWithLifecycle(initialValue = 0)
    // iOS default is LIST (bp_collectionDisplayMode_v2 = "list"). The
    // previous GRID default broke parity: a freshly-installed Android
    // user landed in a sparse 3-column grid while an iOS user with the
    // same account landed in the data-dense list.
    val displayMode = remember(storedDisplayMode) {
        storedDisplayMode?.let { runCatching { DisplayMode.valueOf(it) }.getOrNull() }
            ?: DisplayMode.LIST
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
                    // Tick 400 — BOBAIconTooltip helper (was tick 394's
                    // 3 inline TooltipBox blocks). Same affordance shape.
                    BOBAIconTooltip("Scan a card") {
                        IconButton(onClick = onScanClick) {
                            Icon(
                                imageVector = Icons.Default.QrCodeScanner,
                                contentDescription = "Scan a card",
                            )
                        }
                    }
                    BOBAIconTooltip(
                        text = if (findState.activeFilterCount > 0)
                            "Filters · ${findState.activeFilterCount} active"
                        else "Filters",
                    ) {
                        IconButton(onClick = { filterSheetOpen = true }) {
                            BadgedBox(
                                badge = {
                                    if (findState.activeFilterCount > 0) {
                                        androidx.compose.material3.Badge { Text("${findState.activeFilterCount}") }
                                    }
                                },
                            ) {
                                Icon(Icons.Default.Tune, contentDescription = "Filters")
                            }
                        }
                    }
                    Box {
                        BOBAIconTooltip("Display mode + collection actions") {
                            IconButton(onClick = { menuOpen = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "More")
                            }
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
                            HorizontalDivider()
                            // Grid density picker (GRID mode only) — iOS
                            // @AppStorage("bp_collectionGridColumns_v1") parity.
                            // Rendered inline in the same overflow menu since
                            // M3 doesn't ship nested DropdownMenu; the Decks
                            // tab uses the same pattern (tick 101).
                            if (displayMode == DisplayMode.GRID) {
                                Text(
                                    "Grid columns",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp),
                                )
                                listOf(1, 2, 3).forEach { col ->
                                    DropdownMenuItem(
                                        text = { Text("$col column${if (col > 1) "s" else ""}") },
                                        leadingIcon = {
                                            if (storedGridColumns == col) {
                                                Icon(Icons.Default.Check, contentDescription = "Active")
                                            } else {
                                                androidx.compose.foundation.layout.Spacer(modifier = Modifier.width(24.dp))
                                            }
                                        },
                                        onClick = {
                                            menuOpen = false
                                            scope.launch {
                                                gridDensityVm.setColumns(
                                                    com.bobaplaybook.app.settings.GridDensityStore.Target.COLLECTION,
                                                    col,
                                                )
                                            }
                                        },
                                    )
                                }
                                HorizontalDivider()
                            }
                            // Sort sub-menu — peer-collection iOS parity (P1 #17).
                            // Material 3 doesn't have a built-in nested DropdownMenu;
                            // we expose the active sort label in this row and open a
                            // dedicated sort dialog when tapped. `sortDialogOpen` is
                            // hoisted to the outer Composable so closing the
                            // overflow menu doesn't tear down the dialog's state.
                            DropdownMenuItem(
                                text = { Text("Sort: ${collectionSort.label}") },
                                leadingIcon = { Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null) },
                                onClick = { menuOpen = false; sortDialogOpen = true },
                            )
                            DropdownMenuItem(
                                text = { Text("Rainbow Progress") },
                                leadingIcon = { Icon(Icons.Default.Palette, contentDescription = null) },
                                onClick = { menuOpen = false; onRainbowsClick() },
                            )
                            // Streamer-gated — non-streamers don't see
                            // the row at all. iOS CollectionView gates
                            // the same item on `auth.isStreamer`.
                            if (isStreamer) {
                                DropdownMenuItem(
                                    text = { Text("My Shows") },
                                    leadingIcon = { Icon(Icons.Default.LiveTv, contentDescription = null) },
                                    onClick = { menuOpen = false; onShowsClick() },
                                )
                            }
                            HorizontalDivider()
                            // Scan into the active designation (iOS
                            // collectionMenu compact path). Mirrors iOS
                            // copy: "Scan into Personal", "Scan into For
                            // Sale", etc. — destination chosen by the
                            // segmented row above.
                            DropdownMenuItem(
                                text = { Text("Scan into ${designation.label}") },
                                leadingIcon = { Icon(Icons.Default.QrCodeScanner, contentDescription = null) },
                                onClick = { menuOpen = false; onScanClick() },
                            )
                            // Refresh market values — Android previously
                            // routed this through pull-to-refresh only,
                            // but iOS exposes it in the overflow menu
                            // too. Hidden behind PTR alone is hard for
                            // a coach who just wants the latest pricing
                            // without scrolling to the top.
                            DropdownMenuItem(
                                text = { Text("Refresh market values") },
                                leadingIcon = { Icon(Icons.Default.Refresh, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    viewModel.refreshFromServer()
                                },
                            )
                            HorizontalDivider()
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
            // Signed-out wall before any collection chrome — nothing
            // below is useful without a synced collection.
            if (!state.isSignedIn) {
                BOBASignInPrompt(
                    title = "Sign in to see your collection",
                    body = "Your collection, decks, and wanted list sync across iOS, web, and Android.",
                    onAction = onSignInRequest,
                )
                return@Scaffold
            }

            // 1. Search on top — Ben's punch-list #2. Used to live below
            //    the designation segmented control; surface it first
            //    because "find the card I know I own" is the primary
            //    intent on the Collection tab.
            CollectionSearchPill(
                query = collectionQuery,
                onQueryChange = { collectionQuery = it },
            )

            // 2. Totals — flip between the whole collection and the
            // active designation subset. Mirrors iOS CollectionView's
            // TotalsMode toggle (DESIGN.md §8.4 value summary).
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

            // 3. Designation chips — sections of the collection. The
            // M3 SegmentedButton row was truncating "Personal" → "Persona"
            // at compact width because 5 fixed-width slots couldn't fit
            // the longest label. Switched to a scrollable FilterChip
            // FlowRow so every label renders in full and the right edge
            // hint-scrolls when overflowing the viewport.
            DesignationRow(
                selected = designation,
                onChange = { designation = it },
                counts = state.entriesByDesignation.mapValues { it.value.size },
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            )
            val currentCount = state.entriesByDesignation[designation]?.size ?: 0
            if (currentCount > 0) {
                Text(
                    text = "$currentCount ${designation.label.lowercase()} card${if (currentCount == 1) "" else "s"}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                )
            }

            // Cross-designation lookups for iOS-parity badges:
            //  - bobaIdToDesignations: which designations contain this card
            //  - bobaIdToTotalCopies: how many copies across ALL designations
            // iOS CollectionView.collectionGridCell only renders the
            // multi-designation badge when count > 1; the per-row list
            // pill renders "×N" or "×N (M here)" when total copies > 1.
            // Without these lookups the Android UI showed a designation
            // badge on every cell unconditionally (the "weird overlay
            // not present on iOS" feedback) and no quantity pill at all
            // on the list rows.
            val bobaIdToDesignations = remember(state.entriesByDesignation) {
                buildMap<String, Set<Designation>> {
                    state.entriesByDesignation.forEach { (d, entries) ->
                        entries.forEach { e ->
                            val existing = get(e.card.bobaId) ?: emptySet()
                            put(e.card.bobaId, existing + d)
                        }
                    }
                }
            }
            val bobaIdToTotalCopies = remember(state.entriesByDesignation) {
                buildMap<String, Int> {
                    state.entriesByDesignation.forEach { (_, entries) ->
                        entries.forEach { e ->
                            put(e.card.bobaId, (get(e.card.bobaId) ?: 0) + e.userCard.quantity)
                        }
                    }
                }
            }
            val unsorted = state.entriesByDesignation[designation].orEmpty()
            // Wire findState's filters (weapons / treatment / set /
            // release / power / has-image / card purpose) into the
            // Collection entry pipeline. The Filter sheet shown by
            // tapping the toolbar filter chip is the Find feature's
            // FilterSheet — without this guard the chips toggled
            // FindViewModel state but Collection ignored it, so the
            // "Filters · 3 active" badge appeared with zero effect.
            val filtered = remember(unsorted, collectionQuery, findState) {
                unsorted.filter { entry ->
                    val card = entry.card
                    // Card purpose
                    when (findState.cardPurpose) {
                        com.bobaplaybook.app.feature.find.CardPurpose.ALL      -> {}
                        com.bobaplaybook.app.feature.find.CardPurpose.HEROES   -> if (!card.isHero)   return@filter false
                        com.bobaplaybook.app.feature.find.CardPurpose.PLAYS    -> if (!card.isPlay)   return@filter false
                        com.bobaplaybook.app.feature.find.CardPurpose.HOT_DOGS -> if (!card.isHotDog) return@filter false
                        com.bobaplaybook.app.feature.find.CardPurpose.SEALED   -> if (!card.isSealed) return@filter false
                    }
                    if (findState.hasImageOnly && card.imageFile.isNullOrEmpty()) return@filter false
                    // Showcase filter — iOS Showcases.byId(id).match(card).
                    // Was missing from the Collection filter pipeline so
                    // tapping a Showcase chip in the (Find-shared) filter
                    // sheet did nothing here.
                    findState.showcaseId?.let { sid ->
                        val showcase = com.bobaplaybook.core.domain.showcase.Showcases.byId(sid)
                        if (showcase != null && !showcase.match(card)) return@filter false
                    }
                    if (findState.activeWeapons.isNotEmpty() &&
                        card.element.uppercase() !in findState.activeWeapons.map { it.uppercase() }) return@filter false
                    findState.activeTreatment?.let { t -> if (!card.treatment.equals(t, ignoreCase = true)) return@filter false }
                    findState.activeSet?.let       { s -> if (!card.set.equals(s, ignoreCase = true))       return@filter false }
                    findState.activeRelease?.let   { r -> if (!card.release.equals(r, ignoreCase = true))   return@filter false }
                    val p = card.power
                    if (findState.powerMin != null && (p == null || p < findState.powerMin!!)) return@filter false
                    if (findState.powerMax != null && (p == null || p > findState.powerMax!!)) return@filter false
                    // Free-text search — runs last so non-matching
                    // entries don't waste filter cycles.
                    if (collectionQuery.isNotBlank()) {
                        if (!com.bobaplaybook.core.domain.search.CardSearch.matchesFields(
                                query = collectionQuery,
                                fields = listOf(card.name, card.hero, card.cardNumber, card.set, card.treatment),
                            )) return@filter false
                    }
                    true
                }
            }
            val entries = remember(filtered, collectionSort) { applySort(filtered, collectionSort) }
            // Card-detail swipe-nav siblings — same pattern as Find / Decks.
            // The user's "visible list" is the filtered + sorted entries
            // for the current designation; bobaId is the navigation key.
            val navHolder: com.bobaplaybook.app.feature.carddetail.CardNavigationHolderViewModel = hiltViewModel()
            LaunchedEffect(entries) {
                navHolder.store.set(entries.map { it.card.bobaId })
            }
            if (entries.isEmpty()) {
                // Spinner while the catalog or user_cards is still
                // hydrating. Without this, the empty-state copy flashes
                // briefly on every Collection-tab open before the
                // Supabase refresh round-trip completes.
                if (state.isLoading) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        androidx.compose.material3.CircularProgressIndicator()
                    }
                    return@Scaffold
                }
                if (collectionQuery.isNotBlank()) {
                    BOBAEmptyState(
                        icon = Icons.Default.Inventory2,
                        headline = "No matches",
                        body = "Nothing in your ${designation.label.lowercase()} cards matches \"$collectionQuery\".",
                        actionLabel = "Clear search",
                        onAction = { collectionQuery = "" },
                    )
                } else {
                    // Per-designation brand-voice empty states (parity
                    // with web tick 78 + universal-feature-states skill).
                    // Generic "Scan a card or browse Find" said the same
                    // thing for every designation; each one wants
                    // different next-action copy.
                    val (headline, body) = when (designation) {
                        com.bobaplaybook.core.domain.model.Designation.PERSONAL ->
                            "No personal cards yet" to
                                "Scan a card or use Quick Add from the Find tab to start your stack."
                        com.bobaplaybook.core.domain.model.Designation.FOR_SALE ->
                            "Nothing for sale yet" to
                                "Mark a card from your Personal stack to start moving it."
                        com.bobaplaybook.core.domain.model.Designation.FOR_TRADE ->
                            "Nothing for trade yet" to
                                "Flag a card to find a trading partner once trading launches."
                        com.bobaplaybook.core.domain.model.Designation.WANTED ->
                            "No wanted cards yet" to
                                "Flag the cards you're chasing — start with the ones at the top of your list."
                        com.bobaplaybook.core.domain.model.Designation.GRAILS ->
                            "No grails yet" to
                                "Mark the cards you'd cross a state line for."
                    }
                    // Only Personal gets a CTA button (Scan a card). The
                    // other designations need the user to find cards in
                    // a different surface (Find tab or Personal stack) —
                    // pointing them at a tab they can already see in the
                    // NavigationBar is no-op chrome. Body copy carries
                    // the wayfinding.
                    val isPersonal = designation ==
                        com.bobaplaybook.core.domain.model.Designation.PERSONAL
                    BOBAEmptyState(
                        icon = Icons.Default.Inventory2,
                        headline = headline,
                        body = body,
                        actionLabel = if (isPersonal) "Scan a card" else null,
                        onAction = if (isPersonal) onScanClick else null,
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
            PullToRefreshBox(
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
                    DisplayMode.GRID -> CollectionGrid(
                        entries = entries,
                        onCardClick = onCardClick,
                        columns = storedGridColumns,
                        bobaIdToDesignations = bobaIdToDesignations,
                    )
                    DisplayMode.LIST -> CollectionList(
                        entries = entries,
                        onCardClick = onCardClick,
                        bobaIdToTotalCopies = bobaIdToTotalCopies,
                    )
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
            // Hide Find's sort picker here — Collection has its own
            // sort enum + dialog reachable from the overflow menu.
            // Without this, picking a sort in the filter sheet wrote
            // to Find's state and Collection's list never reordered.
            showSortSection = false,
        )
    }

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
}

@Composable
private fun DesignationRow(
    selected: Designation,
    onChange: (Designation) -> Unit,
    counts: Map<Designation, Int>,
    modifier: Modifier = Modifier,
) {
    val entries = remember { Designation.entries }
    // Horizontal scrollable FilterChip row — replaces the prior
    // SingleChoiceSegmentedButtonRow because M3 SegmentedButton
    // doesn't auto-shrink its label, so 5 equal-width slots at
    // 360 dp truncated "Personal" → "Persona". FilterChips size
    // to their content + the row scrolls horizontally when the
    // total width overflows the viewport (iOS .scrollIndicators
    // parity).
    val scrollState = rememberScrollState()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(scrollState),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        entries.forEach { designation ->
            val count = counts[designation] ?: 0
            FilterChip(
                selected = designation == selected,
                onClick = { onChange(designation) },
                label = {
                    Text(
                        if (count > 0) "${designation.label} ($count)" else designation.label,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                    )
                },
            )
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
            // Tick 414 — locale-format the count (iOS tick 412 +
            // web tick 413 parity). Serious collectors hit 1,000+
            // cards; "1,234" reads cleaner at the headlineSmall
            // weight than "1234".
            Text(
                text = java.text.NumberFormat.getInstance(java.util.Locale.US).format(count),
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
    /**
     * Fixed column count (1/2/3) from the per-tab grid-density store.
     * 0 → adaptive default (preserves prior behavior). iOS
     * @AppStorage("bp_collectionGridColumns_v1") parity.
     */
    columns: Int = 0,
    /**
     * Per-bobaId set of designations the user has assigned to this
     * card. The multi-designation icon strip only renders when the
     * set has ≥2 entries (iOS CollectionView.collectionGridCell).
     * Empty map = treat every card as single-designation.
     */
    bobaIdToDesignations: Map<String, Set<Designation>> = emptyMap(),
) {
    LazyVerticalGrid(
        columns = if (columns > 0) GridCells.Fixed(columns)
                  else GridCells.Adaptive(minSize = 110.dp),
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
                    printRunLabel = entry.card.printRunLabel,
                    formatLegalityHint = CardFormatEligibility.restrictedLegalAbbrev(entry.card),
                    modifier = Modifier
                        .cardSharedBounds(entry.card.bobaId)
                        .clickable { onCardClick(entry.card.bobaId) },
                )
                // Multi-designation badge — only render when this
                // bobaId is present in ≥2 designations. iOS shows the
                // designation icons stacked in a top-trailing row so
                // a coach browsing Personal sees that the same card
                // is also listed For Sale. A per-cell badge on every
                // card (the previous behavior) added visual noise
                // and didn't match iOS at all.
                val cellDesignations = bobaIdToDesignations[entry.card.bobaId] ?: emptySet()
                if (cellDesignations.size > 1) {
                    Row(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(4.dp),
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        cellDesignations.sortedBy { it.ordinal }.forEach { d ->
                            DesignationBadge(
                                designation = d,
                                modifier = Modifier,
                            )
                        }
                    }
                }
                // iOS-parity price chip — anchored top-leading on the
                // card image so it sits over the art (an unoccupied
                // region; print-run is top-trailing per cardThumbBadges,
                // designation badge is bottom-trailing). Hidden when
                // estimatedValue is missing or 0.
                entry.userCard.estimatedValue?.takeIf { it > 0 }?.let { v ->
                    Text(
                        text = "$${v.formatUsdAmount()}",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = androidx.compose.ui.graphics.Color.White,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp)
                            .background(
                                color = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.68f),
                                shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
                            )
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
                // iOS doesn't render a per-cell QuantityBadge in grid
                // mode — quantity surfaces on the list cell's title
                // pill instead. Don't reintroduce it here without first
                // updating iOS to match.
            }
        }
    }
}

@Composable
private fun CollectionList(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
    /**
     * Total copies of each bobaId across EVERY designation. The
     * "×N" pill next to the title shows the full collection-wide
     * count so a coach browsing For Sale still sees they own 3 total
     * (1 for sale + 2 personal). iOS collectionRow uses the same
     * total-across-designations math (CollectionView.swift L1470).
     */
    bobaIdToTotalCopies: Map<String, Int> = emptyMap(),
) {
    // iOS-parity list cell (CollectionView.swift::collectionRow):
    //   [ 60×84 thumb ] [ NAME (large display)              ]  [ $X.XX  ]
    //                  [ WEAPON · ⚡POWER · CARDNUMBER       ]  [ VALUE  ]   >
    //                  [ Treatment                          ]
    //                  [ Added [relative time]              ]
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items = entries, key = { it.userCard.id }) { entry ->
            val card = entry.card
            val weapon = card.element.takeIf { it.isNotBlank() }?.uppercase()
            val acquired = entry.userCard.acquiredAtIso
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onCardClick(card.bobaId) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(modifier = Modifier.width(60.dp).height(84.dp)) {
                    BOBACardCell(
                        imageFile = card.imageFile,
                        isSealed = card.isSealed,
                        contentDescription = card.displayName,
                    )
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    val totalAllDesignations =
                        bobaIdToTotalCopies[card.bobaId] ?: entry.userCard.quantity
                    val copiesHere = entry.userCard.quantity
                    // Title + qty pill on one row. iOS uses display font
                    // (Bebas Neue) at ~18sp here — switching from
                    // titleMedium (Roboto Flex 16sp) brings the name
                    // visually in line with the iOS row.
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            card.displayName,
                            fontSize = 18.sp,
                            fontFamily = com.bobaplaybook.core.ui.theme.DisplayFontFamily,
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        if (totalAllDesignations > 1) {
                            val label = if (totalAllDesignations == copiesHere) {
                                "×$totalAllDesignations"
                            } else {
                                "×$totalAllDesignations ($copiesHere here)"
                            }
                            Text(
                                label,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                color = com.bobaplaybook.core.ui.theme.BobaBrand.Cyan,
                                modifier = Modifier
                                    .background(
                                        color = com.bobaplaybook.core.ui.theme.BobaBrand.Cyan.copy(alpha = 0.15f),
                                        shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
                                    )
                                    .padding(horizontal = 6.dp, vertical = 1.dp),
                            )
                        }
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (weapon != null) {
                            Text(
                                weapon,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                                color = com.bobaplaybook.core.ui.theme.BobaElements.forElement(weapon),
                            )
                        }
                        card.power?.takeIf { it > 0 }?.let { p ->
                            Text(
                                "⚡$p",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            card.cardNumber,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                        )
                    }
                    card.treatment?.takeIf { it.isNotBlank() }?.let { t ->
                        Text(
                            t,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                            maxLines = 1,
                        )
                    }
                    acquired?.let {
                        Text(
                            "Added ${formatAcquiredRelative(it)}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                        )
                    }
                }
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    entry.userCard.estimatedValue?.takeIf { it > 0 }?.let { v ->
                        Text(
                            "$${v.formatUsdAmount()}",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            "VALUE",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                            letterSpacing = 1.sp,
                        )
                    }
                }
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
        }
    }
}

/** Relative time string for the "Added [time]" subtitle. iOS uses
 *  Foundation's date formatter; on Android we mirror the same 5-tier
 *  bucket scheme used everywhere else in the app (today / N days ago
 *  / N weeks ago / N months ago / specific date). */
private fun formatAcquiredRelative(iso: String): String {
    val instant = runCatching { java.time.Instant.parse(iso) }.getOrNull() ?: return "recently"
    val now = java.time.Instant.now()
    val seconds = java.time.Duration.between(instant, now).seconds
    return when {
        seconds < 60 -> "just now"
        seconds < 86_400 -> {
            val zone = java.time.ZoneId.systemDefault()
            val today = java.time.LocalDate.now(zone)
            val target = instant.atZone(zone).toLocalDate()
            if (target == today) "today" else "yesterday"
        }
        seconds < 86_400 * 7 -> "${seconds / 86_400}d ago"
        seconds < 86_400 * 30 -> "${seconds / (86_400 * 7)}w ago"
        seconds < 86_400 * 365 -> "${seconds / (86_400 * 30)}mo ago"
        else -> "${seconds / (86_400 * 365)}y ago"
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

    // Cap render at 200 cards to prevent bitmap-capture OOM on low-end
    // devices. At 1080-wide × ~9000 tall (500 cards at adaptive 90dp on
    // a 480-dpi screen), the captured bitmap is ~39 MB. iOS / web cap
    // to the same 200 number (web tick 43 for canvas-height limit).
    // Cap is unrelated to LazyVerticalGrid's viewport-only rendering;
    // it bounds the bitmap memory cost on share.
    val HARD_CAP = 200
    val truncated = entries.size > HARD_CAP
    val rendered = if (truncated) entries.take(HARD_CAP) else entries

    val graphicsLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
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
            FilterChip(
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
            TextButton(
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
        if (truncated) {
            // GLOW-yellow informational note (matches web tick 43).
            // Honest signal that what the user is about to share isn't
            // every card in the designation.
            // Tick 409 — locale-format the count. Serious collectors hit
            // 1,000+ cards; "1,234" reads cleaner than "1234".
            val nf = java.text.NumberFormat.getInstance(java.util.Locale.US)
            Text(
                "Showing the first ${nf.format(HARD_CAP)} of ${nf.format(entries.size)} cards — capture caps at ${nf.format(HARD_CAP)} for safe bitmap memory. Narrow the scope (e.g. switch designation) for a wall of every card.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFFD9C566),  // GLOW-y, informational
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
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
            items(items = rendered, key = { it.userCard.id }) { entry ->
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
        CollectionSortOrder.DATE_ADDED_DESC -> entries.sortedWith(
            artFirst.thenByDescending { it.userCard.acquiredAtIso ?: "" }
        )
        CollectionSortOrder.DATE_ADDED_ASC -> entries.sortedWith(
            artFirst.thenBy { it.userCard.acquiredAtIso ?: "￿" }
        )
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
    AlertDialog(
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
                        RadioButton(
                            selected = order == selected,
                            onClick = { onSelected(order) },
                        )
                        Text(order.label, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Done") }
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
