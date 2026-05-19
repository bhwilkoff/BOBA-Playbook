@file:OptIn(ExperimentalSharedTransitionApi::class)

package com.bobaplaybook.core.ui.transitions

import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.runtime.compositionLocalOf

/**
 * Composition-local handle to the app's single
 * [SharedTransitionScope]. The scope is provided by the
 * [androidx.compose.animation.SharedTransitionLayout] in [BOBAApp];
 * every container-transform call site reads it from here so we don't
 * have to thread it through every screen signature.
 *
 * Reading [LocalSharedTransition.current] outside a
 * `SharedTransitionLayout` returns `null` — callers must always
 * null-guard or wrap their content in a `SharedTransitionLayout` first.
 */
val LocalSharedTransition = compositionLocalOf<SharedTransitionScope?> { null }

/**
 * Composition-local for the [AnimatedVisibilityScope] of the currently-
 * composed NavHost destination. `NavHost` uses `AnimatedContent` under
 * the hood, so each `composable {}` lambda receives an
 * `AnimatedVisibilityScope` as `this` — we publish it via this local so
 * screens deep in the tree can read it without explicit parameters.
 */
val LocalNavAnimatedVisibilityScope = compositionLocalOf<AnimatedVisibilityScope?> { null }
