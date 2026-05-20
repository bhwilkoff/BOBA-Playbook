package com.bobaplaybook.app.feature.scan

import android.graphics.Rect
import com.bobaplaybook.core.domain.model.Card
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Multi-signal scoring tests — port of iOS DECISIONS.md #035 cases.
 *
 * Test catalog mirrors real BoBA cardNumber shapes:
 *   - Base set heroes have plain-digit cardNumbers ("1", "20")
 *   - Treatment / battlefoil cards have prefix-dash-digit form
 *     ("BHBF-37") — those match the iOS DECISIONS.md #012 regex
 *   - Plain digits ride the bare-digit-suffix + hero-name path,
 *     since the iOS regex requires letters-then-dash.
 *
 * Headline test: `partial_ocr_with_hero_present_commits_correct_card`
 * — simulates the iOS-original silent-wrong scenario (BHBF-37 OCR'd
 * partially as "20") and asserts the hero-veto correctly suppresses
 * the wrong card (Tigre at cardNumber "20") AND commits the right
 * one (JacHammer, via hero top-left).
 */
class ScanCardMatcherTest {

    // ─────── Test catalog — realistic cardNumber shapes ───────────
    // Multiple base-set cards share cardNumber="1" — heroes
    // disambiguate. This is the real catalog shape (~17k cards,
    // duplicate cardNumbers across heroes).
    private val maverickBase = card("1", hero = "Maverick", element = "FIRE", power = 135)
    private val leBossBase   = card("1", hero = "LeBoss",   element = "FIRE", power = 145)
    private val tigreBase    = card("20", hero = "Tigre",   element = "FIRE", power = 75)
    private val jacHammerBhbf = card("BHBF-37", hero = "JacHammer", element = "ICE", power = 110)
    private val catalog = listOf(maverickBase, leBossBase, tigreBase, jacHammerBhbf)
    private val matcher = ScanCardMatcher { catalog }

