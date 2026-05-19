@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3AdaptiveApi::class,
)

package com.bobaplaybook.app.feature.learn

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import com.bobaplaybook.core.ui.adaptive.isCompactWidth
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import kotlinx.coroutines.launch

/**
 * Learn tab — the educator (ANDROID-DESIGN.md §8.2 + §6.6).
 *
 * Compact: standard push nav (root list → push category, push article)
 * Medium / Expanded: NavigableListDetailPaneScaffold with category list
 * in the list pane and selected article in the detail pane.
 *
 * On compact widths this composable just renders the category list and
 * delegates pushes to the caller (the host NavHost handles routing).
 * On medium+ widths the host's NavHost is bypassed in favor of an
 * inline NavigableListDetailPaneScaffold so both panes coexist.
 */
@Composable
fun LearnScreen(
    onCategoryClick: (categoryId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (isCompactWidth()) {
        LearnCategoryList(onCategoryClick = onCategoryClick, modifier = modifier)
    } else {
        LearnListDetailScaffold(modifier = modifier)
    }
}

@Composable
private fun LearnCategoryList(
    onCategoryClick: (categoryId: String) -> Unit,
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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            items(
                items = LearnCategoryId.entries,
                key = { it.name },
            ) { category ->
                ListItem(
                    leadingContent = {
                        Icon(
                            imageVector = category.icon,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                    headlineContent = {
                        Text(
                            category.title,
                            style = MaterialTheme.typography.titleMedium,
                        )
                    },
                    supportingContent = {
                        Text(
                            category.blurb,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    trailingContent = {
                        Icon(
                            imageVector = Icons.Default.ChevronRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    modifier = Modifier.clickable { onCategoryClick(category.name) },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

/**
 * Tablet / Chromebook adaptation — categories in list pane, article in
 * detail pane.
 *
 * The list pane shows the 5 categories. Tapping a category populates
 * the detail pane with article list; tapping an article in the detail
 * pane swaps the detail content to the rendered article.
 *
 * We use a two-level scaffold: outer is category → article-list,
 * embedded is article-list → article-body via local state. Reduces
 * cognitive load vs nesting two ListDetailPaneScaffolds.
 */
@Composable
private fun LearnListDetailScaffold(modifier: Modifier = Modifier) {
    val navigator = rememberListDetailPaneScaffoldNavigator<String>()
    val coroutineScope = rememberCoroutineScope()
    var selectedArticleId by rememberSaveable { mutableStateOf<String?>(null) }

    val currentCategory = navigator.currentDestination?.contentKey?.let { id ->
        LearnCategoryId.fromId(id)
    }

    NavigableListDetailPaneScaffold(
        navigator = navigator,
        modifier = modifier,
        listPane = {
            AnimatedPane {
                Scaffold(
                    topBar = {
                        LargeTopAppBar(
                            title = { Text("Learn") },
                            colors = TopAppBarDefaults.topAppBarColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainer,
                            ),
                        )
                    },
                ) { padding ->
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                    ) {
                        items(
                            items = LearnCategoryId.entries,
                            key = { it.name },
                        ) { category ->
                            val isSelected = currentCategory == category
                            ListItem(
                                leadingContent = {
                                    Icon(
                                        imageVector = category.icon,
                                        contentDescription = null,
                                        tint = if (isSelected) MaterialTheme.colorScheme.primary
                                               else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                },
                                headlineContent = { Text(category.title) },
                                supportingContent = { Text(category.blurb, style = MaterialTheme.typography.labelMedium) },
                                modifier = Modifier.clickable {
                                    selectedArticleId = null
                                    coroutineScope.launch {
                                        navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, category.name)
                                    }
                                },
                            )
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        }
                    }
                }
            }
        },
        detailPane = {
            AnimatedPane {
                when {
                    currentCategory != null && selectedArticleId == null -> {
                        // Show article list for selected category
                        TabletArticleList(
                            category = currentCategory,
                            onArticleClick = { selectedArticleId = it },
                        )
                    }
                    currentCategory != null && selectedArticleId != null -> {
                        // Show article body
                        LearnArticleScreen(
                            articleId = selectedArticleId!!,
                            onBack = { selectedArticleId = null },
                        )
                    }
                    else -> {
                        BOBAEmptyState(
                            headline = "LEARN BoBA",
                            body = "Everything we know about the rules, strategy, collecting, and tournaments. Pick a category to start.",
                        )
                    }
                }
            }
        },
    )
}

@Composable
private fun TabletArticleList(
    category: LearnCategoryId,
    onArticleClick: (articleId: String) -> Unit,
) {
    val articles = remember(category) { LearnCorpus.articlesIn(category) }
    Scaffold(
        topBar = {
            LargeTopAppBar(
                title = { Text(category.title) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        if (articles.isEmpty()) {
            BOBAEmptyState(
                icon = category.icon,
                headline = "${category.title} content coming soon",
                body = "Article corpus port from iOS in progress.",
                modifier = Modifier.fillMaxSize().padding(padding),
            )
            return@Scaffold
        }
        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            items(items = articles, key = { it.id }) { article ->
                ListItem(
                    headlineContent = { Text(article.title, style = MaterialTheme.typography.titleMedium) },
                    supportingContent = {
                        val sectionCount = article.sections.values.flatten().size
                        Text(
                            "$sectionCount sections · ${article.sections.size} skill level${if (article.sections.size != 1) "s" else ""}",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    trailingContent = {
                        Icon(
                            imageVector = Icons.Default.ChevronRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    modifier = Modifier.clickable { onArticleClick(article.id) },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}
