package com.bobaplaybook.app.hints

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.hintsDataStore by preferencesDataStore(name = "hints")

/**
 * First-run hint dismissal store (ANDROID-DESIGN.md §6.8 +
 * DECISIONS.md #031).
 *
 * One boolean per hint ID. Default `false` = not yet dismissed = hint
 * is visible. User taps the X to dismiss permanently.
 *
 * Mirrors iOS HintsManager. Tink encryption NOT used — dismissals
 * are non-sensitive preference data.
 */
@Singleton
class HintsStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    fun isDismissed(id: String): Flow<Boolean> =
        context.hintsDataStore.data.map { it[booleanPreferencesKey(id)] ?: false }

    suspend fun dismiss(id: String) {
        context.hintsDataStore.edit { it[booleanPreferencesKey(id)] = true }
    }

    suspend fun resetAll(ids: List<String>) {
        context.hintsDataStore.edit { prefs ->
            ids.forEach { prefs.remove(booleanPreferencesKey(it)) }
        }
    }

    /** Canonical hint IDs — every hint registered in the app. */
    object Ids {
        const val DECKS_LONG_PRESS_TO_ADD       = "decks_long_press_to_add"
        const val CARD_DETAIL_TAP_PRICE         = "card_detail_tap_price"
        const val COLLECTION_DISPLAY_MODES      = "collection_display_modes"
        const val LEARN_LONG_PRESS_GLOSSARY     = "learn_long_press_glossary"
        const val SCAN_HOLD_STEADY              = "scan_hold_steady"
    }
}
