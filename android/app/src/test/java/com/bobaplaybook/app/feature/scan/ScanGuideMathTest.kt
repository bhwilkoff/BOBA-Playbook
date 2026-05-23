package com.bobaplaybook.app.feature.scan

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM tests for the scan guide-rect math.
 *
 * Critical because the analyzer's ROI filter drops tokens whose bbox
 * falls entirely outside the guide. A subtle bug here would silently
 * strip a legitimate hero name or cardNumber, regressing accuracy.
 */
class ScanGuideMathTest {

    @Test
    fun `unmeasured preview returns null`() {
        assertNull(scanGuideRect(0, 0))
        assertNull(scanGuideRect(1, 1))
        assertNull(scanGuideRect(50, 50))
    }

    @Test
    fun `phone portrait — 1080x2340 — picks 75pct width path`() {
        // 75% of 1080 = 810; 810 * 7/5 = 1134. 62% of 2340 = 1450.8.
        // 1134 <= 1450.8 → width-bound path.
        val r = scanGuideRect(1080, 2340)
        assertNotNull(r); r!!
        assertEquals(810f, r.width, 0.5f)
        assertEquals(1134f, r.height, 0.5f)
        assertEquals((1080 - 810) / 2f, r.left, 0.5f)
        // top = (2340 - 1134) / 2 - 2340 * 0.04 = 603 - 93.6 = 509.4
        assertEquals(509.4f, r.top, 0.5f)
    }

    @Test
    fun `wide short preview — 1200x900 — clamps to 62pct height`() {
        // 75% of 1200 = 900; 900 * 7/5 = 1260. 62% of 900 = 558.
        // 1260 > 558 → height-bound path.
        val r = scanGuideRect(1200, 900)
        assertNotNull(r); r!!
        assertEquals(558f, r.height, 0.5f)
        // width = 558 * 5/7 = 398.57
        assertEquals(398.57f, r.width, 0.5f)
    }

    @Test
    fun `token fully inside guide is kept`() {
        val r = scanGuideRect(1080, 2340)!!
        val tk = token(r.left + 100, r.top + 100, r.left + 200, r.top + 200)
        assertTrue("token inside guide should be kept", tk.intersectsScanGuide(r))
    }

    @Test
    fun `token fully outside guide is dropped`() {
        val r = scanGuideRect(1080, 2340)!!
        // Far right edge of preview, way past guide right + bleed.
        val tk = token(1050f, r.top, 1080f, r.top + 50)
        assertFalse("token outside guide should be dropped", tk.intersectsScanGuide(r))
    }

    @Test
    fun `token straddling guide edge is kept`() {
        val r = scanGuideRect(1080, 2340)!!
        // Half inside / half outside the right edge — should still
        // pass because we accept any intersection.
        val tk = token(r.right - 20, r.top + 50, r.right + 40, r.top + 100)
        assertTrue("straddling token should be kept", tk.intersectsScanGuide(r))
    }

    @Test
    fun `bleed allows token just outside the guide edge`() {
        val r = scanGuideRect(1080, 2340)!!
        // 5% of guide width 810 = 40.5px bleed. A token sitting 30px
        // outside the right edge should still be kept.
        val tk = token(r.right + 5, r.top + 50, r.right + 30, r.top + 80)
        assertTrue("within-bleed token should be kept", tk.intersectsScanGuide(r))
    }

    @Test
    fun `bleed boundary — token past bleed is dropped`() {
        val r = scanGuideRect(1080, 2340)!!
        // 5% of guide width 810 = 40.5px bleed. A token starting 60px
        // outside the right edge is past the bleed — drop.
        val tk = token(r.right + 60, r.top + 50, r.right + 100, r.top + 80)
        assertFalse("past-bleed token should be dropped", tk.intersectsScanGuide(r))
    }

    @Test
    fun `top-left card region falls within guide on portrait phone`() {
        // The matcher's hero-veto reads top-left of the PREVIEW; the
        // card's printed top-left should naturally fall within both the
        // preview's top-left quadrant AND the guide rect. Sanity-check
        // that overlap so we don't accidentally filter out a top-left
        // hero name on portrait phones.
        val r = scanGuideRect(1080, 2340)!!
        val tk = token(r.left + 30, r.top + 30, r.left + 200, r.top + 80)
        assertTrue(tk.intersectsScanGuide(r))
        // And it's in the preview's top-left half.
        assertTrue(tk.isTopLeft)
    }

    private fun token(l: Float, t: Float, ri: Float, b: Float): ScanTextToken =
        ScanTextToken(
            text = "test",
            left = l.toInt(),
            top = t.toInt(),
            right = ri.toInt(),
            bottom = b.toInt(),
            frameWidth = 1080,
            frameHeight = 2340,
        )
}
