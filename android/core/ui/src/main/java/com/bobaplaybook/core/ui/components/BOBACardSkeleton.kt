package com.bobaplaybook.core.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Card-shaped loading skeleton (ANDROID-DESIGN.md §6.7).
 *
 * Shimmer-animated placeholder that matches BOBACardCell shape: 5:7
 * aspect, 12dp rounded corners. Use in grids during initial catalog
 * load instead of a full-screen `CircularProgressIndicator` (which is
 * §6.7 anti-pattern).
 */
@Composable
fun BOBACardSkeleton(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "card-skeleton")
    val translateX by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1000f,
        animationSpec = infiniteRepeatable(
            animation = tween(1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmer",
    )

    val base = MaterialTheme.colorScheme.surfaceContainer
    val highlight = MaterialTheme.colorScheme.surfaceContainerHigh

    Box(
        modifier = modifier
            .aspectRatio(5f / 7f)
            .clip(MaterialTheme.shapes.medium)
            .background(
                Brush.linearGradient(
                    colors = listOf(base, highlight, base),
                    start = androidx.compose.ui.geometry.Offset(translateX - 200f, 0f),
                    end   = androidx.compose.ui.geometry.Offset(translateX, 200f),
                ),
            ),
    )
}
