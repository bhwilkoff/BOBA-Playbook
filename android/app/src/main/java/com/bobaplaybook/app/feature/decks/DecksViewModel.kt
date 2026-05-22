package com.bobaplaybook.app.feature.decks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.data.decks.DeckRepository
import com.bobaplaybook.core.data.decks.SavedDeck
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Decks ViewModel — bridges the in-memory [DeckStore] (UI scope) to
 * the [DeckRepository] (Supabase persistence).
 *
 * Save flow:
 *   - User taps Save → save(authedUserId) → repo.saveDeck(...) →
 *     clear draft + invoke onSaved callback
 *   - Signed-out users see the inline `BOBASignInPrompt` and never
 *     reach this path.
 */
@HiltViewModel
class DecksViewModel @Inject constructor(
    private val store: DeckStore,
    private val repo: DeckRepository,
    private val authManager: AuthManager,
    private val cardRepository: CardRepository,
) : ViewModel() {

    val draft: StateFlow<DeckDraft> = store.draft

    val savedDecks: StateFlow<List<SavedDeck>> = repo.savedDecks
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val authState: StateFlow<AuthState> = authManager.authState

    /** Decks-pool search query (DecksScreen pushes here on text change). */
    private val _poolQuery = MutableStateFlow("")
    fun setPoolQuery(q: String) { _poolQuery.value = q }

    /**
     * Catalog loading flag. UI distinguishes "no cards because catalog
     * hasn't finished decoding" (show spinner) from "no cards because
     * the user's search trimmed everything out" (show empty state).
     */
    val isCatalogLoading: StateFlow<Boolean> = cardRepository.isLoading

    /**
     * Decks-specific pool stream. Reads the FULL catalog directly
     * (NOT through FindViewModel — Decks has its own filter pipeline
     * per iOS DecksView.filteredPoolCards).
     *
     *  • Sealed Products excluded — the deck builder builds player decks.
     *  • Free-text search filters by hero / name / cardNumber / element / treatment.
     *  • Sort: image-first, then Heroes by power desc, Plays by cost asc,
     *    then by cardType for the remainder. Matches DecksView.swift L1363-1375.
     *
     * Catalog priming runs in init so the stream produces results
     * even when the user lands on Decks before tapping Find.
     */
    val poolCards: StateFlow<List<Card>> = combine(
        cardRepository.cards,
        cardRepository.isLoading,
        _poolQuery,
    ) { catalog, isLoading, query ->
        // Wait for Phase 2 to finish before emitting cards. The
        // catalog loads in two phases: Phase 1 = 500 head bundle
        // (synchronous), Phase 2 = full 17,915 cards (background).
        // Without this gate, the user saw the Phase 1 head bundle
        // for a beat (wrong sort, missing 95% of the catalog) and
        // then the pool snapped to the correct full list — Ben's
        // "starts with a specific set of cards and then reloads
        // with the correct set" complaint. CardPoolGrid renders a
        // spinner on empty + isLoading so the screen is honest
        // about waiting instead of showing a partial answer.
        if (isLoading || catalog.isEmpty()) return@combine emptyList()
        val q = query.trim().lowercase()
        val filtered = catalog.asSequence()
            .filter { card -> card.cardType != "Sealed Product" }
            .filter { card ->
                if (q.isEmpty()) return@filter true
                card.hero.lowercase().contains(q) ||
                card.name.lowercase().contains(q) ||
                card.cardNumber.lowercase().contains(q) ||
                card.element.lowercase().contains(q) ||
                (card.treatment ?: "").lowercase().contains(q)
            }
            .toList()
        filtered.sortedWith(
            compareByDescending<Card> { !it.imageFile.isNullOrEmpty() }
                .then(Comparator { a, b ->
                    when {
                        a.cardType == "Hero" && b.cardType == "Hero" ->
                            (b.power ?: 0).compareTo(a.power ?: 0)
                        a.cardType == "Play" && b.cardType == "Play" ->
                            (a.cost ?: 0).compareTo(b.cost ?: 0)
                        else -> a.cardType.compareTo(b.cardType)
                    }
                })
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    init {
        // Prime the catalog so the pool fills even when the user lands
        // on Decks before they've opened Find. primeSync sets the head
        // bundle (~500 cards) synchronously; primeAsync swaps in the
        // full 17k-card catalog from a background dispatcher.
        cardRepository.primeSync()
        cardRepository.primeAsync()
    }

    fun add(card: Card) = store.add(card)
    fun remove(bobaId: String) = store.remove(bobaId)
    fun rename(name: String) = store.rename(name)
    fun setPlayMode(mode: DeckPlayMode) = store.setPlayMode(mode)
    fun clear() = store.clear()
    /** Replace the in-memory draft with a previously-captured snapshot.
     * Wired by the Clear-deck Undo Snackbar (tick 139). */
    fun restoreDraft(snapshot: DeckDraft) = store.restoreDraft(snapshot)

    /** Pull a saved deck into the in-memory draft. Joins via catalog. */
    fun loadSaved(saved: SavedDeck, catalog: List<Card>) =
        store.loadFromSaved(saved, catalog)

    /**
     * Save with a richer error result. `null` = success; otherwise a
     * user-facing message explaining why save failed. The blanket
     * "Couldn't save deck. Check connectivity." snackbar was misleading
     * when the actual cause was sign-out or empty-name — this surface
     * disambiguates so the user knows what to fix.
     */
    fun save(onComplete: (errorMessage: String?) -> Unit) {
        viewModelScope.launch {
            val userId = (authManager.authState.first() as? AuthState.SignedIn)?.userId
            if (userId == null) {
                onComplete("Sign in to save your deck.")
                return@launch
            }
            val draft = store.draft.value
            // Reject empty / whitespace-only names — Supabase column is
            // non-nullable but accepts "" silently; saving "" produces
            // an un-findable deck in Manage / AddToDeck.
            val cleanName = draft.name.trim()
            if (cleanName.isEmpty()) {
                onComplete("Give your deck a name before saving.")
                return@launch
            }
            if (draft.cards.isEmpty()) {
                onComplete("Add at least one card before saving.")
                return@launch
            }
            val cardNumbers = draft.cards.map { it.cardNumber }
            val newId = repo.saveDeck(
                userId = userId,
                name = cleanName,
                cardNumbers = cardNumbers,
            )
            if (newId != null) {
                store.clear()
                onComplete(null)
            } else {
                onComplete("Couldn't save. Check connectivity and try again.")
            }
        }
    }

    fun renameSavedDeck(deckId: String, newName: String) {
        viewModelScope.launch { repo.renameDeck(deckId, newName) }
    }

    /** Force a refetch of saved decks from Supabase. Pull-to-refresh hook. */
    fun refreshSavedDecks() {
        viewModelScope.launch { repo.refresh() }
    }

    fun deleteDeck(deckId: String) {
        viewModelScope.launch { repo.deleteDeck(deckId) }
    }

    /// Restore a just-deleted saved deck (Undo path from the Manage
    /// Decks delete Snackbar — tick 124). Bypasses the draft-state
    /// path used by `save(...)`; calls repo.saveDeck directly with
    /// the captured SavedDeck's data. Returns the NEW deck id (not
    /// the captured original — Supabase issues a fresh UUID on insert).
    fun restoreDeletedDeck(saved: com.bobaplaybook.core.data.decks.SavedDeck, onResult: (String?) -> Unit) {
        viewModelScope.launch {
            val auth = authManager.authState.first()
            val userId = (auth as? AuthState.SignedIn)?.userId ?: run { onResult(null); return@launch }
            // Expand the SavedDeck's quantity-rows back into a flat
            // cardNumber list. saveDeck takes a flat list (one entry
            // per copy) — quantities are inferred server-side.
            val flatCardNumbers = buildList {
                saved.cards.forEach { row ->
                    repeat(row.quantity) { add(row.cardNumber) }
                }
            }
            val newId = repo.saveDeck(
                userId = userId,
                name = saved.name,
                cardNumbers = flatCardNumbers,
            )
            onResult(newId)
        }
    }
}
