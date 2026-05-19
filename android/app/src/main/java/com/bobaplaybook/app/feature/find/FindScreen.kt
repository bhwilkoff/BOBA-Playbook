@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.find

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.R
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAWordmark
import kotlinx.collections.immutable.ImmutableList

/**
 * Find tab — the explorer (ANDROID-DESIGN.md §8.1).
 *
 * M1 ships the minimum that's actually useful:
 *  - Search field at the top with 100ms debounced filter
 *  - FilterChip row for weapon scope
 *  - LazyVerticalGrid of BOBACardCell results, stable-keyed by bobaId
 *  - BOBAEmptyState when zero matches
 *  - LinearProgressIndicator while phase-2 catalog decode runs
 *
 * Deferred to M1 follow-up:
 *  - Featured shelves in the no-search state (HorizontalMultiBrowseCarousel
 *    is in Material 3 Expressive — requires compileSdk 37)
 *  - Container transform animation into card detail (M3 sharedBounds)
 *  - M3 SearchBar full-screen morph (uses OutlinedTextField for M1 pragmatism)
 *  - Suggestion chips while typing
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

/**
 * Stateless variant — passes `state` + `onEvent` explicitly. Easier
 * to preview + screenshot-test. The wrapper above injects the
 * ViewModel; this body knows nothing about Hilt.
 */
@Composable
private fun FindContent(
    state: FindUiState,
    onEvent: (FindEvent) -> Unit,
    onCardClick: (bobaId: String) -> Unit,
    onProfileClick: () -> Unit,
    onScanClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            CenterAlignedTopAppBar(
                title = { BOBAWordmark() },
                navigationIcon = {
                    IconButton(onClick = onProfileClick) {
                        Icon(
                            imageVector = Icons.Default.AccountCircle,
                            contentDescription = stringResource(R.string.action_profile),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onScanClick) {
                        Icon(
                            imageVector = Icons.Default.QrCodeScanner,
                            contentDescription = stringResource(R.string.action_scan),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                    scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            OutlinedTextField(
                value = state.query,
                onValueChange = { onEvent(FindEvent.QueryChanged(it)) },
                placeholder = { Text(stringResource(R.string.find_search_placeholder)) },
                leadingIcon = {
                    Icon(imageVector = Icons.Default.Search, contentDescription = null)
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .testTag("find_search"),
            )

            WeaponFilterRow(
                selected = state.activeWeapon,
                onWeaponToggle = { onEvent(FindEvent.WeaponToggled(it)) },
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            )

            if (state.isLoading) {
                LinearProgressIndicator(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                )
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
                else -> CardGrid(
                    cards = state.results,
                    onCardClick = onCardClick,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

@Composable
private fun WeaponFilterRow(
    selected: String?,
    onWeaponToggle: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val weapons = remember { listOf("FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER") }
    LazyRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(horizontal = 8.dp),
    ) {
        items(weapons) { weapon ->
            FilterChip(
                selected = selected == weapon,
                onClick = { onWeaponToggle(weapon) },
                label = { Text(weapon, style = MaterialTheme.typography.labelMedium) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                ),
            )
        }
    }
}

@Composable
private fun CardGrid(
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
            key = { card -> card.bobaId },     // STABLE KEY per ANDROID-DEV.md §11.4
            contentType = { _ -> "card" },
        ) { card ->
            BOBACardCell(
                imageFile = card.imageFile,
                contentDescription = card.displayName,
                modifier = Modifier
                    .clickable { onCardClick(card.bobaId) }
                    .testTag("card_${card.bobaId}"),
            )
        }
    }
}
