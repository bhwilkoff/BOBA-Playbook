package com.bobaplaybook.app.feature.scan

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Direct unit tests for [canonicalizeHero]. The helper is the hinge
 * of the iter-33 hero-match fix — a regression here silently
 * un-matches whole classes of catalog heroes (dotted abbreviations,
 * hyphenated names, apostrophes). The two matcher-level tests
 * indirectly cover a couple of cases; this exercises the helper
 * directly across all the canonical-form rules at once.
 */
class CanonicalizeHeroTest {

    @Test fun `whitespace collapses`() {
        assertEquals("JACHAMMER", canonicalizeHero("Jac Hammer"))
        assertEquals("JACHAMMER", canonicalizeHero("Jac  Hammer"))
        assertEquals("JACHAMMER", canonicalizeHero(" Jac Hammer "))
    }

    @Test fun `case normalised to upper`() {
        assertEquals("MAVERICK", canonicalizeHero("Maverick"))
        assertEquals("MAVERICK", canonicalizeHero("maverick"))
        assertEquals("MAVERICK", canonicalizeHero("MAVERICK"))
    }

    @Test fun `dots stripped`() {
        // Real catalog heroes: A.C., A.I., C.C., Dr. J
        assertEquals("AC", canonicalizeHero("A.C."))
        assertEquals("DRJ", canonicalizeHero("Dr. J"))
        assertEquals("DRFURTER", canonicalizeHero("Dr. Furter"))
    }

    @Test fun `hyphens stripped`() {
        // Real catalog heroes: D-Harp, D-Hop, Amon-Ra, Eagle-Eye, Big-Z
        assertEquals("DHARP", canonicalizeHero("D-Harp"))
        assertEquals("AMONRA", canonicalizeHero("Amon-Ra"))
        assertEquals("EAGLEEYE", canonicalizeHero("Eagle-Eye"))
        assertEquals("BIGZ", canonicalizeHero("Big-Z"))
    }

    @Test fun `apostrophes stripped`() {
        // Real catalog heroes: "Don't Call It A Comeback", "Another Man's Treasure"
        assertEquals("DONTCALLITACOMEBACK", canonicalizeHero("Don't Call It A Comeback"))
        assertEquals("ANOTHERMANSTREASURE", canonicalizeHero("Another Man's Treasure"))
    }

    @Test fun `combined punctuation`() {
        // "3-Dog-Special" mixes digits + hyphens
        assertEquals("3DOGSPECIAL", canonicalizeHero("3-Dog-Special"))
        // "1-4-1 Hero" — digits + hyphens + whitespace
        assertEquals("141HERO", canonicalizeHero("1-4-1 Hero"))
    }

    @Test fun `non-ASCII letters preserved`() {
        // The Ç in "Curaçao Kid" must NOT be silently Anglicised
        // — collectors recognise the brand spelling.
        assertEquals("CURAÇAOKID", canonicalizeHero("Curaçao Kid"))
    }

    @Test fun `digits in name are preserved`() {
        // Treatment cardNumbers ride a separate signal; hero canonical
        // form must NOT strip digits or the matcher would lose them.
        assertEquals("Z3", canonicalizeHero("Z3"))
        assertEquals("PLAYER10", canonicalizeHero("Player 10"))
    }

    @Test fun `empty and whitespace-only inputs`() {
        assertEquals("", canonicalizeHero(""))
        assertEquals("", canonicalizeHero("   "))
        assertEquals("", canonicalizeHero("...---'''"))
    }

    @Test fun `idempotent — canonicalising twice is a no-op`() {
        val once = canonicalizeHero("D-Harp")
        assertEquals(once, canonicalizeHero(once))
    }
}
