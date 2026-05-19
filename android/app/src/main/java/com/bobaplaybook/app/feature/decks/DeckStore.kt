package com.bobaplaybook.app.feature.decks

import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.scopes.ViewModelScoped
import javax.inject.Inject
import javax.inject.Singleton
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

    fun clear() {
        _draft.value = DeckDraft()
    }
}
