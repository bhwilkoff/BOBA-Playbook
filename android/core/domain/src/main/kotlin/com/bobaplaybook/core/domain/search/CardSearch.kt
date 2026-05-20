package com.bobaplaybook.core.domain.search

import com.bobaplaybook.core.domain.model.Card

/**
 * Word-prefix search helpers. Used by Find filter + Collection +
 * Deck pool searches so every card-search surface behaves the same:
 * "amon" finds Amon-Ra but NOT Johnny Damon. iOS parity — see
 * memory `feedback_search_word_prefix` + iOS CardStore CardSearch.
 *
 * The key constraint: NEVER use raw String.contains() for card
 * search. A search for "amon" must match the word "Amon-Ra" (which
 * starts with "amon") but not "Damon" (where "amon" is a midpoint
 * substring) — substring matching ships false positives like
 * "Johnny Damon" surfacing on the "Amon-Ra" query.
 */
object CardSearch {

    /** Split a string on non-alphanumerics + lowercase. */
    fun wordSplit(s: String): List<String> =
        s.lowercase()
            .split(NON_ALNUM)
            .filter { it.isNotEmpty() }

    /** Build the full searchable word set for a card (Find tab). */
    fun haystackWords(card: Card): List<String> {
        val words = mutableListOf<String>()
        words += wordSplit(card.name)
        words += wordSplit(card.cardNumber)
        words += wordSplit(card.hero)
        words += wordSplit(card.element)
        words += wordSplit(card.set)
        card.athleteInspiration?.let { words += wordSplit(it) }
        card.treatment?.let { words += wordSplit(it) }
        card.subSet?.let { words += wordSplit(it) }
        card.variation?.let { words += wordSplit(it) }
        return words
    }

    /**
     * True when every word in [query] is a prefix of at least one
     * word in [haystack]. Empty query matches everything.
     */
    fun matches(query: String, haystack: List<String>): Boolean {
        val qWords = wordSplit(query)
        if (qWords.isEmpty()) return true
        return qWords.all { q ->
            haystack.any { it.startsWith(q) }
        }
    }

    /** Match against a card's full searchable surface (Find tab). */
    fun matches(query: String, card: Card): Boolean =
        matches(query, haystackWords(card))

    /** Match against an arbitrary scoped list of fields (Collection / Decks). */
    fun matchesFields(query: String, fields: List<String?>): Boolean {
        val words = mutableListOf<String>()
        fields.forEach { f -> f?.let { words += wordSplit(it) } }
        return matches(query, words)
    }

    private val NON_ALNUM = Regex("[^a-z0-9]+", RegexOption.IGNORE_CASE)
}
