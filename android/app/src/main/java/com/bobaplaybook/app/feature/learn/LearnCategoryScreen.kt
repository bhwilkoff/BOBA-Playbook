@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * Learn category screen — list of articles for a single category.
 * Depth 2 inside Learn tab.
 */
@Composable
fun LearnCategoryScreen(
    categoryId: String,
    onArticleClick: (articleId: String) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val category = remember(categoryId) { LearnCategoryId.fromId(categoryId) }
    val articles = remember(category) {
        category?.let { LearnCorpus.articlesIn(it) } ?: emptyList()
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(category?.title ?: "Learn") },
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
        if (articles.isEmpty()) {
            BOBAEmptyState(
                icon = category?.icon,
                headline = "${category?.title ?: "Category"} content coming soon",
                body = "Article corpus port from iOS in progress. Categories with no articles yet still appear here so the IA shape is stable.",
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            items(
                items = articles,
                key = { it.id },
            ) { article ->
                ListItem(
                    headlineContent = {
                        Text(
                            article.title,
                            style = MaterialTheme.typography.titleMedium,
                        )
                    },
                    supportingContent = {
                        val sectionCount = article.sections.values.flatten().size
                        Text(
                            "$sectionCount sections · ${SkillLevel.entries.count { it in article.sections }} skill level${if (article.sections.size != 1) "s" else ""}",
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
