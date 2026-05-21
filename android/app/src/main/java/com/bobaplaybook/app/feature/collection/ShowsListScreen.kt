@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.data.shows.Show
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * My Shows — streamer-only push destination from Collection overflow
 * Menu. Mirrors iOS ShowsListView.
 *
 * Tick 201 — wires the real `ShowRepository` so streamer-role users
 * see their actual `shows` rows. Per-show CRUD (create / add cards /
 * generate wall) + the ShowDetailView equivalent are M2 polish,
 * deferred.
 */
@Composable
fun ShowsListScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm: ShowsViewModel = hiltViewModel()
    val shows by vm.shows.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("My Shows") },
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
        if (shows.isEmpty()) {
            BOBAEmptyState(
                icon = Icons.Default.LiveTv,
                headline = "No shows yet",
                body = "Streamers track per-show card lists, walls, and viewer interactions here. Use the iOS app or web to create a show; Android creation lands in M2 polish.",
                modifier = Modifier.fillMaxSize().padding(padding),
            )
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            items(shows, key = { it.id }) { show ->
                ShowRow(show)
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun ShowRow(show: Show) {
    ListItem(
        headlineContent = { Text(show.name) },
        supportingContent = {
            // updated_at can be ISO-8601; for v1 we just surface the
            // date-prefix (10 chars) so the row stays scannable.
            val timestamp = show.updatedAt?.take(10) ?: show.createdAt?.take(10)
            if (!timestamp.isNullOrBlank()) {
                Text("Updated $timestamp", style = MaterialTheme.typography.labelMedium)
            }
        },
        leadingContent = {
            Icon(Icons.Default.LiveTv, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

