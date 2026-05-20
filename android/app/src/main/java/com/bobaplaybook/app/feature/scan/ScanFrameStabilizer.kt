package com.bobaplaybook.app.feature.scan

/**
 * Multi-frame stability gate. ML Kit fires ~15-30 frames/sec; per-frame
 * matches flicker as the camera moves, focus settles, and OCR confidence
 * jitters. Committing on a single hot frame produces false positives
 * even when the per-frame scorer (ScanCardMatcher) is well-gated.
 *
 * This stabilizer keeps a rolling window of recent ScanMatchResults.
 * A commit emits ONLY when:
 *  1. The same bobaId appears as the top match in ≥ [requiredAgreements]
 *     of the last [windowSize] frames.
 *  2. The average score across those agreeing frames stays >= the
 *     ScanCardMatcher's confidence floor.
 *  3. We haven't already committed this exact bobaId since the last
 *     "no match" frame (avoid re-emitting on a continuous hold).
 *
 * This is the iOS-better-than-iOS lever. iOS DECISIONS.md #035 commits
 * per-frame; Android's stabilizer waits for the camera + OCR to agree
 * across multiple frames before committing.
 */
class ScanFrameStabilizer(
    private val windowSize: Int = 5,
    private val requiredAgreements: Int = 3,
) {

    private data class Frame(val result: ScanMatchResult?)

    private val window = ArrayDeque<Frame>()
    private var lastCommittedBobaId: String? = null

    /**
     * Push a per-frame result. Returns a stable match when the gate
     * conditions pass, or null when we should keep scanning.
     */
    fun push(result: ScanMatchResult?): ScanMatchResult? {
        window.addLast(Frame(result))
        while (window.size > windowSize) window.removeFirst()

        // "No match" frame — clear the de-dupe so the same card can
        // commit again later (user moved the card out, brought it back).
        if (result == null) {
            // Don't immediately clear lastCommittedBobaId; let the user
            // hold the same card and we won't re-emit. We clear only
            // when the window goes mostly empty.
            val nonNullCount = window.count { it.result != null }
            if (nonNullCount == 0) lastCommittedBobaId = null
            return null
        }

        // Count agreements with the most-recent result's bobaId.
        val candidate = result.card.bobaId
        val agreeing = window.mapNotNull { it.result }.filter { it.card.bobaId == candidate }
        if (agreeing.size < requiredAgreements) return null

        val avgScore = agreeing.map { it.score }.average()
        if (avgScore < 1.4) return null

        if (lastCommittedBobaId == candidate) return null   // de-dupe a continuous hold
        lastCommittedBobaId = candidate
        return result.copy(score = avgScore)
    }

    fun reset() {
        window.clear()
        lastCommittedBobaId = null
    }
}
