@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import android.content.Intent
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASignInPrompt
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.transitions.cardSharedBounds

/**
 * Collection tab — the owner (ANDROID-DESIGN.md §8.4).
 *
 * Anatomy:
 *  - LargeTopAppBar (Collection) with overflow Menu (display modes)
 *  - Designation `SingleChoiceSegmentedButtonRow` below the bar
 *  - Value summary header (total estimated value)
 *  - Card grid w/ designation badge overlay per cell, OR list view, OR
 *    Wall view (per DECISIONS.md #036 lifted from streamer-only)
 *  - Signed-out: inline BOBASignInPrompt
 */
@Composable
fun CollectionScreen(
    onCardClick: (bobaId: String) -> Unit,
    onProfileClick: () -> Unit,  // unused per feedback_profile_only_on_find; kept for nav signature symmetry
    modifier: Modifier = Modifier,
) {
    val viewModel: CollectionViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    var designation by rememberSaveable { mutableStateOf(Designation.PERSONAL) }
    var displayMode by rememberSaveable { mutableStateOf(DisplayMode.GRID) }
    var menuOpen by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Collection") },
                actions = {
                    val context = LocalContext.current
                    IconButton(onClick = {
                        shareCollection(context, designation, displayMode)
                    }) {
                        Icon(Icons.Default.Share, contentDescription = "Share")
                    }
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(
                            expanded = menuOpen,
                            onDismissRequest = { menuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Grid") },
                                leadingIcon = { Icon(Icons.Default.GridOn, contentDescription = null) },
                                onClick = { menuOpen = false; displayMode = DisplayMode.GRID },
                                trailingIcon = if (displayMode == DisplayMode.GRID) {
                                    { Icon(Icons.Default.GridOn, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                                } else null,
                            )
                            DropdownMenuItem(
                                text = { Text("List") },
                                leadingIcon = { Icon(Icons.AutoMirrored.Filled.ViewList, contentDescription = null) },
                                onClick = { menuOpen = false; displayMode = DisplayMode.LIST },
                            )
                            DropdownMenuItem(
                                text = { Text("Wall") },
                                leadingIcon = { Icon(Icons.Default.Wallpaper, contentDescription = null) },
                                onClick = { menuOpen = false; displayMode = DisplayMode.WALL },
                            )
                        }
                    }
                },
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
            DesignationRow(
                selected = designation,
                onChange = { designation = it },
                counts = state.entriesByDesignation.mapValues { it.value.size },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            if (state.totalValueUsd > 0.0) {
                ValueSummary(totalUsd = state.totalValueUsd)
            }

            if (!state.isSignedIn) {
                BOBASignInPrompt(
                    title = "Sign in to see your collection",
                    body = "Your collection, decks, and wanted list sync across iOS, web, and Android.",
                    onAction = { /* M7 wires this to Profile sheet's sign-in flow */ },
                )
                return@Scaffold
            }

            val entries = state.entriesByDesignation[designation].orEmpty()
            if (entries.isEmpty()) {
                BOBAEmptyState(
                    icon = Icons.Default.Inventory2,
                    headline = "No ${designation.label.lowercase()} cards yet",
                    body = "Scan a card or browse Find to add your first one.",
                )
                return@Scaffold
            }

            when (displayMode) {
                DisplayMode.GRID -> CollectionGrid(entries = entries, onCardClick = onCardClick)
                DisplayMode.LIST -> CollectionList(entries = entries, onCardClick = onCardClick)
                DisplayMode.WALL -> CollectionWall(entries = entries, onCardClick = onCardClick)
            }
        }
    }
}

@Composable
private fun DesignationRow(
    selected: Designation,
    onChange: (Designation) -> Unit,
    counts: Map<Designation, Int>,
    modifier: Modifier = Modifier,
) {
    val entries = remember { Designation.entries }
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        entries.forEachIndexed { index, designation ->
            SegmentedButton(
                selected = designation == selected,
                onClick = { onChange(designation) },
                shape = SegmentedButtonDefaults.itemShape(index, entries.size),
            ) {
                val count = counts[designation] ?: 0
                Text(
                    if (count > 0) "${designation.shortLabel} ($count)" else designation.shortLabel,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}

@Composable
private fun ValueSummary(totalUsd: Double) {
    Text(
        text = "Estimated value: $${"%.2f".format(totalUsd)}",
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
}

@Composable
private fun CollectionGrid(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 110.dp),
        contentPadding = PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(
            items = entries,
            key = { it.userCard.id },
        ) { entry ->
            Box(modifier = Modifier.fillMaxWidth()) {
                BOBACardCell(
                    imageFile = entry.card.imageFile,
                    contentDescription = entry.card.displayName,
                    modifier = Modifier
                        .cardSharedBounds(entry.card.bobaId)
                        .clickable { onCardClick(entry.card.bobaId) },
                )
                DesignationBadge(
                    designation = entry.userCard.designation,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(6.dp),
                )
                if (entry.userCard.quantity > 1) {
                    QuantityBadge(
                        quantity = entry.userCard.quantity,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionList(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items = entries, key = { it.userCard.id }) { entry ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onCardClick(entry.card.bobaId) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(modifier = Modifier.width(48.dp).height(67.dp)) {
                    BOBACardCell(
                        imageFile = entry.card.imageFile,
                        contentDescription = entry.card.displayName,
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        entry.card.displayName,
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        "${entry.card.cardNumber} · ${entry.card.element.lowercase().replaceFirstChar { it.uppercase() }} · ${entry.userCard.designation.shortLabel}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                entry.userCard.estimatedValue?.let {
                    Text(
                        "$${"%.2f".format(it)}",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

@Composable
private fun CollectionWall(
    entries: List<CollectionEntry>,
    onCardClick: (String) -> Unit,
) {
    // Wall view = small multiples grid w/ no padding, near-black bg —
    // the shareable layout per DECISIONS.md #036
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 90.dp),
        contentPadding = PaddingValues(2.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier
            .fillMaxSize()
            .clip(MaterialTheme.shapes.medium),
    ) {
        items(items = entries, key = { it.userCard.id }) { entry ->
            BOBACardCell(
                imageFile = entry.card.imageFile,
                contentDescription = entry.card.displayName,
                modifier = Modifier
                    .cardSharedBounds(entry.card.bobaId)
                    .clickable { onCardClick(entry.card.bobaId) },
            )
        }
    }
}

@Composable
private fun DesignationBadge(
    designation: Designation,
    modifier: Modifier = Modifier,
) {
    Surface(
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f),
        shape = MaterialTheme.shapes.small,
        modifier = modifier,
    ) {
        Text(
            text = designation.shortLabel,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

@Composable
private fun QuantityBadge(
    quantity: Int,
    modifier: Modifier = Modifier,
) {
    Surface(
        color = BobaBrand.Orange,
        shape = CircleShape,
        modifier = modifier,
    ) {
        Text(
            text = "x$quantity",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

private fun shareCollection(
    context: android.content.Context,
    designation: Designation,
    displayMode: DisplayMode,
) {
    // v1 share: text link to the public collection page (requires the
    // user to have toggled sharing ON in Profile). Full PNG export of
    // the Wall view via GraphicsLayer.toImageBitmap() is a follow-up —
    // needs FileProvider XML config + cache-cleanup policy.
    val text = "Check out my BOBA Playbook ${designation.label.lowercase()}!\n" +
               "https://bobaplaybook.com/u/your-handle"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "My BOBA ${designation.label}")
        putExtra(Intent.EXTRA_TEXT, text)
    }
    context.startActivity(Intent.createChooser(intent, "Share collection"))
}
