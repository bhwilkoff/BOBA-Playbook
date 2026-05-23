package com.bobaplaybook.app.feature.scan

/**
 * Pure geometry for the scan guide frame.
 *
 * The visible card-guide overlay in [ScanGuideOverlay] AND the analyzer-
 * side ROI filter (drops OCR tokens that fall outside the guide) both
 * need to know exactly where the guide rect sits in PreviewView
 * coordinates. Two copies of the math would inevitably drift. Centralise
 * here as a pure function so the visible guide and the matcher's input
 * stay in lockstep — and so the math is testable on JVM.
 *
 * The shape:
 *  - 5:7 portrait aspect (card aspect).
 *  - Width = 75% of preview width.
 *  - If that height would exceed 62% of preview height, clamp to 62%
 *    and back-solve width.
 *  - Vertical centre nudged UP by 4% of preview height so the bottom
 *    controls + detection chip don't crowd the guide.
 */
data class ScanGuideRect(
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float,
) {
    val right: Float get() = left + width
    val bottom: Float get() = top + height
}

/**
 * Compute the guide-frame rectangle for a PreviewView of the given size.
 * Returns null when the preview hasn't been measured yet (≤ 100 px in
 * either dimension is the unmeasured/just-laid-out state).
 */
fun scanGuideRect(previewWidth: Int, previewHeight: Int): ScanGuideRect? {
    if (previewWidth <= 100 || previewHeight <= 100) return null
    val w = previewWidth.toFloat()
    val h = previewHeight.toFloat()
    val cardW0 = w * 0.75f
    val cardH0 = cardW0 * 7f / 5f
    val finalW: Float
    val finalH: Float
    if (cardH0 > h * 0.62f) {
        finalH = h * 0.62f
        finalW = finalH * 5f / 7f
    } else {
        finalW = cardW0
        finalH = cardH0
    }
    val left = (w - finalW) / 2f
    val top = (h - finalH) / 2f - h * 0.04f
    return ScanGuideRect(left = left, top = top, width = finalW, height = finalH)
}

/**
 * Test whether [token]'s bounding box intersects the guide rect plus a
 * relative bleed (5% of guide width by default — hero names sit at the
 * card edge and ML Kit bboxes round outward). Returns true when the
 * token should be considered for matching; false when it's pure
 * background and should be dropped.
 */
fun ScanTextToken.intersectsScanGuide(
    guide: ScanGuideRect,
    bleedFraction: Float = 0.05f,
): Boolean {
    val bleed = guide.width * bleedFraction
    val rLeft = guide.left - bleed
    val rTop = guide.top - bleed
    val rRight = guide.right + bleed
    val rBottom = guide.bottom + bleed
    return right.toFloat() >= rLeft &&
        bottom.toFloat() >= rTop &&
        left.toFloat() <= rRight &&
        top.toFloat() <= rBottom
}
