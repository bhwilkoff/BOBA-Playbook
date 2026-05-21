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

    /// Add a card to the draft. Returns a structured outcome the
    /// caller uses to surface "added" vs "couldn't add — reason"
    /// feedback. Parity with iOS tick 112 + web tick 113 — Android was
    /// fully permissive before this, letting users add 8 copies of the
    /// same Hero or push the bonus-play count past the 7-card cap.
    /// The DeckDraft caps + the duplicate check live here so every
    /// caller (long-press, AddToDeckSheet, scan-into-deck) gets the
    /// same enforcement + feedback shape.
    fun add(card: Card): AddResult {
        val current = _draft.value
        val isHero  = card.cardType.equals("Hero", ignoreCase = true)
        val isBonus = card.cardType.contains("Play", ignoreCase = true) &&
                      (card.cardNumber.startsWith("BPL") || card.treatment == "Bonus Plays")
        val isPlay  = card.cardType.contains("Play", ignoreCase = true) && !isBonus
        val isCoach = card.cardType.contains("Coach", ignoreCase = true)
        val alreadyIn = current.cards.any { it.bobaId == card.bobaId }

        // Heroes + Plays + Coaches can only appear once per deck;
        // bonus plays + hot dogs can repeat up to the cap.
        if ((isHero || isPlay || isCoach) && alreadyIn) {
            return AddResult.Skipped("already in deck")
        }
        if (isHero && current.heroCount >= current.heroCap) {
            return AddResult.Skipped("hero cap reached (${current.heroCap})")
        }
        if (isPlay && current.playCount + current.bonusCount >= current.playCap) {
            return AddResult.Skipped("plays full (${current.playCap})")
        }
        if (isBonus && current.bonusCount >= current.bonusCap) {
            return AddResult.Skipped("bonus plays full (${current.bonusCap})")
        }
        _draft.value = current.adding(card)
        return AddResult.Added
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

    /// Structured outcome returned by [add]. Mirrors the iOS
    /// addCardToDeck no-add reason set (DecksView.swift) so feedback
    /// strings stay cross-platform consistent.
    sealed class AddResult {
        object Added : AddResult()
        data class Skipped(val reason: String) : AddResult()
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
