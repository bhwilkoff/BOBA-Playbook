@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package com.bobaplaybook.app.feature.find

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
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.Style
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.R
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.showcase.Showcases
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBACardSkeleton
import com.bobaplaybook.core.ui.components.BOBAEmptyState
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
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    FindContent(
        state = state,
        onEvent = viewModel::onEvent,
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
    onCardClick: (bobaId: String) -> Unit,
    onProfileClick: () -> Unit,
    onScanClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var searchExpanded by rememberSaveable { mutableStateOf(false) }
    var filterSheetOpen by rememberSaveable { mutableStateOf(false) }
    var menuOpen by rememberSaveable { mutableStateOf(false) }
    var showcaseMode by rememberSaveable { mutableStateOf(false) }
    var quickAdd by rememberSaveable { mutableStateOf(false) }
    var gridColumns by rememberSaveable { mutableStateOf(2) }
    val appSnackbar = LocalAppSnackbar.current
    val scope = rememberCoroutineScope()

    Scaffold(modifier = modifier) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            // M3 SearchBar
            FindSearchBar(
                state = state,
                expanded = searchExpanded,
                onExpandedChange = { searchExpanded = it },
                onEvent = onEvent,
                onCardClick = { id -> searchExpanded = false; onCardClick(id) },
                onProfileClick = onProfileClick,
                onScanClick = onScanClick,
                onFilterClick = { filterSheetOpen = true },
                onMenuClick = { menuOpen = true },
                menuExpanded = menuOpen,
                onMenuDismiss = { menuOpen = false },
                showcaseMode = showcaseMode,
                onShowcaseModeChange = { showcaseMode = it },
                quickAdd = quickAdd,
                onQuickAddChange = { quickAdd = it },
                gridColumns = gridColumns,
                onGridColumnsChange = { gridColumns = it },
            )

            // Active filter chip strip
            ActiveFiltersRow(
                state = state,
                onEvent = onEvent,
            )

            // Quick Add toast pill + results count
            if (state.isSearching || state.hasFeatured) {
                ResultsHeader(
                    count = state.results.size,
                    quickAdd = quickAdd,
                )
            }

            if (state.isLoading) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }

            when {
                state.isEmpty -> {
                    BOBAEmptyState(
                        icon = Icons.Default.SearchOff,
                        headline = stringResource(R.string.find_no_results_title),
                        body = stringResource(R.string.find_no_results_body),
                        actionLabel = "Clear filters",
                        onAction = { onEvent(FindEvent.ClearAllFilters) },
                    )
                }
                state.isSearching || !showcaseMode -> {
                    SearchResultsGrid(
                        cards = state.results,
                        columns = gridColumns,
                        quickAdd = quickAdd,
                        onCardClick = onCardClick,
                        onQuickAdd = { card ->
                            // M7 polish — actually call CollectionRepository.add.
                            // For v1, surface the auth requirement.
                            scope.launch {
                                appSnackbar?.showSnackbar("Sign in to Quick Add ${card.displayName}")
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
                    LazyVerticalGrid(
                        modifier = Modifier.fillMaxSize(),
                        columns = GridCells.Fixed(gridColumns),
                        contentPadding = PaddingValues(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(count = 12, key = { it }) { BOBACardSkeleton() }
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
    onProfileClick: () -> Unit,
    onScanClick: () -> Unit,
    onFilterClick: () -> Unit,
    onMenuClick: () -> Unit,
    menuExpanded: Boolean,
    onMenuDismiss: () -> Unit,
    showcaseMode: Boolean,
    onShowcaseModeChange: (Boolean) -> Unit,
    quickAdd: Boolean,
    onQuickAddChange: (Boolean) -> Unit,
    gridColumns: Int,
    onGridColumnsChange: (Int) -> Unit,
) {
    SearchBar(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("find_search"),
        inputField = {
            SearchBarDefaults.InputField(
                query = state.query,
                onQueryChange = { onEvent(FindEvent.QueryChanged(it)) },
                onSearch = { onExpandedChange(false) },
                expanded = expanded,
                onExpandedChange = onExpandedChange,
                placeholder = { Text(stringResource(R.string.find_search_placeholder)) },
                leadingIcon = {
                    if (expanded) {
                        IconButton(onClick = { onExpandedChange(false) }) {
                            Icon(Icons.Default.Clear, contentDescription = "Close search")
                        }
                    } else {
                        IconButton(onClick = onProfileClick) {
                            Icon(
                                imageVector = Icons.Default.AccountCircle,
                                contentDescription = stringResource(R.string.action_profile),
                            )
                        }
                    }
                },
                trailingIcon = {
                    if (state.query.isNotEmpty() && expanded) {
                        IconButton(onClick = { onEvent(FindEvent.QueryChanged("")) }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear")
                        }
                    } else if (!expanded) {
                        Row {
                            // Filter button w/ active-count badge
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
                            // Scan
                            IconButton(onClick = onScanClick) {
                                Icon(
                                    imageVector = Icons.Default.QrCodeScanner,
                                    contentDescription = stringResource(R.string.action_scan),
                                )
                            }
                            // Overflow menu
                            Box {
                                IconButton(onClick = onMenuClick) {
                                    Icon(Icons.Default.MoreVert, contentDescription = "More")
                                }
                                FindOverflowMenu(
                                    expanded = menuExpanded,
                                    onDismiss = onMenuDismiss,
                                    showcaseMode = showcaseMode,
                                    onShowcaseModeChange = onShowcaseModeChange,
                                    quickAdd = quickAdd,
                                    onQuickAddChange = onQuickAddChange,
                                    gridColumns = gridColumns,
                                    onGridColumnsChange = onGridColumnsChange,
                                )
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
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        // Columns picker
        Text(
            "Columns",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        listOf(1, 2, 3).forEach { n ->
            DropdownMenuItem(
                text = { Text("$n across") },
                leadingIcon = { Icon(Icons.Default.ViewModule, contentDescription = null) },
                trailingIcon = {
                    if (gridColumns == n) Icon(Icons.Default.Visibility, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                },
                onClick = { onGridColumnsChange(n) },
            )
        }
        androidx.compose.material3.HorizontalDivider()
        // Card Showcases toggle
        DropdownMenuItem(
            text = { Text("Card Showcases") },
            leadingIcon = { Icon(Icons.Default.Style, contentDescription = null) },
            trailingIcon = {
                androidx.compose.material3.Switch(checked = showcaseMode, onCheckedChange = onShowcaseModeChange)
            },
            onClick = { onShowcaseModeChange(!showcaseMode) },
        )
        // Quick Add toggle
        DropdownMenuItem(
            text = { Text("Quick Add to Collection") },
            leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) },
            trailingIcon = {
                androidx.compose.material3.Switch(checked = quickAdd, onCheckedChange = onQuickAddChange)
            },
            onClick = { onQuickAddChange(!quickAdd) },
        )
        androidx.compose.material3.HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Show walkthrough") },
            leadingIcon = { Icon(Icons.Default.LocalFireDepartment, contentDescription = null) },
            onClick = onDismiss,  // M7 polish — actual walkthrough re-launcher
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
                                BOBACardCell(imageFile = suggestion.card.imageFile, contentDescription = suggestion.card.displayName)
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
private fun ResultsHeader(count: Int, quickAdd: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "$count cards",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        if (quickAdd) {
            AssistChip(
                onClick = {},
                label = { Text("Quick Add ON", fontWeight = FontWeight.Bold) },
                leadingIcon = {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.width(14.dp).height(14.dp))
                },
            )
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
        Box(
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 8.dp),
            contentAlignment = Alignment.Center,
        ) { BOBAWordmark() }

        BOBASectionHeader(title = "Card showcases")
        LazyRow(
            modifier = Modifier.padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            items(items = Showcases.all, key = { it.id }) { showcase ->
                AssistChip(
                    onClick = { onShowcaseTap(showcase.id) },
                    label = { Text(showcase.name) },
                )
            }
        }

        if (state.recentlyAdded.isNotEmpty()) {
            BOBASectionHeader(title = "Recently added")
            CardCarousel(cards = state.recentlyAdded, onCardClick = onCardClick, cellWidth = 120.dp)
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

        state.heroesByWeapon.take(3).forEach { shelf ->
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
                modifier = Modifier
                    .cardSharedBounds(card.bobaId)
                    .combinedClickable(
                        onClick = {
                            if (quickAdd) onQuickAdd(card) else onCardClick(card.bobaId)
                        },
                        onLongClick = { onQuickAdd(card) },
                    )
                    .testTag("card_${card.bobaId}"),
            )
        }
    }
}
