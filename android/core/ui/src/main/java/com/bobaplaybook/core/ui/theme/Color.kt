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
    val Orange    = Color(0xFFFF4D00) // primary CTA, FIRE
    val Cyan      = Color(0xFF00F5FF) // links, highlights, active states
    val Violet    = Color(0xFF8B00FF) // secondary accents, HEX
    val NearBlack = Color(0xFF080810) // page background
    val Surface   = Color(0xFF0D0D1A) // card / panel surface
    val White     = Color(0xFFFAFAFA)
    val OnSurface = Color(0xFFE4E4ED)
    val OnSurfaceVariant = Color(0xFF9999A6)
    val ErrorContainer = Color(0xFF3B0000)
    val OnError   = Color(0xFFFFB4B4)
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
