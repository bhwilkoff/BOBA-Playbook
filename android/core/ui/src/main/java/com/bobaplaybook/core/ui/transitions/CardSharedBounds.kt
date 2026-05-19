@file:OptIn(ExperimentalSharedTransitionApi::class)

package com.bobaplaybook.core.ui.transitions

import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed

/**
 * Apply M3 container-transform shared bounds for a card cell, reading
 * scopes from CompositionLocals so screens don't need to thread them
 * through their parameter lists.
 *
 * The grid cell (source) and the card-detail art panel (destination)
 * share the same [bobaId]-keyed bounds key. The animation framework
 * morphs the bounding box during navigation. ANDROID-DESIGN.md §6.6.2
 * + §8.6.
 *
 * No-op when not inside a [androidx.compose.animation.SharedTransitionLayout]
 * + a NavHost `composable {}` lambda — that's the medium/expanded
 * pane-switch case (ANDROID-DESIGN.md §6.6.2 compact-only rule),
 * where there's no source→destination travel to animate.
 *
 * Single canonical helper. Find / Decks pool / Collection / detail
 * ArtPanel all call this with the same `bobaId`. No drift.
 */
@Composable
fun Modifier.cardSharedBounds(bobaId: String): Modifier {
    val sts = LocalSharedTransition.current ?: return this
    val avs = LocalNavAnimatedVisibilityScope.current ?: return this
    return cardSharedBoundsImpl(bobaId, sts, avs)
}

@Composable
private fun Modifier.cardSharedBoundsImpl(
    bobaId: String,
    sts: SharedTransitionScope,
    avs: AnimatedVisibilityScope,
): Modifier = with(sts) {
    this@cardSharedBoundsImpl.sharedBounds(
        sharedContentState = rememberSharedContentState(key = "card-$bobaId"),
        animatedVisibilityScope = avs,
    )
}

/**
 * Alternative — explicit scope-passing variant for callers that have
 * the scopes in hand (e.g. inside a NavHost composable that doesn't go
 * through the CompositionLocal path).
 */
@Composable
fun Modifier.cardSharedBounds(
    bobaId: String,
    sharedTransitionScope: SharedTransitionScope?,
    animatedVisibilityScope: AnimatedVisibilityScope?,
): Modifier {
    if (sharedTransitionScope == null || animatedVisibilityScope == null) return this
    return cardSharedBoundsImpl(bobaId, sharedTransitionScope, animatedVisibilityScope)
}
