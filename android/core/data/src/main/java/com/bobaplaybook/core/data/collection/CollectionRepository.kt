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
    /**
     * StateFlow (not bare Flow) so callers — most importantly the
     * `recalculateAll` loop in [CollectionViewModel] — can take a
     * one-shot `.value` snapshot without spinning up a collector.
     */
    val ownedCards: kotlinx.coroutines.flow.StateFlow<List<UserCard>> = _ownedCards.asStateFlow()

    /** Flips true after the first refresh() completes (success or
     *  failure). The Collection UI uses this to distinguish
     *  "haven't asked Supabase yet" from "asked, got 0 rows" — the
     *  former should show a spinner, the latter the empty state.
     *  Without this, the empty-state "No personal cards yet" copy
     *  flashes momentarily on every Collection-tab open before the
     *  refresh round-trip completes. */
    private val _hasRefreshedOnce = MutableStateFlow(false)
    val hasRefreshedOnce: Flow<Boolean> = _hasRefreshedOnce.asStateFlow()

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
        // Always flip — even on failure — so the UI stops spinning and
        // shows the empty / error state rather than spinning forever.
        _hasRefreshedOnce.value = true
    }

    /**
     * Add a card to the user's collection at the given designation.
     * If the card+designation pair already exists, increment quantity;
     * else insert a new row.
     *
     * Optional fields (purchase price / asking price / condition / notes /
     * starting quantity) are persisted on the new row when supplied —
     * matches the iOS shape so the AddToCollection form's rich-data path
     * actually round-trips. Previously these were silently discarded.
     */
    suspend fun add(
        cardBobaId: String,
        cardNumber: String,
        designation: Designation,
        userId: String,
        quantity: Int = 1,
        purchasePrice: Double? = null,
        askingPrice: Double? = null,
        condition: String? = null,
        notes: String? = null,
    ) {
        // Multi-copy semantics live as multiple ROWS in user_cards
        // (iOS pattern — each row is one physical copy). The prior
        // "increment local quantity" early-exit was wrong: it never
        // wrote to Supabase, so Quick-Add the same card twice
        // silently no-op'd server-side and the local quantity bump
        // disappeared on refresh. Ben's 2026-05-22 "quick add doesn't
        // add the cards correctly" report traces here.
        //
        // Now always insert a new row. The catalog JOIN in
        // CollectionViewModel collapses multiple-rows-same-bobaId to
        // one cell with the right quantity in the list view (×N
        // pill); the row count itself reflects the physical-copy
        // count the user sees on iOS.
        runCatching {
            // CardNumber resolves from the catalog (passed in by the
            // ViewModel), not by parsing the bobaId. Base-Set
            // cardNumbers are bare digits ("1", "87"); treatment
            // cardNumbers have one internal hyphen ("BF-217", "RAD-1").
            // bobaId is `{cardNumber}-{hero}-{treatment}-{variation}-{element}` (v3)
            // — the hero/treatment/variation themselves can contain
            // dashes, so reverse-parsing the bobaId for cardNumber
            // is ambiguous. The ViewModel has the Card object in scope
            // and passes the cardNumber explicitly.
            val effectiveCardNumber = cardNumber.ifEmpty { cardBobaId.substringBefore('-') }
            // supabase-kt can't serialize Map<String, Any?> (the prior
            // `buildMap<String, Any?>` shape) — its KotlinXSerializer
            // throws "Serializer for class 'Any' is not found". The
            // canonical insert payload type is JsonObject; supabase-kt
            // handles those directly.
            val payload = kotlinx.serialization.json.buildJsonObject {
                put("user_id", kotlinx.serialization.json.JsonPrimitive(userId))
                put("card_number", kotlinx.serialization.json.JsonPrimitive(effectiveCardNumber))
                put("boba_id", kotlinx.serialization.json.JsonPrimitive(cardBobaId))
                put("designation", kotlinx.serialization.json.JsonPrimitive(designation.key))
                purchasePrice?.let { put("purchase_price", kotlinx.serialization.json.JsonPrimitive(it)) }
                askingPrice?.let   { put("asking_price",   kotlinx.serialization.json.JsonPrimitive(it)) }
                condition?.takeIf { it.isNotBlank() }?.let { put("condition", kotlinx.serialization.json.JsonPrimitive(it)) }
                notes?.takeIf     { it.isNotBlank() }?.let { put("notes",     kotlinx.serialization.json.JsonPrimitive(it)) }
            }
            Log.i(TAG, "Inserting user_card: bobaId=$cardBobaId cardNumber=$cardNumber userId=$userId designation=${designation.key}")
            supabase.postgrest.from("user_cards").insert(payload)
            Log.i(TAG, "Insert OK; refreshing")
            refresh()
        }.onFailure { e ->
            Log.e(TAG, "Failed to insert user_card (bobaId=$cardBobaId): ${e.javaClass.simpleName}: ${e.message}", e)
        }
    }

    /**
     * Stamp a fresh `estimated_value` + `last_price_check` on every
     * user_cards row matching `bobaId`. Used by the Collection's
     * "Refresh market values" recompute loop (parity with iOS
     * `CollectionStore.fetchAndStorePricing`). Keying on bobaId — NOT
     * cardNumber — keeps weapon-variant siblings (DECISIONS.md #057)
     * on distinct pricing tracks; pre-fix the loop wrote one variant's
     * pricing to every same-cardNumber sibling.
     *
     * Optimistically updates the in-memory cache so the value-summary
     * reflects the new number before the next `refresh()` round-trip.
     */
    suspend fun updateEstimatedValue(bobaId: String, value: Double) {
        val nowIso = java.time.Instant.now().toString()
        // Optimistic local update — write to every cached row matching
        // this bobaId. Per [[feedback_derived_arrays_must_rebuild]] we
        // emit a new list reference so Compose recomposes.
        _ownedCards.value = _ownedCards.value.map { uc ->
            if (uc.cardBobaId == bobaId) uc.copy(estimatedValue = value) else uc
        }
        runCatching {
            supabase.postgrest.from("user_cards")
                .update(
                    {
                        set("estimated_value", value)
                        set("last_price_check", nowIso)
                    },
                ) {
                    filter { eq("boba_id", bobaId) }
                }
        }.onFailure { e ->
            Log.w(
                TAG,
                "updateEstimatedValue($bobaId, $value) failed: ${e.javaClass.simpleName}: ${e.message}",
            )
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
        // Tick 256 — grade + gradingCompany now editable post-create.
        // AddToCollection captured them since the sheet shipped; the
        // edit flow couldn't change them. Forward-compatible defaults
        // so callers that don't care leave both untouched.
        grade: String? = null,
        gradingCompany: String? = null,
    ) {
        _ownedCards.value = _ownedCards.value.map {
            if (it.id == userCardId) it.copy(
                purchasePrice = purchasePrice,
                askingPrice = askingPrice,
                condition = condition,
                grade = grade,
                gradingCompany = gradingCompany,
                notes = notes,
            ) else it
        }
        runCatching {
            supabase.postgrest.from("user_cards")
                .update({
                    set("purchase_price", purchasePrice)
                    set("asking_price", askingPrice)
                    set("condition", condition)
                    set("grade", grade)
                    set("grading_company", gradingCompany)
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
    @SerialName("acquired_at") val acquiredAt: String? = null,
) {
    fun toDomain(): UserCard = UserCard(
        id = id,
        userId = userId,
        cardBobaId = bobaId ?: cardNumber,
        designation = designation?.let { Designation.fromKey(it) } ?: Designation.PERSONAL,
        purchasePrice = purchasePrice,
        askingPrice = askingPrice,
        estimatedValue = estimatedValue,
        condition = condition,
        grade = grade,                       // tick 239 — was dropped
        gradingCompany = gradingCompany,     // tick 239 — was dropped
        notes = notes,
        acquiredAtIso = acquiredAt,
    )
}
