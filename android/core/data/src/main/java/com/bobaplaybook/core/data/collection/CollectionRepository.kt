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
 * M2 ships the interface + an in-memory stub. M7 swaps the stub for
 * the real Supabase + Room implementation when Credential Manager
 * lands and we have an authenticated `user_id` to scope queries to.
 *
 * The interface is intentionally compose-friendly — every read returns
 * `Flow<…>` so the ViewModel can `collectAsStateWithLifecycle()`
 * without further plumbing.
 *
 * Schema mirrors iOS `UserCardStore` and the Supabase `user_cards`
 * table — same columns, same designation keys (DECISIONS.md #023).
 */
@Singleton
class CollectionRepository @Inject constructor() {

    private val _ownedCards = MutableStateFlow<List<UserCard>>(emptyList())
    val ownedCards: Flow<List<UserCard>> = _ownedCards.asStateFlow()

    /**
     * Read filtered by designation. UI grids consume this; switching
     * the segmented row swaps the underlying Flow source.
     */
    fun cardsByDesignation(designation: Designation): Flow<List<UserCard>> =
        ownedCards.map { all -> all.filter { it.designation == designation } }

    /**
     * Counts by designation — used by the segmented row's badge dots.
     */
    fun countsByDesignation(): Flow<Map<Designation, Int>> =
        ownedCards.map { all ->
            Designation.entries.associateWith { d ->
                all.count { it.designation == d }
            }
        }

    /**
     * M7 hookup point: replace this stub with the real Supabase query.
     * Until then `ownedCards` is always empty — UI shows the
     * "Sign in to see your collection" empty state.
     */
    fun primeFromRemote(@Suppress("unused") userId: String?) {
        // TODO(M7): supabase-kt postgrest query against user_cards
        //   .filter("user_id" eq userId)
        //   .decodeList<UserCardRow>()
        //   .map(::toDomain)
        //   then write to Room cache + emit through _ownedCards
    }
}
