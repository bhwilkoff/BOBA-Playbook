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
    fun `cardNumber split across tokens still commits`() {
        // ML Kit's text recognizer routinely returns the prefix and
        // the suffix of a card number as separate TextLine tokens —
        // "BHBF" on one line, "37" on the next. The per-token regex
        // missed every such read. With the joined-text fallback the
        // matcher reconstructs "BHBF-37" from the joined stream.
        val tokens = listOf(
            token("JacHammer", topLeft = true),
            token("BHBF", topLeft = false),
            token("37", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull("Expected cross-token cardNumber to assemble", result)
        assertEquals("BHBF-37", result?.card?.cardNumber)
    }

    @Test
    fun `cardNumber split with hyphen suffix still commits`() {
        // Variant where ML Kit keeps the hyphen on the prefix token:
        // "BHBF-" and "37".
        val tokens = listOf(
            token("JacHammer", topLeft = true),
            token("BHBF-", topLeft = false),
            token("37", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull("Expected joined-space regex to catch BHBF- 37", result)
        assertEquals("BHBF-37", result?.card?.cardNumber)
    }

    @Test
    fun `hero name split across tokens still commits`() {
        // ML Kit splits "JacHammer" into ["Jac", "Hammer"] on
        // wide-spaced or interrupted prints. Neither token alone
        // passes the matcher's per-token fuzzy hero check. The
        // adjacent-pair concatenation pass reconstructs "JacHammer"
        // from "Jac"+"Hammer" and credits the hero top-left.
        val tokens = listOf(
            token("Jac", topLeft = true),
            token("Hammer", topLeft = false),
            token("BHBF-37", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull("Expected adjacent-pair hero assembly to recover JacHammer", result)
        assertEquals("JacHammer", result?.card?.hero)
        // Reason set should include hero top-left since "Jac" sat
        // top-left even though the full match is reconstructed.
        assertTrue(
            "Expected hero top-left bonus for split JacHammer",
            result?.reasons?.any { it.contains("hero top-left") } == true,
        )
    }

    @Test
    fun `split-hero top-left still vetoes wrong-card commits`() {
        // Same partial-OCR-silent-wrong scenario as the headline
        // matcher test, but with a SPLIT hero name. "Jac" top-left
        // + "Hammer" elsewhere → JacHammer assembled → top-left.
        // The bare digit "20" would have committed Tigre without
        // the veto. With the adjacent-pair pass adding JacHammer to
        // heroesTopLeft, Tigre takes the −2.0 veto and JacHammer
        // commits.
        val tokens = listOf(
            token("Jac", topLeft = true),
            token("Hammer", topLeft = false),
            token("20", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("Veto suppressed Tigre even with split hero", "JacHammer", result?.card?.hero)
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
    fun `fuzzy-only top-left does not veto legitimate cardNumber match`() {
        // Scenario: OCR catches a strong cardNumber match (clean
        // "BHBF-37" → JacHammer) but a top-left token is OCR garbage
        // that happens to fuzzy-match a different hero name at
        // Levenshtein 2 (e.g. "JACKHAMMR" ← JacHammer at distance 2
        // — wait, that matches JacHammer exactly via substring at
        // Levenshtein 0 because "JACKHAMMR".contains("JACHAMMER")
        // would be false; use a deliberately broken read).
        //
        // For a real veto-false-positive case, imagine top-left
        // OCR reads "TYGRE" (typo for Tigre at Levenshtein 1).
        // Before iter 9, that fuzzy hero match would credit Tigre
        // top-left → veto JacHammer despite BHBF-37 being the
        // clear cardNumber signal. After iter 9, the veto only
        // fires when an EXACT top-left match is found — so
        // JacHammer's cardNumber + non-top-left hero combo wins.
        val tokens = listOf(
            token("TYGRE", topLeft = true),  // fuzzy = Tigre, Levenshtein 1
            token("BHBF-37", topLeft = false),
            token("JacHammer", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals(
            "Expected JacHammer to commit (cardNumber + hero mid-frame); fuzzy 'TYGRE' must not veto",
            "JacHammer",
            result?.card?.hero,
        )
    }

    @Test
    fun `multi-word treatment matches across token split`() {
        // Cards with multi-word treatments like "Red Battlefoil" or
        // "Inspired Ink" print the treatment with each word on its
        // own line. ML Kit returns them as separate tokens, so the
        // per-token contains() check never sees the full phrase.
        // The joined-text fallback closes this gap.
        val redBattlefoilMav = card("RBF-1", hero = "Maverick", element = "FIRE",
            power = 135, treatment = "Red Battlefoil")
        val plainMav = card("1", hero = "Maverick", element = "FIRE", power = 135)
        val custom = ScanCardMatcher { listOf(plainMav, redBattlefoilMav) }
        val tokens = listOf(
            token("RBF-1", topLeft = false),
            token("Maverick", topLeft = true),
            token("RED", topLeft = false),
            token("BATTLEFOIL", topLeft = false),
        )
        val result = custom.match(tokens)
        assertNotNull(result)
        assertEquals("RBF-1", result?.card?.cardNumber)
        // Should reflect the treatment bonus in reasons
        assertTrue(
            "Expected treatment bonus on the joined-text fallback path",
            result?.reasons?.any { it.contains("treatment") } == true,
        )
    }

    @Test
    fun `hero with hyphen still matches when OCR drops the hyphen`() {
        // Real catalog has heroes like "D-Harp", "D-Hop", "Amon-Ra".
        // ML Kit normalizes a hyphen to nothing or a space depending
        // on glyph spacing. With the pre-iter-33 canonical form
        // ("uppercase + strip whitespace only"), "D-HARP" stays
        // "D-HARP" in the catalog while OCR's "DHARP" stays "DHARP"
        // — Levenshtein 1, short-hero tolerance 0, NO MATCH.
        // After iter 33, both canonicalise to "DHARP" → exact.
        val dHarp = card("BLBF-95", hero = "D-Harp", element = "ICE", power = 95)
        val matcher2 = ScanCardMatcher { listOf(dHarp) }
        val tokens = listOf(
            token("BLBF-95", topLeft = false),
            token("DHARP", topLeft = true),  // OCR dropped the hyphen
        )
        val result = matcher2.match(tokens)
        assertNotNull("D-Harp should commit despite hyphen-stripped OCR", result)
        assertEquals("D-Harp", result?.card?.hero)
    }

    @Test
    fun `short hero with dots still matches when OCR drops the dots`() {
        // "A.C." is a real catalog hero. Short heroes (length ≤ 4)
        // run at Levenshtein tolerance 0, so the canonical-form fix
        // is the only way they match OCR-dropped punctuation.
        val ac = card("1", hero = "A.C.", element = "FIRE", power = 75)
        val matcher2 = ScanCardMatcher { listOf(ac) }
        val tokens = listOf(
            token("1", topLeft = false),
            token("AC", topLeft = true),  // OCR dropped both dots
        )
        val result = matcher2.match(tokens)
        assertNotNull("A.C. should commit despite dot-stripped OCR", result)
        assertEquals("A.C.", result?.card?.hero)
    }

    @Test
    fun `element bonus fires when element is on a shared line with other text`() {
        // ML Kit often returns the element + power on one line:
        // token text = "FIRE 135". Previously the matcher checked the
        // entire token text against `idx.elements` — "FIRE 135" is
        // not "FIRE", so no +0.2 bonus. After iter 38, tokens split
        // on non-letters before matching, so "FIRE" hits.
        // The +0.2 doesn't change the winning card (cardNumber + hero
        // dominate) but the score reasons list reveals it.
        val tokens = listOf(
            token("1", topLeft = false),
            token("Maverick", topLeft = true),
            token("FIRE 135", topLeft = false),  // shared-line element
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertEquals("Maverick", result?.card?.hero)
        assertTrue(
            "Expected element bonus in reasons",
            result?.reasons?.any { it.contains("element") } == true,
        )
    }

    @Test
    fun `element bonus survives trailing punctuation`() {
        // OCR sometimes appends a stray dot or comma to the element
        // when it's the last on a line: token "FIRE." Previously no
        // element hit (token != "FIRE"). After iter 38, splits on
        // non-letters so "FIRE" hits.
        val tokens = listOf(
            token("1", topLeft = false),
            token("Maverick", topLeft = true),
            token("FIRE.", topLeft = false),
        )
        val result = matcher.match(tokens)
        assertNotNull(result)
        assertTrue(
            "Expected element bonus in reasons",
            result?.reasons?.any { it.contains("element") } == true,
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
        // "elsewhere" means a box in the bottom-right at (700,700,900,750).
        // Use the int constructor directly — Android Rect's JVM stub
        // returns 0 for every field in unit tests, which would silently
        // break the matcher's isTopLeft computation. The production
        // analyzer uses ScanTextToken.fromRect(...).
        return if (topLeft) ScanTextToken(
            text = text,
            left = 0, top = 0, right = 200, bottom = 50,
            frameWidth = 1000, frameHeight = 1000,
        ) else ScanTextToken(
            text = text,
            left = 700, top = 700, right = 900, bottom = 750,
            frameWidth = 1000, frameHeight = 1000,
        )
    }
}
