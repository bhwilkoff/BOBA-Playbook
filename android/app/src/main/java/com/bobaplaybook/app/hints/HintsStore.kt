package com.bobaplaybook.app.hints

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

private val Context.hintsDataStore by preferencesDataStore(name = "hints")

/**
 * First-run hint dismissal store (ANDROID-DESIGN.md §6.8 +
 * DECISIONS.md #031).
 *
 * One boolean per hint ID. Default `false` = not yet dismissed = hint
 * is visible. User taps the X to dismiss permanently.
 *
 * Composes with a master `globalEnabled` toggle exposed via Profile →
 * Hints. When the toggle is off, [isDismissed] returns `true` for
 * every id (= treat as dismissed = no banners render). Off is the
 * "silence all hints" surface; reset is the "clear all per-id
 * dismissals so banners re-appear" surface.
 *
 * Mirrors iOS HintsManager. Tink encryption NOT used — dismissals
 * are non-sensitive preference data.
 */
@Singleton
class HintsStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    /**
     * Returns true when the hint banner should be HIDDEN, either
     * because the user dismissed this specific id OR because the
     * global hints toggle is off.
     */
    fun isDismissed(id: String): Flow<Boolean> =
        context.hintsDataStore.data.combine(globalEnabled) { prefs, enabled ->
            if (!enabled) return@combine true
            prefs[booleanPreferencesKey(id)] ?: false
        }

    /** Master "show first-run hints" toggle. Default true. */
    val globalEnabled: Flow<Boolean> =
        context.hintsDataStore.data.map { it[GLOBAL_ENABLED_KEY] ?: true }

    suspend fun setGlobalEnabled(enabled: Boolean) {
        context.hintsDataStore.edit { it[GLOBAL_ENABLED_KEY] = enabled }
    }

    suspend fun dismiss(id: String) {
        context.hintsDataStore.edit { it[booleanPreferencesKey(id)] = true }
    }

    /** Reset every per-id dismissal. The global toggle is left as-is. */
    suspend fun resetAll() {
        context.hintsDataStore.edit { prefs ->
            Ids.all.forEach { prefs.remove(booleanPreferencesKey(it)) }
        }
    }

    /** Canonical hint IDs — every hint registered in the app. */
    object Ids {
        const val DECKS_LONG_PRESS_TO_ADD       = "decks_long_press_to_add"
        const val CARD_DETAIL_TAP_PRICE         = "card_detail_tap_price"
        const val COLLECTION_DISPLAY_MODES      = "collection_display_modes"
        const val LEARN_LONG_PRESS_GLOSSARY     = "learn_long_press_glossary"
        const val SCAN_HOLD_STEADY              = "scan_hold_steady"

        val all: List<String> = listOf(
            DECKS_LONG_PRESS_TO_ADD,
            CARD_DETAIL_TAP_PRICE,
            COLLECTION_DISPLAY_MODES,
            LEARN_LONG_PRESS_GLOSSARY,
            SCAN_HOLD_STEADY,
        )
    }

    private companion object {
        val GLOBAL_ENABLED_KEY = booleanPreferencesKey("global_hints_enabled")
    }
}
