package com.bobaplaybook.core.data.decks

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
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
 * Decks repository — owns the read/write contract against the Supabase
 * `decks` + `deck_cards` tables (supabase_schema.sql).
 *
 * The in-memory draft lives in `DeckStore` (UI module) for fast edits.
 * This repo is invoked by `Save` to persist the draft, and on auth
 * change to hydrate `savedDecks` from Supabase.
 *
 * Pattern matches CollectionRepository:
 *  - Auth-aware: refreshes on Authenticated; clears on NotAuthenticated
 *  - Optimistic save: append to local cache before the server round-trip
 *  - Write failures log; full resync on next refresh()
 *
 * `deck_cards` schema stores `card_number` + `quantity` only — no
 * `boba_id`. We collapse duplicates from the draft into quantity rows.
 */
@Singleton
class DeckRepository @Inject constructor(
    private val supabase: SupabaseClient,
) {

    companion object { private const val TAG = "DeckRepository" }

    private val _savedDecks = MutableStateFlow<List<SavedDeck>>(emptyList())
    val savedDecks: Flow<List<SavedDeck>> = _savedDecks.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch {
            supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated   -> refresh()
                    is SessionStatus.NotAuthenticated -> _savedDecks.value = emptyList()
                    is SessionStatus.RefreshFailure   -> _savedDecks.value = emptyList()
                    is SessionStatus.Initializing    -> Unit
                }
            }
        }
    }

    suspend fun refresh() {
        runCatching {
            val decks = supabase.postgrest.from("decks")
                .select(Columns.list("id, name, description, archetype, is_public, created_at, updated_at"))
                .decodeList<DeckRow>()
            val ids = decks.map { it.id }
            val cardRows = if (ids.isEmpty()) emptyList() else {
                supabase.postgrest.from("deck_cards")
                    .select { filter { isIn("deck_id", ids) } }
                    .decodeList<DeckCardRow>()
            }
            val byDeck = cardRows.groupBy { it.deckId }
            _savedDecks.value = decks.map { row ->
                SavedDeck(
                    id = row.id,
                    name = row.name,
                    description = row.description,
                    archetype = row.archetype,
                    isPublic = row.isPublic ?: false,
                    cards = byDeck[row.id].orEmpty().map { SavedDeckCard(it.cardNumber, it.quantity ?: 1) },
                )
            }
            Log.i(TAG, "Loaded ${decks.size} decks (${cardRows.size} card rows) from Supabase")
        }.onFailure { e ->
            Log.e(TAG, "Failed to fetch decks", e)
        }
    }

    /**
     * Persist a draft. New draft → INSERT decks row + deck_cards rows.
     * Returns the new deck id, or null on failure.
     */
    suspend fun saveDeck(
        userId: String,
        name: String,
        cardNumbers: List<String>,
        description: String? = null,
        archetype: String? = null,
    ): String? {
        return runCatching {
            // Insert the parent deck row, asking for the generated id back.
            val inserted = supabase.postgrest.from("decks").insert(
                mapOf(
                    "user_id"     to userId,
                    "name"        to name,
                    "description" to description,
                    "archetype"   to archetype,
                ),
            ) { select() }.decodeSingle<DeckRow>()

            // Collapse the flat card list into card_number + quantity rows.
            val counts = cardNumbers.groupingBy { it }.eachCount()
            if (counts.isNotEmpty()) {
                supabase.postgrest.from("deck_cards").insert(
                    counts.map { (number, qty) ->
                        mapOf(
                            "deck_id"     to inserted.id,
                            "card_number" to number,
                            "quantity"    to qty,
                        )
                    },
                )
            }

            // Optimistic local append; full refresh next auth tick or screen open.
            _savedDecks.value = _savedDecks.value + SavedDeck(
                id = inserted.id,
                name = inserted.name,
                description = inserted.description,
                archetype = inserted.archetype,
                isPublic = inserted.isPublic ?: false,
                cards = counts.map { (number, qty) -> SavedDeckCard(number, qty) },
            )
            inserted.id
        }.onFailure { e ->
            Log.e(TAG, "Failed to save deck", e)
        }.getOrNull()
    }

    suspend fun deleteDeck(deckId: String) {
        _savedDecks.value = _savedDecks.value.filterNot { it.id == deckId }
        runCatching {
            supabase.postgrest.from("decks").delete { filter { eq("id", deckId) } }
        }.onFailure { e ->
            Log.e(TAG, "Failed to delete deck $deckId", e)
            refresh()
        }
    }
}

/** UI-facing saved deck model. */
data class SavedDeck(
    val id: String,
    val name: String,
    val description: String?,
    val archetype: String?,
    val isPublic: Boolean,
    val cards: List<SavedDeckCard>,
)

data class SavedDeckCard(val cardNumber: String, val quantity: Int)

// ────────────────────────────────────────────────────────────────
// Supabase row shapes — supabase_schema.sql lines 21-37
// ────────────────────────────────────────────────────────────────

@Serializable
private data class DeckRow(
    val id: String,
    val name: String,
    val description: String? = null,
    val archetype: String? = null,
    @SerialName("is_public") val isPublic: Boolean? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

@Serializable
private data class DeckCardRow(
    @SerialName("deck_id") val deckId: String,
    @SerialName("card_number") val cardNumber: String,
    val quantity: Int? = null,
)
