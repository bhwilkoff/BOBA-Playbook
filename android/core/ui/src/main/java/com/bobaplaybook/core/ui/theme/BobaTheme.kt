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
import androidx.compose.ui.platform.LocalContext

/**
 * Brand colorScheme — DEFAULT.
 *
 * Per DECISIONS.md #042: BOBA ships with a fixed brand theme by default.
 * The card-art palette is the focal point, and a user's wallpaper-derived
 * primary fighting `#FF4D00` reads muddy.
 *
 * Dynamic color (Material You) is opt-in via [useDynamicColor]. M0
 * doesn't yet expose the toggle in Settings — it's the parameter to
 * [BobaTheme]. Settings UI lands in M7.
 */

private val BobaDarkColorScheme = darkColorScheme(
    primary           = BobaBrand.Orange,
    onPrimary         = BobaBrand.White,
    primaryContainer  = BobaBrand.Orange.copy(alpha = 0.15f),
    onPrimaryContainer = BobaBrand.Orange,

    secondary         = BobaBrand.Cyan,
    onSecondary       = BobaBrand.NearBlack,
    secondaryContainer = BobaBrand.Cyan.copy(alpha = 0.15f),
    onSecondaryContainer = BobaBrand.Cyan,

    tertiary          = BobaBrand.Violet,
    onTertiary        = BobaBrand.White,
    tertiaryContainer = BobaBrand.Violet.copy(alpha = 0.15f),
    onTertiaryContainer = BobaBrand.Violet,

    background        = BobaBrand.NearBlack,
    onBackground      = BobaBrand.OnSurface,

    surface           = BobaBrand.NearBlack,
    onSurface         = BobaBrand.OnSurface,
    surfaceVariant    = BobaBrand.Surface,
    onSurfaceVariant  = BobaBrand.OnSurfaceVariant,

    error             = BobaBrand.OnError,
    onError           = BobaBrand.NearBlack,
    errorContainer    = BobaBrand.ErrorContainer,
    onErrorContainer  = BobaBrand.OnError,

    outline           = BobaBrand.OnSurfaceVariant.copy(alpha = 0.4f),
    outlineVariant    = BobaBrand.OnSurfaceVariant.copy(alpha = 0.2f),

    surfaceContainerLowest  = BobaBrand.NearBlack,
    surfaceContainerLow     = BobaBrand.Surface,
    surfaceContainer        = BobaBrand.Surface,
    surfaceContainerHigh    = BobaBrand.Surface.copy(alpha = 1f),
    surfaceContainerHighest = BobaBrand.Surface,
)

// Light-mode brand palette. BOBA's brand identity is dark-first (the
// card art carries most of the chroma), but Compose requires a light
// scheme for users who force light mode. Tuned to keep the brand seed
// colors recognizable on a light background.
private val BobaLightColorScheme = lightColorScheme(
    primary           = BobaBrand.Orange,
    onPrimary         = BobaBrand.White,
    secondary         = BobaBrand.Cyan,
    onSecondary       = BobaBrand.NearBlack,
    tertiary          = BobaBrand.Violet,
    onTertiary        = BobaBrand.White,
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
