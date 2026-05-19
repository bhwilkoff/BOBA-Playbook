package com.bobaplaybook.core.ui.adaptive

import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.window.core.layout.WindowSizeClass

/**
 * Window-width shortcuts for adaptive code branches (ANDROID-DESIGN.md
 * §6.6).
 *
 * Uses the modern `isWidthAtLeastBreakpoint` API (replaces the
 * deprecated `WindowWidthSizeClass` constants).
 *
 *  - COMPACT  is `< 600dp`
 *  - MEDIUM   is `>= 600dp` and `< 840dp`
 *  - EXPANDED is `>= 840dp`
 */

@Composable
fun isCompactWidth(): Boolean = !currentWindowAdaptiveInfo()
    .windowSizeClass
    .isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)

@Composable
fun isMediumOrExpandedWidth(): Boolean = !isCompactWidth()

@Composable
fun isExpandedWidth(): Boolean = currentWindowAdaptiveInfo()
    .windowSizeClass
    .isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND)
