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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
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
import com.bobaplaybook.app.feature.profile.ProfileScreen
import com.bobaplaybook.app.feature.decks.DeckStore
import com.bobaplaybook.app.feature.purchase.PurchaseScreen
import com.bobaplaybook.app.feature.scan.ScanDestination
import com.bobaplaybook.app.feature.scan.ScanScreen
import com.bobaplaybook.app.feature.scan.rememberScanCoordinator
import com.bobaplaybook.app.navigation.AppDestination
import com.bobaplaybook.app.navigation.DeepLinkRoute
import com.bobaplaybook.app.navigation.NavRoutes
import com.bobaplaybook.app.navigation.PendingDeepLink
import com.bobaplaybook.core.ui.components.BOBAOfflinePill
import com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar
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
    pendingDeepLink: PendingDeepLink,
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
        val isOnline by connectivityState.isOnline.collectAsStateWithLifecycle(initialValue = true)
        val appSnackbar = remember { androidx.compose.material3.SnackbarHostState() }

        // Drain pending deep links — dispatch to the right NavController
        // and consume so we don't repeatedly handle the same intent.
        val pendingRoute by pendingDeepLink.route.collectAsStateWithLifecycle(initialValue = null)
        androidx.compose.runtime.LaunchedEffect(pendingRoute) {
            val route = pendingRoute ?: return@LaunchedEffect
            when (route) {
                is DeepLinkRoute.CardDetail -> {
                    val ctrl = tabControllers.getOrPut(AppDestination.FIND) {
                        @Suppress("UNUSED_EXPRESSION") Unit
                        // The NavController is created lazily by the
                        // composable below; if we land here before
                        // composition, defer. Re-collection picks up.
                        return@LaunchedEffect
                    }
                    currentDestination = AppDestination.FIND
                    ctrl.navigate(NavRoutes.cardDetail(route.bobaId))
                }
                is DeepLinkRoute.Scan -> { scanActive = true }
                is DeepLinkRoute.SearchQuery -> { currentDestination = AppDestination.FIND }
                is DeepLinkRoute.LearnArticle -> {
                    currentDestination = AppDestination.LEARN
                    tabControllers[AppDestination.LEARN]?.navigate(NavRoutes.learnArticle(route.articleId))
                }
                is DeepLinkRoute.PublicCollection -> { /* M7 polish — open web URL or in-app viewer */ }
            }
            pendingDeepLink.consume()
        }

        SharedTransitionLayout(modifier = Modifier.fillMaxSize()) {
            CompositionLocalProvider(
                LocalSharedTransition provides this@SharedTransitionLayout,
                LocalAppSnackbar provides appSnackbar,
            ) {
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
                            onProfileClick = { navController.navigate(NavRoutes.PROFILE) },
                            onScanClick = { scanActive = true },
                            authManager = authManager,
                        )
                    }
                }
            }
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

        // App-scoped Snackbar host — bottom-anchored, reachable from
        // any screen via LocalAppSnackbar.current.showSnackbar(...).
        //
        // Wrapping the NavigationSuiteScaffold area in another Scaffold
        // gives us proper IME + navigation-bar inset math for free —
        // M3 places the snackbar above the bottom bar with the standard
        // 8dp margin. Avoids the hardcoded 96dp magic-number padding
        // that broke on devices with non-standard nav-bar heights.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Bottom)),
            contentAlignment = Alignment.BottomCenter,
        ) {
            androidx.compose.material3.SnackbarHost(
                hostState = appSnackbar,
                modifier = Modifier.padding(bottom = 88.dp),  // ≈ NavigationBar (80dp) + 8dp gap
            )
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
    authManager: AuthManager,
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
                composable(NavRoutes.PROFILE) {
                    com.bobaplaybook.app.feature.profile.ProfileScreen(
                        authManager = authManager,
                        onBack = { navController.popBackStack() },
                    )
                }
                cardDetailComposable(navController)
            }
            AppDestination.LEARN -> {
                composable(NavRoutes.LEARN) {
                    LearnScreen(
                        onArticleClick = { articleId -> navController.navigate(NavRoutes.learnArticle(articleId)) },
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
                            onCardClick = { bobaId -> navController.navigate(NavRoutes.collectionCardDetail(bobaId)) },
                            onProfileClick = onProfileClick,
                            onRainbowsClick = { navController.navigate(NavRoutes.COLLECTION_RAINBOWS) },
                            onShowsClick = { navController.navigate(NavRoutes.COLLECTION_SHOWS) },
                        )
                    }
                }
                composable(
                    NavRoutes.COLLECTION_CARD_DETAIL_PATTERN,
                    arguments = listOf(navArgument(NavRoutes.ARG_BOBA_ID) { type = NavType.StringType }),
                ) { backStackEntry ->
                    val bobaId = backStackEntry.arguments?.getString(NavRoutes.ARG_BOBA_ID).orEmpty()
                    com.bobaplaybook.app.feature.collection.CollectionCardDetailScreen(
                        bobaId = bobaId,
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(NavRoutes.COLLECTION_RAINBOWS) {
                    com.bobaplaybook.app.feature.collection.RainbowsScreen(
                        onRainbowClick = { _, _ -> /* M7 polish — push to RainbowDetail */ },
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(NavRoutes.COLLECTION_SHOWS) {
                    com.bobaplaybook.app.feature.collection.ShowsListScreen(
                        onBack = { navController.popBackStack() },
                    )
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
