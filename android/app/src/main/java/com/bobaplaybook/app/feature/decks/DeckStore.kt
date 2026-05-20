package com.bobaplaybook.app.feature.decks

import com.bobaplaybook.core.data.decks.SavedDeck
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.scopes.ViewModelScoped
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * App-scoped deck draft singleton. Mirrors iOS `DeckBuilderStore` for
 * the in-memory draft layer.
 *
 * Singleton so the Decks tab's pool screen, the editor sheet (which
 * may be in a separate Composable scope), and any future scan-into-
 * deck flow all read/write the same draft.
 */
@Singleton
class DeckStore @Inject constructor() {

    private val _draft = MutableStateFlow(DeckDraft())
    val draft: StateFlow<DeckDraft> = _draft.asStateFlow()

    fun add(card: Card) {
        _draft.value = _draft.value.adding(card)
    }

    fun remove(bobaId: String) {
        _draft.value = _draft.value.removing(bobaId)
    }

    fun rename(name: String) {
        _draft.value = _draft.value.copy(name = name)
    }

    fun setPlayMode(mode: DeckPlayMode) {
        _draft.value = _draft.value.copy(playMode = mode)
    }

    fun clear() {
        _draft.value = DeckDraft()
    }

    /**
     * Replace the current draft with a saved deck — used by
     * AddToDeckSheet's "open saved deck" path and by DeckManageScreen.
     *
     * The saved deck stores card_number + quantity rows; we expand
     * them by joining against the in-memory catalog. Cards not found
     * in the catalog (legacy decks pointing at retired cards) are
     * silently skipped.
     */
    fun loadFromSaved(saved: SavedDeck, catalog: List<Card>) {
        val byCardNumber = catalog.associateBy { it.cardNumber }
        val expanded = buildList {
            saved.cards.forEach { row ->
                val card = byCardNumber[row.cardNumber] ?: return@forEach
                repeat(row.quantity) { add(card) }
            }
        }.toPersistentList()
        _draft.value = DeckDraft(name = saved.name, cards = expanded)
    }
}
