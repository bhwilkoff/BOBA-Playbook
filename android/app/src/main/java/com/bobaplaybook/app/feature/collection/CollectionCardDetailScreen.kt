@file:OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.domain.model.UserCard
import com.bobaplaybook.core.network.CDN
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAStatsGrid
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaElements

/**
 * Collection Card Detail — mirrors iOS CollectionCardDetailView.
 *
 * Tap a card in Collection grid → push to this screen showing every
 * owned copy of that card (multi-copy support), with per-copy
 * designation switch, condition/grade/pricing edit, delete, market
 * value summary. Anchored to a single bobaId.
 */
@Composable
fun CollectionCardDetailScreen(
    bobaId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val viewModel: CollectionViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val card = remember(state, bobaId) {
        state.entriesByDesignation.values.flatten().firstOrNull { it.card.bobaId == bobaId }?.card
    }
    val copies = remember(state, bobaId) {
        state.entriesByDesignation.values.flatten().filter { it.card.bobaId == bobaId }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(card?.displayName ?: "Collection card") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        if (card == null) {
            BOBAEmptyState(
                headline = "Card not in collection",
                body = "This card isn't owned. Add it to your collection from card detail.",
                modifier = Modifier.fillMaxSize().padding(padding),
            )
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
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
            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))
            BOBASectionHeader(title = "Your copies (${copies.size})")
            copies.forEach { entry ->
                CopyRow(
                    entry = entry,
                    onDesignationChange = { newDesignation ->
                        // M7 polish — call CollectionRepository.updateDesignation
                    },
                    onDelete = {
                        // M7 polish — call CollectionRepository.remove
                    },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
            // Add another copy
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                OutlinedButton(onClick = { /* M7 polish — open AddToCollectionSheet */ }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Add another copy")
                }
            }
            Spacer(Modifier.height(48.dp))
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
            .background(Brush.verticalGradient(colors = listOf(accent.copy(alpha = 0.25f), BobaBrand.NearBlack))),
        contentAlignment = Alignment.Center,
    ) {
        val fullUrl = remember(card.imageFile) { CDN.fullUrl(card.imageFile) }
        if (fullUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(fullUrl).crossfade(200).build(),
                contentDescription = card.displayName,
                modifier = Modifier.aspectRatio(5f / 7f).clip(RoundedCornerShape(16.dp)),
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

@Composable
private fun CopyRow(
    entry: CollectionEntry,
    onDesignationChange: (Designation) -> Unit,
    onDelete: () -> Unit,
) {
    var deleteOpen by rememberSaveable { mutableStateOf(false) }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                "Copy",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            entry.userCard.quantity.takeIf { it > 1 }?.let {
                Text("×$it", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = { deleteOpen = true }) {
                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
            }
        }
        // Designation switcher
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Designation.entries.forEach { d ->
                FilterChip(
                    selected = entry.userCard.designation == d,
                    onClick = { onDesignationChange(d) },
                    label = { Text(d.shortLabel, style = MaterialTheme.typography.labelSmall) },
                )
            }
        }
        // Pricing summary
        entry.userCard.estimatedValue?.let { value ->
            Text(
                "Market: $${"%.2f".format(value)}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        entry.userCard.purchasePrice?.let { paid ->
            Text(
                "Paid: $${"%.2f".format(paid)}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        entry.userCard.notes?.takeIf { it.isNotBlank() }?.let { notes ->
            Text(
                notes,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
    if (deleteOpen) {
        AlertDialog(
            onDismissRequest = { deleteOpen = false },
            title = { Text("Remove this copy?") },
            text = { Text("This removes one copy of ${entry.card.displayName} from your collection. The catalog card stays available.") },
            confirmButton = {
                TextButton(onClick = { deleteOpen = false; onDelete() }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteOpen = false }) { Text("Cancel") }
            },
        )
    }
}
