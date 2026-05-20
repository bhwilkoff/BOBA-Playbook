package com.bobaplaybook.core.data.collection

import android.util.Log
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.domain.model.UserCard
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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Collection repository.
 *
 * **Read path** (live): observes Supabase `user_cards` rows for the
 * authenticated user. RLS server-side enforces own-row filtering; we
 * just `from("user_cards").select()` and let the policy clip rows.
 * On sign-out the cache clears.
 *
 * **Write path**: add / remove / updateDesignation mutate the local
 * cache immediately (optimistic UI) AND fire the corresponding
 * Supabase upsert / delete / update. Writes that fail surface via the
 * Snackbar pipeline (M7 polish — for now Log only).
 *
 * Mutations re-emit a NEW list reference (never mutate in place) per
 * iOS lesson [[feedback_derived_arrays_must_rebuild]] — Compose's
 * `collectAsStateWithLifecycle` only fires on reference change.
 */
@Singleton
class CollectionRepository @Inject constructor(
    private val supabase: SupabaseClient,
) {

    companion object {
        private const val TAG = "CollectionRepository"
    }

    private val _ownedCards = MutableStateFlow<List<UserCard>>(emptyList())
    val ownedCards: Flow<List<UserCard>> = _ownedCards.asStateFlow()

    // Dedicated repo scope — survives ViewModel teardown so background
    // refreshes finish even if the user backs out of Collection.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        // Listen for auth changes: signed in → refresh; signed out → clear.
        scope.launch {
            supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> refresh()
                    is SessionStatus.NotAuthenticated -> _ownedCards.value = emptyList()
                    is SessionStatus.RefreshFailure   -> _ownedCards.value = emptyList()
                    is SessionStatus.Initializing -> Unit
                }
            }
        }
    }

    fun cardsByDesignation(designation: Designation): Flow<List<UserCard>> =
        _ownedCards.map { all -> all.filter { it.designation == designation } }

    fun countsByDesignation(): Flow<Map<Designation, Int>> =
        _ownedCards.map { all ->
            Designation.entries.associateWith { d ->
                all.count { it.designation == d }
            }
        }

    /**
     * Pull the user's user_cards rows from Supabase. RLS handles the
     * `user_id = auth.uid()` filter server-side.
     */
    suspend fun refresh() {
        runCatching {
            val rows = supabase.postgrest.from("user_cards")
                .select()
                .decodeList<UserCardRow>()
            _ownedCards.value = rows.map { it.toDomain() }
            Log.i(TAG, "Loaded ${rows.size} user_cards rows from Supabase")
        }.onFailure { e ->
            Log.e(TAG, "Failed to fetch user_cards", e)
        }
    }

    /**
     * Add a card to the user's collection at the given designation.
     * If the card+designation pair already exists, increment quantity;
     * else insert a new row.
     */
    suspend fun add(cardBobaId: String, designation: Designation, userId: String) {
        val existing = _ownedCards.value.firstOrNull {
            it.cardBobaId == cardBobaId && it.designation == designation && it.userId == userId
        }
        if (existing != null) {
            updateQuantity(existing.id, existing.quantity + 1)
            return
        }
        // Insert a new row — Supabase generates `id` + `acquired_at`.
        runCatching {
            val cardNumber = cardBobaId.substringBefore('-')
            supabase.postgrest.from("user_cards").insert(
                mapOf(
                    "user_id"     to userId,
                    "card_number" to cardNumber,
                    "boba_id"     to cardBobaId,
                    "designation" to designation.key,
                ),
            )
            refresh()
        }.onFailure { e ->
            Log.e(TAG, "Failed to insert user_card", e)
        }
    }

    suspend fun remove(userCardId: String) {
        // Optimistic — drop from cache first.
        _ownedCards.value = _ownedCards.value.filterNot { it.id == userCardId }
        runCatching {
            supabase.postgrest.from("user_cards")
                .delete { filter { eq("id", userCardId) } }
        }.onFailure { e ->
            Log.e(TAG, "Failed to delete user_card $userCardId", e)
            refresh()  // resync if the optimistic update was wrong
        }
    }

    suspend fun updateDesignation(userCardId: String, newDesignation: Designation) {
        _ownedCards.value = _ownedCards.value.map {
            if (it.id == userCardId) it.copy(designation = newDesignation) else it
        }
        runCatching {
            supabase.postgrest.from("user_cards")
                .update({ set("designation", newDesignation.key) }) {
                    filter { eq("id", userCardId) }
                }
        }.onFailure { e ->
            Log.e(TAG, "Failed to update designation on $userCardId", e)
            refresh()
        }
    }

    /**
     * Patch the editable fields on an existing user_card row.
     * Passing `null` for any column writes NULL (= clear). Mirrors
     * iOS EditCollectionEntrySheet's save path.
     */
    suspend fun updateEntryFields(
        userCardId: String,
        purchasePrice: Double?,
        askingPrice: Double?,
        condition: String?,
        notes: String?,
    ) {
        _ownedCards.value = _ownedCards.value.map {
            if (it.id == userCardId) it.copy(
                purchasePrice = purchasePrice,
                askingPrice = askingPrice,
                notes = notes,
            ) else it
        }
        runCatching {
            supabase.postgrest.from("user_cards")
                .update({
                    set("purchase_price", purchasePrice)
                    set("asking_price", askingPrice)
                    set("condition", condition)
                    set("notes", notes)
                }) {
                    filter { eq("id", userCardId) }
                }
        }.onFailure { e ->
            Log.e(TAG, "Failed to update entry fields on $userCardId", e)
            refresh()
        }
    }

    private suspend fun updateQuantity(userCardId: String, newQuantity: Int) {
        runCatching {
            // The supabase_schema.sql user_cards table doesn't have a
            // quantity column today — quantity is iOS-side semantics
            // expressed as multiple rows. For now keep the local cache
            // bumped but no server-side write.
            _ownedCards.value = _ownedCards.value.map {
                if (it.id == userCardId) it.copy(quantity = newQuantity) else it
            }
        }.onFailure { e ->
            Log.e(TAG, "Failed to bump quantity on $userCardId", e)
        }
    }
}

/**
 * Serializable row shape matching the Supabase `user_cards` table
 * (supabase_schema.sql lines 2-18). `boba_id` is nullable in the
 * legacy schema; when missing we synthesize from `card_number` so
 * the iOS-canonical CollectionEntry join still works.
 */
@Serializable
private data class UserCardRow(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("card_number") val cardNumber: String,
    @SerialName("boba_id") val bobaId: String? = null,
    val designation: String? = null,
    val condition: String? = null,
    val grade: String? = null,
    @SerialName("grading_company") val gradingCompany: String? = null,
    @SerialName("purchase_price") val purchasePrice: Double? = null,
    @SerialName("asking_price") val askingPrice: Double? = null,
    @SerialName("estimated_value") val estimatedValue: Double? = null,
    val notes: String? = null,
) {
    fun toDomain(): UserCard = UserCard(
        id = id,
        userId = userId,
        cardBobaId = bobaId ?: cardNumber,
        designation = designation?.let { Designation.fromKey(it) } ?: Designation.PERSONAL,
        purchasePrice = purchasePrice,
        askingPrice = askingPrice,
        estimatedValue = estimatedValue,
        notes = notes,
    )
}
