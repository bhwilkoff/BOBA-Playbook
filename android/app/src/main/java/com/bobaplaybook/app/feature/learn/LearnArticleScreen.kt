@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.sp
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.theme.BobaElements
import com.bobaplaybook.app.feature.collection.RainbowCatalogViewModel
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.rememberModalBottomSheetState
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
                LearnCategoryId.STRATEGY   -> StrategyPage()
                LearnCategoryId.COLLECT    -> FlatSectionsPage(LearnCorpus.collect)
                LearnCategoryId.WATCH      -> WatchPage()
                LearnCategoryId.GLOSSARY   -> GlossaryPage()
                LearnCategoryId.TOURNAMENT -> TournamentPage()
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
// Strategy — flat sections + the five archetype templates (iOS parity)
// ════════════════════════════════════════════════════════════════

@Composable
private fun StrategyPage() {
    val catalogVm: RainbowCatalogViewModel = androidx.hilt.navigation.compose.hiltViewModel()
    val catalog by catalogVm.cards.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        itemsIndexed(items = LearnCorpus.strategy, key = { i, _ -> "strat-$i" }) { _, section ->
            // CardExamples requires the catalog — render here with the
            // already-collected `catalog` rather than threading state
            // into the generic SectionRenderer.
            if (section is LearnSection.CardExamples) {
                CardExamplesRow(section, catalog)
            } else {
                SectionRenderer(section)
            }
        }
        item("archetypes-header") {
            BOBASectionHeader(title = "Archetype templates")
        }
        items(items = LearnCorpus.archetypes, key = { "archetype-${it.id}" }) { archetype ->
            ArchetypeCard(archetype = archetype, catalog = catalog)
        }
        item("archetypes-spacer") {
            Spacer(modifier = Modifier.padding(bottom = 16.dp))
        }
    }
}

