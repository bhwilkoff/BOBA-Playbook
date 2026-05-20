@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * My Shows — streamer-only push destination from Collection overflow
 * Menu. Mirrors iOS ShowsListView.
 *
 * v1 ships the IA skeleton. Full Whatnot show management (per-show
 * wall, sub-card lists, viewer chat) is a multi-week M2-polish effort.
 * The screen exists so streamer-role users have a destination + the
 * shape of the feature is correct.
 */
@Composable
fun ShowsListScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
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
        BOBAEmptyState(
            icon = Icons.Default.LiveTv,
            headline = "My Shows — streamer tools",
            body = "Per-show card lists, walls, and viewer interactions. Requires the streamer role; full management ships in M2 polish.",
            modifier = Modifier.fillMaxSize().padding(padding),
        )
    }
}
