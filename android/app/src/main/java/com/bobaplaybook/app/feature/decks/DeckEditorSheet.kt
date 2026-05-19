@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Deck editor — full-screen ModalBottomSheet on compact (ANDROID-
 * DESIGN.md §8.3). Tap the summary bar → this opens.
 *
 *  - Editable name field at top
 *  - Stats row (hero/play/bonus/HD with legality chip)
 *  - Sectioned card list (Heroes / Plays / Bonus / Coach)
 *  - Remove via swipe / tap delete on each row
 *  - Save action triggers Supabase persist when M7 wires it
 */
@Composable
fun DeckEditorSheet(
    draft: DeckDraft,
    onDismiss: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        DeckEditorContent(
            draft = draft,
            onDismiss = onDismiss,
            onRename = onRename,
            onRemove = onRemove,
            onSave = onSave,
        )
    }
}

/**
 * Inline editor variant — same body content as the ModalBottomSheet
 * editor, but rendered directly inside a tablet's right-pane Surface.
 * No close button (the pane is always-visible on tablet).
 */
@Composable
fun DeckEditorContentInline(
    draft: DeckDraft,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
) {
    var name by remember { mutableStateOf(draft.name) }
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it; onRename(it) },
                label = { Text("Deck name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }

        StatsRow(draft = draft)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            androidx.compose.material3.OutlinedButton(onClick = onOpenRules) { Text("Rules") }
            androidx.compose.material3.OutlinedButton(onClick = onOpenLegality) { Text("Legality") }
            Spacer(Modifier.weight(1f))
            Button(
                onClick = onSave,
                enabled = draft.cards.isNotEmpty(),
            ) {
                Icon(Icons.Default.Save, contentDescription = null, modifier = Modifier.width(18.dp).height(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Save")
            }
        }

        HorizontalDivider()

        if (draft.cards.isEmpty()) {
            BOBAEmptyState(
                icon = Icons.Default.Save,
                headline = "Empty draft",
                body = "Long-press cards in the pool to add them.",
                modifier = Modifier.fillMaxSize(),
            )
            return
        }

        SectionedCardList(
            draft = draft,
            onRemove = onRemove,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun DeckEditorContent(
    draft: DeckDraft,
    onDismiss: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
) {
    var name by remember { mutableStateOf(draft.name) }

    Column(
        modifier = Modifier.fillMaxSize(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
            OutlinedTextField(
                value = name,
                onValueChange = {
                    name = it
                    onRename(it)
                },
                label = { Text("Deck name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = onSave,
                enabled = draft.cards.isNotEmpty(),
            ) {
                Icon(
                    Icons.Default.Save,
                    contentDescription = null,
                    modifier = Modifier.width(18.dp).height(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text("Save")
            }
        }

        StatsRow(draft = draft)

        HorizontalDivider()

        if (draft.cards.isEmpty()) {
            BOBAEmptyState(
                icon = Icons.Default.Save,
                headline = "Empty draft",
                body = "Long-press cards in the pool to add them. Or scan a real deck via the scan icon.",
                modifier = Modifier.fillMaxSize(),
            )
            return
        }

        SectionedCardList(
            draft = draft,
            onRemove = onRemove,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun StatsRow(draft: DeckDraft) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StatChip("Heroes", "${draft.heroCount}/${draft.heroCap}")
        StatChip("Plays", "${draft.playCount + draft.bonusCount}/${draft.playCap}")
        StatChip("Bonus", "${draft.bonusCount}/${draft.bonusCap}")
        StatChip("HD", "${draft.totalHD}/${draft.hdCap}")
        Spacer(Modifier.weight(1f))
        if (draft.isStandardLegal) {
            AssistChip(
                onClick = {},
                label = { Text("Legal") },
                leadingIcon = {
                    Icon(
                        Icons.Default.Verified,
                        contentDescription = null,
                        modifier = Modifier.width(16.dp).height(16.dp),
                    )
                },
                colors = AssistChipDefaults.assistChipColors(
                    labelColor = MaterialTheme.colorScheme.primary,
                ),
            )
        }
    }
}

@Composable
private fun StatChip(label: String, value: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.small,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                value,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SectionedCardList(
    draft: DeckDraft,
    onRemove: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val sections = remember(draft.cards) {
        listOf(
            "Heroes" to draft.cards.filter { it.cardType.equals("Hero", ignoreCase = true) },
            "Plays"  to draft.cards.filter { it.cardType.contains("Play", ignoreCase = true) && !it.cardType.contains("Bonus", ignoreCase = true) },
            "Bonus"  to draft.cards.filter { it.cardType.contains("Bonus", ignoreCase = true) },
            "Coach"  to draft.cards.filter { it.cardType.contains("Coach", ignoreCase = true) },
        )
    }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        sections.forEach { (label, cards) ->
            if (cards.isEmpty()) return@forEach
            item(key = "header-$label") {
                BOBASectionHeader(title = "$label (${cards.size})")
            }
            items(
                items = cards,
                key = { it.bobaId },
                contentType = { "card-row" },
            ) { card ->
                DeckCardRow(card = card, onRemove = { onRemove(card.bobaId) })
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

@Composable
private fun DeckCardRow(card: Card, onRemove: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(modifier = Modifier.width(48.dp).height(67.dp)) {
            BOBACardCell(
                imageFile = card.imageFile,
                contentDescription = card.displayName,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                card.displayName,
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                "${card.cardNumber} · ${card.element.lowercase().replaceFirstChar { it.uppercase() }}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                Icons.Default.Delete,
                contentDescription = "Remove from deck",
                tint = MaterialTheme.colorScheme.error,
            )
        }
    }
}
