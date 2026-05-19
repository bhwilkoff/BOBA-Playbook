@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * M1 ships placeholder screens for Learn / Decks / Collection /
 * Purchase. Each renders the canonical [BOBAEmptyState] so the
 * NavigationSuiteScaffold has something to host. Full screens land
 * in M2-M6.
 */

@Composable
fun LearnPlaceholder(modifier: Modifier = Modifier) =
    PlaceholderScreen(
        title = "Learn",
        icon = Icons.AutoMirrored.Filled.LibraryBooks,
        headline = "Learning content lands in M5",
        body = "Rules, Strategy, Collecting Guide, Glossary, Tournament reference.",
        modifier = modifier,
    )

@Composable
fun DecksPlaceholder(modifier: Modifier = Modifier) =
    PlaceholderScreen(
        title = "Decks",
        icon = Icons.Default.ViewModule,
        headline = "Deck builder lands in M4",
        body = "Card pool, draft summary, 3-pane editor on tablet/Chromebook.",
        modifier = modifier,
    )

@Composable
fun CollectionPlaceholder(modifier: Modifier = Modifier) =
    PlaceholderScreen(
        title = "Collection",
        icon = Icons.Default.Storefront,
        headline = "Collection lands in M2",
        body = "Designations · Custom Rainbows · Display modes · Shows.",
        modifier = modifier,
    )

@Composable
fun PurchasePlaceholder(modifier: Modifier = Modifier) =
    PlaceholderScreen(
        title = "Purchase",
        icon = Icons.Default.ShoppingCart,
        headline = "Purchase lands in M6",
        body = "Upcoming Whatnot breaks + Find a Store.",
        modifier = modifier,
    )

@Composable
private fun PlaceholderScreen(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    headline: String,
    body: String,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(title = { Text(title) })
        },
    ) { padding ->
        BOBAEmptyState(
            icon = icon,
            headline = headline,
            body = body,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        )
    }
}