@Composable
private fun CardExamplesRow(
    section: LearnSection.CardExamples,
    catalog: List<Card>,
) {
    val resolved = remember(section.cardNames, section.hotDogsOnly, section.playsOnly, section.heroesOnly, catalog) {
        section.cardNames.mapNotNull { wanted ->
            val matches = catalog.filter { c ->
                c.name.equals(wanted, ignoreCase = true) &&
                    !c.imageFile.isNullOrBlank() &&
                    (!section.hotDogsOnly || c.cardType.contains("Hot Dog", ignoreCase = true) || c.cardType.contains("HotDog", ignoreCase = true)) &&
                    (!section.playsOnly   || c.cardType.contains("Play", ignoreCase = true)) &&
                    (!section.heroesOnly  || c.cardType.equals("Hero", ignoreCase = true))
            }
            matches.firstOrNull { it.treatment.equals("Plays", ignoreCase = true) && it.variation == "First Edition" }
                ?: matches.firstOrNull { it.treatment.equals("Plays", ignoreCase = true) }
                ?: matches.firstOrNull()
        }
    }
    if (resolved.isEmpty()) return

    Column(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        section.heading?.let { BOBASectionHeader(title = it) }
        section.description?.let { desc ->
            Text(
                desc,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(items = resolved, key = { it.bobaId }) { card ->
                val accent = BobaElements.forElement(card.element.uppercase())
                Column(
                    modifier = Modifier.width(80.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        modifier = Modifier
                            .width(80.dp)
                            .height(112.dp),
                    ) {
                        BOBACardCell(
                            imageFile = card.imageFile,
                            isSealed = card.isSealed,
                            contentDescription = card.displayName,
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        card.hero.ifBlank { card.name },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        textAlign = TextAlign.Center,
                    )
                    when {
                        card.cardType.contains("Hot Dog", ignoreCase = true) ||
                        card.cardType.contains("HotDog", ignoreCase = true) -> Text(
                            "HOT DOG",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        card.cardType.contains("Play", ignoreCase = true) -> {
                            val cost = card.cost
                            Text(
                                if (cost == null || cost == 0) "FREE" else "${cost} HD",
                                style = MaterialTheme.typography.labelSmall,
                                color = if (cost == null || cost == 0) com.bobaplaybook.core.ui.theme.BobaBrand.Cyan else accent,
                            )
                        }
                        card.cardType.equals("Hero", ignoreCase = true) -> {
                            Text(
                                "${card.element.uppercase()} · ${card.power ?: 0}",
                                style = MaterialTheme.typography.labelSmall,
                                color = accent,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ArchetypeCard(
    archetype: Archetype,
    catalog: List<Card>,
) {
    val accent = BobaElements.forElement(archetype.element)
    var expanded by rememberSaveable(archetype.id) { mutableStateOf(false) }

    val keyPlayCards = remember(archetype.id, catalog) {
        archetype.keyPlays.mapNotNull { playName ->
            val candidates = catalog.filter { c ->
                c.name.equals(playName, ignoreCase = true) &&
                    c.cardType.contains("Play", ignoreCase = true) &&
                    !c.imageFile.isNullOrBlank()
            }
            candidates.firstOrNull { it.treatment.equals("Plays", ignoreCase = true) && it.variation == "First Edition" }
                ?: candidates.firstOrNull { it.treatment.equals("Plays", ignoreCase = true) }
                ?: candidates.firstOrNull()
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = MaterialTheme.shapes.medium,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.25f)),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded }
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .background(accent, shape = CircleShape),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        archetype.name,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        archetype.tagline,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                    )
                }
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = accent,
                )
            }
            if (expanded) {
                HorizontalDivider(color = accent.copy(alpha = 0.2f))
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (keyPlayCards.isNotEmpty()) {
                        Text(
                            "KEY PLAYS",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(items = keyPlayCards, key = { it.bobaId }) { card ->
                                Column(
                                    modifier = Modifier.width(76.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .width(76.dp)
                                            .height(106.dp),
                                    ) {
                                        BOBACardCell(
                                            imageFile = card.imageFile,
                                            isSealed = card.isSealed,
                                            contentDescription = card.displayName,
                                        )
                                    }
                                    Text(
                                        card.name,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                        textAlign = TextAlign.Center,
                                    )
                                }
                            }
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "STRATEGY",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            archetype.strategy,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "WEAKNESS",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            archetype.weakness,
                            style = MaterialTheme.typography.bodyMedium,
                            color = BobaElements.Brawl.copy(alpha = 0.9f),
                        )
                    }
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Flat sections — Collect / Tournament
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

/**
 * Tournament page — Discord backlog #8 (tick 191). Renders the
 * live "Upcoming Events" list from `assets/data/events.json` at
 * the top, then the static tournament reference content below.
 */
@Composable
private fun TournamentPage() {
    val context = LocalContext.current
    // Tick 219 — Android parity with web tick 218 + iOS LearnView events
    // surface. Bundle includes lastUpdated so the user sees data freshness.
    val bundle = remember { EventsLoader.loadBundle(context) }
    val events = bundle.events
    val sections = LearnCorpus.tournament
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item("events-head") { BOBASectionHeader(title = "Upcoming events") }
        bundle.lastUpdated?.takeIf { it.isNotBlank() }?.let { stamp ->
            item("events-stamp") {
                Text(
                    text = "Last refreshed $stamp",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 0.dp),
                )
            }
        }
        if (events.isEmpty()) {
            item("events-empty") {
                Text(
                    text = "No events scheduled yet. Check back as the BoBA team announces dates.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
        } else {
            items(events, key = { it.id }) { EventRow(it) }
        }

        // Tick 236 — Recent BoBA news from the official blog. Live data
        // refreshed daily at 05:17 UTC; sourced from docs/blog-feed.json
        // (mirrored to android/.../blog-feed.json). Lets users catch up
        // on rules updates, release announcements, and community moments
        // without leaving the app.
        val blogBundle = BlogFeedLoader.loadBundle(context)
        val blogPosts = blogBundle.posts.take(5)
        if (blogPosts.isNotEmpty()) {
            item("blog-head") { BOBASectionHeader(title = "Recent BoBA news") }
            // Tick 244 — surface bundle.lastUpdated as a freshness stamp,
            // matching the events list (tick 219). Daily cron drives this.
            blogBundle.lastUpdated?.takeIf { it.isNotBlank() }?.let { stamp ->
                item("blog-stamp") {
                    Text(
                        text = "Last refreshed $stamp",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 0.dp),
                    )
                }
            }
            items(blogPosts, key = { "blog-${it.id}" }) { post -> BlogPostRow(post) }
            // Tick 259 — "See all N posts" link to the full archive
            // (web tick 258 parity). Renders only when the feed has
            // more posts than the 5-post preview.
            val totalPosts = blogBundle.posts.size
            if (totalPosts > blogPosts.size) {
                item("blog-see-all") {
                    // Tick 261 — visually distinct cyan-bordered card
                    // (matching web .blog-feed-see-all style) instead of a
                    // bare TextButton. Reads as a contained CTA, not a
                    // borderless label that gets lost at the end of the
                    // post list.
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = com.bobaplaybook.core.ui.theme.BobaBrand.Cyan.copy(alpha = 0.05f),
                        border = BorderStroke(1.dp, com.bobaplaybook.core.ui.theme.BobaBrand.Cyan.copy(alpha = 0.3f)),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                            .clickable {
                                androidx.browser.customtabs.CustomTabsIntent.Builder()
                                    .build()
                                    .launchUrl(
                                        context,
                                        android.net.Uri.parse("https://bobattlearena.com/blog/all"),
                                    )
                            },
                    ) {
                        Text(
                            "See all $totalPosts posts on bobattlearena.com ↗",
                            style = MaterialTheme.typography.labelMedium,
                            color = com.bobaplaybook.core.ui.theme.BobaBrand.Cyan,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 10.dp, horizontal = 12.dp),
                        )
                    }
                }
            }
        }

        itemsIndexed(items = sections, key = { i, _ -> "section-$i" }) { _, section ->
            SectionRenderer(section)
        }
    }
}

@Composable
private fun BlogPostRow(post: BlogPost) {
    val context = LocalContext.current
    val accent = com.bobaplaybook.core.ui.theme.BobaBrand.Orange
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable {
                androidx.browser.customtabs.CustomTabsIntent.Builder()
                    .build()
                    .launchUrl(context, android.net.Uri.parse(post.url))
            }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            // Tick 246 — relative-format for recent posts, ISO for older
            // ones. "today" / "Nd ago" reads more naturally than 2026-05-21
            // for posts users likely saw on the web yesterday.
            text = relativeOrIsoDate(post.date),
            style = MaterialTheme.typography.labelSmall,
            color = accent,
        )
        Text(
            text = post.title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.SemiBold,
        )
        if (post.excerpt.isNotBlank()) {
            Text(
                text = post.excerpt,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
        }
    }
}

/// Tick 246 — relative-format YYYY-MM-DD dates for the news rows.
/// Returns "today" / "yesterday" / "Nd ago" / "Nw ago" within 5 weeks;
/// falls back to the raw ISO string for older posts so collectors
/// can still grep their feed history accurately.
private fun relativeOrIsoDate(iso: String): String {
    val raw = iso.trim()
    val parts = raw.split("-")
    if (parts.size != 3) return raw
    val y = parts[0].toIntOrNull() ?: return raw
    val m = parts[1].toIntOrNull() ?: return raw
    val d = parts[2].toIntOrNull() ?: return raw
    val cal = java.util.Calendar.getInstance().apply {
        clear()
        set(y, m - 1, d)
    }
    val days = ((System.currentTimeMillis() - cal.timeInMillis) / 86_400_000L).toInt()
    return when {
        days < 0   -> raw
        days == 0  -> "today"
        days == 1  -> "yesterday"
        days < 7   -> "${days}d ago"
        days < 35  -> "${days / 7}w ago"
        else       -> raw
    }
}

@Composable
private fun EventRow(event: EventEntry) {
    val accent = when (event.kind.lowercase()) {
        "release"    -> com.bobaplaybook.core.ui.theme.BobaBrand.Cyan
        else         -> com.bobaplaybook.core.ui.theme.BobaBrand.Orange  // tournament fallback
    }
    // Tick 254 — past-event detection (web tick 253 parity). Concluded
    // events render dimmed + drop the "Open ↗" CTA + suffix "· PAST"
    // so users can scan the list and immediately see what's upcoming.
    val today = remember {
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
    }
    val isPast = event.date?.takeIf { it.isNotBlank() }?.let { it < today } ?: false
    val dateLabel = event.date?.takeIf { it.isNotBlank() }
        ?.let { if (isPast) "$it · PAST" else it }
        ?: "Date TBA"
    val context = LocalContext.current
    val url = event.url?.takeIf { it.isNotBlank() && !isPast }
    val rowMod = Modifier
        .fillMaxWidth()
        .padding(horizontal = 16.dp, vertical = 2.dp)
        .alpha(if (isPast) 0.55f else 1f)
        .let { base ->
            if (url != null) base.clickable {
                runCatching {
                    androidx.browser.customtabs.CustomTabsIntent.Builder()
                        .build()
                        .launchUrl(context, android.net.Uri.parse(url))
                }
            } else base
        }
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainer,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.45f)),
        modifier = rowMod,
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = event.kind.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = accent,
                    fontWeight = FontWeight.Bold,
                )
                Text(text = "·", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    text = dateLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (url != null) {
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = "Open ↗",
                        style = MaterialTheme.typography.labelMedium,
                        color = accent,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            Text(
                text = event.title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            event.description?.takeIf { it.isNotBlank() }?.let { desc ->
                Text(
                    text = desc,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 18.sp,
                )
            }
            event.location?.takeIf { it.isNotBlank() }?.let {
                Text(
                    text = "Location: $it",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            event.formats.takeIf { it.isNotEmpty() }?.let { fmts ->
                Text(
                    text = fmts.joinToString(" · "),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Glossary — two flat term sections (Game + Trading)
// ════════════════════════════════════════════════════════════════

@Composable
private fun GlossaryPage() {
    var query by rememberSaveable { mutableStateOf("") }
    val needle = query.trim().lowercase()
    val context = LocalContext.current
    // Tick 230 — platform ClipboardManager instead of Compose's
    // LocalClipboardManager (deprecated 1.5.0-alpha19+). The new
    // LocalClipboard is suspend-based; the platform API is non-suspend
    // and matches the pattern already used in ProfileSheet's
    // Send-Feedback fallback.
    val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)
    // First-run hint banner — was registered in HintsStore.Ids as
    // LEARN_LONG_PRESS_GLOSSARY but had no rendering site until tick
    // 84. Tells users the rows are tap-to-copy (useful for Discord +
    // game-night chats where coaches quote definitions verbatim).
    val hintsVm: com.bobaplaybook.app.hints.HintsViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val glossaryHintDismissed by hintsVm
        .isDismissed(com.bobaplaybook.app.hints.HintsStore.Ids.LEARN_LONG_PRESS_GLOSSARY)
        .collectAsStateWithLifecycle(initialValue = true)
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
        // Always-visible instruction line so users learn the long-press
        // gesture immediately — paired with the dismissible hint banner
        // below for first-visit pop.
        Text(
            text = "Press and hold any term to copy or share its definition.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (!glossaryHintDismissed) {
            com.bobaplaybook.core.ui.components.BOBAHintBanner(
                title = "Long-press a term",
                body = "Press and hold any glossary term to copy or share its definition — handy for quoting it in Discord or a coaching note.",
                onDismiss = { hintsVm.dismiss(com.bobaplaybook.app.hints.HintsStore.Ids.LEARN_LONG_PRESS_GLOSSARY) },
            )
        }
        // In-corpus filter — iOS DESIGN.md §6 (Search is the universal
        // navigator) + the Glossary's high term density justify a
        // persistent search field over the OutlinedTextField shape.
        OutlinedTextField(
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
                    TermRow(
                        section = term,
                        onCopy = { copyTermToClipboard(clipboard, context, term) },
                        onShare = { shareTerm(context, term) },
                    )
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
                    TermRow(
                        section = term,
                        onCopy = { copyTermToClipboard(clipboard, context, term) },
                        onShare = { shareTerm(context, term) },
                    )
                }
            }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun TermRow(
    section: LearnSection.Term,
    onCopy: () -> Unit,
    onShare: () -> Unit,
) {
    // Long-press → DropdownMenu offering Copy + Share. Plain tap is a
    // no-op (the always-visible instruction line above the lists tells
    // users to press-and-hold). Mirrors iOS contextMenu (tick 200) and
    // web Popover menu.
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClickLabel = null,
                    onLongClickLabel = "Open copy or share menu",
                    onClick = {},
                    onLongClick = { menuOpen = true },
                )
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
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false },
        ) {
            DropdownMenuItem(
                text = { Text("Copy") },
                leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
                onClick = { menuOpen = false; onCopy() },
            )
            DropdownMenuItem(
                text = { Text("Share") },
                leadingIcon = { Icon(Icons.Default.Share, contentDescription = null) },
                onClick = { menuOpen = false; onShare() },
            )
        }
    }
}

private fun copyTermToClipboard(
    clipboard: android.content.ClipboardManager?,
    context: android.content.Context,
    section: LearnSection.Term,
) {
    val payload = "${section.term} — ${section.definition}"
    clipboard?.setPrimaryClip(
        android.content.ClipData.newPlainText("BOBA glossary: ${section.term}", payload)
    )
    android.widget.Toast
        .makeText(context, "Copied “${section.term}”", android.widget.Toast.LENGTH_SHORT)
        .show()
}

/// Long-press to share a glossary term. Fires Android's Intent.ACTION_SEND
/// chooser so the user can route the term + definition to any installed
/// messaging app (Discord, WhatsApp, Messages, etc.) without bouncing
/// through the clipboard.
private fun shareTerm(context: android.content.Context, section: LearnSection.Term) {
    val payload = "${section.term} — ${section.definition}"
    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(android.content.Intent.EXTRA_TEXT, payload)
        putExtra(android.content.Intent.EXTRA_SUBJECT, "BOBA Glossary: ${section.term}")
    }
    context.startActivity(android.content.Intent.createChooser(intent, "Share term"))
}

// ════════════════════════════════════════════════════════════════
// SectionRenderer — shared by every page type
// ════════════════════════════════════════════════════════════════

@Composable
private fun SectionRenderer(section: LearnSection) {
    when (section) {
        is LearnSection.Body -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            GlossaryAwareBody(text = section.text)
        }
        is LearnSection.Bullets -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                section.items.forEach { item ->
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "•",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.secondary,
                        )
                        // Tick 371 — bullet items now glossary-aware
                        // (iOS tick 367 + web tick 363 parity). Body
                        // sections already had it via GlossaryAwareBody
                        // at line 967; bullets were the gap. Same
                        // primitive, just passing through a Row-context
                        // style + zero-padding modifier.
                        GlossaryAwareBody(
                            text = item,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
        is LearnSection.Callout -> {
            // Element-tinted callout — left border + heading color come
            // from the element key when set. Matches iOS callout style.
            val accent = section.element?.let { BobaElements.forElement(it) }
                ?: MaterialTheme.colorScheme.secondary
            Surface(
                color = accent.copy(alpha = 0.08f),
                shape = MaterialTheme.shapes.medium,
                border = BorderStroke(1.dp, accent.copy(alpha = 0.4f)),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Row(modifier = Modifier.fillMaxWidth()) {
                    // 4dp left bar — matches iOS callout chrome
                    Box(
                        modifier = Modifier
                            .width(4.dp)
                            .padding(vertical = 12.dp)
                            .background(accent),
                    )
                    Column(modifier = Modifier.padding(16.dp).weight(1f)) {
                        section.heading?.let { h ->
                            Text(
                                h,
                                style = MaterialTheme.typography.titleSmall,
                                color = accent,
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                        }
                        Text(
                            text = section.text,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            lineHeight = 20.sp,
                        )
                    }
                }
            }
        }
        is LearnSection.WeaponSynergy -> {
            section.heading?.let { BOBASectionHeader(title = it) }
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                section.rows.forEach { row ->
                    val accent = BobaElements.forElement(row.weapon.uppercase())
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, accent.copy(alpha = 0.3f)),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text(
                                row.weapon,
                                style = MaterialTheme.typography.titleSmall,
                                color = accent,
                            )
                            Spacer(Modifier.height(6.dp))
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                row.plays.forEach { play ->
                                    Surface(
                                        color = accent.copy(alpha = 0.12f),
                                        contentColor = accent,
                                        shape = MaterialTheme.shapes.small,
                                        border = BorderStroke(1.dp, accent.copy(alpha = 0.3f)),
                                    ) {
                                        Text(
                                            play,
                                            style = MaterialTheme.typography.labelMedium,
                                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        is LearnSection.Term -> {
            Text(
                text = "•  ${section.term}: ${section.definition}",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
        is LearnSection.CardExamples -> {
            // CardExamples needs the catalog and is rendered by callers
            // that have it (StrategyPage). If one shows up in a flat
            // page without catalog access, fall back to a labelled bullet.
            section.heading?.let { BOBASectionHeader(title = it) }
            Text(
                text = "Examples: ${section.cardNames.joinToString(" · ")}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Glossary-aware body (Discord backlog #3, tick 184)
// ════════════════════════════════════════════════════════════════
//
// Discord §4: article prose throws around HTD / OBF / G&S / vouch /
// PWE without defining them. The standalone Glossary tab exists but
// users have to know which terms are in it. Inline tap-to-define
// fixes that — terms in article prose become cyan-underlined links
// that pop a ModalBottomSheet with the definition.
//
// Match strategy: word-boundary regex compiled once at the LearnCorpus
// level. Terms are sorted longest-first so "G&S" wins over "G" if
// both were ever in the list. Match is case-sensitive on first letter
// (so "Coach" matches but "coaching" doesn't), case-insensitive on
// the rest. The detector is best-effort — false positives on common
// English words are filtered by the glossary's own niche-vocabulary
// bias (HTD, OBF, PWE — not "the").

private data class GlossaryHit(val term: String, val definition: String, val range: IntRange)

/// Combined glossary as a single ordered list (game first, trading
/// second). Computed once at lookup time via `remember`.
private fun allGlossaryTerms(): List<LearnSection.Term> =
    LearnCorpus.glossaryGame + LearnCorpus.glossaryTrading

/// Scan `text` for any glossary-term occurrences. Returns
/// non-overlapping hits sorted by start index, longest-match-wins
/// when terms overlap.
private fun detectGlossaryHits(text: String, terms: List<LearnSection.Term>): List<GlossaryHit> {
    val sortedTerms = terms.sortedByDescending { it.term.length }
    val claimed = BooleanArray(text.length)
    val hits = mutableListOf<GlossaryHit>()
    for (t in sortedTerms) {
        // Word-boundary regex. Term itself is treated literally
        // (Regex.escape) so "G&S" doesn't try to interpret "&" as
        // a regex metachar. Word boundary works for letter-edged
        // terms; for terms with non-letter chars (G&S, F/S) we
        // fall back to a (^|non-letter) prefix + (end|non-letter)
        // suffix lookaround so they're still bracketed correctly.
        val esc = Regex.escape(t.term)
        // Tick 374 — web tick 373 parity. Letter-edged terms whose
        // singular form doesn't already end in 's' now match an
        // optional trailing `s` so "Hot Dogs" / "Hero Decks" /
        // "Top Decks" / "Bonus Plays" tap-resolve to their singulars.
        // Terms ending in 's' (e.g. "comps") keep the strict
        // boundary to avoid mismatching "comp" → comps' definition.
        val pattern = if (t.term.first().isLetterOrDigit() && t.term.last().isLetterOrDigit()) {
            if (t.term.last().equals('s', ignoreCase = true)) "\\b$esc\\b"
            else "\\b${esc}s?\\b"
        } else {
            "(?<![A-Za-z0-9])$esc(?![A-Za-z0-9])"
        }
        val regex = try { Regex(pattern) } catch (_: Throwable) { continue }
        for (match in regex.findAll(text)) {
            val r = match.range
            val overlaps = (r.first..r.last).any { claimed[it] }
            if (overlaps) continue
            for (i in r.first..r.last) claimed[i] = true
            hits += GlossaryHit(term = t.term, definition = t.definition, range = r)
        }
    }
    return hits.sortedBy { it.range.first }
}

@Composable
private fun GlossaryAwareBody(
    text: String,
    style: androidx.compose.ui.text.TextStyle? = null,
    modifier: Modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
) {
    val terms = remember { allGlossaryTerms() }
    val hits = remember(text) { detectGlossaryHits(text, terms) }
    var openHit by remember { mutableStateOf<GlossaryHit?>(null) }
    val cyan = com.bobaplaybook.core.ui.theme.BobaBrand.Cyan
    // Tick 235 — migrate from deprecated `ClickableText` to native
    // `Text(AnnotatedString)` + `LinkAnnotation.Clickable`. Each
    // glossary hit becomes a per-link tappable span; the listener
    // captures `openHit`'s setter so the sheet fires correctly.
    val linkStyle = androidx.compose.ui.text.TextLinkStyles(
        style = androidx.compose.ui.text.SpanStyle(
            color = cyan,
            textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline,
            fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
        )
    )
    val annotated = remember(text, hits) {
        androidx.compose.ui.text.buildAnnotatedString {
            var cursor = 0
            for (h in hits) {
                if (h.range.first > cursor) append(text.substring(cursor, h.range.first))
                val capturedTerm = h.term
                val link = androidx.compose.ui.text.LinkAnnotation.Clickable(
                    tag = "glossary",
                    styles = linkStyle,
                    linkInteractionListener = {
                        openHit = hits.firstOrNull { it.term == capturedTerm }
                    },
                )
                withLink(link) {
                    append(text.substring(h.range.first, h.range.last + 1))
                }
                cursor = h.range.last + 1
            }
            if (cursor < text.length) append(text.substring(cursor))
        }
    }
    // Tick 371 — caller can override style + modifier so bullet rows
    // and other in-row contexts can reuse the same glossary-aware
    // tappable rendering without inheriting the standalone Body's
    // padding. Default keeps the prior shape so existing call sites
    // are unaffected.
    Text(
        text = annotated,
        style = style ?: MaterialTheme.typography.bodyMedium.copy(
            color = MaterialTheme.colorScheme.onSurface,
            lineHeight = 22.sp,
        ),
        modifier = modifier,
    )
    val hit = openHit
    if (hit != null) {
        val sheetState = rememberModalBottomSheetState()
        ModalBottomSheet(
            onDismissRequest = { openHit = null },
            sheetState = sheetState,
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    hit.term,
                    style = MaterialTheme.typography.titleLarge,
                    color = cyan,
                )
                Text(
                    hit.definition,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    lineHeight = 22.sp,
                    modifier = Modifier.padding(bottom = 32.dp),
                )
            }
        }
    }
}
