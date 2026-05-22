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
import androidx.compose.material3.ContainedLoadingIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.material.icons.filled.Language
import androidx.compose.ui.platform.LocalContext
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.network.StoreLocation
import com.bobaplaybook.core.network.WhatnotShow
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.CameraPositionState
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState

/**
 * Purchase tab — the acquirer (ANDROID-DESIGN.md §8.5).
 *
 * v1 anatomy:
 *  - TopAppBar (Purchase) with refresh action
 *  - SingleChoiceSegmentedButtonRow — Upcoming Breaks / Find a Store
 *  - Breaks: live tile list from boba-ebay-proxy/whatnot/upcoming
 *  - Stores: embedded Google Maps + indie-store dataset Worker (M6
 *    polish landed tick 209-adjacent — Maps SDK + StoresMap composable
 *    above the store list w/ 500-marker cap and auto-fit camera)
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
                                ContainedLoadingIndicator()
                            }
                        }
                        state.upcomingBreaks.isEmpty() -> {
                            BOBAEmptyState(
                                icon = Icons.Default.LiveTv,
                                headline = "No upcoming breaks",
                                body = state.breaksError ?: "Pull to refresh or try again later.",
                                actionLabel = "Refresh",
                                onAction = { viewModel.refreshBreaks() },
                                // Tick 214 — alt path when the Worker is offline or
                                // genuinely no breaks scheduled. Sends the user to
                                // Whatnot's BoBA-tagged category page in a Custom Tab.
                                secondaryActionLabel = "Browse Whatnot",
                                onSecondaryAction = {
                                    androidx.browser.customtabs.CustomTabsIntent.Builder()
                                        .build()
                                        .launchUrl(
                                            context,
                                            android.net.Uri.parse("https://www.whatnot.com/category/trading-cards-and-collectibles?search=Bo+Jackson+Battle+Arena"),
                                        )
                                },
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
                                        count = state.upcomingBreaks.size,
                                        // Index-suffix guarantees uniqueness even when
                                        // the upstream Worker returns shows w/ duplicate
                                        // or empty IDs (which crashed v1).
                                        key = { i -> "${state.upcomingBreaks[i].id}#$i" },
                                    ) { idx ->
                                        val show = state.upcomingBreaks[idx]
                                        WhatnotTile(
                                            show = show,
                                            onClick = {
                                                if (show.showUrl.isNotBlank()) {
                                                    // Custom Tab so back returns to BOBA Purchase
                                                    // tab instead of leaving the app. Whatnot's
                                                    // app deep-link handler still intercepts when
                                                    // the Whatnot app is installed.
                                                    runCatching {
                                                        CustomTabsIntent.Builder().build()
                                                            .launchUrl(context, show.showUrl.toUri())
                                                    }.onFailure {
                                                        runCatching {
                                                            context.startActivity(
                                                                Intent(Intent.ACTION_VIEW, show.showUrl.toUri()),
                                                            )
                                                        }
                                                    }
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
            // Hero thumb (when present) — LIVE pill overlays the top-left
            // corner when the show is currently broadcasting. Mirrors
            // the YouTube Watch tab live treatment.
            show.thumbnailUrl?.let { url ->
                Box {
                    AsyncImage(
                        model = ImageRequest.Builder(LocalContext.current).data(url).crossfade(150).build(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(160.dp)
                            .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)),
                    )
                    if (show.isLive) {
                        Surface(
                            color = androidx.compose.ui.graphics.Color(0xFFFF4D00),
                            shape = RoundedCornerShape(4.dp),
                            modifier = Modifier
                                .align(Alignment.TopStart)
                                .padding(8.dp),
                        ) {
                            Text(
                                "LIVE",
                                style = MaterialTheme.typography.labelSmall,
                                color = androidx.compose.ui.graphics.Color.White,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                            )
                        }
                    }
                }
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
                        if (show.host.isNotBlank()) {
                            Text(
                                text = "@${show.host}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (show.viewerCount > 0) {
                            Icon(
                                Icons.Default.Visibility,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(14.dp),
                            )
                            Text(
                                // Tick 406 — locale-format the viewer count
                                // so 1,234 doesn't render as "1234". Same
                                // NumberFormat / Locale.US pattern Find uses
                                // (tick 359). Streams routinely run into 4-digit
                                // viewer counts so the thousands separator helps.
                                text = java.text.NumberFormat.getInstance(java.util.Locale.US)
                                    .format(show.viewerCount),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    // Stream-time label — iOS UpcomingBreaksList.localTimeText
                    // parity. "Live now" / "Today 7:00 PM" / "Tomorrow 7:00 PM" /
                    // "Fri 7:00 PM". Renders in the user's local timezone so
                    // coaches outside PT see the right clock time.
                    val scheduledAtMs = show.scheduledAt
                    val timeLabel = when {
                        show.isLive -> "Live now"
                        scheduledAtMs != null -> formatStreamTime(scheduledAtMs)
                        else -> null
                    }
                    if (timeLabel != null) {
                        Text(
                            text = timeLabel,
                            style = MaterialTheme.typography.labelMedium,
                            color = if (show.isLive) androidx.compose.ui.graphics.Color(0xFFFF4D00)
                                    else MaterialTheme.colorScheme.primary,
                        )
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
            ContainedLoadingIndicator()
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
    // Open the system "view this place" picker for a store. Same shape
    // as iOS — tapping a row OR a marker hands off to Google Maps /
    // Waze. Pulled out so both call sites share it.
    val openInMaps: (StoreLocation) -> Unit = remember(context) {
        { store ->
            val geoUri = "geo:0,0?q=${store.lat},${store.lng}" +
                "(${android.net.Uri.encode(store.name)})"
            context.startActivity(
                Intent(Intent.ACTION_VIEW, android.net.Uri.parse(geoUri))
            )
        }
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
        // ───── Embedded map ─────
        // Parity with iOS MapKit (StoreLocatorView::mapSection): fixed
        // 240dp band above the list, markers per visible store, camera
        // auto-fits to the filtered set. Limited to 500 markers so
        // big-box +1,800 doesn't pile up onto the GPU.
        StoresMap(
            stores = state.filteredStores,
            onStoreSelected = openInMaps,
            modifier = Modifier
                .fillMaxWidth()
                .height(240.dp),
        )
        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = state.isLoadingStores,
            onRefresh = { viewModel.refreshStores() },
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(items = state.filteredStores, key = { it.id }) { store ->
                    StoreRow(
                        store = store,
                        onClick = { openInMaps(store) },
                    )
                    androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
        }
    }
}

@Composable
private fun StoresMap(
    stores: List<StoreLocation>,
    onStoreSelected: (StoreLocation) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Cap markers at 500 — same ceiling iOS uses. The big-box dataset
    // pushes ~1,800 + the indie ~330; throwing the whole set onto the
    // map melts the GPU and confuses the marker-cluster pass.
    val visible = remember(stores) { stores.take(500) }
    val cameraPositionState: CameraPositionState = rememberCameraPositionState()

    // Recenter / re-fit when the visible set changes.
    androidx.compose.runtime.LaunchedEffect(visible) {
        if (visible.isEmpty()) return@LaunchedEffect
        if (visible.size == 1) {
            val s = visible.first()
            cameraPositionState.position =
                CameraPosition.fromLatLngZoom(LatLng(s.lat, s.lng), 11f)
            return@LaunchedEffect
        }
        val bounds = LatLngBounds.builder().apply {
            visible.forEach { include(LatLng(it.lat, it.lng)) }
        }.build()
        runCatching {
            cameraPositionState.move(
                com.google.android.gms.maps.CameraUpdateFactory
                    .newLatLngBounds(bounds, 80)
            )
        }
    }

    GoogleMap(
        modifier = modifier,
        cameraPositionState = cameraPositionState,
        uiSettings = MapUiSettings(
            zoomControlsEnabled = false,
            compassEnabled = true,
            myLocationButtonEnabled = false,
        ),
        properties = MapProperties(isMyLocationEnabled = false),
    ) {
        visible.forEach { store ->
            Marker(
                state = MarkerState(position = LatLng(store.lat, store.lng)),
                title = store.name,
                snippet = listOfNotNull(store.city, store.state)
                    .joinToString(", ")
                    .takeIf { it.isNotBlank() },
                onClick = {
                    onStoreSelected(store)
                    true  // we handled it; suppress the default info window
                },
            )
        }
    }
}

@Composable
private fun StoreRow(
    store: com.bobaplaybook.core.network.StoreLocation,
    onClick: () -> Unit,
) {
    val context = LocalContext.current
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
            androidx.compose.material3.Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Text(
                    "Indie",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }
        // Open website in Custom Tab if the store has one. iOS shows
        // this as a chevron / detail-disclosure on the row; Android
        // uses an explicit Language icon since the whole row already
        // opens Maps via geo: URI on tap. Both affordances coexist.
        val webUrl = store.website ?: store.officialUrl
        if (!webUrl.isNullOrBlank()) {
            androidx.compose.material3.IconButton(
                onClick = {
                    val normalized = if (webUrl.startsWith("http")) webUrl else "https://$webUrl"
                    runCatching {
                        androidx.browser.customtabs.CustomTabsIntent.Builder().build()
                            .launchUrl(context, android.net.Uri.parse(normalized))
                    }
                },
            ) {
                Icon(
                    imageVector = Icons.Default.Language,
                    contentDescription = "Open store website",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Format a Whatnot show's epoch-ms scheduledAt as a human-readable
 * local-time label. iOS UpcomingBreaksList.localTimeText parity:
 *   - Today      → "Today 7:00 PM"
 *   - Tomorrow   → "Tomorrow 7:00 PM"
 *   - Other day  → "Fri 7:00 PM"
 * Returns null when the timestamp is in the past (no upcoming label
 * useful for a finished show — the worker should have filtered it,
 * but we double-check).
 */
private fun formatStreamTime(epochMs: Long): String? {
    val now = java.time.ZonedDateTime.now(java.time.ZoneId.systemDefault())
    val when_ = java.time.Instant.ofEpochMilli(epochMs)
        .atZone(java.time.ZoneId.systemDefault())
    if (when_.isBefore(now.minusHours(1))) return null  // past show
    val timeFmt = java.time.format.DateTimeFormatter.ofPattern("h:mm a")
    val timeStr = when_.format(timeFmt)
    val today = now.toLocalDate()
    val tomorrow = today.plusDays(1)
    return when (when_.toLocalDate()) {
        today    -> "Today $timeStr"
        tomorrow -> "Tomorrow $timeStr"
        else     -> {
            val dayFmt = java.time.format.DateTimeFormatter.ofPattern("EEE h:mm a")
            when_.format(dayFmt)
        }
    }
}
