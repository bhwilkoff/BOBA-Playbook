package com.bobaplaybook.core.ui.format

import java.util.Locale

/**
 * USD price formatter — always "1,234.56" style regardless of the
 * device locale. iOS NSNumberFormatter(.currency, US) parity.
 *
 * `"%.2f".format(x)` uses the default locale, so devices in
 * es-ES / de-DE / fr-FR render "1234,56" with a comma decimal —
 * disorienting next to the leading "$". BOBA pricing data is
 * USD-denominated (eBay / Radish / COMC are US marketplaces) so
 * the rendering should always be US-style.
 *
 * Returns just the digits + decimal. Callers prepend "$" or
 * wrap in their own pricing UI.
 */
fun Double.formatUsdAmount(): String =
    String.format(Locale.US, "%.2f", this)
