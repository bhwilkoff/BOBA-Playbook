@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

/**
 * Auto Rainbow detail — shows every Treatment + Parallel printed for a
 * given hero, with owned/missing state on each tile. Owned cards from
 * the user's Collection union with the full catalog's hero-filtered
 * slice gives us the gap.
 *
 * Also handles Custom Rainbow detail (kind = "custom") — fetches the
 * user's saved rainbow by UUID, applies its [RainbowCriteria] across
 * the full catalog, and renders the same owned-vs-missing grid. Tick
 * 141 — closes the "kind=custom ignored" stub left by RainbowsScreen's
 * initial pass.
 */
@Composable
fun RainbowDetailScreen(
    kind: String,
    id: String,
    onCardClick: (bobaId: String) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val collectionVm: CollectionViewModel = hiltViewModel()
    val catalogVm: RainbowCatalogViewModel = hiltViewModel()
    val customVm: CustomRainbowsViewModel = hiltViewModel()
    val collectionState by collectionVm.uiState.collectAsStateWithLifecycle()
    val catalogCards by catalogVm.cards.collectAsStateWithLifecycle()
    val customRainbows by customVm.rainbows.collectAsStateWithLifecycle()

    // Resolve the rainbow's identity + matching predicate. Hero rainbows
    // match purely on `card.hero`; custom rainbows apply the saved
    // RainbowCriteria. When a custom rainbow id doesn't resolve (stale
    // deep-link / deleted on another device) we fall through to an
    // empty rainbow with a placeholder title rather than crashing.
    val isCustom = kind == "custom"
    val customRainbow = if (isCustom) customRainbows.firstOrNull { it.id == id } else null
    val title = when {
        isCustom -> customRainbow?.name ?: "Custom Rainbow"
        else     -> id
    }

    val allCards = remember(catalogCards, kind, id, customRainbow?.criteria) {
        val base = when {
            isCustom && customRainbow != null ->
                catalogCards.filter { criteriaMatches(customRainbow.criteria, it) }
            isCustom -> emptyList() // unresolved custom rainbow → empty grid
            else     -> catalogCards.filter { it.hero.equals(id, ignoreCase = true) }
        }
        // Image-first per memory feedback_card_art_sort_priority.
        // Pending-art placeholders sink to the bottom of the rainbow.
        base.sortedWith(
            compareByDescending<com.bobaplaybook.core.domain.model.Card> { !it.imageFile.isNullOrEmpty() }
                .thenBy { it.cardNumber },
        )
    }
    val matchingBobaIds = remember(allCards) { allCards.map { it.bobaId }.toSet() }
    val ownedBobaIds = remember(collectionState, matchingBobaIds) {
        collectionState.entriesByDesignation.values
            .flatten()
            .filter { it.card.bobaId in matchingBobaIds }
            .map { it.card.bobaId }
            .toSet()
    }

    val ownedCount = allCards.count { it.bobaId in ownedBobaIds }
    val pctOwned = if (allCards.isEmpty()) 0f else ownedCount.toFloat() / allCards.size

    val context = androidx.compose.ui.platform.LocalContext.current
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // Share rainbow progress — Intent.ACTION_SEND with a
                    // short bragging-rights blurb. Coaches share "my 12 of
                    // 15 Maverick rainbow" in Discord all the time; this
                    // skips the screenshot+caption round-trip.
                    IconButton(onClick = {
                        val pct = if (allCards.isEmpty()) 0
                                  else ((ownedCount * 100.0) / allCards.size).toInt()
                        val unit = if (isCustom) "cards" else "treatments"
                        val text = "My $title rainbow: $ownedCount of ${allCards.size} $unit ($pct%) · bobaplaybook.com"
                        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(android.content.Intent.EXTRA_SUBJECT, "My $title rainbow")
                            putExtra(android.content.Intent.EXTRA_TEXT, text)
                        }
                        context.startActivity(android.content.Intent.createChooser(intent, "Share rainbow"))
                    }) {
                        Icon(androidx.compose.material.icons.Icons.Default.Share,
                             contentDescription = "Share rainbow progress")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    "$ownedCount / ${allCards.size} owned",
                    style = MaterialTheme.typography.titleMedium,
                )
                LinearProgressIndicator(
                    progress = { pctOwned },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            BOBASectionHeader(title = if (isCustom) "Cards matching your filter" else "Every printing")
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 110.dp),
                contentPadding = PaddingValues(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(items = allCards, key = { it.bobaId }) { card ->
                    RainbowTile(card = card, owned = card.bobaId in ownedBobaIds, onClick = { onCardClick(card.bobaId) })
                }
            }
        }
    }
}

@Composable
private fun RainbowTile(card: Card, owned: Boolean, onClick: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth()) {
        BOBACardCell(
            imageFile = card.imageFile,
            isSealed = card.isSealed,
            contentDescription = card.displayName,
            modifier = Modifier.clickable(onClick = onClick),
        )
        if (!owned) {
            // Dim layer — communicates "you don't have this yet"
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.7f),
                modifier = Modifier.fillMaxSize(),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        "Missing",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/**
 * Tiny ViewModel exposing the full card catalog as a StateFlow for the
 * RainbowDetailScreen. Keeps the screen from having to depend on
 * FindViewModel (which is filter-scoped to search results, not the
 * full catalog).
 */
@HiltViewModel
class RainbowCatalogViewModel @Inject constructor(
    private val cardRepository: CardRepository,
) : ViewModel() {
    val cards: StateFlow<List<Card>> = cardRepository.cards
}
