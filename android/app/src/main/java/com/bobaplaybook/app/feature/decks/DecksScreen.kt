@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBASignInPrompt
import com.bobaplaybook.app.feature.find.FindViewModel

/**
 * Decks tab (ANDROID-DESIGN.md §8.3).
 *
 * M4 ships the compact-width shell:
 *  - TopAppBar
 *  - Card pool (reuses Find's filtered catalog as the source — same
 *    underlying CardRepository; M4 wires its own filter Composable
 *    once Decks-specific format constraints land)
 *  - DeckSummaryBar pinned at the bottom (Scaffold bottomBar) —
 *    shows "Sign in to save decks" inline prompt by default
 *
 * Deferred (post-M4 polish):
 *  - Tap-summary → ModalBottomSheet editor with sharedBounds zoom
 *    (full editor depends on Deck data layer which lands M7)
 *  - 3-pane NavigableListDetailPaneScaffold on tablet/Chromebook
 *  - Long-press on pool card to add (waiting on draft state)
 *  - Drag-and-drop add via Modifier.dragAndDropSource
 *  - Manage / Rules / Legality push destinations
 */
@Composable
fun DecksScreen(
    onCardClick: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Reuse Find's ViewModel as the pool data source for M4 — same
    // catalog repository; Decks-specific filtering arrives when M7
    // wires deck-format legality.
    val viewModel: FindViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Decks") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
        bottomBar = { DeckSummaryBar() },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            CardPoolGrid(
                cards = state.results,
                onCardClick = onCardClick,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
private fun CardPoolGrid(
    cards: List<Card>,
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
            Box(modifier = Modifier.padding(2.dp)) {
                BOBACardCell(
                    imageFile = card.imageFile,
                    contentDescription = card.displayName,
                )
            }
        }
    }
}

/**
 * Persistent draft summary bar — the "always present" tap target for
 * the editor (ANDROID-DESIGN.md §8.3). M4 ships the not-signed-in
 * variant; M7 adds the live-draft variant once Deck data layer lands.
 */
@Composable
private fun DeckSummaryBar() {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 3.dp,
    ) {
        BOBASignInPrompt(
            title = "Build a deck",
            body = "Sign in to save your deck across iOS, web, and Android.",
            actionLabel = "Sign in",
            onAction = { /* M7 — Credential Manager bottom sheet */ },
        )
    }
}
