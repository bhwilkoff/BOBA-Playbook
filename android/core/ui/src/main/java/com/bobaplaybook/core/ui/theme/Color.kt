package com.bobaplaybook.core.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * BOBA color tokens.
 *
 * Two parallel systems — DO NOT MIX. (ANDROID-DESIGN.md §11.2,
 * DECISIONS.md #010.)
 *
 *  - **Brand tokens** ([BobaBrand]): UI chrome only. Buttons, nav-bar
 *    indicator, primary CTA, FAB. Plumbed through MaterialTheme's
 *    colorScheme.
 *  - **Element tokens** ([BobaElements]): content semantic only. Weapon
 *    AssistChips, filter FilterChips, accent dividers, distribution
 *    charts. NOT in colorScheme; element colors stay element colors.
 *
 * Orange = FIRE overlap is intentional — FIRE is the brand-anchor weapon
 * by design.
 *
 * Element UPPERCASE in JSON, mixed-case in UI ("Fire"). Casing is
 * render-only.
 */
object BobaBrand {
    // ─── Brand seeds ─────────────────────────────────────────────
    val Orange    = Color(0xFFFF4D00)   // primary CTA, FIRE
    val Cyan      = Color(0xFF00F5FF)   // links, highlights, active
    val Violet    = Color(0xFF8B00FF)   // secondary accents, HEX

    // ─── Tonal stops derived from the brand seeds ────────────────
    // Container colors = "tone 30" equivalents — solid, not alpha. The
    // M3 spec algorithm produces these by sampling the seed at chroma 8
    // and tone 30/90 (dark/light). Values picked by eye to read as
    // "selected" on dark backgrounds without screaming.
    val OrangeContainer       = Color(0xFF4A1A05)   // dark-mode primaryContainer
    val OnOrangeContainer     = Color(0xFFFFD8C2)
    val CyanContainer         = Color(0xFF003E48)
    val OnCyanContainer       = Color(0xFFB8F3FA)
    val VioletContainer       = Color(0xFF2B0050)
    val OnVioletContainer     = Color(0xFFE2C8FF)

    // ─── Surface tonal hierarchy ─────────────────────────────────
    // 5 distinct stops — this is what makes M3 tonal elevation READ.
    // NearBlack at the very bottom; each stop ~2% brighter than the
    // previous so chrome layers stack visibly.
    val NearBlack             = Color(0xFF080810)
    val SurfaceLowest         = Color(0xFF0A0A14)
    val SurfaceLow            = Color(0xFF0D0D1A)
    val SurfaceContainer      = Color(0xFF12121F)
    val SurfaceContainerHigh  = Color(0xFF181826)
    val SurfaceContainerMax   = Color(0xFF1F1F2E)

    // ─── Foreground (on-surface) ────────────────────────────────
    val White            = Color(0xFFFAFAFA)
    val OnSurface        = Color(0xFFE4E4ED)
    val OnSurfaceVariant = Color(0xFF9999A6)
    val Outline          = Color(0xFF44444F)
    val OutlineVariant   = Color(0xFF2D2D38)

    // ─── Error ──────────────────────────────────────────────────
    val Error            = Color(0xFFFFB4B4)
    val OnError          = Color(0xFF690005)
    val ErrorContainer   = Color(0xFF3B0000)
    val OnErrorContainer = Color(0xFFFFB4B4)

    // ─── Legacy aliases (used in a few places — keep until sweep) ─
    @Deprecated("Use SurfaceLow", ReplaceWith("BobaBrand.SurfaceLow"))
    val Surface = SurfaceLow
}

/**
 * Element semantic colors. NOT in MaterialTheme.colorScheme — looked
 * up by element key. Used only on content (weapon pills, charts, etc.)
 */
object BobaElements {
    val Fire   = Color(0xFFFF4D00)
    val Ice    = Color(0xFF00BFFF)
    val Steel  = Color(0xFF8A9BB0)
    val Brawl  = Color(0xFFC0392B)
    val Glow   = Color(0xFFFFD700)
    val Hex    = Color(0xFF8B00FF)
    val Gum    = Color(0xFFFF69B4)
    val Super  = Color(0xFFFF00FF)
    val None   = Color(0xFF666680)

    /**
     * Resolve element color by the catalog's UPPERCASE element string.
     * Unknown elements fall back to [None] so missing-data renders
     * cleanly instead of crashing.
     */
    fun forElement(elementUppercase: String): Color = when (elementUppercase) {
        "FIRE"  -> Fire
        "ICE"   -> Ice
        "STEEL" -> Steel
        "BRAWL" -> Brawl
        "GLOW"  -> Glow
        "HEX"   -> Hex
        "GUM"   -> Gum
        "SUPER" -> Super
        else    -> None
    }
}
