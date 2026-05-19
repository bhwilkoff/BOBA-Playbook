package com.bobaplaybook.core.network

import com.bobaplaybook.core.domain.model.Card

/**
 * Cloudflare R2 image-CDN helpers (DECISIONS.md #008).
 *
 * **Never hardcode R2 URLs at call sites.** Always go through these
 * functions — matches iOS `CDN.swift` and web `js/api.js`.
 *
 * Two tiers per spec:
 *  - `thumbs/` — 200px WebP, ~10 KB, used in grids
 *  - `full/`   — ≤1200px WebP, ~80 KB, used in detail
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

    fun thumbUrl(card: Card): String? = thumbUrl(card.imageFile)
    fun fullUrl(card: Card): String?  = fullUrl(card.imageFile)
}
