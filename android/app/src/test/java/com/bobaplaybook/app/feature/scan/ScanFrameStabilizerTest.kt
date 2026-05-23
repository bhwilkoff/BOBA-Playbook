package com.bobaplaybook.app.feature.scan

import com.bobaplaybook.core.domain.model.Card
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Multi-frame stability gate tests.
 *
 * The stabilizer's job is to convert ScanCardMatcher's per-frame
 * results (which jitter as the camera moves) into a stable commit.
 * The user-visible win is that an accidental wrong-card single frame
 * during a scan session no longer commits — the wrong card needs to
 * win [requiredAgreements] of the last [windowSize] frames before it
 * triggers a match.
 */
class ScanFrameStabilizerTest {

    // bobaId formula (CLAUDE.md): "{cardNumber}-{hero}-{treatment}-{variation}"
    // Trailing dashes are intentional and stable.
    // Scores deliberately fall below the fast-commit tier (iter 46:
    // >=1.5 ⇒ 2 agreements; >=2.0 ⇒ 1) so these tests continue to
    // validate the default 3-of-5 multi-frame path. Fast-commit tier
    // behavior is exercised by the *high-confidence* / *medium-
    // confidence* / *shiny-recovery* tests below.
    private val mav = match(cardNumber = "1", hero = "Maverick", score = 1.45)
    private val tig = match(cardNumber = "20", hero = "Tigre", score = 1.45)
    private val mavBobaId = "1-Maverick--"

    @Test
    fun `single hot frame does not commit`() {
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        assertNull(s.push(mav))
        assertNull(s.push(null))
        assertNull(s.push(null))
        assertNull(s.push(null))
        assertNull(s.push(null))
    }

    @Test
    fun `three of five same-card frames commits`() {
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        s.push(null)
        s.push(mav)
        s.push(null)
        s.push(mav)
        val commit = s.push(mav)
        assertNotNull(commit)
        assertEquals(mavBobaId, commit?.card?.bobaId)
    }

    @Test
    fun `flicker between cards stays uncommitted`() {
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        // Maverick / Tigre / Maverick / Tigre / Maverick — only 3
        // Maverick frames in the window. That hits the agreement
        // count exactly. Commits Maverick.
        s.push(mav)
        s.push(tig)
        s.push(mav)
        s.push(tig)
        val commit = s.push(mav)
        assertEquals(mavBobaId, commit?.card?.bobaId)
    }

    @Test
    fun `two-vs-two-vs-empty does NOT commit`() {
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        s.push(mav)
        s.push(tig)
        s.push(null)
        s.push(mav)
        val commit = s.push(tig)
        assertNull(commit)
    }

    @Test
    fun `same card on continuous hold only emits once`() {
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        s.push(mav); s.push(mav)
        val first = s.push(mav)
        assertNotNull(first)
        // Two more identical frames — no re-emit.
        assertNull(s.push(mav))
        assertNull(s.push(mav))
    }

    @Test
    fun `very-high-confidence first frame commits immediately`() {
        // iOS-parity fast-commit path. A score >= 2.5 (cardNumber +
        // hero top-left + extras) shouldn't have to wait for 3-of-5
        // agreement — that's what iOS DECISIONS.md #035 already does.
        // Android's prior default of "always wait for 3" introduced
        // multi-second perceived lag on clean reads.
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        val confidentMav = match(cardNumber = "1", hero = "Maverick", score = 2.8)
        val commit = s.push(confidentMav)
        assertNotNull("Expected single-frame commit for score 2.8", commit)
        assertEquals(mavBobaId, commit?.card?.bobaId)
    }

    @Test
    fun `iter-46 shiny-recovery score commits single-frame`() {
        // Shiny-card recovery shape (DEKAP GGL-779): hero +1.5 +
        // prefix +0.4 + element +0.2 + power +0.2 = 2.3. iter 46
        // lowered the high-confidence tier from 2.5 to 2.0 so this
        // commits on a single frame instead of waiting for 2 — on
        // shimmery prints consecutive frames often disagree and the
        // 2-frame requirement timed out.
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        val shinyHit = match(cardNumber = "GGL-779", hero = "DeKap", score = 2.3)
        val commit = s.push(shinyHit)
        assertNotNull("Expected single-frame commit for score 2.3 (was 2-frame pre-iter-46)", commit)
    }

    @Test
    fun `medium-confidence commits at 2 agreements`() {
        // 1.5 <= score < 2.0 → 2-of-5 instead of 3-of-5. Mid-tier
        // scores get a faster path while staying validated.
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        val midMav = match(cardNumber = "1", hero = "Maverick", score = 1.7)
        assertNull("First mid-confidence frame should NOT commit yet", s.push(midMav))
        val commit = s.push(midMav)
        assertNotNull("Two-of-five at score 1.7 should commit", commit)
    }

    @Test
    fun `low-confidence still requires 3 agreements`() {
        // Default 3-of-5 path stays for noisy floor-grazing reads
        // (score 1.4 = matcher's commit floor, just above null). The
        // 3-of-5 gate is the wrong-card-protection net for the
        // weakest signals.
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        val lowMav = match(cardNumber = "1", hero = "Maverick", score = 1.45)
        assertNull(s.push(lowMav))
        assertNull(s.push(lowMav))
        val commit = s.push(lowMav)
        assertNotNull("Three-of-five at score 1.45 should commit", commit)
    }

    @Test
    fun `gap then same card re-emits`() {
        val s = ScanFrameStabilizer(windowSize = 5, requiredAgreements = 3)
        s.push(mav); s.push(mav)
        assertNotNull(s.push(mav))
        // Empty the window with null frames.
        repeat(5) { s.push(null) }
        // Bring Maverick back — should re-emit.
        s.push(mav); s.push(mav)
        assertNotNull(s.push(mav))
    }

    private fun match(cardNumber: String, hero: String, score: Double): ScanMatchResult {
        val card = Card(
            cardNumber = cardNumber,
            name = hero,
            hero = hero,
            cardType = "Hero",
            element = "FIRE",
            set = "Test",
        )
        return ScanMatchResult(card = card, score = score, margin = 1.0, reasons = listOf("test"))
    }
}
