package com.bobaplaybook.app.feature.learn

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Tournament / Release event entry — sourced from
 * `assets/data/events.json` (shared with iOS + web; synced by
 * `android/scripts/sync_shared_assets.sh`).
 *
 * Discord backlog #8 (tick 191). Schema documented in events.json
 * itself under `_schema`.
 */
@Serializable
data class EventEntry(
    val id:          String,
    val kind:        String,                 // "release" | "tournament"
    val title:       String,
    val date:        String? = null,         // "YYYY-MM-DD" or null = TBA
    val endDate:     String? = null,
    val location:    String? = null,
    val description: String? = null,         // optional — sometimes title+url+formats say it all
    val formats:     List<String> = emptyList(),
    val set:         String? = null,
    val url:         String? = null,
)

@Serializable
private data class EventsBundle(val events: List<EventEntry>)

/**
 * Synchronous decoder — events.json is tiny (~1 KB at v1), no
 * background-task needed. Falls back to an empty list when the file
 * is missing or malformed so the Tournament page renders cleanly
 * even on a partially-corrupted install.
 */
object EventsLoader {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
    }

    fun load(context: Context): List<EventEntry> =
        try {
            val text = context.assets.open("data/events.json").bufferedReader().use { it.readText() }
            json.decodeFromString<EventsBundle>(text).events
        } catch (_: Throwable) {
            emptyList()
        }
}
