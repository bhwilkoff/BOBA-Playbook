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
import androidx.compose.material.icons.filled.ViewModule
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
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
    isSignedIn: Boolean,
    onDismiss: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        DeckEditorContent(
            draft = draft,
            isSignedIn = isSignedIn,
            onDismiss = onDismiss,
            onRename = onRename,
            onRemove = onRemove,
            onSave = onSave,
            onSignInRequest = onSignInRequest,
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
    isSignedIn: Boolean,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
) {
    // Bind directly to draft.name so loading a saved deck via the
    // Manage screen actually updates the visible field. Earlier this
    // captured draft.name via `var name by remember` which froze the
    // initial value — typing worked, but loadSaved silently failed
    // to refresh the TextField.
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = draft.name,
                onValueChange = { onRename(it) },
                label = { Text("Deck name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }

        StatsRow(draft = draft)
        PlayModeChipStrip(draft = draft)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            androidx.compose.material3.OutlinedButton(onClick = onOpenRules) { Text("Rules") }
            androidx.compose.material3.OutlinedButton(onClick = onOpenLegality) { Text("Legality") }
            Spacer(Modifier.weight(1f))
            SaveOrSignInButton(
                isSignedIn = isSignedIn,
                hasCards = draft.cards.isNotEmpty(),
                onSave = onSave,
                onSignInRequest = onSignInRequest,
                hasName = draft.name.trim().isNotEmpty(),
            )
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
    isSignedIn: Boolean,
    onDismiss: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
) {
    // Bind directly to draft.name — see DeckEditorContentInline
    // comment for the same fix at the inline variant.

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
                value = draft.name,
                onValueChange = { onRename(it) },
                label = { Text("Deck name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            SaveOrSignInButton(
                isSignedIn = isSignedIn,
                hasCards = draft.cards.isNotEmpty(),
                onSave = onSave,
                onSignInRequest = onSignInRequest,
                hasName = draft.name.trim().isNotEmpty(),
            )
        }

        StatsRow(draft = draft)
        PlayModeChipStrip(draft = draft)

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

/**
 * iOS parity: SAVE button morphs to SIGN IN when signed-out. Tapping
 * routes to the Profile destination (Find tab) for sign-in. Avoids
 * the dead-click where signed-out users tap Save with no feedback.
 *
 * See `feedback_profile_only_on_find` memory + DESIGN.md §6.5
 * inline-sign-in pattern.
 */
@Composable
private fun SaveOrSignInButton(
    isSignedIn: Boolean,
    hasCards: Boolean,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
    hasName: Boolean = true,
) {
    if (isSignedIn) {
        Button(
            onClick = onSave,
            // Require both at least one card AND a non-empty name —
            // the viewModel rejects empty names too but disabling the
            // button keeps the user from a failed-save snackbar loop.
            enabled = hasCards && hasName,
        ) {
            Icon(
                Icons.Default.Save,
                contentDescription = null,
                modifier = Modifier.width(18.dp).height(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text("Save")
        }
    } else {
        Button(onClick = onSignInRequest) {
            Text("Sign in")
        }
    }
}

@Composable
private fun PlayModeChipStrip(draft: DeckDraft) {
    val vm: DecksViewModel = androidx.hilt.navigation.compose.hiltViewModel()
    val modes = remember { DeckPlayMode.entries }
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        modes.forEachIndexed { index, mode ->
            SegmentedButton(
                selected = mode == draft.playMode,
                onClick = { vm.setPlayMode(mode) },
                shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                icon = {},
            ) {
                Text(mode.label, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
    Text(
        text = draft.playMode.description,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
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
        // Each chip tints red when it's BLOCKING legality. Heroes
        // and Plays count exact equality (== cap) as the legal
        // target; Bonus and HD are ≤-cap so only the strictly-over
        // case is "wrong" — under-cap is just an unfinished deck,
        // not an illegal one.
        StatChip(
            "Heroes",
            "${draft.heroCount}/${draft.heroCap}",
            overBudget = draft.heroCount > draft.heroCap,
        )
        StatChip(
            "Plays",
            "${draft.playCount + draft.bonusCount}/${draft.playCap}",
            overBudget = (draft.playCount + draft.bonusCount) > draft.playCap,
        )
        StatChip(
            "Bonus",
            "${draft.bonusCount}/${draft.bonusCap}",
            overBudget = draft.bonusCount > draft.bonusCap,
        )
        StatChip(
            "HD",
            "${draft.totalHD}/${draft.hdCap}",
            overBudget = draft.totalHD > draft.hdCap,
        )
        // DBS chip — Playmaker format only; matches iOS DeckBuilderView
        // line 428 (effectiveEnforceDBS gate). Tints red when over budget.
        if (draft.enforcesDBS) {
            StatChip(
                label = "DBS",
                value = "${draft.totalDBS}/${draft.dbsBudget}",
                overBudget = draft.totalDBS > draft.dbsBudget,
            )
        }
        Spacer(Modifier.weight(1f))
        if (draft.isStandardLegal) {
            androidx.compose.material3.Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        Icons.Default.Verified,
                        contentDescription = null,
                        modifier = Modifier.width(14.dp).height(14.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        "Legal",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
        }
    }
}

@Composable
private fun StatChip(label: String, value: String, overBudget: Boolean = false) {
    Surface(
        color = if (overBudget) MaterialTheme.colorScheme.errorContainer
                else MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.small,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                value,
                style = MaterialTheme.typography.titleSmall,
                color = if (overBudget) MaterialTheme.colorScheme.onErrorContainer
                        else MaterialTheme.colorScheme.onSurface,
            )
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = if (overBudget) MaterialTheme.colorScheme.onErrorContainer
                        else MaterialTheme.colorScheme.onSurfaceVariant,
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

    // Empty-state when no cards are in any section yet. The pool
    // below the editor is where users add cards (long-press); this
    // surface explicitly explains that.
    if (draft.cards.isEmpty()) {
        com.bobaplaybook.core.ui.components.BOBAEmptyState(
            icon = Icons.Default.ViewModule,
            headline = "No cards yet",
            body = "Close the editor and long-press cards in the pool to add them. Heroes, Plays, Bonus Plays, and Coach each get their own section here.",
            modifier = modifier,
        )
        return
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
                isSealed = card.isSealed,
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
