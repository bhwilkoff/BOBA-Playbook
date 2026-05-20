@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)

package com.bobaplaybook.app.feature.purchase

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.CenterAlignedTopAppBar
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.network.WhatnotShow
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * Purchase tab — the acquirer (ANDROID-DESIGN.md §8.5).
 *
 * v1 anatomy:
 *  - TopAppBar (Purchase) with refresh action
 *  - SingleChoiceSegmentedButtonRow — Upcoming Breaks / Find a Store
 *  - Breaks: live tile list from boba-ebay-proxy/whatnot/upcoming
 *  - Stores: placeholder until Google Maps Compose + indie-store
 *    dataset Worker land in M6 polish
 */
@Composable
fun PurchaseScreen(modifier: Modifier = Modifier) {
    val viewModel: PurchaseViewModel = hiltViewModel()
    val state by viewModel.state.collectAsStateWithLifecycle()
    var section by rememberSaveable { mutableStateOf(PurchaseSection.BREAKS) }
    val context = LocalContext.current

    Scaffold(
        modifier = modifier,
        topBar = {
            CenterAlignedTopAppBar(
                title = { com.bobaplaybook.core.ui.components.BOBAWordmark() },
                actions = {
                    if (section == PurchaseSection.BREAKS) {
                        IconButton(onClick = { viewModel.refreshBreaks() }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                        }
                    }
                },
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
            SectionPicker(
                selected = section,
                onChange = { section = it },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            when (section) {
                PurchaseSection.BREAKS -> {
                    when {
                        state.isLoadingBreaks && state.upcomingBreaks.isEmpty() -> {
                            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator()
                            }
                        }
                        state.upcomingBreaks.isEmpty() -> {
                            BOBAEmptyState(
                                icon = Icons.Default.LiveTv,
                                headline = "No upcoming breaks",
                                body = state.breaksError ?: "Pull to refresh or try again later.",
                                actionLabel = "Refresh",
                                onAction = { viewModel.refreshBreaks() },
                            )
                        }
                        else -> {
                            PullToRefreshBox(
                                isRefreshing = state.isLoadingBreaks,
                                onRefresh = { viewModel.refreshBreaks() },
                                modifier = Modifier.fillMaxSize(),
                            ) {
                                LazyColumn(
                                    modifier = Modifier.fillMaxSize(),
                                    contentPadding = PaddingValues(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    items(
                                        items = state.upcomingBreaks,
                                        key = { it.id },
                                    ) { show ->
                                        WhatnotTile(
                                            show = show,
                                            onClick = {
                                                if (show.showUrl.isNotBlank()) {
                                                    context.startActivity(
                                                        Intent(Intent.ACTION_VIEW, show.showUrl.toUri()),
                                                    )
                                                }
                                            },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                PurchaseSection.STORES -> {
                    StoresList(state = state, viewModel = viewModel, context = context)
                }
            }
        }
    }
}

private enum class PurchaseSection(val label: String, val icon: ImageVector) {
    BREAKS("Upcoming Breaks", Icons.Default.LiveTv),
    STORES("Find a Store",    Icons.Default.Storefront),
}

@Composable
private fun SectionPicker(
    selected: PurchaseSection,
    onChange: (PurchaseSection) -> Unit,
    modifier: Modifier = Modifier,
) {
    val entries = remember { PurchaseSection.entries }
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        entries.forEachIndexed { index, section ->
            SegmentedButton(
                selected = section == selected,
                onClick = { onChange(section) },
                shape = SegmentedButtonDefaults.itemShape(index, entries.size),
            ) {
                Text(section.label, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun WhatnotTile(
    show: WhatnotShow,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            // Hero thumb (when present)
            show.thumbnailUrl?.let { url ->
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current).data(url).crossfade(150).build(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp)
                        .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)),
                )
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (show.hostAvatarUrl != null) {
                    AsyncImage(
                        model = ImageRequest.Builder(LocalContext.current).data(show.hostAvatarUrl).crossfade(150).build(),
                        contentDescription = show.host,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(40.dp).clip(CircleShape),
                    )
                } else {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        modifier = Modifier.size(40.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(Icons.Default.Person, contentDescription = null)
                        }
                    }
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = show.title.ifBlank { "Whatnot show" },
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 2,
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "@${show.host}",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (show.viewerCount > 0) {
                            Icon(
                                Icons.Default.Visibility,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(14.dp),
                            )
                            Text(
                                text = show.viewerCount.toString(),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                Icon(
                    Icons.AutoMirrored.Filled.OpenInNew,
                    contentDescription = "Open on Whatnot",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun StoresList(
    state: PurchaseUiState,
    viewModel: PurchaseViewModel,
    context: android.content.Context,
) {
    if (state.isLoadingStores && state.stores.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    if (state.stores.isEmpty()) {
        BOBAEmptyState(
            icon = Icons.Default.Storefront,
            headline = "No stores yet",
            body = "Couldn't fetch stores from bobaplaybook.com. Check connectivity and try again.",
            actionLabel = "Retry",
            onAction = { viewModel.refreshStores() },
        )
        return
    }
    Column(modifier = Modifier.fillMaxSize()) {
        // Query + filter row
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            androidx.compose.material3.OutlinedTextField(
                value = state.storeQuery,
                onValueChange = viewModel::setStoreQuery,
                placeholder = { Text("Filter by name, city, or state") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            androidx.compose.material3.FilterChip(
                selected = state.indieOnly,
                onClick = { viewModel.setIndieOnly(!state.indieOnly) },
                label = { Text("Indie only") },
            )
            androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
            Text(
                "${state.filteredStores.size} stores",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(items = state.filteredStores, key = { it.id }) { store ->
                StoreRow(
                    store = store,
                    onClick = {
                        // Open in maps via geo: URI — system picker handles
                        // routing (Google Maps, Waze, etc.)
                        val geoUri = "geo:0,0?q=${store.lat},${store.lng}(${android.net.Uri.encode(store.name)})"
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, android.net.Uri.parse(geoUri)),
                        )
                    },
                )
                androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

@Composable
private fun StoreRow(
    store: com.bobaplaybook.core.network.StoreLocation,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Storefront,
            contentDescription = null,
            tint = if (store.isIndie) MaterialTheme.colorScheme.primary
                   else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(store.name, style = MaterialTheme.typography.titleSmall)
            Text(store.fullAddress, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (store.isIndie) {
            androidx.compose.material3.AssistChip(
                onClick = {},
                label = { Text("Indie", style = MaterialTheme.typography.labelSmall) },
            )
        }
    }
}
