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

    /// Grid-specific resolver. Same OCR-then-image-similarity
    /// pipeline as `resolve(observation:candidates:)`, but with two
    /// crucial extensions:
    ///
    ///   1. FeaturePrintIndex runs on the **full catalog**, not just
    ///      cardNumber-filtered candidates. When OCR misreads a
    ///      cardNumber (bare digit like "38" matching the wrong base
    ///      card when the physical card was the prefixed "BGBF-38"
    ///      treatment, or noise-extracted "80" from a Marksman crop
    ///      whose actual cardNumber is "GBF-94"), image similarity
    ///      can override the OCR pick by recognizing the actual card
    ///      art.
    ///
    ///   2. Hero-name fallback runs against the full catalog when
    ///      both OCR cardNumber extraction AND image similarity fail
    ///      to land — preserves the existing matchByHero behavior as
    ///      a tertiary fallback.
    ///
    /// Override threshold for FP vs OCR: FP top must be either the
    /// only candidate in top-K (very strong "OCR was wrong" signal)
    /// or have a distance ≤60% of the closest cardNumber-candidate's
    /// distance. Both bars are conservative — when OCR was correct
    /// AND the image is in the index, the FP top will land in the
    /// candidate set and the override never fires.
    @MainActor
    static func resolveGrid(
        observation: ScanObservation,
        allCards: [Card]
    ) async -> Card? {
        let cardsByBobaId = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })

        let cn = observation.cardNumber
        let candidates: [Card] = cn.isEmpty
            ? []
            : allCards.filter { $0.cardNumber.uppercased() == cn }

        let ocrBest: Card? = candidates
            .map { ($0, matchScore($0, observation: observation)) }
            .sorted { $0.1 > $1.1 }
            .first?.0

        if let cgImage = observation.cgImage,
           FeaturePrintIndex.shared.isLoaded {
            let nearest = await FeaturePrintIndex.shared
                .searchNearest(in: cgImage, topK: 25)
            if let absoluteTop = nearest.first {
                let candidateIds = Set(candidates.map { $0.id })
                if candidateIds.contains(absoluteTop.bobaId),
                   let card = cardsByBobaId[absoluteTop.bobaId] {
                    return card
                }
                let bestCandInFP = nearest.first { candidateIds.contains($0.bobaId) }
                if !candidates.isEmpty {
                    // OCR gave us candidates. Override OCR only when
                    // image similarity strongly disagrees — when no
                    // candidate even appears in the FP top-K, the
                    // most likely explanation is that the card just
                    // isn't covered by our index (~17% of the catalog
                    // has no R2 image), NOT that OCR was wrong, so
                    // we trust OCR's filter.
                    if let bcip = bestCandInFP {
                        if absoluteTop.distance < bcip.distance * 0.6,
                           let overrideCard = cardsByBobaId[absoluteTop.bobaId] {
                            return overrideCard
                        }
                        if let c = cardsByBobaId[bcip.bobaId] { return c }
                    }
                    // No candidate in top-K — fall through to ocrBest.
                } else {
                    // No OCR cardNumber → FP top is our best signal.
                    if let overrideCard = cardsByBobaId[absoluteTop.bobaId] {
                        return overrideCard
                    }
                }
            }
        }

        if let best = ocrBest { return best }

        return matchByHero(
            allText:     observation.fullText,
            topLeftText: observation.rawName,
            candidates:  allCards
        )
    }

    /// Hero-name fallback for Grid mode when OCR fails to extract
    /// a cardNumber but DOES read the hero text at the top of the
    /// card. Used when the cardNumber on a specific card is
    /// physically unreadable (tiny low-contrast badges on certain
    /// First-Edition cards) but "WATTAGE" / "PB BUCKETS" / etc.
    /// reads cleanly.
    ///
    /// Searches the catalog for entries whose hero name (or
    /// `name`) appears as a word in the OCR text. Scores by
    /// match in topLeftText (where the hero is printed) ×3 plus
    /// any-region match ×1. Returns the highest-scoring entry,
    /// or nil if no hero word produces any catalog hit.
    static func matchByHero(
        allText: String,
        topLeftText: String,
        candidates: [Card]
    ) -> Card? {
        guard !candidates.isEmpty else { return nil }
        let stopWords: Set<String> = [
            "FIRST", "EDITION", "EDITON", "EDTON", "EDITVON", "EDITIDN",
            "BATTLE", "ARENA", "BATTTE", "TARENA", "POWER", "ROOKIE",
            "INSPIRED", "INSPIREO", "BATTLEFOIL", "BATTL", "BATTI",
            "GLOW", "HEX", "FIRE", "ICE", "BRAWL", "STEEL", "SUPER",
            "GUM", "FRE", "JACKSON", "JAEKSON", "JACISON", "IRIKSON",
            "IAIKSUN", "IKSUN", "BO", "COST", "PLAY", "REVEAL",
            "DISCARD", "REBATE", "SHUFFLE", "HAND", "DECK", "PLAYBOOK",
            "HERO", "HEROS",
        ]
        func wordsFor(_ text: String) -> [String] {
            text.components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
                .filter { $0.count >= 4 && !stopWords.contains($0) }
        }
        let allWords = wordsFor(allText)
        let topLeftWords = wordsFor(topLeftText)
        var best: (card: Card, score: Int)?
        for card in candidates {
            let hero = card.hero.uppercased()
            guard hero.count >= 4 else { continue }
            var score = 0
            for w in allWords {
                if heroWordMatches(hero, w) { score += 1 }
            }
            for w in topLeftWords {
                if heroWordMatches(hero, w) { score += 3 }
            }
            if let cur = best {
                if score > cur.score { best = (card, score) }
            } else if score >= 1 {
                best = (card, score)
            }
        }
        return best?.card
    }

    private static func heroWordMatches(_ hero: String, _ word: String) -> Bool {
        if hero == word { return true }
        if hero.contains(word) { return true }
        if word.contains(hero) { return true }
        let minLen = min(hero.count, word.count)
        guard minLen >= 4 else { return false }
        let heroPref = String(hero.prefix(minLen))
        let wordPref = String(word.prefix(minLen))
        if heroPref == wordPref { return true }
        if minLen >= 5 {
            let h = Array(hero.prefix(minLen))
            let w = Array(word.prefix(minLen))
            let diffs = zip(h, w).filter { $0 != $1 }.count
            if diffs <= 1 { return true }
        }
        return false
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
