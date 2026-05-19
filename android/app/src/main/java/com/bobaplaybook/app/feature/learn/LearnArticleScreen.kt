@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Learn article screen — single article with skill-level segmented
 * picker (ANDROID-DESIGN.md §8.2). Skill level is a scope INSIDE the
 * article, never a third nav level.
 */
@Composable
fun LearnArticleScreen(
    articleId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val article = remember(articleId) { LearnCorpus.findArticle(articleId) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())
    var skill by rememberSaveable { mutableStateOf(SkillLevel.ROOKIE) }

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(article?.title ?: "Article") },
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
        if (article == null) {
            BOBAEmptyState(
                headline = "Article not found",
                body = "Looking for article id `$articleId`. Has it been renamed?",
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Skill-level scope picker (SegmentedButton)
            val availableLevels = SkillLevel.entries.filter { it in article.sections }
            if (availableLevels.size > 1) {
                Surface(color = MaterialTheme.colorScheme.surface) {
                    SingleChoiceSegmentedButtonRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        availableLevels.forEachIndexed { index, level ->
                            SegmentedButton(
                                selected = level == skill,
                                onClick = { skill = level },
                                shape = SegmentedButtonDefaults.itemShape(index, availableLevels.size),
                            ) {
                                Text(level.label, style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
            }

            val sections = article.sections[skill] ?: emptyList()
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(
                    items = sections,
                    key = { section -> "${section::class.simpleName}-${section.heading.orEmpty()}-${sections.indexOf(section)}" },
                ) { section ->
                    SectionRenderer(section, article.glossaryTerms)
                }
            }
        }
    }
}

@Composable
private fun SectionRenderer(section: LearnSection, glossaryTerms: List<String>) {
    when (section) {
        is LearnSection.Body -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            Text(
                text = section.text,
                style = MaterialTheme.typography.bodyLarge,
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
    }
}
