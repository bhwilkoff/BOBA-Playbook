@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.carddetail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.app.R
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.network.CDN
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAStatsGrid
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaElements

/**
 * Card detail surface (ANDROID-DESIGN.md §8.6).
 *
 * M1 ships the canonical anatomy:
 *  - Element-tinted gradient art panel with full-res image
 *  - Canonical 6-cell stats grid (DECISIONS.md #029)
 *  - Card name + element pill below stats
 *
 * Deferred to later milestones:
 *  - Container transform animation from grid cell (M2)
 *  - Pricing panels (M3)
 *  - Per-context body (Add to Collection / Deck / Show — M2-M4)
 *  - Other Versions browsing (M2)
 *  - Hero zoom + shared bounds (M2)
 */
@Composable
fun CardDetailScreen(
    bobaId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val viewModel: CardDetailViewModel = hiltViewModel()
    val state by viewModel.uiStateFor(bobaId).collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = state.card?.displayName ?: "",
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.action_back),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        val card = state.card
        if (card == null) {
            BOBAEmptyState(
                headline = "Card not found",
                body = "Couldn't find a card with bobaId `$bobaId`.",
                actionLabel = "Back",
                onAction = onBack,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        } else {
            CardDetailBody(
                card = card,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        }
    }
}

@Composable
private fun CardDetailBody(card: Card, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()),
    ) {
        ArtPanel(card)
        BOBAStatsGrid(
            cardNumber = card.cardNumber,
            cardType   = card.cardType,
            treatment  = card.treatment,
            weapon     = card.element.takeIf { !card.isSealed }?.lowercase()?.replaceFirstChar { it.uppercase() },
            set        = card.set,
            subSet     = card.subSet,
        )
        // Power + cost when present (Plays only, but render them below
        // the canonical six per DECISIONS.md #029).
        val showPlayStats = card.cost != null || card.dbs != null || card.power != null
        if (showPlayStats) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                card.power?.let { Text("Power: $it", style = MaterialTheme.typography.titleMedium) }
                card.cost?.let  { Text("Cost: $it",  style = MaterialTheme.typography.bodyMedium) }
                card.dbs?.let   { Text("DBS: $it",   style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

@Composable
private fun ArtPanel(card: Card) {
    val context = LocalContext.current
    val accent = if (card.isSealed) BobaBrand.Orange else BobaElements.forElement(card.element)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(420.dp)
            .background(
                Brush.verticalGradient(
                    colors = listOf(accent.copy(alpha = 0.25f), BobaBrand.NearBlack),
                ),
            ),
        contentAlignment = androidx.compose.ui.Alignment.Center,
    ) {
        val fullUrl = remember(card.imageFile) { CDN.fullUrl(card.imageFile) }
        if (fullUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(fullUrl)
                    .crossfade(200)
                    .build(),
                contentDescription = card.displayName,
                modifier = Modifier
                    .aspectRatio(5f / 7f)
                    .clip(RoundedCornerShape(16.dp)),
            )
        } else {
            Text(
                text = card.displayName,
                style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Black),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
