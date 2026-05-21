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
    /** Replace the in-memory draft with a previously-captured snapshot.
     * Wired by the Clear-deck Undo Snackbar (tick 139). */
    fun restoreDraft(snapshot: DeckDraft) = store.restoreDraft(snapshot)

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
        save(onComplete = { reason: String? -> onResult(reason == null) })
    }

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
