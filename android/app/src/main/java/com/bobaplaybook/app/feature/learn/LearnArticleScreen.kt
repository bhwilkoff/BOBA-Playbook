@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Learn category page — one bespoke surface per category, iOS parity.
 *
 * Rules has a Rookie/Substitution/Playmaker SegmentedButton at the
 * page root that swaps the mode-aware body. Strategy / Collect /
 * Glossary / Tournament / Watch are flat — content renders top to
 * bottom with no picker (that's the iOS pattern; the old per-article
 * skill-level picker on flat content was the bug).
 *
 * iOS reference: each iOS category has its own SwiftUI view (RulesView,
 * StrategyView, CollectView, GlossaryView, TournamentView, WatchView).
 * On Android we collapse those into one composable parameterized by
 * category — same shapes, less file sprawl.
 */
@Composable
fun LearnCategoryScreen(
    categoryId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val category = remember(categoryId) { LearnCategoryId.fromId(categoryId) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(category?.title ?: "Learn") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        if (category == null) {
            BOBAEmptyState(
                headline = "Category not found",
                body = "Looking for `$categoryId`. Has it been renamed?",
                modifier = Modifier.fillMaxSize().padding(padding),
            )
            return@Scaffold
        }
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            when (category) {
                LearnCategoryId.RULES      -> RulesPage()
                LearnCategoryId.STRATEGY   -> FlatSectionsPage(LearnCorpus.strategy)
                LearnCategoryId.COLLECT    -> FlatSectionsPage(LearnCorpus.collect)
                LearnCategoryId.WATCH      -> WatchPage()
                LearnCategoryId.GLOSSARY   -> GlossaryPage()
                LearnCategoryId.TOURNAMENT -> FlatSectionsPage(LearnCorpus.tournament)
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Rules — mode-aware page with root-level skill-level picker
// ════════════════════════════════════════════════════════════════

@Composable
private fun RulesPage() {
    var mode by rememberSaveable { mutableStateOf(GameMode.ROOKIE) }
    val modes = remember { GameMode.entries }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp, horizontal = 0.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Always-visible intro
        items(items = LearnCorpus.rulesIntro, key = { "intro-${LearnCorpus.rulesIntro.indexOf(it)}" }) { section ->
            SectionRenderer(section)
        }

        // Mode picker — iOS keeps this at the page root, NOT per-section
        item("mode-picker") {
            Surface(color = MaterialTheme.colorScheme.surface) {
                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    modes.forEachIndexed { index, m ->
                        SegmentedButton(
                            selected = m == mode,
                            onClick = { mode = m },
                            shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                            icon = {},
                        ) {
                            Text(m.label, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
        }

        // Mode-specific body
        val modeBody = LearnCorpus.rulesForMode(mode)
        itemsIndexed(items = modeBody, key = { i, _ -> "mode-${mode.name}-$i" }) { _, section ->
            SectionRenderer(section)
        }

        // Always-visible appendix below the mode-specific body
        itemsIndexed(items = LearnCorpus.rulesAppendix, key = { i, _ -> "appendix-$i" }) { _, section ->
            SectionRenderer(section)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Watch — three-section YouTube feed sourced from `boba-youtube-feed`
// Worker. Implementation lives in WatchPage.kt so imports stay clean.
// ════════════════════════════════════════════════════════════════

@Composable
private fun WatchPage() {
    WatchPageContent()
}

// ════════════════════════════════════════════════════════════════
// Flat sections — Strategy / Collect / Tournament
// ════════════════════════════════════════════════════════════════

@Composable
private fun FlatSectionsPage(sections: List<LearnSection>) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        itemsIndexed(items = sections, key = { i, _ -> i }) { _, section ->
            SectionRenderer(section)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Glossary — two flat term sections (Game + Trading)
// ════════════════════════════════════════════════════════════════

@Composable
private fun GlossaryPage() {
    var query by androidx.compose.runtime.saveable.rememberSaveable {
        androidx.compose.runtime.mutableStateOf("")
    }
    val needle = query.trim().lowercase()
    val gameFiltered = remember(needle) {
        if (needle.isEmpty()) LearnCorpus.glossaryGame
        else LearnCorpus.glossaryGame.filter {
            it.term.lowercase().contains(needle) ||
                it.definition.lowercase().contains(needle)
        }
    }
    val tradingFiltered = remember(needle) {
        if (needle.isEmpty()) LearnCorpus.glossaryTrading
        else LearnCorpus.glossaryTrading.filter {
            it.term.lowercase().contains(needle) ||
                it.definition.lowercase().contains(needle)
        }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        // In-corpus filter — iOS DESIGN.md §6 (Search is the universal
        // navigator) + the Glossary's high term density justify a
        // persistent search field over the OutlinedTextField shape.
        androidx.compose.material3.OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Filter terms or definitions") },
            singleLine = true,
            leadingIcon = {
                Icon(Icons.Default.Search, contentDescription = null)
            },
            trailingIcon = if (query.isNotEmpty()) {
                {
                    IconButton(onClick = { query = "" }) {
                        Icon(Icons.Default.Clear, contentDescription = "Clear")
                    }
                }
            } else null,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (gameFiltered.isEmpty() && tradingFiltered.isEmpty()) {
            BOBAEmptyState(
                headline = "No matches",
                body = "Try a different word — \"$query\" didn't match any term or definition.",
                actionLabel = "Clear search",
                onAction = { query = "" },
                modifier = Modifier.fillMaxSize(),
            )
            return@Column
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (gameFiltered.isNotEmpty()) {
                item("game-head") { BOBASectionHeader(title = "Game glossary") }
                items(items = gameFiltered, key = { "game-${it.term}" }) { term ->
                    TermRow(term)
                }
            }
            if (gameFiltered.isNotEmpty() && tradingFiltered.isNotEmpty()) {
                item("divider") {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp, horizontal = 16.dp))
                }
            }
            if (tradingFiltered.isNotEmpty()) {
                item("trading-head") { BOBASectionHeader(title = "Trading glossary") }
                items(items = tradingFiltered, key = { "trade-${it.term}" }) { term ->
                    TermRow(term)
                }
            }
        }
    }
}

@Composable
private fun TermRow(section: LearnSection.Term) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = section.term,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.padding(end = 12.dp),
        )
        Text(
            text = section.definition,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

// ════════════════════════════════════════════════════════════════
// SectionRenderer — shared by every page type
// ════════════════════════════════════════════════════════════════

@Composable
private fun SectionRenderer(section: LearnSection) {
    when (section) {
        is LearnSection.Body -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            Text(
                text = section.text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        is LearnSection.Bullets -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                section.items.forEach { item ->
                    Text(
                        text = "•  $item",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
        is LearnSection.Callout -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainer,
                shape = MaterialTheme.shapes.medium,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Text(
                    text = section.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp),
                )
            }
        }
        is LearnSection.Term -> {
            // Rendered separately by GlossaryPage; if a Term lands in a
            // flat-page list (it shouldn't), render as a bullet for safety.
            Text(
                text = "•  ${section.term}: ${section.definition}",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}
