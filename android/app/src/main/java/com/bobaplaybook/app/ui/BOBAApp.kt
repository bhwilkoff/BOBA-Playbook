@file:OptIn(
    ExperimentalMaterial3AdaptiveNavigationSuiteApi::class,
    ExperimentalSharedTransitionApi::class,
)

package com.bobaplaybook.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.ExperimentalMaterial3AdaptiveNavigationSuiteApi
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.connectivity.ConnectivityState
import com.bobaplaybook.app.feature.carddetail.CardDetailScreen
import com.bobaplaybook.app.feature.collection.CollectionScreen
import com.bobaplaybook.app.feature.decks.DecksScreen
import com.bobaplaybook.app.feature.find.FindScreen
import com.bobaplaybook.app.feature.learn.LearnScreen
import com.bobaplaybook.app.feature.profile.ProfileSheet
import com.bobaplaybook.app.feature.decks.DeckStore
import com.bobaplaybook.app.feature.purchase.PurchaseScreen
import com.bobaplaybook.app.feature.scan.ScanDestination
import com.bobaplaybook.app.feature.scan.ScanScreen
import com.bobaplaybook.app.feature.scan.rememberScanCoordinator
import com.bobaplaybook.app.navigation.AppDestination
import com.bobaplaybook.app.navigation.NavRoutes
import com.bobaplaybook.core.ui.components.BOBAOfflinePill
import com.bobaplaybook.core.ui.theme.BobaTheme
import com.bobaplaybook.core.ui.transitions.LocalNavAnimatedVisibilityScope
import com.bobaplaybook.core.ui.transitions.LocalSharedTransition

/**
 * Root Composable — `BobaTheme` → `SharedTransitionLayout` →
 * `NavigationSuiteScaffold` → per-tab `NavHost`.
 *
 * Container transforms work across tabs because everything sits inside
 * one [SharedTransitionLayout]. Per-tab back stacks are isolated.
 *
 * **Adaptive behavior** (ANDROID-DESIGN.md §6.6): NavigationSuiteScaffold
 * morphs the tab chrome to NavigationBar (compact) / NavigationRail
 * (medium/expanded). Pickers, sheets, and grids inside each screen
 * adapt via `currentWindowAdaptiveInfo()`.
 */
@Composable
fun BOBAApp(
    authManager: AuthManager,
    connectivityState: ConnectivityState,
) {
    BobaTheme {
        // One NavController per tab so back stacks don't cross-pollute.
        val tabControllers = remember {
            mutableMapOf<AppDestination, NavHostController>()
        }
        var currentDestination by rememberSaveable {
            mutableStateOf(AppDestination.FIND)
        }
        var scanActive by rememberSaveable { mutableStateOf(false) }
        var profileOpen by rememberSaveable { mutableStateOf(false) }
        val isOnline by connectivityState.isOnline.collectAsStateWithLifecycle(initialValue = true)

        SharedTransitionLayout(modifier = Modifier.fillMaxSize()) {
            CompositionLocalProvider(LocalSharedTransition provides this@SharedTransitionLayout) {
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
                                    if (destination == currentDestination) {
                                        // Tap same tab pops to its root
                                        tabControllers[destination]?.popBackStack(
                                            destination.startRoute,
                                            inclusive = false,
                                        )
                                    } else {
                                        currentDestination = destination
                                    }
                                },
                            )
                        }
                    },
                ) {
                    if (scanActive) {
                        // Scan coordinator routes the match by current tab
                        // context — Find/Collection → card detail push;
                        // Decks → DeckStore.add, no nav. Single scan UI.
                        val scanCoordinator = rememberScanCoordinator()
                        val cardRepository = androidx.hilt.navigation.compose.hiltViewModel<com.bobaplaybook.app.feature.scan.ScanCoordinatorViewModel>()
                            .cardRepository
                        ScanScreen(
                            onBack = { scanActive = false },
                            onMatch = { matchedBobaId ->
                                scanActive = false
                                val destination = when (currentDestination) {
                                    AppDestination.DECKS      -> ScanDestination.CURRENT_DECK
                                    AppDestination.COLLECTION -> ScanDestination.COLLECTION
                                    else                       -> ScanDestination.CARD_DETAIL
                                }
                                val navTarget = scanCoordinator.onMatch(
                                    bobaId = matchedBobaId,
                                    destination = destination,
                                    cardRepository = cardRepository,
                                )
                                if (navTarget != null) {
                                    val ctrl = tabControllers[currentDestination]
                                    ctrl?.navigate(NavRoutes.cardDetail(navTarget))
                                }
                            },
                        )
                    } else {
                        // Only the current tab is composed — keeps memory
                        // down. Each tab's nav controller persists across
                        // switches via the remember-saveable map.
                        val navController = tabControllers.getOrPut(currentDestination) {
                            rememberNavController()
                        }
                        TabNavHost(
                            destination = currentDestination,
                            navController = navController,
                            onProfileClick = { profileOpen = true },
                            onScanClick = { scanActive = true },
                        )
                    }
                }
            }
        }

        if (profileOpen) {
            ProfileSheet(
                authManager = authManager,
                onDismiss = { profileOpen = false },
            )
        }

        // Global offline pill — top-trailing overlay, fades in when
        // network is lost (ANDROID-DESIGN.md §6.7). Above the
        // NavigationSuiteScaffold so it overlays whatever tab is active.
        AnimatedVisibility(
            visible = !isOnline,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.TopEnd,
            ) {
                Box(modifier = Modifier.padding(top = 56.dp, end = 16.dp)) {
                    BOBAOfflinePill()
                }
            }
        }
    }
}

