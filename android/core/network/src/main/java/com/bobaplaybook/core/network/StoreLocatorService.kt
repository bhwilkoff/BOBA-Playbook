package com.bobaplaybook.core.network

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

/**
 * Store-locator service — fetches the canonical stores.json shipped by
 * bobaplaybook.com (~330 indie + 1,800 big-box stores). Mirrors iOS
 * StoreLocatorService.
 *
 * Single source of truth across iOS, web, and Android.
 */
@Singleton
class StoreLocatorService @Inject constructor(
    private val httpClient: HttpClient,
) {
    suspend fun fetchStores(): List<StoreLocation> = withContext(Dispatchers.IO) {
        runCatching {
            val response: List<StoreRow> = httpClient
                .get("https://bobaplaybook.com/assets/data/stores.json")
                .body()
            response.mapNotNull { it.toDomain() }
        }.getOrDefault(emptyList())
    }
}

data class StoreLocation(
    val id: Long,
    val name: String,
    val street: String?,
    val city: String,
    val state: String,
    val stateShort: String,
    val postCode: String?,
    val lat: Double,
    val lng: Double,
    val website: String?,
    val officialUrl: String?,
    /**
     * Best-effort indie classification — a store qualifies as
     * "indie" when its name doesn't contain a big-box chain marker.
     * Coarse filter; real source of truth is the BOBA backend.
     */
    val isIndie: Boolean,
) {
    val fullAddress: String
        get() = listOfNotNull(street, city, "$stateShort ${postCode.orEmpty()}".trim())
            .joinToString(", ")
}

@Serializable
private data class StoreRow(
    val id: Long? = null,
    val name: String? = null,
    val website: String? = null,
    val officialUrl: String? = null,
    val address: StoreAddress? = null,
    val location: StoreLatLng? = null,
) {
    fun toDomain(): StoreLocation? {
        val a = address ?: return null
        val l = location ?: return null
        val nameLower = (name ?: "").lowercase()
        val bigBoxMarkers = listOf("dick's", "target", "walmart", "best buy", "barnes & noble")
        val isIndie = bigBoxMarkers.none { nameLower.contains(it) }
        return StoreLocation(
            id = id ?: 0,
            name = name ?: return null,
            street = a.street,
            city = a.city.orEmpty(),
            state = a.state.orEmpty(),
            stateShort = a.stateShort.orEmpty(),
            postCode = a.postCode,
            lat = l.lat,
            lng = l.lng,
            website = website,
            officialUrl = officialUrl,
            isIndie = isIndie,
        )
    }
}

@Serializable
private data class StoreAddress(
    val full: String? = null,
    val street: String? = null,
    val city: String? = null,
    val state: String? = null,
    val stateShort: String? = null,
    val postCode: String? = null,
)

@Serializable
private data class StoreLatLng(val lat: Double, val lng: Double)
