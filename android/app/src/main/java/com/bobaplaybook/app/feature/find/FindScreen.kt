@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package com.bobaplaybook.app.feature.find

import java.text.NumberFormat
import java.util.Locale
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import coil3.request.crossfade
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Style
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.InputChip
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.R
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.model.CardFormatEligibility
import com.bobaplaybook.core.domain.showcase.Showcases
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBACardSkeleton
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAWordmark
import com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar
import com.bobaplaybook.core.ui.transitions.cardSharedBounds
import kotlinx.collections.immutable.ImmutableList
import kotlinx.coroutines.launch

/**
 * Find tab — full parity with iOS SearchView (ANDROID-DESIGN.md §8.1).
 *
 * Anatomy:
 *  - SearchBar w/ Profile (leading) + Scan (trailing) when collapsed
 *  - Active filter chip strip below the bar
 *  - Toolbar Menu: Columns picker, Card Showcases toggle, Quick Add,
 *    Walkthrough re-launch
 *  - Filters button (with active-filter dot badge) opens FilterSheet
 *  - No-search state: optional Card Showcases ribbons OR full grid
 *  - Search-active state: LazyVerticalGrid of results
 *  - Cell: tap → detail (zoom transition), long-press → context menu,
 *    Quick Add mode → tap adds to Personal collection
 */
@Composable
fun FindScreen(
    onCardClick: (bobaId: String) -> Unit,
    onProfileClick: () -> Unit,
    onScanClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val viewModel: FindViewModel = hiltViewModel()
    val collectionViewModel: com.bobaplaybook.app.feature.collection.CollectionViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // Populate CardNavigationStore whenever the visible result set
    // changes — the detail screen reads it to enable horizontal swipe
    // between siblings. Mirrors iOS SearchView passing
    // `store.filteredCards` as the navigation list.
    val navHolder: com.bobaplaybook.app.feature.carddetail.CardNavigationHolderViewModel = hiltViewModel()
    LaunchedEffect(state.results) {
        navHolder.store.set(state.results.map { it.bobaId })
    }
    // Tick 279 — keyboard 'r' shortcut from BOBAApp root key handler.
    // Singleton FindActions bus emits surpriseRequested; collect here
    // and run the same pick logic the overflow Menu uses.
    LaunchedEffect(Unit) {
        viewModel.findActions.surpriseRequested.collect {
            val pool = state.results
            if (pool.isEmpty()) return@collect
            val pick = if (kotlin.random.Random.nextDouble() < 0.30) {
                val rares = pool.filter { card ->
                    val t = (card.treatment ?: "").lowercase()
                    card.isInspiredInk || t.contains("superfoil") || t.contains("kanji")
                }
                rares.randomOrNull() ?: pool.random()
            } else {
                pool.random()
            }
            onCardClick(pick.bobaId)
        }
    }
    FindContent(
        state = state,
        onEvent = viewModel::onEvent,
        collectionViewModel = collectionViewModel,
        onCardClick = onCardClick,
        onProfileClick = onProfileClick,
        onScanClick = onScanClick,
        modifier = modifier,
    )
}

