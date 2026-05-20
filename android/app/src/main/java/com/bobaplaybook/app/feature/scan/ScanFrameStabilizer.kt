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

    /**
     * State the UI can render between commits. Lets the viewfinder
     * show "Scoring 2/3 — Maverick" feedback while the camera is
     * accumulating agreements. iOS doesn't surface this; it's a real
     * Android win.
     */
    sealed interface State {
        data object Idle : State                              // No recent frames
        data object Scanning : State                          // Recent frames; no candidate yet
        data class Scoring(                                   // Candidate emerging
            val card: com.bobaplaybook.core.domain.model.Card,
            val agreements: Int,
            val required: Int,
            val avgScore: Double,
        ) : State
        data class Committed(val result: ScanMatchResult) : State
    }

    private data class Frame(val result: ScanMatchResult?)

    private val window = ArrayDeque<Frame>()
    private var lastCommittedBobaId: String? = null

    /** Snapshot of the live state for UI rendering. */
    var state: State = State.Idle
        private set

    /**
     * Push a per-frame result. Returns a stable match when the gate
     * conditions pass, or null when we should keep scanning. Also
     * updates [state] for UI consumption.
     */
    fun push(result: ScanMatchResult?): ScanMatchResult? {
        window.addLast(Frame(result))
        while (window.size > windowSize) window.removeFirst()

        // "No match" frame — clear the de-dupe so the same card can
        // commit again later (user moved the card out, brought it back).
        if (result == null) {
            val nonNullCount = window.count { it.result != null }
            if (nonNullCount == 0) {
                lastCommittedBobaId = null
                state = State.Idle
            } else {
                state = State.Scanning
            }
            return null
        }

        // Count agreements with the most-recent result's bobaId.
        val candidate = result.card.bobaId
        val agreeing = window.mapNotNull { it.result }.filter { it.card.bobaId == candidate }
        val avgScore = agreeing.map { it.score }.average()

        if (agreeing.size < requiredAgreements) {
            state = State.Scoring(result.card, agreeing.size, requiredAgreements, avgScore)
            return null
        }
        if (avgScore < 1.4) {
            state = State.Scoring(result.card, agreeing.size, requiredAgreements, avgScore)
            return null
        }
        if (lastCommittedBobaId == candidate) {
            // De-dupe a continuous hold. State stays at Committed so
            // the UI doesn't flicker back to Scoring.
            return null
        }
        lastCommittedBobaId = candidate
        val committed = result.copy(score = avgScore)
        state = State.Committed(committed)
        return committed
    }

    fun reset() {
        window.clear()
        lastCommittedBobaId = null
        state = State.Idle
    }
}
