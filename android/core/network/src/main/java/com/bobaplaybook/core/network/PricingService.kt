package com.bobaplaybook.core.network

import android.util.Log
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Pricing service — single request to the `boba-ebay-proxy` Worker
 * root which aggregates eBay active + eBay sold into one response.
 * Matches iOS PricingService.swift exactly.
 *
 * **Worker contract** (verified 2026-05-23, v18 — Radish-free):
 *   `GET /?cardNumber={n}&hero={h}&set={s}&element={e}&days=90`
 *   →
 *   {
 *     "active": { "low":..., "average":..., "high":..., "count":..., "items":[{title,price,date,url}] },
 *     "sold":   { "low":..., "average":..., "high":..., "count":..., "items":[...] },
 *     "low":..., "average":..., "high":..., "count":..., "priceType":"listed"|"sold",
 *     "items":  [...],                  // legacy flat list (mirrors whichever section drove the headline)
 *   }
 *
 * COMC stays out of the sold-comp waterfall (DECISIONS.md #034); the
 * Worker doesn't fold it in. Radish Price Guide is no longer consulted
 * by the Worker (DECISIONS.md #056 / RADISH_REMOVAL_LOOP.md). The
 * client-side "View on Radish" button reads `Card.radishUrl` from the
 * catalog directly — not from this Worker response.
 */
@Singleton
class PricingService @Inject constructor(
    private val httpClient: HttpClient,
) {
    companion object { private const val TAG = "PricingService" }

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    /** Single fetch — populates both active and sold buckets. */
    suspend fun fetchAll(
        cardNumber: String,
        hero: String?,
        set: String?,
        element: String?,
        days: Int = 90,
    ): PricingBundle = withContext(Dispatchers.IO) {
        runCatching {
            val response: PricingResponse = httpClient.get(WorkerConfig.EBAY_PROXY) {
                parameter("cardNumber", cardNumber)
                hero?.takeIf { it.isNotBlank() }?.let { parameter("hero", it) }
                set?.takeIf { it.isNotBlank() }?.let { parameter("set", it) }
                element?.takeIf { it.isNotBlank() }?.let { parameter("element", it) }
                parameter("days", days)
            }.body()

            // Every listing comes from eBay post-2026-05-23 — the Worker
            // no longer consults Radish. Tagging all tiles EBAY so the
            // UI label and tap-through expectations match reality.
            val activeItems = response.active?.items.orEmpty().map { it.toListing(PricingSource.EBAY) }
            val soldItems = response.sold?.items.orEmpty().map { it.toListing(PricingSource.EBAY) }
            // Worker pre-computes the canonical low/average/high over
            // the preferred source (sold first; active as fallback).
            // The `priceType` field tags which source landed in the
            // top-level fields. Surfacing these directly avoids
            // re-deriving the waterfall on-device, so iOS and Android
            // render identical market estimates for the same Worker
            // response.
            PricingBundle(
                ebayActive = activeItems,
                ebaySold = soldItems,
                marketAverageUsd = response.average,
                marketSource = response.priceType,
                marketCount = response.count,
            )
        }.onFailure { e ->
            Log.e(TAG, "fetchAll($cardNumber) failed", e)
        }.getOrDefault(PricingBundle())
    }
}

// ─────────────────────────────────────────────────────────────────
// Domain types
// ─────────────────────────────────────────────────────────────────

data class PricingBundle(
    val ebayActive: List<PricingListing> = emptyList(),
    val ebaySold: List<PricingListing> = emptyList(),
    /**
     * Worker's pre-computed canonical market average. Reflects the
     * Worker's source-waterfall (sold > active). Use this directly
     * in the UI instead of recomputing a median locally — keeps
     * iOS + Android pricing displays in lockstep.
     */
    val marketAverageUsd: Double? = null,
    /** "sold" or "listed" — names which underlying source the average came from. */
    val marketSource: String? = null,
    /** Number of items the Worker averaged over. */
    val marketCount: Int = 0,
)

data class PricingListing(
    val priceUsd: Double,
    val title: String,
    val thumbUrl: String?,   // Worker doesn't surface thumbnails today; reserved for future
    val url: String,
    val date: String?,
    val source: PricingSource,
)

enum class PricingSource { EBAY }

// ─────────────────────────────────────────────────────────────────
// Worker response wire shapes
// ─────────────────────────────────────────────────────────────────

@Serializable
private data class PricingResponse(
    val active: PricingSection? = null,
    val sold: PricingSection? = null,
    val low: Double? = null,
    val average: Double? = null,
    val high: Double? = null,
    val count: Int = 0,
    @SerialName("priceType") val priceType: String? = null,
    val items: List<PricingItem> = emptyList(),
)

@Serializable
private data class PricingSection(
    val low: Double? = null,
    val average: Double? = null,
    val high: Double? = null,
    val count: Int = 0,
    val items: List<PricingItem> = emptyList(),
)

@Serializable
private data class PricingItem(
    val title: String? = null,
    val price: Double? = null,
    val date: String? = null,
    val url: String? = null,
) {
    fun toListing(source: PricingSource) = PricingListing(
        priceUsd = price ?: 0.0,
        title = title.orEmpty(),
        thumbUrl = null,
        url = url.orEmpty(),
        date = date?.takeIf { it.isNotBlank() },
        source = source,
    )
}
