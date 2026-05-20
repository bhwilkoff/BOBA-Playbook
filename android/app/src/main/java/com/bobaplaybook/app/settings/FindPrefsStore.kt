package com.bobaplaybook.app.settings

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.findPrefsDataStore by preferencesDataStore(name = "find_prefs")

/**
 * Persistent Find-tab preferences across app launches —
 * showcase-mode (shelf gallery vs raw grid) + quick-add. iOS
 * @AppStorage("bp_findShowcaseMode_v1") parity.
 *
 * Tink encryption NOT used — non-sensitive (ANDROID-DEV.md §5.7).
 */
@Singleton
class FindPrefsStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    private object Keys {
        val SHOWCASE_MODE = booleanPreferencesKey("showcase_mode")
        val QUICK_ADD    = booleanPreferencesKey("quick_add")
    }

    val showcaseMode: Flow<Boolean> =
        context.findPrefsDataStore.data.map { it[Keys.SHOWCASE_MODE] ?: true }

    val quickAdd: Flow<Boolean> =
        context.findPrefsDataStore.data.map { it[Keys.QUICK_ADD] ?: false }

    suspend fun setShowcaseMode(enabled: Boolean) {
        context.findPrefsDataStore.edit { it[Keys.SHOWCASE_MODE] = enabled }
    }

    suspend fun setQuickAdd(enabled: Boolean) {
        context.findPrefsDataStore.edit { it[Keys.QUICK_ADD] = enabled }
    }
}
