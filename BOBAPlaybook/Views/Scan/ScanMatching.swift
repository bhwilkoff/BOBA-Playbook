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

    /// Grid-specific resolver. Combines three independent signals —
    /// OCR cardNumber, hero-name text search, and FeaturePrintIndex
    /// image similarity — and picks the card with the most
    /// corroboration. The Grid pipeline benefits enormously from
    /// cross-checking because each signal fails in different
    /// conditions:
    ///
    ///   • OCR cardNumber misreads when the bottom-left badge is
    ///     glare-blocked, partially cropped, or near-impossible to
    ///     read at small scale (Wattage 141, PB Buckets 7). It can
    ///     also pick up a NEIGHBORING card's number when the crop is
    ///     slightly off-center, which is what produced the
    ///     Cicada→"Phoenix BF-30", Castler→"Go-Cart BLBF-785", and
    ///     Jachammer→"Gunner 202" misreads in real-world testing.
    ///
    ///   • Hero-name search misses on cards where the hero text is
    ///     stylized or partially obscured (rare).
    ///
    ///   • Image similarity misses on cards that aren't in the FP
    ///     index (~17% of the catalog has no R2 image).
    ///
    /// Decision tree:
    ///
    ///   Stage 1. FP top ∈ cardNumber candidates → use it. Image
    ///            confirms OCR. Highest-confidence outcome.
    ///
    ///   Stage 2. OCR best's hero matches FP top's hero OR matches
    ///            heroSearch's hero → use OCR best. cardNumber +
    ///            either independent signal agrees.
    ///
    ///   Stage 3. FP top's hero matches heroSearch's hero (and OCR
    ///            best disagrees) → use FP top. Image AND text
    ///            agree on hero, OCR alone is contradicted.
    ///
    ///   Stage 4. FP top distance ≤ 85% of best-cand-in-FP distance
    ///            → override to FP top. Image is meaningfully closer
    ///            than the OCR pick (loosened from the original 60%
    ///            threshold based on real-world distance distributions).
    ///
    ///   Stage 5. Fall back: ocrBest ?? heroBest ?? fpTop.
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

        // Hero-name search across the full catalog. Used as an
        // independent confirmation signal even when OCR successfully
        // extracted a cardNumber — when the printed hero name
        // disagrees with the OCR cardNumber's hero, that's a strong
        // "OCR misread the cardNumber" signal.
        let heroBestPair = matchByHeroWithScore(
            allText:     observation.fullText,
            topLeftText: observation.rawName,
            candidates:  allCards
        )
        let heroBest: Card? = heroBestPair?.card
        // Score ≥ 3 means the hero name appeared in topLeftText (the
        // top of the card — the most legible printed text). That's
        // the strongest single OCR signal available; we trust it
        // even when it contradicts ocrBest's cardNumber.
        let heroIsStrong = (heroBestPair?.score ?? 0) >= 3

        // FP top + neighbors. Keep the full top-K accessible so later
        // stages can look up the FP distance for arbitrary card ids
        // (e.g. comparing ocrBest's image distance against fpTop's
        // when both belong to the same hero).
        var fpTop: Card?
        var fpTopDistance: Float = .greatestFiniteMagnitude
        var bestCandInFPDistance: Float = .greatestFiniteMagnitude
        var fpDistanceById: [String: Float] = [:]
        if let cgImage = observation.cgImage,
           FeaturePrintIndex.shared.isLoaded {
            // topK = 50: large enough that several variants of the
            // identified hero (base + Battlefoils + Inspired Ink, etc.)
            // typically all land in the results, which lets later
            // stages pick the right variant by image distance even
            // when the OCR-derived pick is the wrong treatment.
            let nearest = await FeaturePrintIndex.shared
                .searchNearest(in: cgImage, topK: 50)
            for entry in nearest { fpDistanceById[entry.bobaId] = entry.distance }
            if let top = nearest.first {
                fpTop = cardsByBobaId[top.bobaId]
                fpTopDistance = top.distance
            }
            let candidateIds = Set(candidates.map { $0.id })
            if let bcip = nearest.first(where: { candidateIds.contains($0.bobaId) }) {
                bestCandInFPDistance = bcip.distance
            }
        }

        let candidateIds = Set(candidates.map { $0.id })

        // Hero comparison helper — matches across treatments. Two cards
        // share a "hero identity" if their `hero` fields agree (case-
        // insensitive, trimmed). Sealed products fall back to `name`.
        func heroIdentity(_ card: Card) -> String {
            let h = card.hero.uppercased()
            return h.isEmpty ? card.name.uppercased() : h
        }

        let ocrHero = ocrBest.map(heroIdentity)
        let heroBestHero = heroBest.map(heroIdentity)
        let fpHero = fpTop.map(heroIdentity)

        // Stage 1: cardNumber + hero text + FP image all agree on
        // hero. Within that hero group, prefer FP's specific variant
        // when it's a meaningfully better image match than OCR's
        // cardNumber-derived pick. Catches the "right hero, wrong
        // variant" failure where OCR extracts a bare digit ("38",
        // "135", "34") that maps to a real-but-wrong variant of the
        // identified hero, OR a glyph-confused prefix (CBF→GBF, etc).
        if let oh = ocrHero, oh == heroBestHero, oh == fpHero,
           let ocr = ocrBest, let fp = fpTop {
            // Same exact card: image confirms OCR.
            if fp.id == ocr.id { return fp }
            // Bare-digit cardNumber suggests OCR lost the prefix
            // (typical OCR partial read on stylized treatment badges).
            // The FP-identified variant of the same hero is more
            // likely correct than the catalog's bare-digit base
            // variant.
            let isBareDigit = ocr.cardNumber.allSatisfy { $0.isNumber }
                              && !ocr.cardNumber.isEmpty
            if isBareDigit { return fp }
            // Different variants, prefixed cardNumber. Compare image
            // distances: if FP top is meaningfully closer to the
            // captured image than OCR's pick, FP got the right
            // variant.
            let ocrFPDist = fpDistanceById[ocr.id] ?? .greatestFiniteMagnitude
            if fpTopDistance < ocrFPDist * 0.85 {
                return fp
            }
            return ocr
        }

        // Stage 2: cardNumber + hero text agree (FP unavailable or
        // disagreed on hero). Same bare-digit check as Stage 1, but
        // without an FP variant to fall back to — leave ocrBest alone
        // unless we can do better.
        if let oh = ocrHero, oh == heroBestHero, let ocr = ocrBest {
            return ocr
        }

        // Stage 3: FP image + hero text agree on a hero (and OCR's
        // cardNumber points to a different hero). Strongest "OCR
        // cardNumber was wrong" signal — the printed hero name and
        // the card art both contradict OCR. Catches the common
        // "neighbor crop bled into mine" failure where OCR pulled a
        // cardNumber from an adjacent grid cell.
        if let fh = fpHero, fh == heroBestHero, let fp = fpTop {
            return fp
        }

        // Stage 4: cardNumber + FP image agree on hero (hero text was
        // unreliable or didn't read clearly).
        if let oh = ocrHero, oh == fpHero, let ocr = ocrBest {
            return ocr
        }

        // Stage 5: hero text is strong (appeared in topLeftText) but
        // OCR and FP both disagree with it AND with each other. Trust
        // the printed hero name. Within that hero's group, prefer the
        // card with the smallest FP distance (best image match) — that
        // disambiguates variants more reliably than matchScore (which
        // is text-based and can't tell treatments apart). Falls back
        // to matchScore when no hero-group card lands in FP top-K.
        if heroIsStrong, let hh = heroBestHero {
            let inHero = allCards.filter { heroIdentity($0) == hh }
            let inHeroByFP = inHero.compactMap { card -> (Card, Float)? in
                guard let d = fpDistanceById[card.id] else { return nil }
                return (card, d)
            }
            if let closest = inHeroByFP.min(by: { $0.1 < $1.1 })?.0 {
                return closest
            }
            if let bestVariant = inHero
                .map({ ($0, matchScore($0, observation: observation)) })
                .max(by: { $0.1 < $1.1 })?.0 {
                return bestVariant
            }
        }

        // Stage 6: FP image is meaningfully closer than the OCR pick.
        // Catches OCR cardNumber misreads where hero text was missing.
        if let fp = fpTop,
           bestCandInFPDistance != .greatestFiniteMagnitude,
           fpTopDistance < bestCandInFPDistance * 0.85 {
            return fp
        }

        // Stage 7: FP top happens to be in OCR candidates (image
        // confirms OCR even without hero corroboration).
        if let fp = fpTop, candidateIds.contains(fp.id) {
            return fp
        }

        // Stage 8: fallbacks in priority order.
        if let ocr = ocrBest { return ocr }
        if let hb = heroBest { return hb }
        return fpTop
    }

    /// Hero-name match with the score returned alongside the card,
    /// so callers can gate decisions on confidence. Score 3+ means
    /// the hero appeared at least once in topLeftText (the +3 weight).
    /// Score 1–2 is a less confident allText-only hit.
    static func matchByHeroWithScore(
        allText: String,
        topLeftText: String,
        candidates: [Card]
    ) -> (card: Card, score: Int)? {
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
        return best
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