    @Test
    fun `confident BHBF cardNumber match commits`() {
        val tokens = listOf(
            token("BoBA", topLeft = false),
            token("BHBF-37", topLeft = false),
            token("JacHammer", topLeft = true),
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("BHBF-37", result?.card?.cardNumber)
        // 1.0 cardNumber + 1.5 hero top-left = 2.5
        assertTrue("Expected score >= 1.4 but was ${result?.score}", (result?.score ?: 0.0) >= 1.4)
    }

    @Test
    fun `partial_ocr_with_hero_present_commits_correct_card`() {
        // SIMULATION: User scans BHBF-37 JacHammer. OCR catches
        // "JacHammer" top-left and a digit blob "20" (partial read of
        // "37"). Without hero veto a naive matcher commits Tigre
        // (which has cardNumber="20"). With the iOS-matched veto,
        // Tigre takes a −2.0 hit (hero top-left says JacHammer); the
        // matcher commits JacHammer via the strong hero signal alone.
        val tokens = listOf(
            token("JacHammer", topLeft = true),
            token("20", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("Correct hero wins; veto rejected Tigre.", "JacHammer", result?.card?.hero)
    }

    @Test
    fun `hero only frame still gates on confidence floor`() {
        // Camera caught the hero clearly but the card-number is
        // motion-blurred. Hero top-left scores 1.5 → above 1.4 floor.
        // Only Maverick is a candidate (heroesMentioned drives the
        // pool); margin against the empty set is positive. Commits.
        val tokens = listOf(token("Maverick", topLeft = true))
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("Maverick", result?.card?.hero)
    }

    @Test
    fun `bare digit alone below floor`() {
        // Naked digit blob with no hero context. "20" matches Tigre's
        // suffix → +0.4. No hero anywhere → no other points. Total
        // 0.4 < 1.4 floor. Matcher returns null → keep scanning.
        val tokens = listOf(token("20", topLeft = false))
        assertNull(matcher.match(tokens))
    }

    @Test
    fun `base set Maverick scan — hero plus weapon plus power commits`() {
        // Realistic happy path for a base-set card (no BHBF-style
        // cardNumber to match). Hero top-left + element + power
        // disambiguate Maverick from LeBoss (both share cardNumber 1).
        val tokens = listOf(
            token("Maverick", topLeft = true),
            token("1", topLeft = false),       // bare-digit hit → both Maverick + LeBoss
            token("FIRE", topLeft = false),
            token("135", topLeft = false),     // Maverick.power=135, LeBoss.power=145
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("Maverick", result?.card?.hero)
        // Maverick: 0.4 (bare-digit) + 1.5 (hero top-left) + 0.2 (element) + 0.2 (power) = 2.3
        assertTrue("Expected score >= 2.2 but was ${result?.score}", (result?.score ?: 0.0) >= 2.2)
        // LeBoss should score below — veto'd by hero top-left.
        // Margin is therefore comfortable.
        assertTrue("Expected margin >= 0.3 but was ${result?.margin}", (result?.margin ?: 0.0) >= 0.3)
    }

    @Test
    fun `empty tokens returns null`() {
        assertNull(matcher.match(emptyList()))
    }

    @Test
    fun `fuzzy hero match recovers from OCR character flip`() {
        // "MAVERIK" (missing a C) should still match Maverick via the
        // Levenshtein-bounded fuzzy match. Distance 1 vs Maverick's
        // 8 chars → allowed since len > 6.
        val tokens = listOf(
            token("MAVERIK", topLeft = true),
            token("1", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull("Expected fuzzy match to recover Maverick", result)
        assertEquals("Maverick", result?.card?.hero)
    }

    @Test
    fun `treatment text earns the 0_2 bonus`() {
        val battlefoilMav = card("RBF-1", hero = "Maverick", element = "FIRE", power = 135, treatment = "Red Battlefoil")
        val custom = ScanCardMatcher { listOf(maverickBase, battlefoilMav) }
        val tokens = listOf(
            token("RBF-1", topLeft = false),
            token("Maverick", topLeft = true),
            token("Red Battlefoil", topLeft = false),
        )
        val result = custom.match(tokens)
        assertNotNull(result)
        assertEquals("RBF-1", result?.card?.cardNumber)
        assertTrue("Expected score >= 2.7 (1.0 cardNumber + 1.5 hero + 0.2 treatment)", (result?.score ?: 0.0) >= 2.7)
        assertTrue(
            "Expected reasons to include treatment bonus",
            result?.reasons?.any { it.contains("treatment") } == true,
        )
    }

    @Test
    fun `LeBoss disambiguated by hero top-left even when Maverick power leaks`() {
        // Adversarial case: tokens have LeBoss top-left but a "135"
        // (Maverick's power) somewhere else in frame — maybe a
        // background card in view. Hero veto should still drive the
        // result to LeBoss, not Maverick.
        val tokens = listOf(
            token("LeBoss", topLeft = true),
            token("1", topLeft = false),
            token("135", topLeft = false),  // Maverick.power — would have leaked toward Maverick
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("LeBoss", result?.card?.hero)
    }

    // ─── helpers ─────────────────────────────────────────────────

    private fun card(
        cardNumber: String,
        hero: String,
        element: String,
        power: Int,
        treatment: String? = null,
    ): Card = Card(
        cardNumber = cardNumber,
        name = hero,
        hero = hero,
        cardType = "Hero",
        element = element,
        set = "Test Set",
        power = power,
        treatment = treatment,
    )

    private fun token(text: String, topLeft: Boolean): ScanTextToken {
        // Frame is 1000x1000; "top-left" means bbox at (0,0,200,50),
        // "elsewhere" means a box in the bottom-right at (700,700).
        val frame = if (topLeft) Rect(0, 0, 200, 50) else Rect(700, 700, 900, 750)
        return ScanTextToken(
            text = text,
            frame = frame,
            frameWidth = 1000,
            frameHeight = 1000,
        )
    }
}
