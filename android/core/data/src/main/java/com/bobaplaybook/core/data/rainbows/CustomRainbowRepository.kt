package com.bobaplaybook.core.data.rainbows

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * Custom rainbows repository — user-defined collecting goals saved
 * as filter expressions over the catalog. Maps to the
 * `user_custom_rainbows` Supabase table (migration
 * 2026_05_15_user_custom_rainbows.sql).
 *
 * Each rainbow has a name and a criteria jsonb that holds
 * heroes/sets/subSets/elements/treatments/cardTypes/releases arrays
 * plus an inspiredInkOnly toggle. iOS DECISIONS.md-adjacent feature;
 * Android v1 ships the same shape.
 *
 * RLS handles own-row filtering server-side; we just select() and
 * insert() with `user_id` matching the JWT.
 */
@Singleton
class CustomRainbowRepository @Inject constructor(
    private val supabase: SupabaseClient,
) {
    companion object { private const val TAG = "CustomRainbowRepo" }

    private val _rainbows = MutableStateFlow<List<CustomRainbow>>(emptyList())
    val rainbows: Flow<List<CustomRainbow>> = _rainbows.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch {
            supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated   -> refresh()
                    is SessionStatus.NotAuthenticated -> _rainbows.value = emptyList()
                    is SessionStatus.RefreshFailure   -> _rainbows.value = emptyList()
                    is SessionStatus.Initializing    -> Unit
                }
            }
        }
    }

    suspend fun refresh() {
        runCatching {
            val rows = supabase.postgrest.from("user_custom_rainbows")
                .select()
                .decodeList<CustomRainbowRow>()
            _rainbows.value = rows.map { it.toDomain() }
            Log.i(TAG, "Loaded ${rows.size} custom rainbows")
        }.onFailure { Log.e(TAG, "Failed to fetch rainbows", it) }
    }

    suspend fun save(userId: String, name: String, criteria: RainbowCriteria): String? {
        return runCatching {
            val inserted = supabase.postgrest.from("user_custom_rainbows").insert(
                mapOf(
                    "user_id" to userId,
                    "name" to name,
                    "criteria" to criteria.toJsonString(),
                ),
            ) { select() }.decodeSingle<CustomRainbowRow>()
            _rainbows.value = _rainbows.value + inserted.toDomain()
            inserted.id
        }.onFailure { Log.e(TAG, "Failed to save rainbow", it) }
            .getOrNull()
    }

    suspend fun delete(id: String) {
        _rainbows.value = _rainbows.value.filterNot { it.id == id }
        runCatching {
            supabase.postgrest.from("user_custom_rainbows")
                .delete { filter { eq("id", id) } }
        }.onFailure { e ->
            Log.e(TAG, "Failed to delete rainbow $id", e)
            refresh()
        }
    }
}

// ────────────────────────────────────────────────────────────────
// Domain types
// ────────────────────────────────────────────────────────────────

data class CustomRainbow(
    val id: String,
    val name: String,
    val criteria: RainbowCriteria,
)

data class RainbowCriteria(
    val heroes: List<String> = emptyList(),
    val sets: List<String> = emptyList(),
    val subSets: List<String> = emptyList(),
    val elements: List<String> = emptyList(),
    val treatments: List<String> = emptyList(),
    val cardTypes: List<String> = emptyList(),
    val releases: List<String> = emptyList(),
    val inspiredInkOnly: Boolean = false,
) {
    fun toJsonString(): String = kotlinx.serialization.json.Json.encodeToString(
        kotlinx.serialization.json.JsonObject.serializer(),
        kotlinx.serialization.json.buildJsonObject {
            put("heroes", kotlinx.serialization.json.JsonArray(heroes.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("sets", kotlinx.serialization.json.JsonArray(sets.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("subSets", kotlinx.serialization.json.JsonArray(subSets.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("elements", kotlinx.serialization.json.JsonArray(elements.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("treatments", kotlinx.serialization.json.JsonArray(treatments.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("cardTypes", kotlinx.serialization.json.JsonArray(cardTypes.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("releases", kotlinx.serialization.json.JsonArray(releases.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("inspiredInkOnly", kotlinx.serialization.json.JsonPrimitive(inspiredInkOnly))
        },
    )

    companion object {
        fun fromJson(json: JsonObject?): RainbowCriteria {
            if (json == null) return RainbowCriteria()
            fun pickStrings(key: String): List<String> =
                json[key]?.let { (it as? kotlinx.serialization.json.JsonArray)?.mapNotNull { e -> (e as? kotlinx.serialization.json.JsonPrimitive)?.contentOrNull } } ?: emptyList()
            fun pickBool(key: String): Boolean =
                (json[key] as? kotlinx.serialization.json.JsonPrimitive)?.booleanOrNull ?: false
            return RainbowCriteria(
                heroes = pickStrings("heroes"),
                sets = pickStrings("sets"),
                subSets = pickStrings("subSets"),
                elements = pickStrings("elements"),
                treatments = pickStrings("treatments"),
                cardTypes = pickStrings("cardTypes"),
                releases = pickStrings("releases"),
                inspiredInkOnly = pickBool("inspiredInkOnly"),
            )
        }
    }
}

private val kotlinx.serialization.json.JsonPrimitive.contentOrNull: String?
    get() = if (this.isString) this.content else null

private val kotlinx.serialization.json.JsonPrimitive.booleanOrNull: Boolean?
    get() = this.content.toBooleanStrictOrNull()

// ────────────────────────────────────────────────────────────────
// Supabase row shape
// ────────────────────────────────────────────────────────────────

@Serializable
private data class CustomRainbowRow(
    val id: String,
    val name: String,
    @SerialName("criteria") val criteriaJson: JsonObject? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    fun toDomain() = CustomRainbow(
        id = id,
        name = name,
        criteria = RainbowCriteria.fromJson(criteriaJson),
    )
}
