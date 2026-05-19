package com.bobaplaybook.core.data.collection

import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.domain.model.UserCard
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map

/**
 * Collection repository.
 *
 * v1 ships the interface + an in-memory store. v2 swaps in a real
 * Supabase + Room layer when M7 lands Credential Manager and we have
 * an authenticated `user_id` to scope queries to.
 *
 * Mutations re-emit a NEW list reference (never mutate in place) per
 * iOS lesson [[feedback_derived_arrays_must_rebuild]] — Compose's
 * `collectAsStateWithLifecycle` only fires on reference change.
 */
@Singleton
class CollectionRepository @Inject constructor() {

    private val _ownedCards = MutableStateFlow<List<UserCard>>(emptyList())
    val ownedCards: Flow<List<UserCard>> = _ownedCards.asStateFlow()

    fun cardsByDesignation(designation: Designation): Flow<List<UserCard>> =
        _ownedCards.map { all -> all.filter { it.designation == designation } }

    fun countsByDesignation(): Flow<Map<Designation, Int>> =
        _ownedCards.map { all ->
            Designation.entries.associateWith { d ->
                all.count { it.designation == d }
            }
        }

    /**
     * Add a card to the user's collection at the given designation.
     * If the card+designation pair already exists, increment quantity;
     * else create a new row.
     */
    fun add(cardBobaId: String, designation: Designation, userId: String) {
        _ownedCards.value = _ownedCards.value.let { current ->
            val existing = current.firstOrNull {
                it.cardBobaId == cardBobaId && it.designation == designation && it.userId == userId
            }
            if (existing != null) {
                current.map {
                    if (it.id == existing.id) it.copy(quantity = it.quantity + 1) else it
                }
            } else {
                current + UserCard(
                    id = "${userId}-${cardBobaId}-${designation.key}-${System.currentTimeMillis()}",
                    userId = userId,
                    cardBobaId = cardBobaId,
                    designation = designation,
                )
            }
        }
    }

    fun remove(userCardId: String) {
        _ownedCards.value = _ownedCards.value.filterNot { it.id == userCardId }
    }

    fun updateDesignation(userCardId: String, newDesignation: Designation) {
        _ownedCards.value = _ownedCards.value.map {
            if (it.id == userCardId) it.copy(designation = newDesignation) else it
        }
    }

    /**
     * M7 hookup point: replace this stub with the real Supabase query.
     * Implementation plan (when M7 ships):
     *  - supabase-kt postgrest query against user_cards filtered by
     *    user_id (own-row RLS enforces server-side)
     *  - decode into a typed `UserCardRow` data class
     *  - map to domain UserCard
     *  - persist into Room cache for offline browsing
     *  - emit through _ownedCards on every change
     */
    fun primeFromRemote(@Suppress("unused") userId: String?) {
        // TODO(M7-polish): supabase + room wiring
    }
}
