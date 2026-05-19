@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Inventory
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * Learn tab (ANDROID-DESIGN.md §8.2).
 *
 * M5 ships the IA skeleton:
 *  - LargeTopAppBar with "Learn" title (exitUntilCollapsed scroll behavior)
 *  - 5 category rows (Rules / Strategy / Collect / Glossary / Tournament)
 *  - Tap → push to a per-category screen with a "Article content
 *    coming soon" placeholder; M5-polish lands the actual article
 *    corpus port from iOS (large body of text content; not blocking
 *    for the milestone marker)
 *
 * Deferred to M5-polish (substantial content port from iOS):
 *  - Full article corpus per category (Rules has ~20 articles on iOS,
 *    Strategy has ~30, etc. Each one is multi-paragraph reference text.
 *    Porting these is content work that's editor-time, not engineering
 *    time — does NOT need a re-architecture)
 *  - Skill-level SegmentedButton scope (Rookie / Sub / Playmaker)
 *  - Glossary TooltipBox on highlighted terms
 *  - In-corpus SearchBar
 */
@Composable
fun LearnScreen(modifier: Modifier = Modifier) {
    var currentCategory by remember { mutableStateOf<LearnCategory?>(null) }

    if (currentCategory != null) {
        CategoryDetail(
            category = currentCategory!!,
            onBack = { currentCategory = null },
            modifier = modifier,
        )
    } else {
        CategoryList(
            onCategoryClick = { currentCategory = it },
            modifier = modifier,
        )
    }
}

private enum class LearnCategory(val title: String, val icon: ImageVector, val blurb: String) {
    RULES     ("Rules",      Icons.Default.AutoStories,             "Match flow, phases, win conditions"),
    STRATEGY  ("Strategy",   Icons.Default.Lightbulb,                "Archetype guides + matchups"),
    COLLECT   ("Collecting", Icons.Default.Inventory,                "Sets, treatments, parallels, rarity"),
    GLOSSARY  ("Glossary",   Icons.AutoMirrored.Filled.MenuBook,     "Every BoBA term in one place"),
    TOURNAMENT("Tournament", Icons.Default.EmojiEvents,              "Format rules, divisions, scoring"),
}

@Composable
private fun CategoryList(
    onCategoryClick: (LearnCategory) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Learn") },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier
            .fillMaxSize()
            .padding(padding)) {
            items(LearnCategory.entries) { category ->
                ListItem(
                    leadingContent = {
                        Icon(
                            imageVector = category.icon,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                    headlineContent = { Text(category.title, style = MaterialTheme.typography.titleMedium) },
                    supportingContent = { Text(category.blurb, style = MaterialTheme.typography.bodyMedium) },
                    trailingContent = {
                        Icon(
                            imageVector = Icons.Default.ChevronRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    modifier = Modifier.clickable { onCategoryClick(category) },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

@Composable
private fun CategoryDetail(
    category: LearnCategory,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(category.title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        BOBAEmptyState(
            icon = category.icon,
            headline = "${category.title} content coming soon",
            body = "iOS article corpus ports next. The category list + push navigation are ready; content is editor work.",
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        )
    }
}

