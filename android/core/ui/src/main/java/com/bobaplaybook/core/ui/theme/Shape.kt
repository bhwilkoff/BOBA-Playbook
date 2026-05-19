package com.bobaplaybook.core.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * M3 Expressive's 10-step corner-radius scale, narrowed to BOBA's three
 * load-bearing values (ANDROID-DESIGN.md §6.3).
 *
 *  - small   (8dp)  — chips, small buttons
 *  - medium  (12dp) — card cells (matches iOS RoundedRectangle 16pt at
 *                    the iOS image scale)
 *  - large   (16dp) — surfaces, sheets
 *
 * Sheets default to 28dp top corners; leave that alone.
 * Buttons default to fully-rounded; leave that alone.
 */
val BobaShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small      = RoundedCornerShape(8.dp),
    medium     = RoundedCornerShape(12.dp),
    large      = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(28.dp),
)
