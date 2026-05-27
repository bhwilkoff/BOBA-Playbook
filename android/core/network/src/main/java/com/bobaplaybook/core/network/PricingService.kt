package com.bobaplaybook.core.network

import android.util.Log
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
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

    /**
     * Market Est. fallback fetch — `boba-price-estimator` Worker.
     * Returns null when no estimate exists for the given bobaId (404 —
     * cron hasn't computed yet, or zero comps available). Used by
     * `CardDetailViewModel` when the eBay-proxy returned no sold
     * section, so the UI can render a "MARKET EST." surface instead
     * of "No recent sales found."
     */
    suspend fun fetchMarketEstimate(bobaId: String): MarketEstimate? = withContext(Dispatchers.IO) {
        if (bobaId.isBlank()) return@withContext null
        runCatching {
            val response: EstimatorResponse = httpClient.get("${WorkerConfig.PRICE_ESTIMATOR}/estimate") {
                parameter("bobaId", bobaId)
            }.body()
            if (response.mid <= 0) null else MarketEstimate(
                low  = response.low,
                mid  = response.mid,
                high = response.high,
                comparableCount = response.comparableCount ?: 0,
                comparableSources = response.comparableSources ?: emptyList(),
            )
        }.onFailure { e ->
            Log.d(TAG, "fetchMarketEstimate($bobaId) — no estimate yet: ${e.message}")
        }.getOrNull()
    }

    /**
     * Persistence-layer fast path — read the latest snapshot rows for
     * [bobaId] from Supabase's `card_prices_latest` view. Returns a
     * [PricingBundle] equivalent to a live ebay-proxy response when a
     * fresh row (< 24h) exists, or null when nothing usable is in the
     * table yet (cron hasn't seen this card, no eBay data, etc.) so
     * the caller falls through to the live ebay-proxy path.
     */
    suspend fun fetchCachedBundle(bobaId: String): PricingBundle? = withContext(Dispatchers.IO) {
        if (bobaId.isBlank()) return@withContext null
        runCatching {
            val rows: List<CardPricesLatestRow> = httpClient.get(
                "${WorkerConfig.SUPABASE_URL}/rest/v1/card_prices_latest"
            ) {
                parameter("boba_id", "eq.$bobaId")
                parameter("select", "source,snapshot_at,low_usd,avg_usd,high_usd,item_count")
                header("apikey", WorkerConfig.SUPABASE_ANON_KEY)
                header("Authorization", "Bearer ${WorkerConfig.SUPABASE_ANON_KEY}")
            }.body()
            if (rows.isEmpty()) return@runCatching null
            val freshThresholdMs = 24L * 3600 * 1000
            val now = System.currentTimeMillis()
            var soldAvg: Double? = null
            var soldCount = 0
            var activeRows = 0
            for (row in rows) {
                val snapMs = parseIso(row.snapshotAt) ?: continue
                if ((now - snapMs) >= freshThresholdMs) continue
                when (row.source) {
                    "ebay_sold"   -> { soldAvg = row.avgUsd; soldCount = row.itemCount ?: 0 }
                    "ebay_active" -> { activeRows++ }
                    "estimator"   -> { if (soldAvg == null) { soldAvg = row.avgUsd; soldCount = row.itemCount ?: 0 } }
                }
            }
            val anyFresh = rows.any { row ->
                val snapMs = parseIso(row.snapshotAt) ?: return@any false
                (now - snapMs) < freshThresholdMs
            }
            if (!anyFresh) return@runCatching null
            PricingBundle(
                ebayActive = emptyList(),   // Snapshot stores aggregates only; per-listing rows not cached.
                ebaySold = emptyList(),
                marketAverageUsd = soldAvg ?: 0.0,
                marketSource = if (activeRows > 0 && soldAvg == null) "listed" else "sold",
                marketCount = soldCount,
            )
        }.onFailure { e ->
            Log.d(TAG, "fetchCachedBundle($bobaId) skipped: ${e.message}")
        }.getOrNull()
    }

    /** Single fetch — populates both active and sold buckets. */
    suspend fun fetchAll(
        cardNumber: String,
        hero: String?,
        set: String?,
        element: String?,
        days: Int = 90,
        bobaId: String = "",
    ): PricingBundle = withContext(Dispatchers.IO) {
        runCatching {
            val response: PricingResponse = httpClient.get(WorkerConfig.EBAY_PROXY) {
                parameter("cardNumber", cardNumber)
                hero?.takeIf { it.isNotBlank() }?.let { parameter("hero", it) }
                set?.takeIf { it.isNotBlank() }?.let { parameter("set", it) }
                element?.takeIf { it.isNotBlank() }?.let { parameter("element", it) }
                parameter("days", days)
                // bobaId → proxy pushes active listings to the vanish tracker (#058).
                if (bobaId.isNotBlank()) parameter("bobaId", bobaId)
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

    /**
     * Whatnot active product listings (Tier 2 — an ASKING signal for the
     * Buy Now area only; NEVER folded into any sold/value number, #034).
     * Queries by the distinctive hero token; the Worker binds to the card
     * via cardNumber + weapon and flags matchesCard (best-first). Soft-
     * fails to empty on any error or a Cloudflare challenge, so a Whatnot
     * hiccup never blocks the eBay pricing render. Matches iOS
     * WhatnotProductsService + web fetchWhatnotProducts.
     */
    suspend fun fetchWhatnotProducts(
        query: String,
        cardNumber: String,
        weapon: String,
        treatment: String = "",
        power: Int? = null,
        bobaId: String = "",
    ): List<WhatnotListing> = withContext(Dispatchers.IO) {
        val q = query.trim()
        if (q.isEmpty()) return@withContext emptyList()
        runCatching {
            // BoBA sellers title by card number OR power — send both so the
            // Worker can match on whichever the listing used.
            val response: WhatnotProductsResponse = httpClient.get("${WorkerConfig.EBAY_PROXY}/whatnot/products") {
                parameter("query", q)
                if (cardNumber.isNotBlank()) parameter("cardNumber", cardNumber)
                if (weapon.isNotBlank()) parameter("weapon", weapon)
                if (treatment.isNotBlank()) parameter("treatment", treatment)
                if (power != null) parameter("power", power.toString())
                // bobaId → proxy pushes matched listings to the vanish tracker (#058).
                if (bobaId.isNotBlank()) parameter("bobaId", bobaId)
            }.body()
            if (response.challenged == true) emptyList()
            else response.listings.map { it.toDomain() }
        }.onFailure { e -> Log.e(TAG, "fetchWhatnotProducts failed", e) }
            .getOrDefault(emptyList())
    }

    /**
     * Real transacted comps (Recent Sales) from `boba-pricing-tracker
     * /comps` — vanish-inferred eBay/Whatnot sales + mod-approved community
     * comps (DECISIONS.md #058). The REAL sold signal we generate ourselves;
     * the resolver ranks it above Listed Range. Returns null when no comps
     * exist yet so the caller falls through to Listed Range. Soft-fails.
     */
    // `days` defaults to a full year: sold history doesn't go stale like
    // active asks, and the wider window surfaces the most comps as vanish-
    // inference accrues. Independent of the card-detail active-listing picker.
    suspend fun fetchComps(bobaId: String, days: Int = 365): CompsResult? = withContext(Dispatchers.IO) {
        if (bobaId.isBlank()) return@withContext null
        runCatching {
            val resp: CompsResponse = httpClient.get("${WorkerConfig.PRICING_TRACKER}/comps") {
                parameter("bobaId", bobaId)
                parameter("days", days)
            }.body()
            val summary = resp.summary
            if (summary == null || summary.count <= 0 || resp.comps.isEmpty()) null
            else CompsResult(
                comps = resp.comps.map { Comp(it.price ?: 0.0, it.soldAt, it.confidence, it.source) },
                low = summary.low, median = summary.median, high = summary.high, count = summary.count,
            )
        }.onFailure { e -> Log.d(TAG, "fetchComps($bobaId) — none yet: ${e.message}") }
            .getOrNull()
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

/**
 * A current Whatnot active listing (asking signal). matchesCard is true
 * when the Worker bound it to the viewed card (cardNumber + weapon);
 * the UI shows matched listings first, then "Other {hero}".
 */
data class WhatnotListing(
    val title: String,
    val priceUsd: Double,
    val listingUrl: String,
    val seller: String?,
    val format: String?,    // "buy_now" | "auction"
    val matchesCard: Boolean,
)

/**
 * Comparability-derived Market Est. range from `boba-price-estimator`.
 * Surfaces as a "MARKET EST." section in the card-detail pricing
 * panels when no recent eBay sold comps exist for the card.
 */
data class MarketEstimate(
    val low: Double,
    val mid: Double,
    val high: Double,
    val comparableCount: Int = 0,
    val comparableSources: List<String> = emptyList(),
)

/**
 * One transacted comp from boba-pricing-tracker /comps (#058) — the real
 * "Recent Sales" signal we generate ourselves (vanish-inferred eBay/Whatnot
 * sales + mod-approved community comps).
 */
data class Comp(
    val priceUsd: Double,
    val soldAt: String?,
    val confidence: Double?,
    val source: String?,    // "ebay-inferred" | "whatnot-inferred" | "community-…"
)

/** Aggregated comps for one card. */
data class CompsResult(
    val comps: List<Comp>,
    val low: Double,
    val median: Double,
    val high: Double,
    val count: Int,
)

/** A Recent Sales row — carries its provenance pill (no tap-through for
 *  vanish-inferred/community rows; eBay sold rows keep their URL). */
data class RecentSaleRow(
    val priceUsd: Double,
    val date: String?,
    val sourcePill: String,
    val url: String? = null,
)

/**
 * Provenance-honest resolution (DECISIONS.md #058) — the ONE place the
 * four-signal hierarchy lives on Android, shared by card detail + (future)
 * Collection value. Built by [marketValue]; consumed by `PricingPanels`.
 */
data class ResolvedPricing(
    val recentSales: List<RecentSaleRow> = emptyList(),
    val recentLow: Double = 0.0,
    val recentAvg: Double = 0.0,
    val recentHigh: Double = 0.0,
    val listedLow: Double = 0.0,
    val listedAvg: Double = 0.0,
    val listedHigh: Double = 0.0,
    val listedCount: Int = 0,
    val listedHasEbay: Boolean = false,
    val listedHasWhatnot: Boolean = false,
    val headlineValue: Double? = null,
    val headlineSource: String? = null,   // "recent_sales" | "listed_range" | "estimate"
    val headlineBasis: String? = null,
) {
    val hasRecentSales: Boolean get() = recentSales.isNotEmpty()
    val hasListedRange: Boolean get() = listedCount > 0
    val hasAnySignal: Boolean get() = hasRecentSales || hasListedRange
}

/** Human-readable provenance pill for a comp `source` (#058). */
fun compSourcePill(source: String?): String = when {
    source == null -> "sale"
    source == "ebay-inferred" -> "eBay sale"
    source == "whatnot-inferred" -> "Whatnot sale"
    source.startsWith("community") ->
        source.split("-").getOrNull(1)?.let { "BoBA Community · $it" } ?: "BoBA Community"
    else -> "sale"
}

/**
 * Provenance-honest market-value resolver (DECISIONS.md #058) — most-specific
 * honestly-labeled signal wins:
 *   1. Recent Sales — `comps` (vanish-inferred + community) + real eBay sold.
 *   2. Listed Range — eBay active + Whatnot **matched** asks combined (the (A)
 *      fold, PRICING_PLAYBOOK §4.3). The honest signal when there are no sales.
 * Buy Now (eBay actives + Whatnot tiles) is additive; asks NEVER enter a
 * sold/value number (#034). The estimator (Tier 4) is suppressed while starved
 * and handled by the caller's existing fallback.
 */
fun marketValue(
    ebayActive: List<PricingListing>,
    ebaySold: List<PricingListing>,
    comps: CompsResult?,
    whatnotMatched: List<WhatnotListing>,
): ResolvedPricing {
    var out = ResolvedPricing()

    // 1. Recent Sales (transacted) — comps first, then any real eBay sold.
    val compRows = comps?.comps.orEmpty().map {
        RecentSaleRow(priceUsd = it.priceUsd, date = it.soldAt, sourcePill = compSourcePill(it.source))
    }
    val soldRows = ebaySold.map {
        RecentSaleRow(priceUsd = it.priceUsd, date = it.date, sourcePill = "eBay sale",
            url = it.url.takeIf { u -> u.isNotBlank() })
    }
    val recentRows = compRows + soldRows
    if (recentRows.isNotEmpty()) {
        val prices = recentRows.map { it.priceUsd }.filter { it > 0 }.sorted()
        val low = prices.firstOrNull() ?: comps?.low ?: 0.0
        val high = prices.lastOrNull() ?: comps?.high ?: 0.0
        val median = if (prices.isNotEmpty()) prices[(prices.size - 1) / 2] else (comps?.median ?: 0.0)
        out = out.copy(
            recentSales = recentRows,
            recentLow = low, recentAvg = median, recentHigh = high,
            headlineValue = median, headlineSource = "recent_sales",
            headlineBasis = "based on ${prices.size} recent sale${if (prices.size != 1) "s" else ""}",
        )
    }

    // 2. Listed Range (eBay active + Whatnot matched asks).
    val ebayPrices = ebayActive.map { it.priceUsd }.filter { it > 0 }
    val wnPrices = whatnotMatched.map { it.priceUsd }.filter { it > 0 }
    val all = ebayPrices + wnPrices
    if (all.isNotEmpty()) {
        val hasEbay = ebayPrices.isNotEmpty()
        val hasWhatnot = wnPrices.isNotEmpty()
        val avg = all.average()
        out = out.copy(
            listedLow = all.min(), listedAvg = avg, listedHigh = all.max(), listedCount = all.size,
            listedHasEbay = hasEbay, listedHasWhatnot = hasWhatnot,
        )
        if (!out.hasRecentSales) {
            val where = if (hasWhatnot && hasEbay) "eBay + Whatnot" else if (hasWhatnot) "Whatnot" else "eBay"
            out = out.copy(
                headlineValue = avg, headlineSource = "listed_range",
                headlineBasis = "${all.size} active $where listing${if (all.size != 1) "s" else ""} · no recent sales yet",
            )
        }
    }
    return out
}

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
private data class CardPricesLatestRow(
    val source: String,
    @SerialName("snapshot_at") val snapshotAt: String,
    @SerialName("low_usd")    val lowUsd: Double? = null,
    @SerialName("avg_usd")    val avgUsd: Double? = null,
    @SerialName("high_usd")   val highUsd: Double? = null,
    @SerialName("item_count") val itemCount: Int? = null,
)

private fun parseIso(s: String): Long? = runCatching {
    java.time.OffsetDateTime.parse(s).toInstant().toEpochMilli()
}.getOrNull()

@Serializable
private data class EstimatorResponse(
    val low: Double = 0.0,
    val mid: Double = 0.0,
    val high: Double = 0.0,
    @SerialName("comparableCount") val comparableCount: Int? = null,
    @SerialName("comparableSources") val comparableSources: List<String>? = null,
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

@Serializable
private data class WhatnotProductsResponse(
    val count: Int = 0,
    val bestMatchCount: Int? = null,
    val challenged: Boolean? = null,
    val listings: List<WhatnotProductItem> = emptyList(),
)

@Serializable
private data class WhatnotProductItem(
    val title: String? = null,
    val price: Double? = null,
    val listingUrl: String? = null,
    val seller: String? = null,
    val format: String? = null,
    val matchesCard: Boolean? = null,
) {
    fun toDomain() = WhatnotListing(
        title = title.orEmpty(),
        priceUsd = price ?: 0.0,
        listingUrl = listingUrl.orEmpty(),
        seller = seller,
        format = format,
        matchesCard = matchesCard == true,
    )
}

@Serializable
private data class CompsResponse(
    val comps: List<CompItem> = emptyList(),
    val summary: CompsSummary? = null,
)

@Serializable
private data class CompItem(
    val price: Double? = null,
    val soldAt: String? = null,
    val confidence: Double? = null,
    val source: String? = null,
)

@Serializable
private data class CompsSummary(
    val low: Double = 0.0,
    val median: Double = 0.0,
    val high: Double = 0.0,
    val count: Int = 0,
)
