package com.bobaplaybook.core.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * BOBA typography (ANDROID-DESIGN.md §5).
 *
 * Three weights × two sizes = six levels. Refuse a seventh.
 *
 * M0 ships with `FontFamily.Default` (the system Roboto/Roboto Flex)
 * because Bebas Neue / Russo One / Chakra Petch bundling lands in M0
 * Phase 2 (Gradle copy task pulls TTFs from /BOBAPlaybook/Resources/Fonts).
 * Until then, the brand wordmark uses system fonts — visually wrong but
 * functional. M0 build verification doesn't depend on having the fonts.
 *
 * When the TTFs land in /android/app/src/main/res/font/, swap
 * `DisplayFontFamily` and `BodyFontFamily` accordingly.
 */
internal val DisplayFontFamily = FontFamily.Default
internal val BodyFontFamily    = FontFamily.Default
internal val MonoFontFamily    = FontFamily.Monospace

val BobaTypography = Typography(
    // L1 — Page title (root)
    displayMedium = TextStyle(
        fontFamily = DisplayFontFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 36.sp,
        lineHeight = 44.sp,
        letterSpacing = 0.sp,
    ),
    // L2 — Section header
    headlineSmall = TextStyle(
        fontFamily = DisplayFontFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
        letterSpacing = 0.sp,
    ),
    // L3 — Card title / row primary
    titleMedium = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.15.sp,
    ),
    // L4 — Body
    bodyMedium = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.25.sp,
    ),
    // L5 — Caption
    labelMedium = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
    ),
    // L6 — Tabular numerics (card #, power, DBS, cost)
    bodySmall = TextStyle(
        fontFamily = MonoFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.4.sp,
    ),
)
