package com.bobaplaybook.core.network

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.HttpRequestRetry
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.serialization.kotlinx.json.json
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Pricing service — eBay active + sold + Radish via the BOBA Worker
 * (`boba-ebay-proxy`). DECISIONS.md #013 + #034.
 *
 * COMC is INTENTIONALLY NOT WIRED — Turnstile-blocked across all
 * platforms per Ben note 2026-05-19.
 *
 * Each method returns a typed result; soft-fails when the Worker
 * returns errors (we treat empty results as "no data" rather than
 * crashing the detail view).
 */
@Singleton
class PricingService @Inject constructor(
    private val httpClient: HttpClient,
) {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    /**
     * eBay active listings (Buy Now). Tile-renderable thumbnails +
     * prices + tap-through URLs.
     */
    suspend fun ebayActive(cardNumber: String, hero: String?): List<PricingListing> =
        withContext(Dispatchers.IO) {
            runCatching {
                val response: EbayActiveResponse = httpClient.get(
                    "${WorkerConfig.EBAY_PROXY}/ebay/active",
                ) {
                    parameter("q", buildQuery(cardNumber, hero))
                    parameter("limit", 12)
                }.body()
                response.items.map { it.toListing() }
            }.getOrDefault(emptyList())
        }

    /**
     * eBay sold history. Returns transacted prices for the Sold panel.
     */
    suspend fun ebaySold(cardNumber: String, hero: String?): List<PricingListing> =
        withContext(Dispatchers.IO) {
            runCatching {
                val response: EbayActiveResponse = httpClient.get(
                    "${WorkerConfig.EBAY_PROXY}/ebay/sold",
                ) {
                    parameter("q", buildQuery(cardNumber, hero))
                    parameter("limit", 12)
                }.body()
                response.items.map { it.toListing() }
            }.getOrDefault(emptyList())
        }

    /**
     * Radish recent sales — the preferred TCG comp source. When
     * present, gets the headline "Market est." number.
     */
    suspend fun radish(cardNumber: String): List<PricingListing> =
        withContext(Dispatchers.IO) {
            runCatching {
                val response: RadishResponse = httpClient.get(
                    "${WorkerConfig.EBAY_PROXY}/radish/recent",
                ) {
                    parameter("cardNumber", cardNumber)
                    parameter("limit", 8)
                }.body()
                response.sales.map {
                    PricingListing(
                        priceUsd = it.priceUsd,
                        title = it.title,
                        thumbUrl = it.thumbUrl,
                        url = it.url,
                        source = PricingSource.RADISH,
                    )
                }
            }.getOrDefault(emptyList())
        }

    private fun buildQuery(cardNumber: String, hero: String?): String =
        buildString {
            append("BoBA ")
            append(cardNumber)
            hero?.takeIf { it.isNotBlank() }?.let { append(" "); append(it) }
        }
}

@Serializable
private data class EbayActiveResponse(
    val items: List<EbayItem> = emptyList(),
)

@Serializable
private data class EbayItem(
    val title: String? = null,
    @SerialName("price") val priceUsd: Double? = null,
    @SerialName("image") val thumbUrl: String? = null,
    val url: String? = null,
) {
    fun toListing() = PricingListing(
        priceUsd = priceUsd ?: 0.0,
        title = title.orEmpty(),
        thumbUrl = thumbUrl,
        url = url.orEmpty(),
        source = PricingSource.EBAY,
    )
}

@Serializable
private data class RadishResponse(
    val sales: List<RadishSale> = emptyList(),
)

@Serializable
private data class RadishSale(
    val title: String,
    @SerialName("price") val priceUsd: Double,
    @SerialName("image") val thumbUrl: String? = null,
    val url: String,
)

/**
 * Domain pricing listing — uniform shape across eBay / Radish / future
 * sources. Source identified so tiles can render the right pill.
 */
data class PricingListing(
    val priceUsd: Double,
    val title: String,
    val thumbUrl: String?,
    val url: String,
    val source: PricingSource,
)

enum class PricingSource { EBAY, RADISH }
