package com.bobaplaybook.core.network

import com.bobaplaybook.core.domain.model.Card

/**
 * Cloudflare R2 image-CDN helpers (DECISIONS.md #008).
 *
 * **Never hardcode R2 URLs at call sites.** Always go through these
 * functions — matches iOS `CDN.swift` and web `js/api.js`.
 *
 * Two tiers per regular card:
 *  - `thumbs/` — 200px WebP, ~10 KB, used in grids
 *  - `full/`   — ≤1200px WebP, ~80 KB, used in detail
 *
 * Sealed products (Booster Boxes etc.) live under a separate prefix
 * (`sealed/thumbs/` + `sealed/optimized/`) per iOS CDN.swift. They
 * route via the Card overload's `card.isSealed` check; the bare
 * imageFile overloads default to the regular tier and should only
 * be used when the caller has already classified the card.
 *
 * Cards with empty / null `imageFile` return null — the cell renders
 * a placeholder (DECISIONS.md #015 "imageAvailable flag bypass": the
 * filename is the only thing that gates loading).
 */
object CDN {

    private const val BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"

    fun thumbUrl(imageFile: String?): String? =
        imageFile?.takeIf { it.isNotEmpty() }?.let { "$BASE/thumbs/$it" }

    fun fullUrl(imageFile: String?): String? =
        imageFile?.takeIf { it.isNotEmpty() }?.let { "$BASE/full/$it" }

    private fun sealedThumbUrl(imageFile: String?): String? =
        imageFile?.takeIf { it.isNotEmpty() }?.let { "$BASE/sealed/thumbs/$it" }

    private fun sealedFullUrl(imageFile: String?): String? =
        imageFile?.takeIf { it.isNotEmpty() }?.let { "$BASE/sealed/optimized/$it" }

    /**
     * Card-aware thumb URL. Sealed products route to /sealed/thumbs/;
     * regular cards to /thumbs/. iOS CDN.thumbURL(for:) parity.
     */
    fun thumbUrl(card: Card): String? =
        if (card.isSealed) sealedThumbUrl(card.imageFile) else thumbUrl(card.imageFile)

    /**
     * Card-aware full-resolution URL. Sealed products route to
     * /sealed/optimized/; regular cards to /full/. iOS CDN.fullURL(for:)
     * parity.
     */
    fun fullUrl(card: Card): String? =
        if (card.isSealed) sealedFullUrl(card.imageFile) else fullUrl(card.imageFile)
}
