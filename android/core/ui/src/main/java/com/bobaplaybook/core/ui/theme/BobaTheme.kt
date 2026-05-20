package com.bobaplaybook.core.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/**
 * Brand color schemes — DEFAULT.
 *
 * Per DECISIONS.md #042: BOBA ships with a fixed brand theme by default.
 * The card-art palette is the focal point, and a user's wallpaper-derived
 * primary fighting `#FF4D00` reads muddy.
 *
 * Surface tokens use 5 distinct tonal stops so M3 tonal elevation
 * actually reads — different chrome layers (TopAppBar / NavigationBar /
 * ModalBottomSheet / FAB / DropdownMenu) stack with visible hierarchy.
 *
 * Container colors are SOLID (not alpha-on-transparent) so selection
 * states (FilterChip selected, Badge, BadgedBox) paint consistently
 * over any underlying surface.
 *
 * Dynamic color (Material You) is opt-in via [useDynamicColor].
 */
private val BobaDarkColorScheme = darkColorScheme(
    // Primary (orange / FIRE — brand anchor weapon)
    primary               = BobaBrand.Orange,
    onPrimary             = BobaBrand.White,
    primaryContainer      = BobaBrand.OrangeContainer,
    onPrimaryContainer    = BobaBrand.OnOrangeContainer,

    // Secondary (cyan — links / active states)
    secondary             = BobaBrand.Cyan,
    onSecondary           = BobaBrand.NearBlack,
    secondaryContainer    = BobaBrand.CyanContainer,
    onSecondaryContainer  = BobaBrand.OnCyanContainer,

    // Tertiary (violet — HEX accent)
    tertiary              = BobaBrand.Violet,
    onTertiary            = BobaBrand.White,
    tertiaryContainer     = BobaBrand.VioletContainer,
    onTertiaryContainer   = BobaBrand.OnVioletContainer,

    // Background — same as NearBlack so card art has no chrome to compete with
    background            = BobaBrand.NearBlack,
    onBackground          = BobaBrand.OnSurface,

    // Surface family — 5 distinct tonal stops (the load-bearing change)
    surface                 = BobaBrand.NearBlack,
    onSurface               = BobaBrand.OnSurface,
    surfaceVariant          = BobaBrand.SurfaceContainer,
    onSurfaceVariant        = BobaBrand.OnSurfaceVariant,
    surfaceContainerLowest  = BobaBrand.SurfaceLowest,
    surfaceContainerLow     = BobaBrand.SurfaceLow,
    surfaceContainer        = BobaBrand.SurfaceContainer,
    surfaceContainerHigh    = BobaBrand.SurfaceContainerHigh,
    surfaceContainerHighest = BobaBrand.SurfaceContainerMax,

    // Outlines
    outline                 = BobaBrand.Outline,
    outlineVariant          = BobaBrand.OutlineVariant,

    // Errors
    error                   = BobaBrand.Error,
    onError                 = BobaBrand.OnError,
    errorContainer          = BobaBrand.ErrorContainer,
    onErrorContainer        = BobaBrand.OnErrorContainer,
)

/**
 * Light scheme — full M3 token set so users on system-light mode get
 * a coherent surface family. Brand seeds (orange/cyan/violet) stay
 * recognizable on a near-white background.
 */
private val BobaLightColorScheme = lightColorScheme(
    primary               = BobaBrand.Orange,
    onPrimary             = Color.White,
    primaryContainer      = Color(0xFFFFDBCB),
    onPrimaryContainer    = Color(0xFF361100),

    secondary             = Color(0xFF006875),         // darker cyan readable on white
    onSecondary           = Color.White,
    secondaryContainer    = Color(0xFFA1EFFD),
    onSecondaryContainer  = Color(0xFF001F25),

    tertiary              = Color(0xFF7028D5),         // darker violet
    onTertiary            = Color.White,
    tertiaryContainer     = Color(0xFFEDDBFF),
    onTertiaryContainer   = Color(0xFF270060),

    background            = Color(0xFFFFFBFF),
    onBackground          = Color(0xFF201A18),

    surface                 = Color(0xFFFFFBFF),
    onSurface               = Color(0xFF201A18),
    surfaceVariant          = Color(0xFFF4DED5),
    onSurfaceVariant        = Color(0xFF52443D),
    surfaceContainerLowest  = Color(0xFFFFFFFF),
    surfaceContainerLow     = Color(0xFFFFF1EB),
    surfaceContainer        = Color(0xFFFCEAE2),
    surfaceContainerHigh    = Color(0xFFF7E4DC),
    surfaceContainerHighest = Color(0xFFF1DED6),

    outline                 = Color(0xFF85746C),
    outlineVariant          = Color(0xFFD7C2B9),

    error                   = Color(0xFFBA1A1A),
    onError                 = Color.White,
    errorContainer          = Color(0xFFFFDAD6),
    onErrorContainer        = Color(0xFF410002),
)

/**
 * Single source of theming for every Composable in the app.
 *
 * @param useDarkTheme defaults to the system setting. Override to lock
 *   a particular Composable into dark/light for previews.
 * @param useDynamicColor when `true`, replaces the brand primary with
 *   the Material You wallpaper-derived palette (Android 12+ only). Off
 *   by default per DECISIONS.md #042; flip in Settings.
 */
@Composable
fun BobaTheme(
    useDarkTheme: Boolean = isSystemInDarkTheme(),
    useDynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (useDarkTheme) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        useDarkTheme -> BobaDarkColorScheme
        else         -> BobaLightColorScheme
    }

    CompositionLocalProvider(LocalBobaElementColors provides BobaElements) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography  = BobaTypography,
            shapes      = BobaShapes,
            content     = content,
        )
    }
}

/**
 * Element colors are accessed via this CompositionLocal so feature
 * Composables don't have to import the singleton directly — and so
 * tests can swap them.
 */
val LocalBobaElementColors = staticCompositionLocalOf { BobaElements }
