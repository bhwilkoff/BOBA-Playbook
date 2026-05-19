@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASignInPrompt

/**
 * Collection tab (ANDROID-DESIGN.md §8.4).
 *
 * M2 ships the UI shell:
 *  - LargeTopAppBar with "Collection" title
 *  - SingleChoiceSegmentedButtonRow with 5 designations
 *  - Either:
 *    * BOBASignInPrompt when the user isn't signed in (current default)
 *    * BOBAEmptyState when signed-in but designation is empty
 *    * LazyVerticalGrid of BOBACardCell when designation has cards
 *
 * Stub state: `isSignedIn = false`. M7 swaps this for the real auth
 * manager; the rest of the screen is data-driven so no UI rewrite
 * needed.
 *
 * Deferred to post-M2:
 *  - Custom Rainbow editor (mirrors iOS v2.219+)
 *  - Shows (streamer-role-gated)
 *  - Wall display mode (DECISIONS.md #036)
 *  - Designation badge overlay on each cell
 *  - Value summary header
 */
@Composable
fun CollectionScreen(modifier: Modifier = Modifier) {
    // Stub auth — M7 wires real Credential Manager state.
    val isSignedIn = remember { false }
    var designation by remember { mutableStateOf(Designation.PERSONAL) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Collection") },
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
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            if (!isSignedIn) {
                BOBASignInPrompt(
                    title = "Sign in to see your collection",
                    body = "Your collection, decks, and wanted list sync across iOS, web, and Android.",
                    onAction = { /* M7 — opens Credential Manager bottom sheet */ },
                )
            } else {
                CollectionGrid(
                    designation = designation,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

@Composable
private fun DesignationRow(
    selected: Designation,
    onChange: (Designation) -> Unit,
    modifier: Modifier = Modifier,
) {
    val entries = remember { Designation.entries }
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        entries.forEachIndexed { index, designation ->
            SegmentedButton(
                selected = designation == selected,
                onClick = { onChange(designation) },
                shape = SegmentedButtonDefaults.itemShape(index, entries.size),
            ) {
                Text(designation.shortLabel, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun CollectionGrid(
    designation: Designation,
    modifier: Modifier = Modifier,
) {
    // M2 stub — empty until M7 wires Supabase.
    BOBAEmptyState(
        icon = Icons.Default.Inventory2,
        headline = "No ${designation.label.lowercase()} cards yet",
        body = "Scan a card or browse Find to add your first one.",
        modifier = modifier,
    )
}

// Reserved — real grid wires here once CollectionRepository emits real
// data. Skeleton ready for M7 hookup.
@Suppress("unused")
@Composable
private fun CollectionGridSkeleton(
    cards: List<com.bobaplaybook.core.domain.model.UserCard>,
    catalogLookup: (String) -> com.bobaplaybook.core.domain.model.Card?,
    onCardClick: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyVerticalGrid(
        modifier = modifier,
        columns = GridCells.Adaptive(minSize = 110.dp),
        contentPadding = PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(cards, key = { it.id }, contentType = { "user_card" }) { uc ->
            val card = catalogLookup(uc.cardBobaId) ?: return@items
            BOBACardCell(
                imageFile = card.imageFile,
                contentDescription = card.displayName,
                modifier = Modifier
            )
        }
    }
}
