@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Add to Deck sheet — mirrors iOS AddToDeckSheet.swift.
 *
 * Lists the active draft + any saved decks (when M7 lands persistence).
 * Tap a deck → adds the card and closes. v1 shows the active draft only.
 */
@Composable
fun AddToDeckSheet(
    card: Card,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val decksViewModel: DecksViewModel = hiltViewModel()
    val draft by decksViewModel.draft.collectAsStateWithLifecycle()
    val savedDecks by decksViewModel.savedDecks.collectAsStateWithLifecycle()
    // Catalog snapshot for the load-then-add path on saved decks.
    val catalogVm: com.bobaplaybook.app.feature.collection.RainbowCatalogViewModel = hiltViewModel()
    val catalog by catalogVm.cards.collectAsStateWithLifecycle()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(bottom = 32.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Add to Deck",
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close")
                }
            }
            HorizontalDivider()
            Text(
                "Adding ${card.displayName} to:",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            BOBASectionHeader(title = "Current draft")
            // Project the post-add deck shape so the user can see at a
            // glance whether this card pushes them over a cap. Mirrors
            // iOS DeckBuilderView's add-time projection helper.
            val projectedHD = draft.totalHD + (card.hd ?: 0)
            val projectedDBS = draft.totalDBS + (card.dbs ?: 0)
            val projectedPlays = draft.playCount + draft.bonusCount +
                (if (card.cardType.contains("Play", ignoreCase = true)) 1 else 0)
            val overHD = projectedHD > draft.hdCap
            val overPlays = projectedPlays > draft.playCap
            val overDBS = draft.enforcesDBS && projectedDBS > draft.dbsBudget
            ListItem(
                headlineContent = { Text(draft.name) },
                supportingContent = {
                    Column {
                        Text(
                            "${draft.heroCount} heroes · $projectedPlays/${draft.playCap} plays · $projectedHD/${draft.hdCap} HD",
                            style = MaterialTheme.typography.labelMedium,
                            color = if (overHD || overPlays) MaterialTheme.colorScheme.error
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (draft.enforcesDBS) {
                            Text(
                                "DBS $projectedDBS/${draft.dbsBudget}",
                                style = MaterialTheme.typography.labelMedium,
                                color = if (overDBS) MaterialTheme.colorScheme.error
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
                leadingContent = {
                    Icon(Icons.Default.ViewModule, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                },
                trailingContent = {
                    Icon(Icons.Default.Add, contentDescription = "Add")
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        decksViewModel.add(card)
                        onDismiss()
                    },
            )

            if (savedDecks.isNotEmpty()) {
                HorizontalDivider()
                BOBASectionHeader(title = "Saved decks")
                savedDecks.forEach { saved ->
                    ListItem(
                        headlineContent = { Text(saved.name) },
                        supportingContent = {
                            val total = saved.cards.sumOf { it.quantity }
                            Text("$total cards", style = MaterialTheme.typography.labelMedium)
                        },
                        leadingContent = {
                            Icon(Icons.Default.ViewModule, contentDescription = null)
                        },
                        trailingContent = {
                            Icon(Icons.Default.Add, contentDescription = "Open and add")
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                // Load the saved deck as the draft, then push
                                // the new card. User sees the deck open with
                                // the card already added.
                                decksViewModel.loadSaved(saved, catalog)
                                decksViewModel.add(card)
                                onDismiss()
                            },
                    )
                }
            } else {
                HorizontalDivider()
                BOBASectionHeader(title = "Saved decks")
                Text(
                    "Sign in + tap Save in the editor to keep decks across iOS, web, and Android.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}
