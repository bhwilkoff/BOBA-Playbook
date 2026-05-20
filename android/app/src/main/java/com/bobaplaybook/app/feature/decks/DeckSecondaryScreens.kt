@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Push destinations off the Decks editor — Manage / Rules / Legality.
 *
 * ANDROID-DESIGN.md §8.3 — secondary surfaces push as nav destinations
 * inside the Decks NavHost, never stacked sheets on top of the editor.
 */

@Composable
fun DeckManageScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val vm: DecksViewModel = hiltViewModel()
    val savedDecks by vm.savedDecks.collectAsStateWithLifecycle()
    // Use CollectionViewModel's exposed catalog flow. Both Find and
    // Collection-detail screens already consume it; reusing it here
    // avoids adding a third copy.
    val collectionViewModel: com.bobaplaybook.app.feature.collection.CollectionViewModel = hiltViewModel()
    val catalog by collectionViewModel.catalogCards.collectAsStateWithLifecycle()
    var pendingDelete by remember { mutableStateOf<String?>(null) }
    var pendingRename by remember { mutableStateOf<String?>(null) }
    var query by androidx.compose.runtime.saveable.rememberSaveable {
        androidx.compose.runtime.mutableStateOf("")
    }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current

    // Filter saved decks by name OR archetype — both surfaces are
    // user-meaningful when looking up "that Maverick deck I built
    // last month." Case-insensitive substring (deck names are short
    // so word-prefix isn't necessary the way it is for the catalog).
    val needle = query.trim().lowercase()
    val filteredDecks = remember(savedDecks, needle) {
        if (needle.isEmpty()) savedDecks
        else savedDecks.filter {
            it.name.lowercase().contains(needle) ||
                (it.archetype?.lowercase()?.contains(needle) == true)
        }
    }

    DeckSecondaryScaffold(title = "Manage Decks", onBack = onBack, modifier = modifier) {
        if (savedDecks.isEmpty()) {
            BOBAEmptyState(
                icon = Icons.Default.Save,
                headline = "No saved decks yet",
                body = "Build a draft in the pool, then tap Save in the editor. Decks sync across iOS, web, and Android.",
            )
        } else {
            androidx.compose.foundation.layout.Column(modifier = Modifier.fillMaxSize()) {
                // Persistent in-list filter — shows when there's at
                // least one deck so the user can type even when none
                // currently match (the empty-state below explains).
                androidx.compose.material3.OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text("Filter decks by name or archetype") },
                    singleLine = true,
                    leadingIcon = {
                        Icon(
                            androidx.compose.material.icons.Icons.Default.Search,
                            contentDescription = null,
                        )
                    },
                    trailingIcon = if (query.isNotEmpty()) {
                        {
                            IconButton(onClick = { query = "" }) {
                                Icon(
                                    androidx.compose.material.icons.Icons.Default.Clear,
                                    contentDescription = "Clear",
                                )
                            }
                        }
                    } else null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
                if (filteredDecks.isEmpty()) {
                    BOBAEmptyState(
                        headline = "No matches",
                        body = "No saved decks match \"$query\".",
                        actionLabel = "Clear search",
                        onAction = { query = "" },
                    )
                    return@Column
                }
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(items = filteredDecks, key = { it.id }) { deck ->
                    ListItem(
                        headlineContent = { Text(deck.name) },
                        supportingContent = {
                            val total = deck.cards.sumOf { it.quantity }
                            val archetypeLabel = deck.archetype?.takeIf { it.isNotBlank() }?.let { " · $it" } ?: ""
                            Text(
                                "$total cards$archetypeLabel",
                                style = MaterialTheme.typography.labelMedium,
                            )
                        },
                        trailingContent = {
                            Row {
                                IconButton(onClick = { pendingRename = deck.id }) {
                                    Icon(
                                        Icons.Default.Edit,
                                        contentDescription = "Rename deck",
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(onClick = { pendingDelete = deck.id }) {
                                    Icon(
                                        Icons.Default.Delete,
                                        contentDescription = "Delete deck",
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                }
                            }
                        },
                        modifier = Modifier.clickable {
                            // Replace the draft with this saved deck + pop back
                            // to the editor. Mirrors iOS DeckBuilderStore.loadDeck.
                            vm.loadSaved(deck, catalog)
                            scope.launch {
                                appSnackbar?.showSnackbar("Loaded \"${deck.name}\"")
                            }
                            onBack()
                        },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
        }
    }

    pendingDelete?.let { id ->
        val deck = savedDecks.firstOrNull { it.id == id }
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Delete \"${deck?.name ?: "deck"}\"?") },
            text = { Text("This removes the deck from every device. Can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    vm.deleteDeck(id)
                    pendingDelete = null
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("Cancel") }
            },
        )
    }
    pendingRename?.let { id ->
        val deck = savedDecks.firstOrNull { it.id == id } ?: return@let
        var nameText by remember(id) { mutableStateOf(deck.name) }
        AlertDialog(
            onDismissRequest = { pendingRename = null },
            title = { Text("Rename deck") },
            text = {
                androidx.compose.material3.OutlinedTextField(
                    value = nameText,
                    onValueChange = { nameText = it },
                    label = { Text("Deck name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    enabled = nameText.trim().isNotEmpty() && nameText.trim() != deck.name,
                    onClick = {
                        vm.renameSavedDeck(id, nameText.trim())
                        scope.launch { appSnackbar?.showSnackbar("Renamed to \"${nameText.trim()}\"") }
                        pendingRename = null
                    },
                ) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { pendingRename = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
fun DeckRulesScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    DeckSecondaryScaffold(title = "Deck Rules", onBack = onBack, modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            BOBASectionHeader(title = "Standard Construction")
            Text(
                "• 8 Heroes (no duplicates) — your match-flow lineup\n" +
                "• 30 Plays + Bonus Plays — fielded sub-decks per match\n" +
                "• 1 Coach (optional) — passive bonus support\n" +
                "• Match Cost ceiling: 10 HD (Heroic Damage)",
                style = MaterialTheme.typography.bodyMedium,
            )

            BOBASectionHeader(title = "Hot Dog Constraint")
            Text(
                "Bonus Plays cap at 7 in a standard deck. Going beyond requires a Hot Dog parallel slot per the BoBA Comprehensive Rules Guide.",
                style = MaterialTheme.typography.bodyMedium,
            )

            BOBASectionHeader(title = "DBS Budget (Playmaker only)")
            Text(
                "Playmaker decks must keep total DBS across all 30 Plays at " +
                    "or below 1,000. The Deck Balancing System scores each Play " +
                    "by power level — high-DBS plays force balance with low-DBS " +
                    "ones. Rookie + Substitution formats ignore DBS entirely.",
                style = MaterialTheme.typography.bodyMedium,
            )

            BOBASectionHeader(title = "Format Tiers")
            Text(
                "• Rookie — 8 Heroes / 30 Plays / 6 Bonus / 10 HD. No DBS.\n" +
                "• Substitution — Rookie + 4 subs + 1 Coach. No DBS.\n" +
                "• Playmaker — full BoBA economy. DBS budget 1,000.",
                style = MaterialTheme.typography.bodyMedium,
            )

            BOBASectionHeader(title = "Tournament Format")
            Text(
                "Tournament play locks weapon distribution and adds a Sideboard. Tournament-legal subset enforced by the Legality screen.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
fun DeckLegalityScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val vm: DecksViewModel = hiltViewModel()
    val draft by vm.draft.collectAsStateWithLifecycle()

    DeckSecondaryScaffold(title = "Legality", onBack = onBack, modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Overall verdict
            LegalityVerdict(legal = draft.isStandardLegal)

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // Per-rule rows
            BOBASectionHeader(title = "Standard checks")
            LegalityRow(
                rule = "Heroes",
                value = "${draft.heroCount} / ${draft.heroCap}",
                ok = draft.heroCount == draft.heroCap,
            )
            LegalityRow(
                rule = "Plays + Bonus",
                value = "${draft.playCount + draft.bonusCount} / ${draft.playCap}",
                ok = draft.playCount + draft.bonusCount == draft.playCap,
            )
            LegalityRow(
                rule = "Bonus Plays",
                value = "${draft.bonusCount} / ${draft.bonusCap}",
                ok = draft.bonusCount <= draft.bonusCap,
            )
            LegalityRow(
                rule = "Heroic Damage cap",
                value = "${draft.totalHD} / ${draft.hdCap}",
                ok = draft.totalHD <= draft.hdCap,
            )
            // DBS row only renders in Playmaker (the only format that
            // enforces it). Skipping the row on Rookie/Substitution
            // keeps the screen short for formats where DBS is N/A.
            if (draft.enforcesDBS) {
                LegalityRow(
                    rule = "DBS budget",
                    value = "${draft.totalDBS} / ${draft.dbsBudget}",
                    ok = draft.totalDBS <= draft.dbsBudget,
                )
            }

            if (!draft.isStandardLegal) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
                        Text(
                            "  Resolve the items above before submitting to a tournament.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LegalityVerdict(legal: Boolean) {
    Surface(
        color = if (legal) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (legal) Icons.Default.Verified else Icons.Default.Warning,
                contentDescription = null,
                tint = if (legal) MaterialTheme.colorScheme.onPrimaryContainer
                       else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = if (legal) "  Standard legal — ready to submit"
                       else "  Not yet legal — see checks below",
                style = MaterialTheme.typography.titleMedium,
                color = if (legal) MaterialTheme.colorScheme.onPrimaryContainer
                        else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun LegalityRow(rule: String, value: String, ok: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = if (ok) Icons.Default.Verified else Icons.Default.Warning,
            contentDescription = null,
            tint = if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
        )
        Text(
            rule,
            modifier = Modifier.padding(start = 8.dp).weight(1f),
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            value,
            style = MaterialTheme.typography.titleSmall,
            color = if (ok) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error,
        )
    }
}

@Composable
private fun DeckSecondaryScaffold(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            content()
        }
    }
}
