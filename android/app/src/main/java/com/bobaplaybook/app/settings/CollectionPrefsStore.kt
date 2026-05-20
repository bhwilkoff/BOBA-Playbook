package com.bobaplaybook.app.settings

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.collectionPrefsDataStore by preferencesDataStore(name = "collection_prefs")

/**
 * Persistent Collection preferences across app launches —
 * `displayMode` (grid / list / wall) and `sortOrder`. iOS
 * @AppStorage("bp_collectionDisplayMode_v2") + sibling keys parity.
 *
 * Both stored as raw strings so the enums can evolve without
 * breaking saved values. Unknown / missing values fall back to the
 * Composable's default.
 *
 * Tink encryption NOT used here — display preference is non-
 * sensitive (ANDROID-DEV.md §5.7).
 */
@Singleton
class CollectionPrefsStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    private object Keys {
        val DISPLAY_MODE = stringPreferencesKey("display_mode")
        val SORT_ORDER   = stringPreferencesKey("sort_order")
    }

    val displayMode: Flow<String?> =
        context.collectionPrefsDataStore.data.map { it[Keys.DISPLAY_MODE] }

    val sortOrder: Flow<String?> =
        context.collectionPrefsDataStore.data.map { it[Keys.SORT_ORDER] }

    suspend fun setDisplayMode(mode: String) {
        context.collectionPrefsDataStore.edit { it[Keys.DISPLAY_MODE] = mode }
    }

    suspend fun setSortOrder(order: String) {
        context.collectionPrefsDataStore.edit { it[Keys.SORT_ORDER] = order }
    }
}
