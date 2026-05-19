package com.bobaplaybook.core.domain.model

/**
 * User-built deck. Mirrors iOS `Deck` + Supabase `decks` /
 * `deck_cards` (DECISIONS.md #021).
 *
 * Format string ("rookie" / "substitution" / "playmaker") matches the
 * iOS Picker keys exactly — DON'T rename without coordinating with
 * iOS / web. Cross-platform string stability.
 */
data class Deck(
    val id: String,
    val userId: String,
    val name: String,
    val format: String = "playmaker",
    val cards: List<DeckCard> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

data class DeckCard(
    val deckId: String,
    val cardBobaId: String,
    val slot: DeckSlot,
    val quantity: Int = 1,
)

enum class DeckSlot(val key: String, val label: String) {
    HERO  ("hero",  "Heroes"),
    PLAY  ("play",  "Plays"),
    BONUS ("bonus", "Bonus Plays"),
    HOTDOG("hotdog","Hot Dogs"),
}
