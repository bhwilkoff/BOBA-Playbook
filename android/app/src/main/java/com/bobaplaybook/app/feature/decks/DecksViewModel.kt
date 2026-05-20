package com.bobaplaybook.app.feature.decks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.auth.AuthState
import com.bobaplaybook.core.data.decks.DeckRepository
import com.bobaplaybook.core.data.decks.SavedDeck
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
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
) : ViewModel() {

    val draft: StateFlow<DeckDraft> = store.draft

    val savedDecks: StateFlow<List<SavedDeck>> = repo.savedDecks
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val authState: StateFlow<AuthState> = authManager.authState

    fun add(card: Card) = store.add(card)
    fun remove(bobaId: String) = store.remove(bobaId)
    fun rename(name: String) = store.rename(name)
    fun setPlayMode(mode: DeckPlayMode) = store.setPlayMode(mode)
    fun clear() = store.clear()

    /** Pull a saved deck into the in-memory draft. Joins via catalog. */
    fun loadSaved(saved: SavedDeck, catalog: List<Card>) =
        store.loadFromSaved(saved, catalog)

    /**
     * Persist the current draft. No-op when signed out — the UI should
     * route the user to sign-in before calling this.
     *
     * Returns true on success so the caller can dismiss the editor.
     */
    fun save(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val userId = (authManager.authState.first() as? AuthState.SignedIn)?.userId
            if (userId == null) {
                onResult(false)
                return@launch
            }
            val draft = store.draft.value
            val cardNumbers = draft.cards.map { it.cardNumber }
            val newId = repo.saveDeck(
                userId = userId,
                name = draft.name,
                cardNumbers = cardNumbers,
            )
            if (newId != null) {
                store.clear()
                onResult(true)
            } else {
                onResult(false)
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
}
