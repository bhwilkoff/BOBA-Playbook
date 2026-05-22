@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bobaplaybook.app.feature.collection.WallShareHelper
import com.bobaplaybook.core.ui.components.BOBACardCell
import kotlinx.coroutines.launch

/**
 * Generate-deck-wall sheet (DESIGN.md §8.8 + DECISIONS.md #036).
 *
 * Renders the current draft's cards as a near-black small-multiples
 * grid + share-as-PNG capture. iOS uses CollectionWallSheet w/ deck
 * context; web tick 9 ships a `db-wall-btn` that reuses the canvas
 * Wall pipeline with a deck branch. This is the Android equivalent.
 *
 * Reuses the WallShareHelper introduced for CollectionWall — same
 * graphics-layer capture, same FileProvider + ACTION_SEND chooser,
 * same 200-card HARD_CAP for safe bitmap memory.
 */
@Composable
fun DeckWallSheet(
    draft: DeckDraft,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        DeckWallContent(draft = draft, onDismiss = onDismiss)
    }
}

@Composable
private fun DeckWallContent(
    draft: DeckDraft,
    onDismiss: () -> Unit,
) {
    val HARD_CAP = 200
    val cards = draft.cards
    val truncated = cards.size > HARD_CAP
    val rendered = if (truncated) cards.take(HARD_CAP) else cards.toList()

    val graphicsLayer = rememberGraphicsLayer()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val deckLabel = "Deck: ${draft.name.ifBlank { "Untitled" }}"

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
            Text(
                deckLabel,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = {
                    scope.launch {
                        val img = graphicsLayer.toImageBitmap()
                        val bmp = img.asAndroidBitmap()
                        WallShareHelper.share(
                            context = context,
                            bitmap = bmp,
                            designationLabel = deckLabel,
                            username = null,
                        )
                    }
                },
                enabled = rendered.isNotEmpty(),
            ) {
                Icon(
                    Icons.Default.Share,
                    contentDescription = null,
                    modifier = Modifier.width(16.dp).height(16.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text("Share")
            }
        }

        if (truncated) {
            // GLOW-yellow informational note — same pattern as
            // CollectionWall (tick 64) + iOS CollectionWallSheet (tick 72).
            // Tick 409 — locale-format the counts (CollectionScreen parity).
            val nf = java.text.NumberFormat.getInstance(java.util.Locale.US)
            Text(
                "Showing the first ${nf.format(HARD_CAP)} of ${nf.format(cards.size)} cards — capture caps at ${nf.format(HARD_CAP)} for safe bitmap memory.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFFD9C566),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            )
        }

        if (rendered.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "Empty draft — add cards before sharing.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return
        }

        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 90.dp),
            contentPadding = PaddingValues(2.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier
                .fillMaxSize()
                .clip(MaterialTheme.shapes.medium)
                .drawWithContent {
                    graphicsLayer.record { this@drawWithContent.drawContent() }
                    drawLayer(graphicsLayer)
                },
        ) {
            items(items = rendered, key = { it.bobaId }) { card ->
                BOBACardCell(
                    imageFile = card.imageFile,
                    isSealed = card.isSealed,
                    contentDescription = card.displayName,
                )
            }
        }
    }
}
