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
 * medium/expanded.
 */
enum class AppDestination(
    @param:StringRes val labelRes: Int,
    val icon: ImageVector,
    val startRoute: String,
) {
    FIND      (R.string.tab_find,       Icons.Default.Search,                      NavRoutes.FIND),
    LEARN     (R.string.tab_learn,      Icons.AutoMirrored.Filled.LibraryBooks,    NavRoutes.LEARN),
    DECKS     (R.string.tab_decks,      Icons.Default.ViewModule,                  NavRoutes.DECKS),
    COLLECTION(R.string.tab_collection, Icons.Default.Storefront,                  NavRoutes.COLLECTION),
    PURCHASE  (R.string.tab_purchase,   Icons.Default.ShoppingCart,                NavRoutes.PURCHASE),
}
