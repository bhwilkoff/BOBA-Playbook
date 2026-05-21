package com.bobaplaybook.core.data.shows

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
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

/**
 * Shows repository — owns the read contract against the Supabase
 * `shows` table for streamer-role users. iOS counterpart:
 * SupabaseClient.fetchShows() at /rest/v1/shows.
 *
 * Tick 201 — landed the list path. Per-show CRUD (createShow,
 * addCardsToShow, generateWall) + the ShowDetailView equivalent
 * are M2 polish, deferred. The skeleton here keeps the
 * sessionStatus-aware refresh pattern matching DeckRepository +
 * CollectionRepository so future polish has the right shape.
 */
@Singleton
class ShowRepository @Inject constructor(
    private val supabase: SupabaseClient,
) {
    companion object { private const val TAG = "ShowRepository" }

    private val _shows = MutableStateFlow<List<Show>>(emptyList())
    val shows: Flow<List<Show>> = _shows.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch {
            supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated    -> refresh()
                    is SessionStatus.NotAuthenticated -> _shows.value = emptyList()
                    is SessionStatus.RefreshFailure   -> _shows.value = emptyList()
                    is SessionStatus.Initializing     -> Unit
                }
            }
        }
    }

    suspend fun refresh() {
        runCatching {
            val rows = supabase.postgrest.from("shows")
                .select(Columns.list("id, name, created_at, updated_at")) {
                    order(column = "updated_at", order = Order.DESCENDING)
                }
                .decodeList<ShowRow>()
            _shows.value = rows.map {
                Show(id = it.id, name = it.name, createdAt = it.createdAt, updatedAt = it.updatedAt)
            }
            Log.i(TAG, "Loaded ${rows.size} shows from Supabase")
        }.onFailure { e ->
            Log.e(TAG, "Failed to fetch shows", e)
        }
    }
}

data class Show(
    val id: String,
    val name: String,
    val createdAt: String?,
    val updatedAt: String?,
)

@Serializable
private data class ShowRow(
    val id: String,
    val name: String,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)
