import Foundation

/// Pure functions for matching a `ScanObservation` to a `Card` candidate.
/// Used by both the streaming scanner (ScanView) and the Grid still-image
/// scanner (GridTestHarnessView / GridScanView). ScanView keeps its
/// private versions for now — refactor those to call here once Grid
/// mode ships and the dual implementations are confirmed equivalent.
enum ScanMatching {

    /// Full single-card matching pipeline as it exists in
    /// `ScanView.handleDetected`. Each Grid cell goes through this
    /// to receive identical treatment to a single-card scan:
    ///
    ///   1. Filter `candidates` by `observation.cardNumber` (caller
    ///      supplies the candidates so we can avoid taking a CardStore
    ///      dependency in this helper).
    ///   2. Score every candidate via `matchScore` (hero/power/element).
    ///   3. Phase-2 image-similarity tiebreak when:
    ///      - 2+ candidates remain after step 1
    ///      - Top OCR score is within 2 of runner-up
    ///      - FeaturePrintIndex is loaded
    ///      - observation.cgImage is non-nil
    ///      The tiebreak runs `FeaturePrintIndex.searchNearest` and
    ///      picks the closest indexed card whose bobaId is in our
    ///      candidate set, falling back to the OCR top pick.
    @MainActor
    static func resolve(
        observation: ScanObservation,
        candidates: [Card]
    ) async -> Card? {
        guard !candidates.isEmpty else { return nil }
        let scored = candidates
            .map { (card: $0, score: matchScore($0, observation: observation)) }
            .sorted { $0.score > $1.score }
        guard let best = scored.first?.card else { return nil }
        let needsTiebreak = scored.count >= 2 &&
                            (scored[0].score - scored[1].score) <= 2
        if needsTiebreak,
           let cgImage = observation.cgImage,
           FeaturePrintIndex.shared.isLoaded {
            let candidateBobaIds = Set(candidates.map { $0.id })
            let nearest = await FeaturePrintIndex.shared
                .searchNearest(in: cgImage, topK: 10)
            if let refinedId = nearest
                .first(where: { candidateBobaIds.contains($0.bobaId) })?.bobaId,
               let refined = candidates.first(where: { $0.id == refinedId }) {
                return refined
            }
        }
        return best
    }

    /// Synchronous score-only version. Picks the highest-scoring
    /// candidate without the Phase-2 image-similarity tiebreak.
    /// Use `resolve(observation:candidates:)` when the caller has
    /// the cropped CGImage available — that's the version that
    /// matches `ScanView.handleDetected`.
    static func bestMatch(
        observation: ScanObservation,
        candidates: [Card]
    ) -> Card? {
        guard !candidates.isEmpty else { return nil }
        return candidates
            .map { ($0, matchScore($0, observation: observation)) }
            .max { lhs, rhs in lhs.1 < rhs.1 }
            .map { $0.0 }
    }

    /// Numerical score of how well `card` matches the OCR text. Mirrors
    /// the scoring in ScanView.matchScore; tuned over the M3 milestone.
    static func matchScore(_ card: Card, observation: ScanObservation) -> Int {
        var score = 0
        let full = observation.fullText

        // Power match (+3)
        let powerText = observation.rawPower.isEmpty ? full : observation.rawPower
        if let power = card.power, extractIntegers(from: powerText).contains(power) {
            score += 3
        }

        // Hero / name match (+5 per word) — searched across ALL quadrant text
        score += heroNameScore(card.hero, in: full) * 5
        if card.name.uppercased() != card.hero.uppercased() {
            score += heroNameScore(card.name, in: full) * 3
        }

        // Top-left quadrant bonus
        if !observation.rawName.isEmpty {
            score += heroNameScore(card.hero, in: observation.rawName) * 2
        }

        // Element match (+2)
        if full.contains(card.element.uppercased()) {
            score += 2
        }

        // Treatment / variation match (+1 per word)
        let varText = observation.rawVariation.isEmpty ? full : "\(observation.rawVariation) \(full)"
        if let treatment = card.treatment, !treatment.isEmpty {
            let tWords = treatment.uppercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }
            score += tWords.filter { varText.contains($0) }.count
        }

        return score
    }

    /// Returns 3 for full-phrase match, otherwise word-level match count.
    /// Long words (≥5 chars) match by prefix (handles truncated OCR);
    /// short words (3–4 chars) require exact match.
    static func heroNameScore(_ name: String, in text: String) -> Int {
        let upperName = name.uppercased()
        if text.contains(upperName) { return 3 }
        let nameWords = upperName.components(separatedBy: .whitespaces).filter { $0.count >= 3 }
        guard !nameWords.isEmpty else { return 0 }
        let textWords = text.components(separatedBy: .whitespaces)
        var matches = 0
        for nw in nameWords {
            for tw in textWords where tw.count >= 3 {
                if nw.count >= 5 {
                    let (shorter, longer) = nw.count <= tw.count ? (nw, tw) : (tw, nw)
                    if shorter.count >= 5, longer.hasPrefix(shorter) {
                        matches += 1; break
                    }
                } else if nw == tw {
                    matches += 1; break
                }
            }
        }
        return matches
    }

    /// Extracts all integer runs from arbitrary text. "PWR 125 AIR 19"
    /// → {125, 19}.
    static func extractIntegers(from text: String) -> Set<Int> {
        var result = Set<Int>()
        var current = ""
        for ch in text {
            if ch.isNumber { current.append(ch) }
            else {
                if let n = Int(current) { result.insert(n) }
                current = ""
            }
        }
        if let n = Int(current) { result.insert(n) }
        return result
    }
}
