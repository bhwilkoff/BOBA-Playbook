package com.bobaplaybook.core.ui.format

import java.util.Locale

/**
 * USD price formatter — always "1,234.56" style regardless of the
 * device locale. iOS NSNumberFormatter(.currency, US) parity.
 *
 * `"%.2f".format(x)` uses the default locale AND skips grouping —
 * which made `$13533.55` render without the comma on the Collection
 * value summary. `"%,.2f"` adds the locale's grouping separator
 * (comma in en-US, the canonical USD rendering).
 *
 * `Locale.US` is hard-pinned: devices in es-ES / de-DE / fr-FR
 * would otherwise render "1234,56" with comma-decimal, which is
 * disorienting next to the leading "$". BOBA pricing data is
 * USD-denominated (eBay / Radish / COMC are US marketplaces) so
 * the rendering should always be US-style.
 *
 * Returns just the digits + grouping commas + decimal. Callers
 * prepend "$" or wrap in their own pricing UI.
 */
fun Double.formatUsdAmount(): String =
    String.format(Locale.US, "%,.2f", this)
