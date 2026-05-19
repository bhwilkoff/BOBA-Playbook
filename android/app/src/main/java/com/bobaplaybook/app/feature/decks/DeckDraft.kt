package com.bobaplaybook.app.feature.decks

import androidx.compose.runtime.Immutable
import com.bobaplaybook.core.domain.model.Card
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList

/**
 * In-memory deck draft model. Mirrors iOS `DeckBuilderStore.currentDraft`.
 *
 * Persisted to Supabase `decks` + `deck_cards` only when the user
 * signs in and hits Save. v1 keeps the draft purely in-memory; v2
 * adds Room-backed persistence so unsigned-in users don't lose work
 * on app restart.
 */
@Immutable
data class DeckDraft(
    val name: String = "New Deck",
    val cards: ImmutableList<Card> = persistentListOf(),
) {
    /** Section breakdowns matching iOS DeckSummaryPill shape. */
    val heroCount: Int get() = cards.count { isHero(it) }
    val playCount: Int get() = cards.count { isPlay(it) && !isBonus(it) }
    val bonusCount: Int get() = cards.count { isBonus(it) }
    val coachCount: Int get() = cards.count { isCoach(it) }

    val totalCost: Int get() = cards.sumOf { it.cost ?: 0 }
    val totalHD: Int get() = cards.sumOf { it.hd ?: 0 }

    /** Standard construction caps (Comprehensive Rules Guide v1). */
    val heroCap = 8
    val playCap = 30
    val bonusCap = 7
    val hdCap = 10

    val isStandardLegal: Boolean
        get() = heroCount == heroCap &&
                playCount + bonusCount == playCap &&
                bonusCount <= bonusCap &&
                totalHD <= hdCap

    fun adding(card: Card): DeckDraft = copy(cards = (cards + card).toPersistentList())
    fun removing(bobaId: String): DeckDraft =
        copy(cards = cards.filterNot { it.bobaId == bobaId }.toPersistentList())

    private fun isHero(c: Card)  = c.cardType.equals("Hero", ignoreCase = true)
    private fun isPlay(c: Card)  = c.cardType.contains("Play", ignoreCase = true)
    private fun isBonus(c: Card) = c.cardType.contains("Bonus", ignoreCase = true)
    private fun isCoach(c: Card) = c.cardType.contains("Coach", ignoreCase = true)
}
