@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Custom + auto Rainbows list — mirrors iOS Rainbow Progress screen.
 *
 * v1 shows:
 *  - Custom Rainbows section (user-defined collecting goals, empty by
 *    default until M7 lands the editor sheet + Supabase persistence)
 *  - Per-hero Auto Rainbows (computed from owned cards)
 *
 * Tap a rainbow → push to RainbowDetailScreen.
 */
@Composable
fun RainbowsScreen(
    onRainbowClick: (kind: String, id: String) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val viewModel: CollectionViewModel = hiltViewModel()
    val customVm: CustomRainbowsViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val customRainbows by customVm.rainbows.collectAsStateWithLifecycle()
    val catalog by viewModel.catalogCards.collectAsStateWithLifecycle()
    // Tick 159 — Snackbar host + scope so the Custom Rainbow delete
    // confirm can offer Undo. Closes parity with web tick 158.
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current
    var pendingDeleteId by androidx.compose.runtime.saveable.rememberSaveable {
        androidx.compose.runtime.mutableStateOf<String?>(null)
    }
    var editorOpen by androidx.compose.runtime.saveable.rememberSaveable {
        androidx.compose.runtime.mutableStateOf(false)
    }
    // Edit target — null means create-new (the FAB path).
    var editorTarget by androidx.compose.runtime.saveable.rememberSaveable {
        androidx.compose.runtime.mutableStateOf<String?>(null)
    }


    // Per-hero total treatment count from the catalog — used to render
    // owned/total ("5 of 15 treatments") instead of just "5 treatments."
    // iOS + web parity (tick 8). Computed via remember on the catalog
    // list so the O(catalog) pass only re-runs when the catalog
    // changes, not on every body re-eval.
    val totalTreatmentsByHero: Map<String, Int> = androidx.compose.runtime.remember(catalog) {
        catalog.asSequence()
            .filter { it.hero.isNotBlank() && !it.treatment.isNullOrBlank() }
            .groupBy { it.hero }
            .mapValues { (_, cards) -> cards.mapNotNull { it.treatment }.distinct().size }
    }

    // Group owned cards by hero for auto rainbows. Sort by completion
    // ratio (owned-treatments / catalog-treatments) descending — the
    // closest-to-complete rainbows surface first, matching web tick 8.
    val heroRainbows: List<AutoRainbow> = state.entriesByDesignation.values.flatten()
        .filter { it.card.hero.isNotBlank() }
        .groupBy { it.card.hero }
        .map { entry ->
            val ownedTreatments = entry.value.mapNotNull { it.card.treatment }.distinct().size
            val totalTreatments = totalTreatmentsByHero[entry.key] ?: ownedTreatments
            AutoRainbow(
                hero = entry.key,
                treatmentCount = ownedTreatments,
                totalTreatments = totalTreatments,
                totalCopies = entry.value.size,
            )
        }
        .sortedWith(
            compareByDescending<AutoRainbow> {
                if (it.totalTreatments == 0) 0.0 else it.treatmentCount.toDouble() / it.totalTreatments
            }.thenBy { it.hero }
        )

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Rainbow Progress") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
        floatingActionButton = {
            // Hide FAB when signed-out — tapping with no editor backing
            // is a dead-click. The signed-out empty state already
            // surfaces the sign-in CTA.
            if (state.isSignedIn) {
                FloatingActionButton(onClick = {
                    editorTarget = null  // FAB = create-mode; clear any prior edit target
                    editorOpen = true
                }) {
                    Icon(Icons.Default.Add, contentDescription = "New custom rainbow")
                }
            }
        },
    ) { padding ->
        if (heroRainbows.isEmpty() && !state.isSignedIn) {
            BOBAEmptyState(
                icon = Icons.Default.Palette,
                headline = "Sign in to track rainbows",
                body = "Rainbows show you which Treatments + Parallels you own per hero. Sign in to start tracking.",
                modifier = Modifier.fillMaxSize().padding(padding),
            )
            return@Scaffold
        }
        // Hoisted OUTSIDE the LazyColumn body — LazyListScope isn't a
        // @Composable scope so `remember(...)` calls inside it (outside
        // `item {}` / `items {}` builders) fail to compile. iOS Custom
        // Rainbow detail does the same "compute once, use per-row"
        // optimization.
        val ownedBobaIds = remember(state) {
            state.entriesByDesignation.values.flatten()
                .filter { it.userCard.designation in setOf(
                    com.bobaplaybook.core.domain.model.Designation.PERSONAL,
                    com.bobaplaybook.core.domain.model.Designation.FOR_SALE,
                    com.bobaplaybook.core.domain.model.Designation.FOR_TRADE,
                ) }
                .map { it.card.bobaId }.toSet()
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 96.dp),
        ) {
            item("custom-header") { BOBASectionHeader(title = "Custom rainbows") }
            if (customRainbows.isEmpty()) {
                item("custom-empty") {
                    Text(
                        "User-defined collecting goals. Tap the + button to define a new rainbow with weapon, set, treatment, or hero criteria.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            } else {
                items(items = customRainbows, key = { it.id }) { rainbow ->
                    // Catalog cards that match this rainbow's criteria.
                    // Memoized on (catalog, rainbow) so the per-recompose
                    // cost is zero. Owned count = intersection with
                    // ownedBobaIds — "5 of 30 owned · 17%". iOS parity.
                    val matching = remember(catalog, rainbow.criteria) {
                        catalog.filter { criteriaMatches(rainbow.criteria, it) }
                    }
                    val owned = matching.count { it.bobaId in ownedBobaIds }
                    val pct = if (matching.isEmpty()) 0
                              else ((owned * 100.0) / matching.size).toInt()
                    ListItem(
                        headlineContent = { Text(rainbow.name) },
                        supportingContent = {
                            // Reflect all 7 criterion dimensions (tick 81 added
                            // sets / sub-sets / releases / card types to the
                            // editor). Without this, custom rainbows whose
                            // only filter is e.g. "Sets: Season One" looked
                            // identical to "Any card" in the list.
                            val parts = buildList {
                                if (rainbow.criteria.heroes.isNotEmpty())     add("${rainbow.criteria.heroes.size} heroes")
                                if (rainbow.criteria.elements.isNotEmpty())   add("${rainbow.criteria.elements.size} weapons")
                                if (rainbow.criteria.treatments.isNotEmpty()) add("${rainbow.criteria.treatments.size} treatments")
                                if (rainbow.criteria.sets.isNotEmpty())       add("${rainbow.criteria.sets.size} sets")
                                if (rainbow.criteria.subSets.isNotEmpty())    add("${rainbow.criteria.subSets.size} sub-sets")
                                if (rainbow.criteria.releases.isNotEmpty())   add("${rainbow.criteria.releases.size} releases")
                                if (rainbow.criteria.cardTypes.isNotEmpty())  add("${rainbow.criteria.cardTypes.size} card types")
                                if (rainbow.criteria.inspiredInkOnly)         add("Inspired Ink only")
                            }
                            Column {
                                Text(
                                    "$owned of ${matching.size} owned · $pct%",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text(
                                    parts.joinToString(" · ").ifEmpty { "Any card" },
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        },
                        trailingContent = {
                            // Tick 429 — BOBAIconTooltip on per-row Edit +
                            // Delete (extends tick 411's Manage Decks
                            // pattern). Long-press / hover surfaces the
                            // action label so users hesitating over the
                            // red Delete get a clear hint.
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                BOBAIconTooltip("Edit custom rainbow") {
                                    IconButton(onClick = {
                                        editorTarget = rainbow.id
                                        editorOpen = true
                                    }) {
                                        Icon(
                                            Icons.Default.Edit,
                                            contentDescription = "Edit custom rainbow",
                                        )
                                    }
                                }
                                BOBAIconTooltip("Delete custom rainbow") {
                                    IconButton(onClick = { pendingDeleteId = rainbow.id }) {
                                        Icon(
                                            Icons.Default.Delete,
                                            contentDescription = "Delete custom rainbow",
                                            tint = MaterialTheme.colorScheme.error,
                                        )
                                    }
                                }
                                Icon(Icons.Default.ChevronRight, contentDescription = null)
                            }
                        },
                        modifier = Modifier.clickable { onRainbowClick("custom", rainbow.id) },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            item("divider") { HorizontalDivider() }
            item("auto-header") { BOBASectionHeader(title = "Per-hero auto rainbows") }
            if (heroRainbows.isEmpty()) {
                item("auto-empty") {
                    Text(
                        "Add cards to your collection to see per-hero treatment progress.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            } else {
                items(items = heroRainbows, key = { it.hero }) { rainbow ->
                    // iOS + web parity (tick 8): show owned/total
                    // treatments + completion %, so the user can see at
                    // a glance how far along each per-hero rainbow is.
                    val pct = if (rainbow.totalTreatments == 0) 0
                        else ((rainbow.treatmentCount * 100.0) / rainbow.totalTreatments).toInt()
                    ListItem(
                        headlineContent = { Text(rainbow.hero) },
                        supportingContent = {
                            Text(
                                "${rainbow.treatmentCount} of ${rainbow.totalTreatments} treatments · $pct% · ${rainbow.totalCopies} copies",
                                style = MaterialTheme.typography.labelMedium,
                            )
                        },
                        trailingContent = {
                            Icon(Icons.Default.ChevronRight, contentDescription = null)
                        },
                        modifier = Modifier.clickable { onRainbowClick("hero", rainbow.hero) },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
        }
    }

    pendingDeleteId?.let { id ->
        val rb = customRainbows.firstOrNull { it.id == id }
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pendingDeleteId = null },
            title = { Text("Delete \"${rb?.name ?: "rainbow"}\"?") },
            text = {
                Text(
                    "Removes the saved goal definition. Your owned cards stay in your collection.",
                )
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    // Capture the rainbow BEFORE delete so Undo can
                    // recreate it via the public create API. Supabase
                    // issues a new id but user-visible data round-
                    // trips losslessly. Same shape as web tick 158.
                    val captured = rb
                    customVm.delete(id)
                    pendingDeleteId = null
                    if (captured != null) {
                        scope.launch {
                            val result = appSnackbar?.showSnackbar(
                                message = "Deleted \"${captured.name}\"",
                                actionLabel = "Undo",
                                duration = androidx.compose.material3.SnackbarDuration.Short,
                            )
                            if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                                customVm.create(captured.name, captured.criteria) { ok ->
                                    if (!ok) {
                                        scope.launch {
                                            appSnackbar.showSnackbar("Couldn't restore — try again.")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { pendingDeleteId = null }) {
                    Text("Cancel")
                }
            },
        )
    }

    if (editorOpen) {
        val target = editorTarget?.let { id -> customRainbows.firstOrNull { it.id == id } }
        CustomRainbowEditorSheet(
            existing = target,
            onDismiss = {
                editorOpen = false
                editorTarget = null
            },
        )
    }
}

private data class AutoRainbow(
    val hero: String,
    val treatmentCount: Int,
    val totalTreatments: Int,
    val totalCopies: Int,
)

/**
 * Card-matches-criteria check used by the Custom Rainbow row's
 * "5 of 30 owned" computation. Mirrors iOS RainbowCriteria.matches
 * + the web equivalent (rainbowCriteriaMatches). Local to this file
 * to avoid touching the shared data model; promote to
 * `RainbowCriteria.matches(card)` when a 2nd call site needs it.
 *
 * Empty criteria fields are interpreted as "any" (not "none") —
 * a rainbow with no constraints matches every catalog card.
 */
internal fun criteriaMatches(
    criteria: com.bobaplaybook.core.data.rainbows.RainbowCriteria,
    card: com.bobaplaybook.core.domain.model.Card,
): Boolean {
    if (criteria.heroes.isNotEmpty()    && card.hero !in criteria.heroes) return false
    if (criteria.elements.isNotEmpty()  && card.element !in criteria.elements) return false
    if (criteria.treatments.isNotEmpty()) {
        val t = card.treatment ?: ""
        if (t !in criteria.treatments) return false
    }
    if (criteria.sets.isNotEmpty()      && card.set !in criteria.sets) return false
    if (criteria.subSets.isNotEmpty()) {
        val s = card.subSet ?: ""
        if (s !in criteria.subSets) return false
    }
    if (criteria.releases.isNotEmpty()) {
        val r = card.release ?: ""
        if (r !in criteria.releases) return false
    }
    if (criteria.cardTypes.isNotEmpty() && card.cardType !in criteria.cardTypes) return false
    if (criteria.inspiredInkOnly) {
        val isInspired = (card.treatment ?: "").lowercase().contains("inspired ink")
        if (!isInspired) return false
    }
    return true
}
