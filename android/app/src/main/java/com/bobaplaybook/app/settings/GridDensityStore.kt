package com.bobaplaybook.app.settings

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.gridDensityDataStore by preferencesDataStore(name = "grid_density")

/**
 * Per-tab grid column count (ANDROID-DESIGN.md §6.6 / §11.1).
 *
 * Single source of truth — Find / Decks / Collection each have their
 * own key so density preferences don't leak across tabs.
 *
 * Sentinel `0` = "use the size-class default" (compact: 2, medium/
 * expanded: 5). Non-zero overrides per user choice.
 *
 * Tink encryption NOT used here — grid density is non-sensitive
 * preference data per ANDROID-DEV.md §5.7.
 */
@Singleton
class GridDensityStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    private object Keys {
        val FIND       = intPreferencesKey("find_columns")
        val DECKS      = intPreferencesKey("decks_columns")
        val COLLECTION = intPreferencesKey("collection_columns")
    }

    fun columnsFor(target: Target): Flow<Int> =
        context.gridDensityDataStore.data.map { it[target.key] ?: 0 }

    suspend fun setColumns(target: Target, columns: Int) {
        context.gridDensityDataStore.edit { it[target.key] = columns }
    }

    enum class Target(val key: androidx.datastore.preferences.core.Preferences.Key<Int>) {
        FIND       (Keys.FIND),
        DECKS      (Keys.DECKS),
        COLLECTION (Keys.COLLECTION),
    }
}
