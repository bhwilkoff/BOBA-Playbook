@file:OptIn(ExperimentalMaterial3AdaptiveNavigationSuiteApi::class)

package com.bobaplaybook.app.ui

import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.ExperimentalMaterial3AdaptiveNavigationSuiteApi
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.feature.carddetail.CardDetailScreen
import com.bobaplaybook.app.feature.collection.CollectionScreen
import com.bobaplaybook.app.feature.decks.DecksScreen
import com.bobaplaybook.app.feature.find.FindScreen
import com.bobaplaybook.app.feature.learn.LearnScreen
import com.bobaplaybook.app.feature.profile.ProfileSheet
import com.bobaplaybook.app.feature.purchase.PurchaseScreen
import com.bobaplaybook.app.feature.scan.ScanScreen
import com.bobaplaybook.app.navigation.AppDestination
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Root Composable — NavigationSuiteScaffold + per-tab content.
 *
 * Each tab gets its own back stack so deep links inside Find don't
 * pollute Learn / Decks / etc. (mirrors iOS DESIGN.md "tab → list →
 * detail" depth ≤ 2 rule).
 *
 * M1 wires Find with a working back stack into [CardDetailScreen].
 * Other tabs show placeholders.
 *
 * Adaptive behavior (ANDROID-DESIGN.md §6.6):
 *  - Compact (phone portrait): NavigationBar at bottom (5 items)
 *  - Medium (tablet portrait, large phone landscape): NavigationRail on the left
 *  - Expanded (tablet landscape, Chromebook): PermanentNavigationDrawer
 *
 * `NavigationSuiteScaffold` reads the current `WindowSizeClass` and
 * adapts automatically. No manual size-class branching needed.
 */
@Composable
fun BOBAApp(authManager: AuthManager) {
    BobaTheme {
        var currentDestination by rememberSaveable {
            mutableStateOf(AppDestination.FIND)
        }
        // M1 ships per-tab "selected card" as a single nullable bobaId.
        // M2+ keeps the same lightweight model — Nav3 NavBackStack
        // adoption deferred until a real second push level lands.
        var detailBobaId by rememberSaveable { mutableStateOf<String?>(null) }
        // Cross-cutting Scan flow — modal over the current tab.
        var scanActive by rememberSaveable { mutableStateOf(false) }
        // Cross-cutting Profile sheet — Find-only entry per ANDROID-DESIGN.md §6.5
        var profileOpen by rememberSaveable { mutableStateOf(false) }

        NavigationSuiteScaffold(
            navigationSuiteItems = {
                AppDestination.entries.forEach { destination ->
                    item(
                        icon = {
                            Icon(
                                imageVector = destination.icon,
                                contentDescription = stringResource(destination.labelRes),
                            )
                        },
                        label = { Text(stringResource(destination.labelRes)) },
                        selected = destination == currentDestination,
                        onClick = {
                            currentDestination = destination
                            detailBobaId = null  // leaving a tab clears its detail
                        },
                    )
                }
            },
        ) {
            if (scanActive) {
                ScanScreen(
                    onBack = { scanActive = false },
                    onMatch = { matchedBobaId ->
                        scanActive = false
                        detailBobaId = matchedBobaId
                    },
                )
            } else if (detailBobaId != null) {
                CardDetailScreen(
                    bobaId = detailBobaId!!,
                    onBack = { detailBobaId = null },
                )
            } else {
                when (currentDestination) {
                    AppDestination.FIND -> FindScreen(
                        onCardClick = { detailBobaId = it },
                        onProfileClick = { profileOpen = true },
                        onScanClick = { scanActive = true },
                    )
                    AppDestination.LEARN      -> LearnScreen()
                    AppDestination.DECKS      -> DecksScreen(onCardClick = { detailBobaId = it })
                    AppDestination.COLLECTION -> CollectionScreen()
                    AppDestination.PURCHASE   -> PurchaseScreen()
                }
            }
        }

        if (profileOpen) {
            ProfileSheet(
                authManager = authManager,
                onDismiss = { profileOpen = false },
            )
        }
    }
}
