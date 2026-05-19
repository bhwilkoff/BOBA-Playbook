package com.bobaplaybook.app.feature.scan

import com.bobaplaybook.core.domain.model.Card

/**
 * Card-number regex — VERBATIM from iOS DECISIONS.md #012.
 *
 *   #?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)
 *
 * Matches the printed card-number on every BoBA card. The bare-suffix
 * branch (`-` or `/` then digits) covers serialized inserts like
 * `BL-IRT-25/50` (Inspired Ink).
 *
 * Kotlin's `Regex` uses identical PCRE semantics to Swift's
 * NSRegularExpression / Vision text matching, so this regex is a
 * drop-in port. Don't deviate without coordinating with iOS.
 */
private val CARD_NUMBER_REGEX =
    Regex("""#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)""")

/**
 * Pure-Kotlin card-number → catalog match. ML Kit pipeline feeds
 * recognized text blocks into this function; UI consumes the result.
 *
 * Mirrors iOS `ScanMatching.resolve(observation:allCards:)` —
 * DECISIONS.md #035 — but simplified for M3:
 *  - Card-number regex against ML Kit text lines
 *  - First confident hit wins
 *  - Hero-name veto + image-fingerprint scoring deferred to v2
 *
 * That's the M3 acceptance — DECISIONS.md #043 explicitly defers
 * fingerprint matching post-v1. Single-card live scan with the
 * confident-cardNumber path shipped for months on iOS and is
 * sufficient for v1.
 */
class ScanCardMatcher(private val catalog: () -> List<Card>) {

    fun match(textLines: List<String>): Card? {
        val candidateCardNumbers = textLines
            .asSequence()
            .flatMap { line -> CARD_NUMBER_REGEX.findAll(line) }
            .map { it.groupValues[1] }
            .toList()

        if (candidateCardNumbers.isEmpty()) return null

        val all = catalog()
        for (number in candidateCardNumbers) {
            val hit = all.firstOrNull { it.cardNumber.equals(number, ignoreCase = true) }
            if (hit != null) return hit
        }
        return null
    }
}
