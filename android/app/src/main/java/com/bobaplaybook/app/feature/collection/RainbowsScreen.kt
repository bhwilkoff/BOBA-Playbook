@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.ui.components.BOBAEmptyState
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
    var editorOpen by androidx.compose.runtime.saveable.rememberSaveable {
        androidx.compose.runtime.mutableStateOf(false)
    }


    // Group owned cards by hero for auto rainbows
    val heroRainbows: List<AutoRainbow> = state.entriesByDesignation.values.flatten()
        .filter { it.card.hero.isNotBlank() }
        .groupBy { it.card.hero }
        .map { entry ->
            val treatments = entry.value.mapNotNull { it.card.treatment }.distinct()
            AutoRainbow(hero = entry.key, treatmentCount = treatments.size, totalCopies = entry.value.size)
        }
        .sortedByDescending { it.treatmentCount }

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
            FloatingActionButton(onClick = { editorOpen = true }) {
                Icon(Icons.Default.Add, contentDescription = "New custom rainbow")
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
                    ListItem(
                        headlineContent = { Text(rainbow.name) },
                        supportingContent = {
                            val parts = buildList {
                                if (rainbow.criteria.heroes.isNotEmpty()) add("${rainbow.criteria.heroes.size} heroes")
                                if (rainbow.criteria.elements.isNotEmpty()) add("${rainbow.criteria.elements.size} weapons")
                                if (rainbow.criteria.treatments.isNotEmpty()) add("${rainbow.criteria.treatments.size} treatments")
                                if (rainbow.criteria.inspiredInkOnly) add("Inspired Ink only")
                            }
                            Text(
                                parts.joinToString(" · ").ifEmpty { "Any card" },
                                style = MaterialTheme.typography.labelMedium,
                            )
                        },
                        trailingContent = { Icon(Icons.Default.ChevronRight, contentDescription = null) },
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
                    ListItem(
                        headlineContent = { Text(rainbow.hero) },
                        supportingContent = {
                            Text(
                                "${rainbow.treatmentCount} treatments · ${rainbow.totalCopies} copies",
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

    if (editorOpen) {
        CustomRainbowEditorSheet(onDismiss = { editorOpen = false })
    }
}

private data class AutoRainbow(val hero: String, val treatmentCount: Int, val totalCopies: Int)
