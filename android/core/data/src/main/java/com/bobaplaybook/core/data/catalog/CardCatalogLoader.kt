package com.bobaplaybook.core.data.catalog

import android.content.Context
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Two-phase catalog loader — Android mirror of iOS [CardStore.init]
 * + [CardStore.loadFullCatalog] (DECISIONS.md #014 + ANDROID-DEV.md
 * §9.1).
 *
 *  - **Phase 1 — synchronous** ([loadHead]). Decodes `cards-head.json`
 *    (500 cards, ~192 KB). MUST run BEFORE the first Compose frame so
 *    the Find shelf has something to render. Call from
 *    `Application.onCreate` directly on the main thread; decode budget
 *    ≤ 50 ms.
 *
 *  - **Phase 2 — background** ([loadFull]). Decodes the full
 *    `cards.json` (~17,974 cards, ~5 MB) on `Dispatchers.IO`. Atomic
 *    swap into the in-memory `Map<bobaId, Card>` once ready.
 *
 * Catalog assets are committed to repo root `assets/data/` and copied
 * into `app/src/main/assets/data/` by the Gradle `syncSharedAssets`
 * task at build time (ANDROID-DEV.md §13.3).
 *
 * Decoder configured with `ignoreUnknownKeys = true` so the catalog
 * schema can grow new fields without breaking the Android client
 * (mirrors iOS Codable's "extra keys are silently dropped" semantics).
 */
@Singleton
class CardCatalogLoader @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        coerceInputValues = true
        isLenient = true
    }

    /**
     * Phase 1 — synchronous decode of `cards-head.json`. Call from
     * [BOBAApplication.onCreate].
     *
     * Returns an empty list if the head file is missing or fails to
     * decode — the catalog feature can recover via the Phase 2 load.
     */
    fun loadHead(): List<Card> = runCatching {
        context.assets.open("data/cards-head.json").use { stream ->
            json.decodeFromString<List<Card>>(stream.bufferedReader().readText())
        }
    }.getOrDefault(emptyList())

    /**
     * Phase 2 — background decode of the full catalog. Spawn a
     * `viewModelScope.launch(Dispatchers.IO) { loader.loadFull() }`.
     * The repository swaps the resulting map atomically.
     */
    suspend fun loadFull(): List<Card> = withContext(Dispatchers.IO) {
        runCatching {
            context.assets.open("data/cards.json").use { stream ->
                json.decodeFromString<List<Card>>(stream.bufferedReader().readText())
            }
        }.getOrDefault(emptyList())
    }
}