@Composable
private fun FindContent(
    state: FindUiState,
    onEvent: (FindEvent) -> Unit,
    collectionViewModel: com.bobaplaybook.app.feature.collection.CollectionViewModel,
    onCardClick: (bobaId: String) -> Unit,
    onProfileClick: () -> Unit,
    onScanClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Tick 344 — re-acquire FindViewModel inside FindContent so the
    // empty-state secondary CTA can call findActions.requestSurprise()
    // without threading the bus through 5 levels of composables.
    // hiltViewModel() returns the same NavBackStackEntry-scoped
    // instance the outer FindScreen got — no duplicate VM.
    val viewModel: FindViewModel = hiltViewModel()
    var searchExpanded by rememberSaveable { mutableStateOf(false) }
    var filterSheetOpen by rememberSaveable { mutableStateOf(false) }
    var menuOpen by rememberSaveable { mutableStateOf(false) }
    // Default to showcase / no-search state — iOS DESIGN.md §8.1 calls
    // for featured ribbons above the grid when the user lands on Find
    // with no query. Toggle in the overflow Menu flips to grid mode.
    // Persistent showcase + quick-add toggles — iOS @AppStorage parity
    // via FindPrefsStore (DataStore<Preferences>). User preference
    // survives process death.
    val findPrefs: com.bobaplaybook.app.settings.FindPrefsViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val showcaseMode by findPrefs.showcaseMode.collectAsStateWithLifecycle(initialValue = true)
    val quickAdd by findPrefs.quickAdd.collectAsStateWithLifecycle(initialValue = false)
    // Grid density persists across launches via GridDensityStore
    // (DataStore<Preferences>) — iOS @AppStorage("bp_findGridColumns_v1")
    // parity. Sentinel 0 → use the size-class default of 2.
    val gridDensityVm: com.bobaplaybook.app.settings.GridDensityViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val storedColumns by gridDensityVm
        .columnsFor(com.bobaplaybook.app.settings.GridDensityStore.Target.FIND)
        .collectAsStateWithLifecycle(initialValue = 0)
    val gridColumns = if (storedColumns > 0) storedColumns else 2
    val appSnackbar = LocalAppSnackbar.current
    val scope = rememberCoroutineScope()

    Scaffold(
        modifier = modifier,
        topBar = {
            CenterAlignedTopAppBar(
                title = { BOBAWordmark() },
                navigationIcon = {
                    // Show the user's avatar (from user_profiles
                    // or provider) when signed in; fall back to the
                    // generic icon when signed out. iOS ProfileView
                    // parity — small visual signal that the user is
                    // authenticated.
                    val profileVm: com.bobaplaybook.app.feature.profile.ProfileViewModel =
                        androidx.hilt.navigation.compose.hiltViewModel()
                    val authVm: com.bobaplaybook.app.auth.AuthViewModel =
                        androidx.hilt.navigation.compose.hiltViewModel()
                    val profile by profileVm.profile.collectAsStateWithLifecycle(initialValue = null)
                    val authForAvatar by authVm.authState.collectAsStateWithLifecycle()
                    val avatarUrl = (authForAvatar as? com.bobaplaybook.app.auth.AuthState.SignedIn)?.let { signed ->
                        profile?.avatarUrl ?: profile?.discordAvatarUrl ?: signed.providerAvatarUrl
                    }
                    // Tick 400 — BOBAIconTooltip helper extracted from 11+
                    // identical TooltipBox call sites. Same affordance:
                    // mouse-hover / long-press surface "Profile".
                    BOBAIconTooltip("Profile") {
                        IconButton(onClick = onProfileClick) {
                            if (avatarUrl != null) {
                                val avatarCtx = LocalContext.current
                                coil3.compose.AsyncImage(
                                    model = coil3.request.ImageRequest.Builder(avatarCtx)
                                        .data(avatarUrl).crossfade(150).build(),
                                    contentDescription = stringResource(R.string.action_profile),
                                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                    modifier = Modifier
                                        .size(28.dp)
                                        .clip(CircleShape),
                                )
                            } else {
                                Icon(
                                    imageVector = Icons.Default.AccountCircle,
                                    contentDescription = stringResource(R.string.action_profile),
                                )
                            }
                        }
                    }
                },
                actions = {
                    Box {
                        BOBAIconTooltip("More") {
                            IconButton(onClick = { menuOpen = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "More")
                            }
                        }
                        FindOverflowMenu(
                            expanded = menuOpen,
                            onDismiss = { menuOpen = false },
                            showcaseMode = showcaseMode,
                            onShowcaseModeChange = { findPrefs.setShowcaseMode(it) },
                            quickAdd = quickAdd,
                            onQuickAddChange = { findPrefs.setQuickAdd(it) },
                            gridColumns = gridColumns,
                            onGridColumnsChange = {
                                gridDensityVm.setColumns(
                                    com.bobaplaybook.app.settings.GridDensityStore.Target.FIND,
                                    it,
                                )
                            },
                            // Tick 299 — pool size for Surprise label
                            // (iOS v2.317 + web tick 298 parity).
                            surpriseCount = state.results.size,
                            onSurpriseMe = {
                                // Tick 264 — Surprise Me: pick a random
                                // card from the FindUiState results
                                // (which mirrors the full catalog when no
                                // search is active).
                                // Tick 266 — bias toward higher-rarity
                                // pulls (Inspired Ink / Superfoil) so
                                // Surprise Me actually surfaces something
                                // notable instead of yet another Base
                                // Battlefoil. ~30% of picks weight toward
                                // rare treatments when they exist in the
                                // current filter scope.
                                val pool = state.results
                                if (pool.isEmpty()) return@FindOverflowMenu
                                val pick = if (kotlin.random.Random.nextDouble() < 0.30) {
                                    val rares = pool.filter { card ->
                                        val t = (card.treatment ?: "").lowercase()
                                        card.isInspiredInk || t.contains("superfoil") || t.contains("kanji")
                                    }
                                    rares.randomOrNull() ?: pool.random()
                                } else {
                                    pool.random()
                                }
                                onCardClick(pick.bobaId)
                            },
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            // M3 SearchBar — Filter + Scan as the only trailing actions
            FindSearchBar(
                state = state,
                expanded = searchExpanded,
                onExpandedChange = { searchExpanded = it },
                onEvent = onEvent,
                onCardClick = { id -> searchExpanded = false; onCardClick(id) },
                onScanClick = onScanClick,
                onFilterClick = { filterSheetOpen = true },
            )

            // Active filter chip strip
            ActiveFiltersRow(
                state = state,
                onEvent = onEvent,
            )

            // Quick Add toast pill + results count.
            // Only show when actually narrowing — otherwise "506 cards"
            // reads as "BOBA has 506 cards" when it's actually the
            // featured-shelf count (catalog is ~17,974).
            if (state.isSearching) {
                ResultsHeader(
                    count = state.results.size,
                    quickAdd = quickAdd,
                    // Tick 359 — surface active non-default sort as a suffix
                    // (web tick 353 + iOS v2.329 parity). Default reads as
                    // just the count; any other sort appends "· {label}" so
                    // users see what's ordering results without opening the
                    // overflow menu.
                    sortLabel = if (state.sortOrder == SortOrder.DEFAULT) null
                                else state.sortOrder.label,
                )
            }

            if (state.isLoading) {
                LinearWavyProgressIndicator(modifier = Modifier.fillMaxWidth())
            }

            when {
                state.isEmpty -> {
                    // Dynamic body line that names the active filters
                    // (web tick 29 parity). "Nothing matches FIRE.
                    // Try loosening or removing the filter." beats the
                    // generic "Try a different search."
                    val active = buildList {
                        state.query.takeIf { it.isNotBlank() }?.let { add("\"$it\"") }
                        state.activeWeapons.forEach { add(it) }
                        state.activeSet?.let { add("Set: $it") }
                        state.activeTreatment?.let { add("Treatment: $it") }
                        state.activeRelease?.let { add("Release: $it") }
                        state.showcaseId?.let { id ->
                            add("Showcase: ${Showcases.byId(id)?.name ?: id}")
                        }
                        if (state.hasImageOnly) add("image-only")
                        if (state.powerMin != null || state.powerMax != null) {
                            val mn = state.powerMin?.toString() ?: "0"
                            val mx = state.powerMax?.toString() ?: "∞"
                            add("power $mn–$mx")
                        }
                    }
                    val body = when {
                        active.isEmpty()  -> "Try a different search."
                        active.size == 1  -> "Nothing matches ${active[0]}. Try loosening or removing the filter."
                        else              -> "Nothing matches all of: ${active.joinToString(" · ")}. Try removing one."
                    }
                    BOBAEmptyState(
                        icon = Icons.Default.SearchOff,
                        headline = stringResource(R.string.find_no_results_title),
                        body = body,
                        actionLabel = "Clear filters",
                        onAction = { onEvent(FindEvent.ClearAllFilters) },
                        // Tick 344 — secondary "Surprise me from all
                        // cards" CTA (iOS v2.326 + web tick 343 parity).
                        // Clears filters then requests Surprise via the
                        // existing FindActions bus; FindScreen's
                        // LaunchedEffect picks from the freshly-recomputed
                        // results.
                        secondaryActionLabel = "🎲 Surprise me from all cards",
                        onSecondaryAction = {
                            onEvent(FindEvent.ClearAllFilters)
                            viewModel.findActions.requestSurprise()
                        },
                    )
                }
                state.isSearching || !showcaseMode -> {
                    SearchResultsGrid(
                        cards = state.results,
                        columns = gridColumns,
                        quickAdd = quickAdd,
                        onCardClick = onCardClick,
                        onQuickAdd = { card ->
                            // Quick Add = add to Personal designation. Signed-out
                            // users get a Snackbar telling them to sign in (the
                            // write would fail at RLS anyway).
                            val authState = collectionViewModel.uiState.value
                            if (!authState.isSignedIn) {
                                scope.launch {
                                    appSnackbar?.showSnackbar("Sign in to Quick Add ${card.displayName}")
                                }
                            } else {
                                collectionViewModel.add(
                                    cardBobaId = card.bobaId,
                                    designation = com.bobaplaybook.core.domain.model.Designation.PERSONAL,
                                )
                                scope.launch {
                                    appSnackbar?.showSnackbar("Added ${card.displayName} to your Collection")
                                }
                            }
                        },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                state.hasFeatured -> {
                    FeaturedShelves(
                        state = state,
                        onCardClick = onCardClick,
                        onWeaponTap = { onEvent(FindEvent.WeaponToggled(it)) },
                        onShowcaseTap = { onEvent(FindEvent.ShowcaseChanged(it)) },
                    )
                }
                else -> {
                    // Render 3 rows × column-count skeleton cells — M3
                    // guidance for LazyVerticalGrid loading state. More
                    // cells just waste compose work.
                    LazyVerticalGrid(
                        modifier = Modifier.fillMaxSize(),
                        columns = GridCells.Fixed(gridColumns),
                        contentPadding = PaddingValues(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(count = gridColumns * 3, key = { it }) { BOBACardSkeleton() }
                    }
                }
            }
        }
    }

    if (filterSheetOpen) {
        FilterSheet(
            state = state,
            onEvent = onEvent,
            onDismiss = { filterSheetOpen = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FindSearchBar(
    state: FindUiState,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onEvent: (FindEvent) -> Unit,
    onCardClick: (bobaId: String) -> Unit,
    onScanClick: () -> Unit,
    onFilterClick: () -> Unit,
) {
    // windowInsets = WindowInsets(0) — drop SearchBar's default
    // statusBarsForVisualComponents inset; the TopAppBar above
    // already draws the status bar zone. Without this override
    // the search bar sits ~status-bar-height below the wordmark.
    SearchBar(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("find_search"),
        windowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0),
        inputField = {
            SearchBarDefaults.InputField(
                query = state.query,
                onQueryChange = { onEvent(FindEvent.QueryChanged(it)) },
                onSearch = { onExpandedChange(false) },
                expanded = expanded,
                onExpandedChange = onExpandedChange,
                placeholder = { Text(stringResource(R.string.find_search_placeholder)) },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Search,
                        contentDescription = null,
                    )
                },
                trailingIcon = {
                    when {
                        expanded && state.query.isNotEmpty() -> {
                            IconButton(onClick = { onEvent(FindEvent.QueryChanged("")) }) {
                                Icon(Icons.Default.Clear, contentDescription = "Clear")
                            }
                        }
                        !expanded -> {
                            // Two trailing actions max: Filter (high-frequency,
                            // contextual) + Scan (cross-cutting). Profile +
                            // Overflow live in the TopAppBar above.
                            // Tick 400 — BOBAIconTooltip helper.
                            // Filters tooltip dynamically shows " · N active"
                            // when filters are on (tick 389 iOS/web parity).
                            Row {
                                BOBAIconTooltip(
                                    text = if (state.activeFilterCount > 0)
                                        "Filters · ${state.activeFilterCount} active"
                                    else "Filters",
                                ) {
                                    IconButton(onClick = onFilterClick) {
                                        BadgedBox(
                                            badge = {
                                                if (state.activeFilterCount > 0) {
                                                    Badge { Text("${state.activeFilterCount}") }
                                                }
                                            },
                                        ) {
                                            Icon(Icons.Default.Tune, contentDescription = "Filters")
                                        }
                                    }
                                }
                                BOBAIconTooltip("Scan a card") {
                                    IconButton(onClick = onScanClick) {
                                        Icon(
                                            imageVector = Icons.Default.QrCodeScanner,
                                            contentDescription = stringResource(R.string.action_scan),
                                        )
                                    }
                                }
                            }
                        }
                    }
                },
            )
        },
        expanded = expanded,
        onExpandedChange = onExpandedChange,
    ) {
        SearchSuggestionsList(
            suggestions = state.suggestions,
            query = state.query,
            onSuggestionTap = { suggestion ->
                onEvent(FindEvent.SuggestionTapped(suggestion))
                when (suggestion) {
                    is SearchSuggestion.CardHit -> onCardClick(suggestion.card.bobaId)
                    is SearchSuggestion.Token   -> onExpandedChange(false)
                }
            },
            onChipQuery = { onEvent(FindEvent.QueryChanged(it)) },
        )
    }
}

@Composable
private fun FindOverflowMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    showcaseMode: Boolean,
    onShowcaseModeChange: (Boolean) -> Unit,
    quickAdd: Boolean,
    onQuickAddChange: (Boolean) -> Unit,
    gridColumns: Int,
    onGridColumnsChange: (Int) -> Unit,
    surpriseCount: Int = 0,
    onSurpriseMe: () -> Unit = {},
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        // Columns picker — single-select group. Selected item gets Check.
        listOf(1, 2, 3).forEach { n ->
            DropdownMenuItem(
                text = { Text("$n column${if (n == 1) "" else "s"}") },
                leadingIcon = {
                    if (gridColumns == n) {
                        Icon(Icons.Default.Check, contentDescription = "Selected")
                    } else {
                        Icon(Icons.Default.ViewModule, contentDescription = null)
                    }
                },
                onClick = { onGridColumnsChange(n); onDismiss() },
            )
        }
        HorizontalDivider()
        // Toggle commands — tapping inverts state. Check icon shows when on.
        DropdownMenuItem(
            text = { Text("Card Showcases") },
            leadingIcon = {
                if (showcaseMode) Icon(Icons.Default.Check, contentDescription = "On")
                else Icon(Icons.Default.Style, contentDescription = null)
            },
            onClick = { onShowcaseModeChange(!showcaseMode); onDismiss() },
        )
        DropdownMenuItem(
            text = { Text("Quick Add to Collection") },
            leadingIcon = {
                if (quickAdd) Icon(Icons.Default.Check, contentDescription = "On")
                else Icon(Icons.Default.Add, contentDescription = null)
            },
            onClick = { onQuickAddChange(!quickAdd); onDismiss() },
        )
        HorizontalDivider()
        // Tick 264 — Surprise Me discovery action. Picks a random card
        // from the currently-visible results (or full catalog if none
        // filtered) and pushes its detail. Real value for collectors
        // exploring 17k+ cards who don't know what to search for.
        DropdownMenuItem(
            // Tick 299 — pool size in label (iOS v2.317 + web tick 298
            // parity). Tells users what Surprise is drawing from before
            // they fire it. NumberFormat / Locale.US matches the rest
            // of the app's locale-formatting convention.
            text = {
                val label = if (surpriseCount > 0)
                    "Surprise me 🎲 (${NumberFormat.getInstance(Locale.US).format(surpriseCount)})"
                else "Surprise me 🎲"
                Text(label)
            },
            // Tick 281 — Star reads more "discovery / serendipity" than
            // Bolt (which is BOBA's weapon-filter chip icon). Icons.Star
            // is in the baseline icon set (already used in
            // CardDetailScreen's owned-state).
            leadingIcon = { Icon(Icons.Default.Star, contentDescription = null) },
            enabled = surpriseCount > 0,
            onClick = { onDismiss(); onSurpriseMe() },
        )
    }
}

@Composable
private fun SearchSuggestionsList(
    suggestions: ImmutableList<SearchSuggestion>,
    query: String,
    onSuggestionTap: (SearchSuggestion) -> Unit,
    onChipQuery: (String) -> Unit,
) {
    if (query.length < 2) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            BOBASectionHeader(title = "Try")
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(horizontal = 16.dp),
            ) {
                items(items = listOf("Maverick", "LeBoss", "Tigre", "JacHammer", "Skeee"), key = { it }) { hint ->
                    AssistChip(
                        onClick = { onChipQuery(hint) },
                        label = { Text(hint) },
                        leadingIcon = {
                            Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.width(18.dp).height(18.dp))
                        },
                    )
                }
            }
        }
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items = suggestions, key = { it.suggestionKey() }) { suggestion ->
            when (suggestion) {
                is SearchSuggestion.CardHit -> {
                    ListItem(
                        headlineContent = { Text(suggestion.card.displayName) },
                        supportingContent = {
                            Text(
                                "${suggestion.card.cardNumber} · ${suggestion.card.element.lowercase().replaceFirstChar { it.uppercase() }}",
                                style = MaterialTheme.typography.labelMedium,
                            )
                        },
                        leadingContent = {
                            Box(modifier = Modifier.width(40.dp).height(56.dp)) {
                                BOBACardCell(
                                    imageFile = suggestion.card.imageFile,
                                    contentDescription = suggestion.card.displayName,
                                    isSealed = suggestion.card.isSealed,
                                )
                            }
                        },
                        modifier = Modifier.clickable { onSuggestionTap(suggestion) },
                    )
                }
                is SearchSuggestion.Token -> {
                    ListItem(
                        headlineContent = {
                            Text("${suggestion.kind.name.lowercase().replaceFirstChar { it.uppercase() }}: ${suggestion.value}")
                        },
                        supportingContent = { Text("Filter the catalog", style = MaterialTheme.typography.labelMedium) },
                        leadingContent = {
                            val icon = when (suggestion.kind) {
                                TokenKind.WEAPON -> Icons.Default.Bolt
                                TokenKind.TREATMENT, TokenKind.SET -> Icons.Default.Style
                            }
                            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        },
                        modifier = Modifier.clickable { onSuggestionTap(suggestion) },
                    )
                }
            }
        }
    }
}

private fun SearchSuggestion.suggestionKey(): String = when (this) {
    is SearchSuggestion.CardHit -> "card-${card.bobaId}"
    is SearchSuggestion.Token   -> "token-$kind-$value"
}

@Composable
private fun ActiveFiltersRow(state: FindUiState, onEvent: (FindEvent) -> Unit) {
    if (state.activeFilterCount == 0) return
    LazyRow(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        state.activeWeapons.forEach { w ->
            item(key = "weapon-$w") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.WeaponToggled(w)) },
                    label = { Text("Weapon: $w") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        state.activeTreatment?.let { t ->
            item(key = "treatment") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.TreatmentChanged(null)) },
                    label = { Text("Treatment: $t") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        state.activeSet?.let { s ->
            item(key = "set") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.SetChanged(null)) },
                    label = { Text("Set: $s") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        state.activeRelease?.let { r ->
            item(key = "release") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.ReleaseChanged(null)) },
                    label = { Text("Release: $r") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        if (state.cardPurpose != CardPurpose.ALL) {
            item(key = "purpose") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.CardPurposeChanged(CardPurpose.ALL)) },
                    label = { Text(state.cardPurpose.label) },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        state.showcaseId?.let { id ->
            item(key = "showcase") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.ShowcaseChanged(null)) },
                    label = { Text(Showcases.byId(id)?.name ?: "Showcase") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        if (state.hasImageOnly) {
            item(key = "has-image") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.HasImageToggled(false)) },
                    label = { Text("Has image") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        if (state.powerMin != null || state.powerMax != null) {
            item(key = "power") {
                InputChip(
                    selected = true,
                    onClick = {
                        onEvent(FindEvent.PowerMinChanged(null))
                        onEvent(FindEvent.PowerMaxChanged(null))
                    },
                    label = {
                        val mn = state.powerMin?.toString() ?: "—"
                        val mx = state.powerMax?.toString() ?: "—"
                        Text("Power: $mn → $mx")
                    },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
    }
}

@Composable
private fun ResultsHeader(count: Int, quickAdd: Boolean, sortLabel: String? = null) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Tick 359 — locale-format the count + suffix active sort
        // (iOS v2.329 + web tick 353 parity).
        val countLabel = remember(count, sortLabel) {
            val n = NumberFormat.getInstance(Locale.US).format(count)
            if (sortLabel.isNullOrBlank()) "$n cards"
            else "$n cards · $sortLabel"
        }
        Text(
            countLabel,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        if (quickAdd) {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        Icons.Default.Add,
                        contentDescription = null,
                        modifier = Modifier.width(14.dp).height(14.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        "Quick Add ON",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
private fun FeaturedShelves(
    state: FindUiState,
    onCardClick: (String) -> Unit,
    onWeaponTap: (String) -> Unit,
    onShowcaseTap: (String) -> Unit,
) {
    val scrollState = rememberScrollState()
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Spacer(Modifier.height(8.dp))

        if (state.recentlyAdded.isNotEmpty()) {
            BOBASectionHeader(title = "Recently added")
            CardCarousel(cards = state.recentlyAdded, onCardClick = onCardClick, cellWidth = 120.dp)
        }

        // Card showcases — one carousel per Showcase (WoBA, Rookie
        // Inspired, every named sport). iOS DESIGN.md sec 8.1 parity.
        state.showcaseShelves.forEach { showcase ->
            BOBASectionHeader(
                title = showcase.name,
                actionLabel = "See all",
                onAction = { onShowcaseTap(showcase.showcaseId) },
            )
            CardCarousel(cards = showcase.cards, onCardClick = onCardClick, cellWidth = 110.dp)
        }

        BOBASectionHeader(title = "By weapon")
        LazyRow(
            modifier = Modifier.padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            items(items = state.heroesByWeapon, key = { it.weapon }) { shelf ->
                FilterChip(
                    selected = state.activeWeapons.contains(shelf.weapon),
                    onClick = { onWeaponTap(shelf.weapon) },
                    label = { Text(shelf.weapon) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                )
            }
        }

        // Render all weapon carousels (was take(3) — audit P1 #3
        // called for the full 8-weapon set).
        state.heroesByWeapon.forEach { shelf ->
            BOBASectionHeader(title = "${shelf.weapon} heroes", actionLabel = "See all", onAction = { onWeaponTap(shelf.weapon) })
            CardCarousel(cards = shelf.cards, onCardClick = onCardClick, cellWidth = 110.dp)
        }

        if (state.coachingStaff.isNotEmpty()) {
            BOBASectionHeader(title = "Coaching staff")
            CardCarousel(cards = state.coachingStaff, onCardClick = onCardClick, cellWidth = 110.dp)
        }

        Spacer(Modifier.height(80.dp))
    }
}

@Composable
private fun CardCarousel(
    cards: ImmutableList<Card>,
    onCardClick: (String) -> Unit,
    cellWidth: androidx.compose.ui.unit.Dp,
) {
    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(items = cards, key = { it.bobaId }, contentType = { "card" }) { card ->
            Box(modifier = Modifier.width(cellWidth)) {
                BOBACardCell(
                    imageFile = card.imageFile,
                    contentDescription = card.displayName,
                    isSealed = card.isSealed,
                    printRunLabel = card.printRunLabel,
                    formatLegalityHint = CardFormatEligibility.restrictedLegalAbbrev(card),
                    modifier = Modifier
                        .cardSharedBounds(card.bobaId)
                        .clickable { onCardClick(card.bobaId) },
                )
            }
        }
    }
}

@Composable
private fun SearchResultsGrid(
    cards: ImmutableList<Card>,
    columns: Int,
    quickAdd: Boolean,
    onCardClick: (bobaId: String) -> Unit,
    onQuickAdd: (Card) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Tick 249 — haptic confirmation on long-press → Quick Add.
    // Matches iOS UIImpactFeedbackGenerator(.medium); the user
    // gets a small bump confirming the card landed before the
    // snackbar surfaces. Without it, long-press feels like
    // "did anything happen?" Pulled outside LazyVerticalGrid since
    // LazyGridScope is non-composable.
    val haptic = LocalHapticFeedback.current
    LazyVerticalGrid(
        modifier = modifier,
        columns = if (columns >= 1) GridCells.Fixed(columns) else GridCells.Adaptive(minSize = 110.dp),
        contentPadding = PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(items = cards, key = { it.bobaId }, contentType = { "card" }) { card ->
            BOBACardCell(
                imageFile = card.imageFile,
                contentDescription = card.displayName,
                isSealed = card.isSealed,
                printRunLabel = card.printRunLabel,
                formatLegalityHint = CardFormatEligibility.restrictedLegalAbbrev(card),
                modifier = Modifier
                    .cardSharedBounds(card.bobaId)
                    .combinedClickable(
                        onClick = {
                            if (quickAdd) {
                                haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                                onQuickAdd(card)
                            } else {
                                onCardClick(card.bobaId)
                            }
                        },
                        onLongClick = {
                            haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                            onQuickAdd(card)
                        },
                    )
                    .testTag("card_${card.bobaId}"),
            )
        }
    }
}
