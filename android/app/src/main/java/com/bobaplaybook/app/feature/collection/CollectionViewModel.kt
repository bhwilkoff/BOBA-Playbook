package com.bobaplaybook.app.feature.collection

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.data.collection.CollectionRepository
import com.bobaplaybook.core.data.decks.DeckRepository
import com.bobaplaybook.core.data.decks.SavedDeck
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.domain.model.UserCard
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Collection ViewModel. Wires:
 *  - [AuthManager.authState] — signed-in vs signed-out shows different
 *    surfaces.
 *  - [CollectionRepository.ownedCards] — owned UserCard rows. v1 is an
 *    in-memory stub; v2 hits Supabase user_cards with own-row RLS.
 *  - [CardRepository.cards] — joins UserCard.cardBobaId → live Card
 *    model so the grid can render thumbnails.
 *
 * UI state combines all three into a single immutable [CollectionUiState].
 */
@HiltViewModel
class CollectionViewModel @Inject constructor(
    private val collectionRepository: CollectionRepository,
    private val cardRepository: CardRepository,
    private val deckRepository: DeckRepository,
    private val authManager: AuthManager,
) : ViewModel() {

    /**
     * Saved decks flow — exposed so the Collection Card Detail screen
     * can render "Decks containing this card." iOS DESIGN.md §8.4
     * surfaces the same list off `SupabaseClient.decksContaining(bobaId:)`.
     *
     * Android's `deck_cards` row stores `card_number` (not `boba_id`)
     * per the supabase_schema.sql, so the filter happens by cardNumber.
     */
    val savedDecks: StateFlow<List<SavedDeck>> = deckRepository.savedDecks
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val catalogCards: StateFlow<List<Card>> = cardRepository.cards
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val uiState: StateFlow<CollectionUiState> = combine(
        collectionRepository.ownedCards,
        cardRepository.cards,
        authManager.authState,
    ) { owned, catalog, auth ->
        val catalogByBobaId = catalog.associateBy { it.bobaId }
        // Fallback index: cardNumber → first Card with that number. The
        // user_cards table has BOTH `card_number` (legacy) and `boba_id`
        // (newer). Rows added before the bobaId migration may have
        // `boba_id = null`, in which case toDomain() falls back to
        // cardNumber as the join key. Lookup-by-bobaId would miss
        // those; lookup-by-cardNumber recovers them. iOS does the
        // same dual-key lookup (CollectionView.swift). Without this
        // fallback, legacy rows silently disappear from the Collection
        // tab — which is the "no cards pulling in" bug.
        val catalogByCardNumber = catalog.groupBy { it.cardNumber }
            .mapValues { (_, cards) -> cards.first() }
        val joined = owned.mapNotNull { uc ->
            val card = catalogByBobaId[uc.cardBobaId]
                ?: catalogByCardNumber[uc.cardBobaId]
            card?.let { CollectionEntry(card = it, userCard = uc) }
        }
        if (owned.isNotEmpty() && joined.size < owned.size) {
            android.util.Log.w(
                "CollectionViewModel",
                "Dropped ${owned.size - joined.size}/${owned.size} owned rows in catalog join " +
                "(catalog has ${catalog.size} cards). Sample missing keys: " +
                owned.mapNotNull { uc ->
                    if (catalogByBobaId[uc.cardBobaId] == null &&
                        catalogByCardNumber[uc.cardBobaId] == null) uc.cardBobaId else null
                }.take(5).joinToString(),
            )
        }
        val byDesignation = Designation.entries.associateWith { d ->
            joined.filter { it.userCard.designation == d }.toPersistentList()
        }
        val totalValue = joined.sumOf { it.userCard.estimatedValue ?: 0.0 }
        CollectionUiState(
            isSignedIn = auth is AuthState.SignedIn,
            entriesByDesignation = byDesignation,
            totalValueUsd = totalValue,
            isLoading = false,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = CollectionUiState(),
    )

    init {
        // Prime catalog so the join lookups work on first emit.
        cardRepository.primeSync()
        cardRepository.primeAsync()
    }

    /**
     * Force a fresh refetch of user_cards from Supabase. Wired to
     * pull-to-refresh on the Collection grid + list.
     */
    fun refreshFromServer() {
        viewModelScope.launch { collectionRepository.refresh() }
    }

    /**
     * Add a card to the user's collection. No-ops when signed out.
     * Repository handles the optimistic update + Supabase insert; UI
     * just hands the bobaId + designation in.
     *
     * Optional fields (quantity / purchase price / asking price /
     * condition / notes) are persisted on the new row — matches the
     * iOS UserCard shape so the AddToCollectionSheet form's rich-data
     * path round-trips. Defaults preserve source-compat for the
     * single-card Quick Add callers (Find tab + scan flow).
     */
    fun add(
        cardBobaId: String,
        designation: Designation,
        quantity: Int = 1,
        purchasePrice: Double? = null,
        askingPrice: Double? = null,
        condition: String? = null,
        notes: String? = null,
    ) {
        viewModelScope.launch {
            val auth = authManager.authState.first()
            val userId = (auth as? AuthState.SignedIn)?.userId ?: return@launch
            collectionRepository.add(
                cardBobaId       = cardBobaId,
                designation      = designation,
                userId           = userId,
                quantity         = quantity,
                purchasePrice    = purchasePrice,
                askingPrice      = askingPrice,
                condition        = condition,
                notes            = notes,
            )
        }
    }

    fun remove(userCardId: String) {
        viewModelScope.launch { collectionRepository.remove(userCardId) }
    }

    fun updateDesignation(userCardId: String, newDesignation: Designation) {
        viewModelScope.launch {
            collectionRepository.updateDesignation(userCardId, newDesignation)
        }
    }

    fun updateEntry(
        userCardId: String,
        purchasePrice: Double?,
        askingPrice: Double?,
        condition: String?,
        notes: String?,
        grade: String? = null,
        gradingCompany: String? = null,
    ) {
        viewModelScope.launch {
            collectionRepository.updateEntryFields(
                userCardId, purchasePrice, askingPrice, condition, notes,
                grade = grade, gradingCompany = gradingCompany,
            )
        }
    }
}

@Immutable
data class CollectionUiState(
    val isSignedIn: Boolean = false,
    val entriesByDesignation: Map<Designation, ImmutableList<CollectionEntry>> =
        Designation.entries.associateWith { persistentListOf() },
    val totalValueUsd: Double = 0.0,
    val isLoading: Boolean = true,
)

/** A single owned card joined with its catalog row for grid rendering. */
@Immutable
data class CollectionEntry(
    val card: Card,
    val userCard: UserCard,
)

enum class DisplayMode { GRID, LIST, WALL }