/**
 * Per-tab NavHost. Each tab starts at its tab root; pushes add
 * CardDetail / etc. on top.
 *
 * Each `composable {}` lambda publishes its
 * [androidx.compose.animation.AnimatedVisibilityScope] via the
 * [LocalNavAnimatedVisibilityScope] composition local so screens
 * deep in the tree can wire `Modifier.cardSharedBounds(bobaId)`
 * without explicit parameters.
 */
@Composable
private fun TabNavHost(
    destination: AppDestination,
    navController: NavHostController,
    onProfileClick: () -> Unit,
    onScanClick: () -> Unit,
) {
    NavHost(
        navController = navController,
        startDestination = destination.startRoute,
        modifier = Modifier.fillMaxSize(),
    ) {
        when (destination) {
            AppDestination.FIND -> {
                composable(NavRoutes.FIND) {
                    CompositionLocalProvider(LocalNavAnimatedVisibilityScope provides this) {
                        FindScreen(
                            onCardClick = { bobaId -> navController.navigate(NavRoutes.cardDetail(bobaId)) },
                            onProfileClick = onProfileClick,
                            onScanClick = onScanClick,
                        )
                    }
                }
                cardDetailComposable(navController)
            }
            AppDestination.LEARN -> {
                composable(NavRoutes.LEARN) {
                    LearnScreen(
                        onCategoryClick = { categoryId -> navController.navigate(NavRoutes.learnCategory(categoryId)) },
                    )
                }
                composable(
                    NavRoutes.LEARN_CATEGORY_PATTERN,
                    arguments = listOf(navArgument(NavRoutes.ARG_CATEGORY) { type = NavType.StringType }),
                ) { backStackEntry ->
                    val categoryId = backStackEntry.arguments?.getString(NavRoutes.ARG_CATEGORY).orEmpty()
                    com.bobaplaybook.app.feature.learn.LearnCategoryScreen(
                        categoryId = categoryId,
                        onArticleClick = { articleId -> navController.navigate(NavRoutes.learnArticle(articleId)) },
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(
                    NavRoutes.LEARN_ARTICLE_PATTERN,
                    arguments = listOf(navArgument(NavRoutes.ARG_ARTICLE) { type = NavType.StringType }),
                ) { backStackEntry ->
                    val articleId = backStackEntry.arguments?.getString(NavRoutes.ARG_ARTICLE).orEmpty()
                    com.bobaplaybook.app.feature.learn.LearnArticleScreen(
                        articleId = articleId,
                        onBack = { navController.popBackStack() },
                    )
                }
            }
            AppDestination.DECKS -> {
                composable(NavRoutes.DECKS) {
                    CompositionLocalProvider(LocalNavAnimatedVisibilityScope provides this) {
                        DecksScreen(
                            onCardClick = { bobaId -> navController.navigate(NavRoutes.cardDetail(bobaId)) },
                            onOpenManage = { navController.navigate(NavRoutes.DECK_MANAGE) },
                            onOpenRules = { navController.navigate(NavRoutes.DECK_RULES) },
                            onOpenLegality = { navController.navigate(NavRoutes.DECK_LEGALITY) },
                        )
                    }
                }
                composable(NavRoutes.DECK_MANAGE) {
                    com.bobaplaybook.app.feature.decks.DeckManageScreen(onBack = { navController.popBackStack() })
                }
                composable(NavRoutes.DECK_RULES) {
                    com.bobaplaybook.app.feature.decks.DeckRulesScreen(onBack = { navController.popBackStack() })
                }
                composable(NavRoutes.DECK_LEGALITY) {
                    com.bobaplaybook.app.feature.decks.DeckLegalityScreen(onBack = { navController.popBackStack() })
                }
                cardDetailComposable(navController)
            }
            AppDestination.COLLECTION -> {
                composable(NavRoutes.COLLECTION) {
                    CompositionLocalProvider(LocalNavAnimatedVisibilityScope provides this) {
                        CollectionScreen(
                            onCardClick = { bobaId -> navController.navigate(NavRoutes.cardDetail(bobaId)) },
                            onProfileClick = onProfileClick,  // Collection has no Profile entry per feedback_profile_only_on_find; kept for parity but unused
                        )
                    }
                }
                cardDetailComposable(navController)
            }
            AppDestination.PURCHASE -> {
                composable(NavRoutes.PURCHASE) {
                    PurchaseScreen()
                }
            }
        }
    }
}

private fun androidx.navigation.NavGraphBuilder.cardDetailComposable(navController: NavHostController) {
    composable(
        route = NavRoutes.CARD_DETAIL_PATTERN,
        arguments = listOf(navArgument(NavRoutes.ARG_BOBA_ID) { type = NavType.StringType }),
    ) { backStackEntry ->
        val bobaId = backStackEntry.arguments?.getString(NavRoutes.ARG_BOBA_ID).orEmpty()
        CompositionLocalProvider(LocalNavAnimatedVisibilityScope provides this) {
            CardDetailScreen(
                bobaId = bobaId,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
