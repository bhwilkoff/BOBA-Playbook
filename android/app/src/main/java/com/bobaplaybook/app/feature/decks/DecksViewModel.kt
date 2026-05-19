package com.bobaplaybook.app.feature.decks

import androidx.lifecycle.ViewModel
import com.bobaplaybook.core.domain.model.Card
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

/**
 * Decks ViewModel — thin wrapper over [DeckStore] singleton.
 *
 * The store IS the source of truth; the ViewModel exists only to be
 * the Hilt entry point and to bridge `hiltViewModel()` into Compose.
 */
@HiltViewModel
class DecksViewModel @Inject constructor(
    private val store: DeckStore,
) : ViewModel() {

    val draft: StateFlow<DeckDraft> = store.draft

    fun add(card: Card) = store.add(card)
    fun remove(bobaId: String) = store.remove(bobaId)
    fun rename(name: String) = store.rename(name)
    fun clear() = store.clear()
}
