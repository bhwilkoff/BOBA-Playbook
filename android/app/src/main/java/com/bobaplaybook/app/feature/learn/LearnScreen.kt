@file:OptIn(
    ExperimentalMaterial3Api::class,
    androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class,
)

package com.bobaplaybook.app.feature.learn

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
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.carousel.HorizontalUncontainedCarousel
import androidx.compose.material3.carousel.rememberCarouselState
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp

/**
 * Learn tab — canonical M3 **Feed** layout.
 *
 * Pattern (sourced from M3 spec + Google News 2025 redesign):
 *   LargeTopAppBar  → "Learn BoBA" w/ exitUntilCollapsed
 *   PrimaryScrollableTabRow → 6 categories (All / Rules / Strategy / ...)
 *   HorizontalUncontainedCarousel → featured articles strip (when "All")
 *   LazyColumn of M3 Cards → one card per article, tap → push to body
 *
 * 2 nav levels max (feed + article body). No category-list intermediate
 * screen — that's the "2009" pattern this rebuild replaces.
 *
 * Sources:
 *   - M3 canonical layouts → Feed (m3.material.io)
 *   - PrimaryScrollableTabRow (composables.com/material3/primaryscrollabletabrow)
 *   - HorizontalUncontainedCarousel (developer.android.com/develop/ui/compose/components/carousel)
 *   - Google News Android redesign 2025
 */
@Composable
fun LearnScreen(
    onCategoryClick: (categoryId: String) -> Unit = {},  // legacy nav signature; ignored in feed model
    onArticleClick: (articleId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabs = remember { listOf<LearnCategoryId?>(null) + LearnCategoryId.entries }
    var selectedIndex by rememberSaveable { mutableStateOf(0) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    val selectedCategory = tabs[selectedIndex]
    val articles = remember(selectedCategory) {
        if (selectedCategory == null) LearnCorpus.articles
        else LearnCorpus.articlesIn(selectedCategory)
    }
    val featured = remember { LearnCorpus.articles.take(8) }

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Learn BoBA") },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Sticky category tab strip — PrimaryScrollableTabRow is the
            // M3 spec component for >5 categories on touch interfaces.
            PrimaryScrollableTabRow(
                selectedTabIndex = selectedIndex,
                containerColor = MaterialTheme.colorScheme.surfaceContainer,
            ) {
                tabs.forEachIndexed { index, category ->
                    Tab(
                        selected = index == selectedIndex,
                        onClick = { selectedIndex = index },
                        text = {
                            Text(
                                text = category?.title ?: "All",
                                style = MaterialTheme.typography.labelLarge,
                            )
                        },
                    )
                }
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 32.dp),
            ) {
                // Featured carousel — only on the "All" tab. M3 spec
                // says HorizontalUncontainedCarousel for "items of equal
                // weight glance-browsable in a row."
                if (selectedCategory == null && featured.isNotEmpty()) {
                    item("featured-header") {
                        Text(
                            text = "Featured",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp),
                        )
                    }
                    item("featured-carousel") {
                        FeaturedCarousel(
                            articles = featured,
                            onArticleClick = onArticleClick,
                        )
                    }
                    item("all-articles-header") {
                        Text(
                            text = "All articles",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp),
                        )
                    }
                }
                items(items = articles, key = { it.id }) { article ->
                    ArticleCard(
                        article = article,
                        onClick = { onArticleClick(article.id) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun FeaturedCarousel(
    articles: List<LearnArticle>,
    onArticleClick: (articleId: String) -> Unit,
) {
    HorizontalUncontainedCarousel(
        state = rememberCarouselState(itemCount = { articles.size }),
        itemWidth = 220.dp,
        itemSpacing = 12.dp,
        contentPadding = PaddingValues(horizontal = 16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(168.dp),
    ) { i ->
        val article = articles[i]
        Card(
            onClick = { onArticleClick(article.id) },
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.tertiaryContainer,
            ),
            shape = MaterialTheme.shapes.large,
            modifier = Modifier
                .width(220.dp)
                .height(168.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Bottom),
            ) {
                Surface(
                    color = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.2f),
                    shape = MaterialTheme.shapes.small,
                ) {
                    Text(
                        text = article.categoryId.title,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onTertiaryContainer,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                    )
                }
                Text(
                    text = article.title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                    maxLines = 3,
                )
            }
        }
    }
}

@Composable
private fun ArticleCard(
    article: LearnArticle,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val skillLevels = article.sections.keys.toList().sortedBy { it.ordinal }
    val sectionCount = article.sections.values.flatten().size
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
        shape = MaterialTheme.shapes.large,
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = article.categoryId.icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(end = 12.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = article.title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "${article.categoryId.title} · $sectionCount sections · ${skillLevels.size} skill level${if (skillLevels.size != 1) "s" else ""}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
