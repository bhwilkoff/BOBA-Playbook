package com.bobaplaybook.app.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.ui.graphics.vector.ImageVector
import com.bobaplaybook.app.R

/**
 * Five top-level tabs (ANDROID-DESIGN.md §2.1).
 *
 * Order matches iOS DESIGN.md §8 — Find / Learn / Decks / Collection /
 * Purchase. Find is first because it's the default landing tab per
 * `feedback_profile_only_on_find`.
 *
 * Material 3 Adaptive's `NavigationSuiteScaffold` reads this list and
 * adapts the chrome: `NavigationBar` on compact, `NavigationRail` on
 * medium/expanded, `PermanentNavigationDrawer` on extra-large.
 */
enum class AppDestination(
    val route: TopRoute,
    @StringRes val labelRes: Int,
    val icon: ImageVector,
) {
    FIND      (TopRoute.Find,       R.string.tab_find,       Icons.Default.Search),
    LEARN     (TopRoute.Learn,      R.string.tab_learn,      Icons.AutoMirrored.Filled.LibraryBooks),
    DECKS     (TopRoute.Decks,      R.string.tab_decks,      Icons.Default.ViewModule),
    COLLECTION(TopRoute.Collection, R.string.tab_collection, Icons.Default.Storefront),
    PURCHASE  (TopRoute.Purchase,   R.string.tab_purchase,   Icons.Default.ShoppingCart),
}
