package com.bobaplaybook.core.domain.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Domain-model smoke tests. These run via `./gradlew :core:domain:test`
 * — pure JVM tests, no Android dependencies, fast.
 *
 * Confirms:
 *  1. The Card data class decodes a representative JSON payload using
 *     the same lenient Json config the catalog loader uses.
 *  2. `bobaId` matches the iOS `scripts/boba_id.py` formula.
 */
class CardTest {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        coerceInputValues = true
        isLenient = true
    }

    @Test
    fun `bobaId formula matches v3 — heroed card`() {
        val card = Card(
            cardNumber = "1",
            name = "Maverick",
            hero = "Maverick",
            cardType = "Hero",
            element = "FIRE",
            set = "Base Set",
            treatment = "Base Set",
            variation = "First Edition",
        )
        // v3 (DECISIONS.md #057): cardNumber-hero-treatment-variation-element
        assertEquals("1-Maverick-Base Set-First Edition-FIRE", card.bobaId)
    }

    @Test
    fun `bobaId formula matches v3 — sealed product falls back to name`() {
        val card = Card(
            cardNumber = "BOX-1",
            name = "Booster Box",
            hero = "",
            cardType = "Sealed Product",
            element = "NONE",
            set = "Base Set",
        )
        // Sealed products use name when hero is empty; element NONE
        // still occupies the 5th slot for stability.
        assertEquals("BOX-1-Booster Box---NONE", card.bobaId)
    }

    @Test
    fun `trailing dashes are stable when treatment + variation are null`() {
        val card = Card(
            cardNumber = "42",
            name = "Showtime",
            hero = "Showtime",
            cardType = "Hero",
            element = "ICE",
            set = "Base Set",
            treatment = null,
            variation = null,
        )
        // Two trailing dashes from empty treatment + variation, then -ICE
        assertEquals("42-Showtime---ICE", card.bobaId)
    }

    @Test
    fun `decoder tolerates unknown keys in catalog JSON`() {
        val raw = """
            {
              "cardNumber": "1",
              "name": "Maverick",
              "hero": "Maverick",
              "cardType": "Hero",
              "element": "FIRE",
              "set": "Base Set",
              "futureFieldThatDoesntExistYet": "ignored gracefully"
            }
        """.trimIndent()
        val card = json.decodeFromString<Card>(raw)
        assertEquals("Maverick", card.hero)
        assertEquals("FIRE", card.element)
    }

    @Test
    fun `displayName falls back to name for sealed products`() {
        val sealed = Card(
            cardNumber = "BOX-1",
            name = "Booster Box",
            hero = "",
            cardType = "Sealed Product",
            element = "NONE",
            set = "Base Set",
        )
        assertEquals("Booster Box", sealed.displayName)
        assertTrue(sealed.isSealed)
    }

    @Test
    fun `displayName uses hero for normal cards`() {
        val heroed = Card(
            cardNumber = "1",
            name = "Maverick #1",
            hero = "Maverick",
            cardType = "Hero",
            element = "FIRE",
            set = "Base Set",
        )
        assertEquals("Maverick", heroed.displayName)
        assertNotNull(heroed.bobaId)
    }
}
