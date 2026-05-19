@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
)

package com.bobaplaybook.app.feature.find

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.Style
import androidx.compose.material3.AssistChip
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.R
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.adaptive.isCompactWidth
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBACardSkeleton
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAWordmark
import com.bobaplaybook.core.ui.transitions.cardSharedBounds
import kotlinx.collections.immutable.ImmutableList

/**
 * Find tab — the explorer (ANDROID-DESIGN.md §8.1).
 *
 * Anatomy:
 *  - M3 `SearchBar` morphs to full-screen on focus
 *  - Live suggestions inside the expanded SearchBar content area
 *  - InputChip row for committed filters (weapon, treatment)
 *  - No-search state: BOBAWordmark + featured carousels
 *  - Search-active state: LazyVerticalGrid results
 *
 * Container transform into card detail uses
 * [Modifier.cardSharedBounds] which reads the shared-transition scope
 * from CompositionLocal — no scope plumbing through this function's
 * signature.
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

    Scaffold(modifier = modifier) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            FindSearchBar(
                state = state,
                expanded = searchExpanded,
                onExpandedChange = { searchExpanded = it },
                onEvent = onEvent,
                onCardClick = { bobaId ->
                    searchExpanded = false
                    onCardClick(bobaId)
                },
                onProfileClick = onProfileClick,
                onScanClick = onScanClick,
            )

            ActiveFiltersRow(
                state = state,
                onEvent = onEvent,
            )

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
                        onAction = { onEvent(FindEvent.ClearFilters) },
                    )
                }
                state.isSearching -> {
                    SearchResultsGrid(
                        cards = state.results,
                        onCardClick = onCardClick,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                state.hasFeatured -> {
                    FeaturedShelves(
                        state = state,
                        onCardClick = onCardClick,
                        onWeaponTap = { onEvent(FindEvent.WeaponToggled(it)) },
                    )
                }
                else -> {
                    // Catalog still booting — show shape-of-real-grid
                    // shimmer skeletons rather than an empty-state.
                    LazyVerticalGrid(
                        modifier = Modifier.fillMaxSize(),
                        columns = GridCells.Adaptive(minSize = 110.dp),
                        contentPadding = PaddingValues(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(count = 12, key = { it }) {
                            BOBACardSkeleton()
                        }
                    }
                }
            }
        }
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
                        IconButton(onClick = onScanClick) {
                            Icon(
                                imageVector = Icons.Default.QrCodeScanner,
                                contentDescription = stringResource(R.string.action_scan),
                            )
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
            onChipQuery = { hint ->
                onEvent(FindEvent.QueryChanged(hint))
            },
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
                items(
                    items = listOf("Maverick", "LeBoss", "Tigre", "JacHammer", "Skeee"),
                    key = { it },
                ) { hint ->
                    AssistChip(
                        onClick = { onChipQuery(hint) },
                        label = { Text(hint) },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = null,
                                modifier = Modifier.width(18.dp).height(18.dp),
                            )
                        },
                    )
                }
            }
        }
        return
    }

    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(
            items = suggestions,
            key = { suggestion ->
                when (suggestion) {
                    is SearchSuggestion.CardHit -> "card-${suggestion.card.bobaId}"
                    is SearchSuggestion.Token   -> "token-${suggestion.kind}-${suggestion.value}"
                }
            },
        ) { suggestion ->
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
                                TokenKind.WEAPON    -> Icons.Default.Bolt
                                TokenKind.TREATMENT -> Icons.Default.Style
                                TokenKind.SET       -> Icons.Default.Style
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

@Composable
private fun ActiveFiltersRow(
    state: FindUiState,
    onEvent: (FindEvent) -> Unit,
) {
    if (state.activeWeapon == null && state.activeTreatment == null) return
    LazyRow(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        state.activeWeapon?.let { w ->
            item(key = "weapon") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.WeaponToggled(null)) },
                    label = { Text("Weapon: $w") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
        state.activeTreatment?.let { t ->
            item(key = "treatment") {
                InputChip(
                    selected = true,
                    onClick = { onEvent(FindEvent.TreatmentToggled(null)) },
                    label = { Text("Treatment: $t") },
                    trailingIcon = { Icon(Icons.Default.Clear, contentDescription = "Remove") },
                )
            }
        }
    }
}

@Composable
private fun FeaturedShelves(
    state: FindUiState,
    onCardClick: (String) -> Unit,
    onWeaponTap: (String) -> Unit,
) {
    val scrollState = rememberScrollState()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp, bottom = 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            BOBAWordmark()
        }

        if (state.recentlyAdded.isNotEmpty()) {
            BOBASectionHeader(title = "Recently added")
            CardCarousel(
                cards = state.recentlyAdded,
                onCardClick = onCardClick,
                cellWidth = 120.dp,
            )
        }

        BOBASectionHeader(title = "By weapon")
        LazyRow(
            modifier = Modifier.padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            items(
                items = state.heroesByWeapon,
                key = { it.weapon },
            ) { shelf ->
                FilterChip(
                    selected = state.activeWeapon == shelf.weapon,
                    onClick = { onWeaponTap(shelf.weapon) },
                    label = { Text(shelf.weapon) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                )
            }
        }

        state.heroesByWeapon.take(3).forEach { shelf ->
            BOBASectionHeader(
                title = "${shelf.weapon} heroes",
                actionLabel = "See all",
                onAction = { onWeaponTap(shelf.weapon) },
            )
            CardCarousel(
                cards = shelf.cards,
                onCardClick = onCardClick,
                cellWidth = 110.dp,
            )
        }

        if (state.coachingStaff.isNotEmpty()) {
            BOBASectionHeader(title = "Coaching staff")
            CardCarousel(
                cards = state.coachingStaff,
                onCardClick = onCardClick,
                cellWidth = 110.dp,
            )
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
        items(
            items = cards,
            key = { card -> card.bobaId },
            contentType = { "card" },
        ) { card ->
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
    onCardClick: (bobaId: String) -> Unit,
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
            contentType = { _ -> "card" },
        ) { card ->
            BOBACardCell(
                imageFile = card.imageFile,
                contentDescription = card.displayName,
                modifier = Modifier
                    .cardSharedBounds(card.bobaId)
                    .clickable { onCardClick(card.bobaId) }
                    .testTag("card_${card.bobaId}"),
            )
        }
    }
}
