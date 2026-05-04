import Foundation
import CoreGraphics

/// Unified card recognition. Every scan mode (single live, multi live,
/// show live, photo-picker still, grid burst) routes through
/// `ScanMatching.resolve(observation:allCards:label:)` so they all
/// benefit from the same evidence fusion: image fingerprint +
/// cardNumber + hero name, scored together with a hero-name veto and
/// "don't guess" confidence/margin gates.
///
/// In DEBUG builds the resolver prints a structured per-call trace
/// to the Xcode console — OCR text, top-5 FP candidates, top-5
/// scored candidates with per-signal breakdowns, and the rejection
/// reason when nothing committed. That makes it possible to look at
/// a wrong commit in the UI and diagnose the actual cause without
/// guessing about what Vision/OCR/FP returned.
/// `nonisolated` so every static helper inside (scoreCandidate,
/// kMin* constants, hero/color helpers, regex extractors, etc.) is
/// callable from the off-MainActor `resolve` / `resolveDetailed`
/// entry points. Without this the project's default-MainActor
/// isolation reapplies to every member, breaking the whole point of
/// taking the entry points off MainActor for grid-scan parallelism.
nonisolated enum ScanMatching {

    // MARK: - Public API

    /// Resolve an observation to a card, or `nil` when signals don't
    /// agree well enough. Pass a `label` (e.g., "cell row=0 col=2")
    /// to tag the console trace — call sites that batch many
    /// resolves should always set this so the per-cell traces don't
    /// interleave.
    /// Result of resolving a single cell's observation. `chosen` is the
    /// auto-committed card (nil when the resolver couldn't pick a clear
    /// winner). `topCandidates` is always populated when ANY candidate
    /// scored above zero — the UI uses it to drive the user-assisted
    /// disambiguation picker for cells where `chosen == nil`, AND for
    /// the optional "review" affordance on cells where `chosen != nil`
    /// but the margin to the runner-up was thin.
    struct Resolution {
        let chosen: Card?
        let topCandidates: [PickerCandidate]
    }

    /// Surfaced to the picker UI. `score` is the raw scoring total
    /// (~0–5 typical range); `normalizedScore` is the same value
    /// rescaled to 0…1 against the highest-scoring candidate in the
    /// set so the confidence bars compare candidates within this cell
    /// rather than across all cells.
    struct PickerCandidate: Identifiable, Equatable {
        let id: String          // card.id (== bobaId)
        let card: Card
        let score: Float
        let normalizedScore: Double

        static func == (lhs: PickerCandidate, rhs: PickerCandidate) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// Convenience wrapper that returns just the chosen card for callers
    /// (live single-card scan) that don't surface the picker.
    @MainActor
    static func resolve(
        observation: ScanObservation,
        allCards: [Card],
        label: String = ""
    ) async -> Card? {
        await resolveDetailed(
            observation: observation,
            allCards: allCards,
            label: label
        ).chosen
    }

    /// Back on MainActor (was nonisolated in 1.981 for grid-scan
    /// parallelism). Concurrent FP queries from 4 cells were
    /// competing with concurrent OCR for the Neural Engine and
    /// degrading both. Serializing on main lets each FP query
    /// run at full speed in the slot between OCR completions.
    @MainActor
    static func resolveDetailed(
        observation: ScanObservation,
        allCards: [Card],
        label: String = ""
    ) async -> Resolution {
        guard !allCards.isEmpty else {
            log(label: label, "empty catalog")
            return Resolution(chosen: nil, topCandidates: [])
        }

        let cardsById = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })

        // Border-color signal — sample two horizontal strips of the
        // cell crop (top and bottom borders, where the treatment
        // band lives) and classify into a color bucket. Treatments
        // with distinctive borders (Fire Tracks orange, Blizzard
        // blue, Pink/Bubble Gum pink, etc.) get +0.6 in scoring
        // when their expected color matches the detected bucket.
        // FP can't reliably tell same-hero treatments apart when
        // the central artwork is shared — color directly targets
        // the treatment-discriminating signal that FP averages out.
        let cellColorBucket: ColorBucket? = observation.cgImage
            .flatMap { extractCellColorBucket(cgImage: $0) }
        let borderSignature: BorderSignature? = observation.cgImage
            .flatMap { extractBorderSignature(cgImage: $0) }

        // OCR-text cardNumber signals.
        //
        // Two things get extracted from `observation.fullText`:
        //
        // (1) `ocrTreatmentPrefixes` — the leading letter run from
        //     any cardNumber-shaped pattern. "LBF-786" → "LBF",
        //     "BGBF-33" → "BGBF". Used by `treatment_prefix` to
        //     boost candidates whose own prefix is a substring of
        //     (or contains) the OCR prefix — catches "BLBF" via
        //     OCR's "LBF" because BLBF contains LBF.
        //
        // (2) `ocrFullPatterns` — the entire cardNumber-shaped
        //     pattern, including digits-in-prefix that the strict
        //     extractor rejects. "F1-76", "LBF-786", "BGBF-33".
        //     Used by `cn_fuzzy` to boost candidates whose
        //     cardNumber is within edit-distance-1 of any pattern.
        //     This is the structural fix for OCR misreading a
        //     single character: FT-76 ↔ F1-76 (T→1), GBF-94 ↔
        //     CBF-94 (G→C), BLBF-786 ↔ LBF-786 (missing leading B).
        let ocrTreatmentPrefixes = extractCardNumberPrefixes(from: observation.fullText)
        var ocrFullPatterns = extractCardNumberFullPatterns(from: observation.fullText)
        // The CardScanner OCR pipeline already runs glyph substitution
        // (S→5, B→8, I→1, etc.) and catalog validation to produce
        // `observation.cardNumber`. That string is high-quality OCR
        // signal, but until now it only fed `cn_exact` and `cn_suffix`.
        // Adding it to the fuzzy-match pattern set lets neighboring
        // candidates also get cn_fuzzy credit — e.g., when OCR settles
        // on "RHBF-35" but the real card is "RHBF-39", `RHBF-39-Rook`
        // now picks up cn_fuzzy_d1 (+1.2) instead of getting nothing.
        if !observation.cardNumber.isEmpty {
            ocrFullPatterns.insert(observation.cardNumber.uppercased())
        }

        // 1. FP query — single Vision pass, full distance map.
        var fpDistance: [String: Float] = [:]
        var fpRanked: [String] = []
        if let cgImage = observation.cgImage,
           FeaturePrintIndex.shared.isLoaded {
            fpDistance = await FeaturePrintIndex.shared.distances(in: cgImage)
            fpRanked = fpDistance
                .sorted { $0.value < $1.value }
                .map { $0.key }
        }

        // 2. Strong hero set — hero identities the resolver is
        //    confident about. Two sources, unioned:
        //    (a) Hero name reads in the top-left quadrant. The
        //        traditional signal — works when OCR cleanly reads
        //        "CASTLER" / "CALIBER" / etc.
        //    (b) FP-majority hero — when ≥3 of the FP top-5 share
        //        the same hero identity, FP itself is telling us
        //        this is that hero. Catches cases where OCR fails
        //        on the hero text (only got "N" for Marksman in
        //        the r1c0 trace) but FP clearly identifies the
        //        hero (5/5 of top-5 were Marksman variants).
        let topLeftHeroIdentities = heroIdentitiesInTopLeft(
            allCards:    allCards,
            topLeftText: observation.rawName
        )
        var strongHeroIdentities = topLeftHeroIdentities
        // FP-majority threshold: ≥2 of FP top-3 share a hero, AND
        // top-1 is that hero. The "top-1 must be the hero" gate
        // protects against spurious additions when top-3 happens to
        // contain 2 of an unrelated hero — if FP put that hero at
        // position 1, FP is genuinely confident about it. Catches
        // BaldWing-scan-2-style cases where hero text didn't OCR
        // (topLeft was empty) but FP top-3 had BaldWing at position
        // 0 and 2 (with Game Over interleaved at 1).
        if fpRanked.count >= 2,
           let topId = fpRanked.first,
           let topCard = cardsById[topId] {
            let topHero = heroIdentity(topCard)
            var topHeroCount = 1
            for id in fpRanked.prefix(3).dropFirst() {
                if let card = cardsById[id], heroIdentity(card) == topHero {
                    topHeroCount += 1
                }
            }
            if topHeroCount >= 2 {
                strongHeroIdentities.insert(topHero)
            }
        }

        // 3. Candidate pool — union of four independent sources.
        //    The picker only sees what's in this pool, so the goal
        //    here is to err generously on inclusion and let scoring
        //    rank within. A card that's never in the pool can never
        //    be picked.
        var candidateIds: Set<String> = []

        // (a) FP top-50: image-similarity rank. Bumped from 30 so
        //     visually-close candidates that FP ranked just outside
        //     the cut also reach the picker.
        for id in fpRanked.prefix(50) { candidateIds.insert(id) }

        let cn = observation.cardNumber.uppercased()
        if !cn.isEmpty {
            for c in allCards where c.cardNumber.uppercased() == cn {
                candidateIds.insert(c.id)
            }
        }

        // Digit-suffix recovery — extract the numeric portion from
        // the OCR cardNumber and seed any catalog entry whose
        // cardNumber ends in `-{digits}`. Two cases:
        //   (a) Bare-digit cn ("20", "135") — same logic as before,
        //       finds matching base-set cards and prefixed variants.
        //   (b) Letters-prefix cn ("BF-94") where the letters partially
        //       miscount — the digit suffix "94" should still match
        //       the *real* cardNumber ("GBF-94" = Marksman Green
        //       Battlefoil) because OCR likely missed a letter from
        //       the prefix. This is the r1c0 case from the trace.
        let digitSuffix: String? = {
            if cn.isEmpty { return nil }
            if cn.allSatisfy({ $0.isNumber }) { return cn }
            // Pattern: anything-digits at the end. Take the trailing
            // digit run.
            let digits = cn.reversed().prefix(while: { $0.isNumber })
            let s = String(digits.reversed())
            return s.isEmpty ? nil : s
        }()
        if let digits = digitSuffix {
            let target = "-" + digits
            for c in allCards where c.cardNumber.uppercased().hasSuffix(target) {
                candidateIds.insert(c.id)
            }
        }

        // Element-filtered bare-suffix expansion: when OCR captures a
        // confident element word (>= 2 mentions in fullText) AND a
        // short bare-digit cn (1-2 chars), seed cards whose bare
        // cardNumber ends with that digit AND matches the element.
        // Recovers cases where OCR truncated a bare cardNumber
        // (Skuba "188" → "8") — paired with the cn_suffix_element
        // scoring bonus, this lifts the right Base Set card into the
        // picker top-8 alongside the cn_exact bare matches.
        if !cn.isEmpty, cn.allSatisfy({ $0.isNumber }), cn.count <= 2 {
            let upperFull = observation.fullText.uppercased()
            let allElements = ["FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER"]
            let strongElement = allElements.first {
                countOccurrences(of: $0, in: upperFull) + countFuzzyElementOccurrences(in: upperFull, element: $0) >= 2
            }
            if let element = strongElement {
                for c in allCards {
                    let cardCN = c.cardNumber.uppercased()
                    let cardCNIsBare = !cardCN.contains("-")
                    guard cardCNIsBare, cardCN.hasSuffix(cn), cardCN.count > cn.count else { continue }
                    if c.element.uppercased() == element {
                        candidateIds.insert(c.id)
                    }
                }
            }
        }
        // ELEMENT + NO-CN SEEDING. When OCR captures NO usable
        // cardNumber but DOES capture a confident element word
        // (≥2 exact OR fuzzy mentions in any quadrant), surface
        // ALL Base Set cards of that element as candidates. Pure
        // recovery for cells where the badge is unreadable but the
        // element badge bled through.
        if cn.isEmpty {
            let allElements = ["FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER"]
            let upperFull = observation.fullText.uppercased()
            let strongElement = allElements.first {
                countOccurrences(of: $0, in: upperFull) + countFuzzyElementOccurrences(in: upperFull, element: $0) >= 2
            }
            if let element = strongElement {
                for c in allCards {
                    guard c.element.uppercased() == element else { continue }
                    guard c.treatment == "Base Set" else { continue }
                    candidateIds.insert(c.id)
                }
            }
        }

        // HERO + DIGIT-SUFFIX RECOVERY (Maverick-class). When the
        // bottom-area OCR contains a token like "80F-72" — clean
        // digit suffix but garbled prefix that can't be reverse-
        // substituted — extract the suffix and look for cards
        // matching the strong hero whose cardNumber ends in that
        // suffix. Recovers cases where Vision misread prefix
        // letters as digits (R→8, B→0) and the prefix is
        // unrecoverable but the digit tail is clean.
        var heroSuffixHits: Set<String> = []
        if !strongHeroIdentities.isEmpty {
            let suffixPattern = try! NSRegularExpression(pattern: #"[A-Z0-9]{1,6}-(\d{1,4})"#)
            let botText = "\(observation.rawVariation) \(observation.fullText)".uppercased()
            let r = NSRange(botText.startIndex..., in: botText)
            var foundSuffixes: Set<String> = []
            suffixPattern.enumerateMatches(in: botText, range: r) { m, _, _ in
                if let m, let rr = Range(m.range(at: 1), in: botText) {
                    foundSuffixes.insert(String(botText[rr]))
                }
            }
            for suffix in foundSuffixes {
                let target = "-" + suffix
                for c in allCards
                where strongHeroIdentities.contains(heroIdentity(c))
                  && c.cardNumber.uppercased().hasSuffix(target) {
                    candidateIds.insert(c.id)
                    heroSuffixHits.insert(suffix)
                }
            }
        }

        // (c) Strong-hero variants top-20 by FP distance. Bumped from
        //     12 so more treatment options for the identified hero
        //     reach the picker — the user often needs to choose among
        //     5-8 variants, not the resolver's top 12.
        if !strongHeroIdentities.isEmpty {
            let heroVariants = allCards.filter {
                strongHeroIdentities.contains(heroIdentity($0))
            }
            let ranked = heroVariants.sorted {
                (fpDistance[$0.id] ?? .greatestFiniteMagnitude) <
                (fpDistance[$1.id] ?? .greatestFiniteMagnitude)
            }
            for c in ranked.prefix(20) { candidateIds.insert(c.id) }
        }

        // (d) Color-matching hero variants (NEW). When BOTH the cell's
        //     border color is detected AND a hero is identified, every
        //     variant of that hero whose treatment maps to the same
        //     color bucket earns candidacy regardless of FP rank.
        //     This is the targeted fix for "the right red Doublecheck
        //     wasn't even an option" — FP can't reliably tell red
        //     treatments apart from each other, but a red card almost
        //     certainly belongs to a red-bucketed treatment, so all
        //     red treatments of the right hero must be in the pool.
        if let cellColor = cellColorBucket, !strongHeroIdentities.isEmpty {
            let colorMatched = allCards.filter { card in
                guard strongHeroIdentities.contains(heroIdentity(card)),
                      let treatment = card.treatment,
                      let expected = expectedColorBucket(for: treatment)
                else { return false }
                return expected == cellColor
            }
            let ranked = colorMatched.sorted {
                (fpDistance[$0.id] ?? .greatestFiniteMagnitude) <
                (fpDistance[$1.id] ?? .greatestFiniteMagnitude)
            }
            for c in ranked.prefix(20) { candidateIds.insert(c.id) }
        }

        let candidates = candidateIds.compactMap { cardsById[$0] }

        guard !candidates.isEmpty else {
            logTrace(
                label:                 label,
                observation:           observation,
                strongHeroIdentities:  strongHeroIdentities,
                fpRanked:              fpRanked,
                fpDistance:            fpDistance,
                cardsById:             cardsById,
                topCandidates:         [],
                chosen:                nil,
                rejection:             "no candidates",
                cellColorBucket:       cellColorBucket
            )
            return Resolution(chosen: nil, topCandidates: [])
        }

        // 4. Score every candidate, with per-signal breakdown for
        //    the trace.
        let fpRankIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: fpRanked.enumerated().map { ($1, $0) }
        )
        let scored = candidates.map { card in
            scoreCandidate(
                card,
                observation:           observation,
                fpRankIndex:           fpRankIndex,
                fpDistance:            fpDistance,
                strongHeroIdentities:  strongHeroIdentities,
                topLeftHeroIdentities: topLeftHeroIdentities,
                ocrTreatmentPrefixes:  ocrTreatmentPrefixes,
                ocrFullPatterns:       ocrFullPatterns,
                cellColorBucket:       cellColorBucket,
                heroSuffixHits:        heroSuffixHits,
                borderSignature:       borderSignature
            )
        }

        // 5. Pick winner with confidence + hero-aware margin gates.
        // Pre-sort: total descending, then FP distance ascending so
        // candidates that score identically (Ozzmosis-172 vs
        // Laviathan-172 — same hero, element, power, treatment, cn)
        // get tiebroken by FP distance — closer card wins.
        let ranked = scored.sorted { (a, b) -> Bool in
            if a.total != b.total { return a.total > b.total }
            let aDist = fpDistance[a.card.id] ?? .greatestFiniteMagnitude
            let bDist = fpDistance[b.card.id] ?? .greatestFiniteMagnitude
            return aDist < bDist
        }
        let chosen: Card?
        let rejection: String?

        if let top = ranked.first, top.total >= kMinConfidence {
            if ranked.count >= 2 {
                let nextDifferentHero = ranked.dropFirst().first { entry in
                    heroIdentity(entry.card) != heroIdentity(top.card)
                }
                if let other = nextDifferentHero {
                    let margin = top.total - other.total
                    if margin < kMinMargin {
                        chosen = nil
                        rejection = String(
                            format: "tight margin (top %.2f vs different-hero %.2f, Δ %.2f < %.2f)",
                            top.total, other.total, margin, kMinMargin
                        )
                    } else {
                        chosen = top.card
                        rejection = nil
                    }
                } else {
                    chosen = top.card
                    rejection = nil
                }
            } else {
                chosen = top.card
                rejection = nil
            }
        } else {
            chosen = nil
            rejection = String(
                format: "below confidence (top %.2f < %.2f)",
                ranked.first?.total ?? 0, kMinConfidence
            )
        }

        // Top-8 for the picker (was 5) — when same-hero treatments
        // cluster within a fraction of a point of each other, the
        // user benefits from seeing more options. Console trace still
        // logs the top-5 to keep the per-cell trace compact.
        let top5ForTrace = Array(ranked.prefix(5))
        let top8ForPicker = Array(ranked.prefix(8))
        logTrace(
            label:                 label,
            observation:           observation,
            strongHeroIdentities:  strongHeroIdentities,
            fpRanked:              fpRanked,
            fpDistance:            fpDistance,
            cardsById:             cardsById,
            topCandidates:         top5ForTrace,
            chosen:                chosen,
            rejection:             rejection,
            cellColorBucket:       cellColorBucket
        )

        // Normalize scores against the highest-scoring candidate so
        // the confidence bars compare candidates within this cell
        // rather than across cells.
        let maxScore = max(0.001, top8ForPicker.first.map { Double($0.total) } ?? 0.001)
        let pickerCandidates: [PickerCandidate] = top8ForPicker.map { scored in
            PickerCandidate(
                id: scored.card.id,
                card: scored.card,
                score: scored.total,
                normalizedScore: max(0, min(1, Double(scored.total) / maxScore))
            )
        }

        return Resolution(chosen: chosen, topCandidates: pickerCandidates)
    }

    // MARK: - Scoring (1.937-era weights — restored after a series of
    //         speculative tweaks to FP boost / OCR corroboration /
    //         prefix matching that each fixed one case while breaking
    //         others. Holding these weights stable until console
    //         traces give us real data to tune against.)

    /// Confidence floor — at least one OCR-text signal needs to
    /// corroborate FP for a commit. FP top-1 alone (+1.0) is below
    /// the floor, which prevents committing on a coincidental
    /// nearest-neighbor when OCR fails entirely.
    private static let kMinConfidence: Float = 1.4

    /// Margin floor between the top candidate and the highest-scoring
    /// DIFFERENT-hero candidate. Same-hero treatment ambiguity is
    /// not gated (FP rank picks the treatment).
    private static let kMinMargin: Float = 0.3

    private struct Scored {
        let card: Card
        let total: Float
        let signals: [(name: String, weight: Float)]
    }

    private static func scoreCandidate(
        _ card: Card,
        observation: ScanObservation,
        fpRankIndex: [String: Int],
        fpDistance: [String: Float],
        strongHeroIdentities: Set<String>,
        topLeftHeroIdentities: Set<String>,
        ocrTreatmentPrefixes: Set<String>,
        ocrFullPatterns: Set<String>,
        cellColorBucket: ColorBucket?,
        heroSuffixHits: Set<String>,
        borderSignature: BorderSignature?
    ) -> Scored {
        var signals: [(name: String, weight: Float)] = []
        var total: Float = 0

        // FP rank — top-1 = 1.0, decays linearly to 0 at rank 13.
        if let r = fpRankIndex[card.id] {
            let w = max(0, 1.0 - Float(r) * 0.08)
            if w > 0 {
                total += w
                signals.append(("fp_rank_\(r)", w))
            }
        }
        // Tiny continuous FP-distance bonus to break ties between
        // candidates that otherwise score identically (e.g.
        // Ozzmosis-172 vs Laviathan-172). Capped at +0.05 so it
        // never overrides a real signal.
        if let d = fpDistance[card.id] {
            let bonus = max(0, min(0.05, (1.0 - d) * 0.1))
            if bonus > 0 {
                total += bonus
                signals.append(("fp_proximity", bonus))
            }
        }

        // CardNumber — three mutually-exclusive signals, in priority
        // order. Only the strongest one fires per candidate, so a
        // single OCR read can't double-boost any candidate.
        //
        //   cn_exact (+1.5): observation.cardNumber matches card
        //   exactly. Strongest signal — OCR successfully read the
        //   printed badge.
        //
        //   cn_fuzzy (+1.2): card.cardNumber is within edit-distance-1
        //   of any pattern extracted from observation.fullText.
        //   Catches OCR substitutions ("F1-76" ↔ "FT-76",
        //   "CBF-94" ↔ "GBF-94"), insertions ("LBF-786" ↔
        //   "BLBF-786"), and deletions. Both prefix-side and
        //   suffix-side errors get caught.
        //
        //   cn_suffix (+0.4): the digit suffix of observation
        //   .cardNumber matches the card's digit suffix even though
        //   the prefix differs. Weaker because the same digit suffix
        //   can occur across many treatment families.
        let cardCN = card.cardNumber.uppercased()
        let cn = observation.cardNumber.uppercased()
        let cardCNIsBare = !cardCN.contains("-")
        var cnFired = false
        if !cn.isEmpty, cardCN == cn {
            let isBareDigits = cn.allSatisfy { $0.isNumber }
            // Bare-digit cn matches stay weak (0.6) by default
            // because OCR often confuses single tokens (e.g. "BO" →
            // "80"). But when the extracted cn appears 2+ times in
            // OCR text — Ozzmosis "172 172 2026 172" — that's
            // high-confidence and gets the same 1.5 weight as a
            // prefixed cn_exact. Catches Base Set cards where FP
            // picks the wrong treatment.
            var weight: Float = isBareDigits ? 0.6 : 1.5
            if isBareDigits {
                let occurrences = countOccurrences(of: cn, in: observation.fullText)
                if occurrences >= 2 { weight = 1.5 }
            }
            total += weight
            signals.append((isBareDigits ? "cn_exact_bare" : "cn_exact", weight))
            cnFired = true
        }
        if !cnFired {
            var bestDist = 3
            for pattern in ocrFullPatterns {
                let dist = levenshtein(cardCN, pattern)
                if dist < bestDist { bestDist = dist }
                if bestDist == 0 { break }
            }
            if bestDist <= 1 {
                total += 1.2
                signals.append(("cn_fuzzy_d\(bestDist)", 1.2))
                cnFired = true
            } else if bestDist == 2 {
                // For bare-digit cardCNs, d=2 means matching only 1
                // of ~3 digits ("172"↔"163") — way too loose. Drop
                // the weight so it can't compete with cn_exact.
                let w: Float = cardCNIsBare ? 0.3 : 1.0
                total += w
                signals.append(("cn_fuzzy_d2", w))
                cnFired = true
            }
        }
        if !cnFired, !cn.isEmpty {
            let digits = cn.reversed().prefix(while: { $0.isNumber })
            let suffix = String(digits.reversed())
            if !suffix.isEmpty {
                // Prefixed cardCN (BF-188): match "-188".
                // Bare cardCN (188): match suffix when OCR cn is
                // shorter (truncated read of "188" → "8").
                let prefixedSuffix = cardCN.hasSuffix("-" + suffix)
                let bareSuffix = cardCNIsBare
                              && cardCN != suffix
                              && cardCN.hasSuffix(suffix)
                              && cardCN.count > suffix.count
                if prefixedSuffix || bareSuffix {
                    total += 0.4
                    signals.append(("cn_suffix", 0.4))
                    cnFired = true
                }
            }
        }

        // Hero name — strongest in top-left, decays for "anywhere",
        // and when neither OCR signal fires we fall back to "this
        // card's hero is in the strongHero set" (which can come from
        // FP-majority detection — see step 2 of resolve). The fallback
        // is what lifts a Marksman variant above the confidence floor
        // when OCR couldn't read "MARKSMAN" but FP top-5 unanimously
        // identified the hero.
        let heroAtTop = heroNameScore(card.hero, in: observation.rawName)
        let heroAnywhere = heroNameScore(card.hero, in: observation.fullText)
        if heroAtTop > 0 {
            total += 1.5
            signals.append(("hero_topleft", 1.5))
        } else if heroAnywhere > 0 {
            total += 0.6
            signals.append(("hero_anywhere", 0.6))
        } else if strongHeroIdentities.contains(heroIdentity(card)) {
            total += 1.0
            signals.append(("hero_inferred", 1.0))
        } else if cnFired,
                  signals.contains(where: { $0.name == "cn_exact" || $0.name == "cn_exact_bare" }) {
            // cn matched exactly but the FP/topLeft hero list pointed
            // somewhere else. Only grant the implied bonus when the
            // topLeft hero set is silent — if topLeft clearly named
            // a hero (Hoopie, Discard Rebate), trust that over a
            // noisy bare-digit cn read of a different hero.
            let topLeftSilent = topLeftHeroIdentities.isEmpty
            let topLeftAgrees = topLeftHeroIdentities.contains(heroIdentity(card))
            if topLeftSilent || topLeftAgrees {
                total += 1.0
                signals.append(("hero_implied_by_cn", 1.0))
            }
        }

        // Hero veto — printed hero contradicts this candidate.
        // Bypassed when cn_exact (any) fires for THIS card: OCR
        // reading the cardNumber exactly is a stronger signal than
        // FP-derived hero majority. Recovers the Ozzmosis-172 case
        // where FP says Big-Z but OCR clearly read "172".
        var cnExactFired = false
        for s in signals {
            if s.name == "cn_exact" || s.name == "cn_exact_bare" {
                cnExactFired = true; break
            }
        }
        let heroMatched = strongHeroIdentities.contains(heroIdentity(card))
        let shouldVeto = !strongHeroIdentities.isEmpty && !heroMatched && !cnExactFired
        if shouldVeto {
            total -= 2.0
            signals.append(("hero_veto", -2.0))
        }

        // Treatment-prefix match — only fires when no cn signal
        // already credited this candidate (otherwise it'd
        // double-count: cn_exact already encodes the prefix). When
        // FP can't distinguish treatments that share artwork
        // (Castler's LOGO-786 vs BLBF-786 — same character art,
        // different foil) and OCR couldn't extract a usable
        // cardNumber, the leading letter run that OCR salvaged from
        // the badge text is the deciding signal. Compares with
        // bidirectional substring (Swift `contains`) so OCR
        // mangling at either end of the prefix is tolerated:
        // catalog "BLBF" contains OCR "LBF" (missed leading B),
        // catalog "BLB" is contained in OCR "BLBF" (extra trailing
        // letter), etc.
        if !cnFired, !ocrTreatmentPrefixes.isEmpty {
            let dashIdx = cardCN.firstIndex(of: "-")
            let cardPrefix = dashIdx.map { String(cardCN[..<$0]) } ?? ""
            if !cardPrefix.isEmpty, cardPrefix.allSatisfy({ $0.isLetter }) {
                let matches = ocrTreatmentPrefixes.contains { ocr in
                    cardPrefix.contains(ocr) || ocr.contains(cardPrefix)
                }
                if matches {
                    total += 0.5
                    signals.append(("treatment_prefix", 0.5))
                }
            }
        }

        // Element word — exact OR fuzzy. Vision occasionally misreads
        // element badges on stylized treatments ("BRAWL"→"BRAWIL",
        // "ICE"→"HCE"); a 1-edit fuzzy match recovers these.
        var elementWordFired = false
        if !card.element.isEmpty {
            let upperElem = card.element.uppercased()
            let upperFull = observation.fullText.uppercased()
            if upperFull.contains(upperElem) {
                total += 0.2
                signals.append(("element_word", 0.2))
                elementWordFired = true
            } else if elementFuzzyContains(upperFull, element: upperElem) {
                total += 0.15
                signals.append(("element_word_fuzzy", 0.15))
                elementWordFired = true
            }
        }
        if elementWordFired,
           cardCNIsBare,
           !cn.isEmpty,
           cardCN != cn,
           cardCN.hasSuffix(cn) {
            let upperFull = observation.fullText.uppercased()
            let upperElem = card.element.uppercased()
            let elementCount = countOccurrences(of: upperElem, in: upperFull)
                             + countFuzzyElementOccurrences(in: upperFull, element: upperElem)
            if elementCount >= 2 {
                total += 0.6
                signals.append(("cn_suffix_element", 0.6))
            }
        }

        // Treatment word.
        if let treatment = card.treatment, !treatment.isEmpty {
            let words = treatment.uppercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }
            let hits = words.filter { observation.fullText.contains($0) }.count
            if hits > 0 {
                let w = min(0.3, Float(hits) * 0.1)
                total += w
                signals.append(("treatment_word_x\(hits)", w))
            }
        }

        // Power match.
        let powerText = observation.rawPower.isEmpty
            ? observation.fullText : observation.rawPower
        if let power = card.power, extractIntegers(from: powerText).contains(power) {
            total += 0.3
            signals.append(("power_match", 0.3))
        }

        // Treatment-color match — when the cell-crop's border color
        // bucket matches the candidate's expected treatment color
        // (Fire Tracks→orange, Blizzard→blue, Pink→pink, etc.). This
        // is the targeted fix for FP's same-hero treatment confusion:
        // FP averages all visual signal into one 768-d embedding, so
        // border colors get diluted by central character art that's
        // shared across treatments. Sampling the border directly
        // gives a clean treatment signal.
        if let cellColor = cellColorBucket,
           let treatment = card.treatment,
           let expected = expectedColorBucket(for: treatment),
           expected == cellColor {
            // Reduced from 0.6 to 0.3 — the strip-sample border
            // detector occasionally bleeds in artwork color (PB
            // Buckets basketball orange triggered Grillin' orange,
            // beating the correct Base Set). Color is still useful
            // as a tiebreaker but shouldn't override fp_rank_0 wins.
            total += 0.3
            signals.append(("treatment_color_\(cellColor.name)", 0.3))
        }

        // BORDER SPECKLE SIGNATURE.
        // High pixel-to-pixel luminance variance in the border samples
        // indicates a fine-grained speckled foil treatment —
        // distinctively characteristic of Icon Battlefoils + Power
        // Glove Battlefoils (small icon shapes embedded in metallic
        // foil at high spatial frequency). Other "holographic"
        // treatments (Mixtape, 80's Rad, Linoleum, Logofoil) have
        // larger pattern features that smooth out at the pixel-pair
        // level (localVar < 15 in baseline). Catches Icon Battlefoils
        // when OCR fails to read the cn badge on the silver-on-silver
        // foil background — solves the Doublecheck IBF-291 / Forcefield
        // IBF-191 case where FP wrongly favored Alpha/Grillin'.
        if let sig = borderSignature, sig.localVarianceAboveSpeckleThreshold,
           let treatment = card.treatment {
            let speckleClass: Set<String> = [
                "Icon Battlefoil",
                "Power Glove Battlefoil"
            ]
            if speckleClass.contains(treatment) {
                total += 1.0
                signals.append(("border_speckle_signature", 1.0))
            }
        }

        // HERO + DIGIT-SUFFIX RECOVERY (Maverick-class). Fires when
        // this card's hero matches the strong-hero set AND its
        // cardNumber ends with one of the digit suffixes Vision
        // picked up from the badge area where the prefix letters
        // were mangled beyond reverse-substitution.
        if !heroSuffixHits.isEmpty,
           strongHeroIdentities.contains(heroIdentity(card)) {
            let cardCNUpper = card.cardNumber.uppercased()
            for suffix in heroSuffixHits {
                if cardCNUpper.hasSuffix("-" + suffix) || cardCNUpper == suffix {
                    total += 0.7
                    signals.append(("hero_suffix_recovery", 0.7))
                    break
                }
            }
        }

        return Scored(card: card, total: total, signals: signals)
    }

    // MARK: - Console trace
    //
    // Per-cell scan tracing is silenced. The hooks remain so the
    // resolver flow stays unchanged; flip these to print() bodies
    // again if a future debugging session needs the per-cell signal
    // breakdown back.

    private static func log(label: String, _ message: String) { }

    private static func logTrace(
        label: String,
        observation: ScanObservation,
        strongHeroIdentities: Set<String>,
        fpRanked: [String],
        fpDistance: [String: Float],
        cardsById: [String: Card],
        topCandidates: [Scored],
        chosen: Card?,
        rejection: String?,
        cellColorBucket: ColorBucket?
    ) { }

    // MARK: - Hero identity helpers

    static func heroIdentity(_ card: Card) -> String {
        let h = card.hero.uppercased().trimmingCharacters(in: .whitespaces)
        return h.isEmpty
            ? card.name.uppercased().trimmingCharacters(in: .whitespaces)
            : h
    }

    private static let stopWords: Set<String> = [
        "FIRST", "EDITION", "EDITON", "EDTON", "EDITVON", "EDITIDN",
        "BATTLE", "ARENA", "BATTTE", "TARENA", "POWER", "ROOKIE",
        "INSPIRED", "INSPIREO", "BATTLEFOIL", "BATTL", "BATTI",
        // Common OCR misreads of BATTLE / ARENA that otherwise leak
        // into hero matching via heroWordMatches' 1-char-diff
        // tolerance and falsely trigger heroes like "BATTLE BACK"
        // or "DUMPSTER BATTLE" from the cell's boilerplate text.
        "BAITLE", "BAITTI", "BAITTLE", "BATILE", "BATIL", "BATT",
        "AREMA", "ABENA", "AREWA", "ARENG", "AREN", "AREWG",
        "GLOW", "HEX", "FIRE", "ICE", "BRAWL", "STEEL", "SUPER",
        "GUM", "FRE", "JACKSON", "JAEKSON", "JACISON", "IRIKSON",
        "IAIKSUN", "IKSUN", "BO", "COST", "PLAY", "REVEAL",
        "DISCARD", "REBATE", "SHUFFLE", "HAND", "DECK", "PLAYBOOK",
        "HERO", "HEROS",
    ]

    /// Count occurrences of a substring in a haystack (non-overlapping).
    /// Used by cn_exact_bare repetition gating and cn_suffix_element
    /// element-strength check.
    static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var idx = haystack.startIndex
        while let r = haystack.range(of: needle, range: idx..<haystack.endIndex) {
            count += 1
            idx = r.upperBound
        }
        return count
    }

    /// Fuzzy element-word match: split the haystack into uppercase
    /// alphabetic words ≥3 chars and check whether any is within
    /// edit-distance 1 of `element`. Recovers Vision misreads of
    /// element badges on stylized treatments — "BRAWL" → "BRAWIL"
    /// (insert I), "ICE" → "HCE" (substitute H for I), etc.
    static func elementFuzzyContains(_ haystack: String, element: String) -> Bool {
        guard element.count >= 3 else { return false }
        let tokens = haystack.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.uppercased() }
            .filter { $0.count >= max(2, element.count - 1) && $0.count <= element.count + 2 }
        for tok in tokens {
            if tok == element { return true }
            if levenshtein(tok, element) <= 1 { return true }
        }
        return false
    }

    static func countFuzzyElementOccurrences(in haystack: String, element: String) -> Int {
        guard element.count >= 3 else { return 0 }
        let tokens = haystack.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.uppercased() }
            .filter { $0.count >= max(2, element.count - 1) && $0.count <= element.count + 2 }
        var count = 0
        for tok in tokens {
            if tok == element || levenshtein(tok, element) <= 1 { count += 1 }
        }
        return count
    }

    static func heroIdentitiesInTopLeft(
        allCards: [Card],
        topLeftText: String
    ) -> Set<String> {
        guard !topLeftText.isEmpty else { return [] }
        let words = topLeftText
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        guard !words.isEmpty else { return [] }
        var identitiesSeen: Set<String> = []
        var matched: Set<String> = []
        for card in allCards {
            let hero = card.hero.uppercased()
            guard hero.count >= 4 else { continue }
            let ident = heroIdentity(card)
            if identitiesSeen.contains(ident) { continue }
            identitiesSeen.insert(ident)
            for w in words where heroWordMatches(hero, w) {
                matched.insert(ident)
                break
            }
        }
        return matched
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

    /// Extract entire cardNumber-shaped patterns (prefix + dash +
    /// digits) from OCR text. The regex is permissive about a stray
    /// digit/letter mixed into the prefix so it captures OCR misreads
    /// like "F1-76" (real "FT-76" with T→1) or "BLB7-786" (real
    /// "BLBF-786" with F→7). Patterns are compared via Levenshtein
    /// distance to catalog cardNumbers in `cn_fuzzy` scoring.
    static func extractCardNumberFullPatterns(from text: String) -> Set<String> {
        let upper = text.uppercased()
        guard !upper.isEmpty else { return [] }
        // Allow 1-5 leading characters (letters-or-digits), at least
        // one of which must be a letter (the `[A-Z]` anchor at the
        // start). Trailing 1-4 digits after the dash. Whitespace
        // around the dash is tolerated and stripped from the capture.
        // Separator class `[\s-]+` allows OCR to drop the dash entirely
        // and substitute a space — "EHBF 43" matches as "EHBF" + "43"
        // even though no literal dash is present. Catalog cardNumbers
        // always render as `PREFIX-DIGITS` (with a literal dash), so
        // we synthesize the dash on the way out for fuzzy-match
        // comparisons.
        let pattern = #"\b([A-Z][A-Z0-9]{0,4})[\s-]+(\d{1,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var patterns: Set<String> = []
        let range = NSRange(upper.startIndex..., in: upper)
        regex.enumerateMatches(in: upper, range: range) { match, _, _ in
            guard let match = match,
                  let prefRange = Range(match.range(at: 1), in: upper),
                  let digRange = Range(match.range(at: 2), in: upper)
            else { return }
            patterns.insert("\(upper[prefRange])-\(upper[digRange])")
        }
        return patterns
    }

    /// Levenshtein edit distance — the minimum number of single-
    /// character insertions, deletions, or substitutions needed to
    /// transform one string into the other. Used by `cn_fuzzy` to
    /// boost candidates whose cardNumber is one character off from
    /// what OCR actually read in fullText. The DP table is small
    /// (strings are ~10 chars) so this is essentially free.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,            // deletion
                    curr[j - 1] + 1,        // insertion
                    prev[j - 1] + cost      // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }

    /// Extract leading-letter prefixes from cardNumber-like patterns
    /// in OCR text. The regex permits a stray digit/letter inside
    /// the prefix (between letters and the dash) because OCR
    /// frequently mangles stylized treatment badges — "BLBF-786"
    /// reads as "BLB7-786" with the F→7 substitution. The capture
    /// group is the LEADING letter run, so "BLB7-786" yields "BLB".
    /// That partial prefix is enough to favor BLBF over LOGO/GGL/
    /// RAD when FP can't tell same-hero treatments apart.
    static func extractCardNumberPrefixes(from text: String) -> Set<String> {
        let upper = text.uppercased()
        guard !upper.isEmpty else { return [] }
        let pattern = #"\b([A-Z]{2,5})[A-Z0-9]?[\s-]+\d{1,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var prefixes: Set<String> = []
        let range = NSRange(upper.startIndex..., in: upper)
        regex.enumerateMatches(in: upper, range: range) { match, _, _ in
            guard let match = match,
                  let prefixRange = Range(match.range(at: 1), in: upper)
            else { return }
            prefixes.insert(String(upper[prefixRange]))
        }
        return prefixes
    }

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

    // MARK: - Color signal

    /// Coarse color bucket for treatment-border classification.
    /// Card treatments cluster into a small set of distinct color
    /// families (Fire Tracks orange, Blizzard blue, Pink pink, etc.)
    /// or are visibly holographic/multicolor (Logofoil, Grandma's
    /// Linoleum, Mixtape). Bucketing rather than RGB-distance
    /// matching is more robust to lighting and toploader reflections.
    struct ColorBucket: Equatable {
        let name: String
        static let red         = ColorBucket(name: "red")
        static let orange      = ColorBucket(name: "orange")
        static let yellow      = ColorBucket(name: "yellow")
        static let green       = ColorBucket(name: "green")
        static let blue        = ColorBucket(name: "blue")
        static let purple      = ColorBucket(name: "purple")
        static let pink        = ColorBucket(name: "pink")
        static let white       = ColorBucket(name: "white")
        static let holographic = ColorBucket(name: "holographic")
    }

    /// Border-pattern signature exposing finer-grained metrics than
    /// the dominant-hue ColorBucket. Used to detect treatment classes
    /// that share a color signal but differ in texture (e.g., Icon
    /// Battlefoils have silver-speckled foil borders that produce
    /// HIGH localVariance even when an element color dominates the
    /// hue histogram from element bleed).
    ///
    /// `localVariance`: average abs(luminance - prev neighbor) along
    /// the scan direction. Empirical baseline: solid-color treatments
    /// (Battlefoil, Alpha, Headlines, Base Set) and most "holographic"
    /// treatments (Mixtape, 80's Rad, Linoleum, Logofoil) stay below
    /// 15. Icon Battlefoils with visible speckle pattern register
    /// 25-35. The 18.0 threshold separates cleanly with margin.
    struct BorderSignature {
        let localVariance: Float
        let desatRatio: Float
        let hueBuckets: Int
        let coloredCount: Int
        let brightDesatCount: Int
        let dominantHueShare: Float

        var localVarianceAboveSpeckleThreshold: Bool { localVariance >= 18.0 }
    }

    /// Compute a border signature in the same border strips
    /// extractCellColorBucket samples — but exposes per-pixel
    /// luminance variance + saturation distribution instead of just
    /// the dominant hue. The localVariance metric specifically
    /// detects fine-grained speckle patterns characteristic of Icon
    /// Battlefoils + Power Glove Battlefoils (small icons embedded
    /// in metallic foil at high spatial frequency). Other holographic
    /// treatments have larger pattern features that average out at
    /// the pixel-pair level.
    static func extractBorderSignature(cgImage: CGImage) -> BorderSignature? {
        let width = cgImage.width
        let height = cgImage.height
        guard width >= 40, height >= 40 else { return nil }
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var bucketCounts: [String: Int] = [:]
        var coloredCount = 0
        var brightDesatCount = 0
        var varianceSum: Float = 0
        var varianceCount = 0

        let topStrip    = Int(Double(height) * 0.04)..<Int(Double(height) * 0.16)
        let bottomStrip = Int(Double(height) * 0.84)..<Int(Double(height) * 0.96)
        let leftStrip   = Int(Double(width)  * 0.04)..<Int(Double(width)  * 0.13)
        let rightStrip  = Int(Double(width)  * 0.87)..<Int(Double(width)  * 0.96)
        let xCornerInset = max(1, Int(Double(width)  * 0.18))
        let yCornerInset = max(1, Int(Double(height) * 0.18))

        @inline(__always) func sampleAndScan(xs: [Int], ys: [Int]) {
            for y in ys {
                var prevLum: Float = -1
                for x in xs {
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let idx = y * bytesPerRow + x * 4
                    let r = Float(data[idx])
                    let g = Float(data[idx + 1])
                    let b = Float(data[idx + 2])
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b
                    let (h, s, v) = rgbToHsv(r: Double(r), g: Double(g), b: Double(b))
                    if s >= 30 && v >= 50 {
                        if let bucket = hueToColorBucket(h: h) {
                            bucketCounts[bucket.name, default: 0] += 1
                            coloredCount += 1
                        }
                    } else if v >= 170 && s < 30 {
                        brightDesatCount += 1
                    }
                    if prevLum >= 0 {
                        varianceSum += abs(lum - prevLum)
                        varianceCount += 1
                    }
                    prevLum = lum
                }
            }
        }

        let xRange = Array(stride(from: xCornerInset, to: width - xCornerInset, by: 3))
        let yRange = Array(stride(from: yCornerInset, to: height - yCornerInset, by: 3))
        sampleAndScan(xs: xRange, ys: Array(topStrip).filter    { $0 % 3 == 0 })
        sampleAndScan(xs: xRange, ys: Array(bottomStrip).filter { $0 % 3 == 0 })
        sampleAndScan(xs: Array(leftStrip).filter  { $0 % 3 == 0 }, ys: yRange)
        sampleAndScan(xs: Array(rightStrip).filter { $0 % 3 == 0 }, ys: yRange)

        let localVariance = varianceCount > 0 ? varianceSum / Float(varianceCount) : 0
        let desatRatio: Float = (brightDesatCount + coloredCount) > 0
            ? Float(brightDesatCount) / Float(brightDesatCount + coloredCount)
            : 0
        let bucketsAbove1pct = bucketCounts.filter {
            coloredCount > 0 && Double($0.value) / Double(coloredCount) >= 0.01
        }.count
        let dominantHueShare: Float = coloredCount > 0
            ? Float(bucketCounts.values.max() ?? 0) / Float(coloredCount)
            : 0

        return BorderSignature(
            localVariance: localVariance,
            desatRatio: desatRatio,
            hueBuckets: bucketsAbove1pct,
            coloredCount: coloredCount,
            brightDesatCount: brightDesatCount,
            dominantHueShare: dominantHueShare
        )
    }

    /// Sample four border strips from the cell crop and classify the
    /// dominant color via hue histogram. Sampling four strips
    /// (top, bottom, left, right) means the central character art
    /// can't fully contaminate the measurement: even when one strip
    /// has character intrusion, the others vote pink/blue/whatever
    /// the actual treatment border is.
    ///
    /// We bucket each colored pixel by hue and pick the largest
    /// bucket. This is more robust than averaging RGB — average
    /// blends a pink border with a red character into orange-ish
    /// noise, while the histogram correctly identifies pink as the
    /// dominant cluster regardless of how much red noise sits
    /// alongside it.
    ///
    /// Returns nil when there aren't enough colored pixels (cell
    /// is mostly dark/neutral), `.white` when most pixels are
    /// bright but desaturated, `.holographic` when hue distribution
    /// is too diverse to call any single bucket dominant, or one of
    /// the named buckets when a clear winner emerges.
    static func extractCellColorBucket(cgImage: CGImage) -> ColorBucket? {
        let width = cgImage.width
        let height = cgImage.height
        guard width >= 20, height >= 20 else { return nil }

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Hue → bucket-name → count. Track separately to find the
        // dominant hue family without averaging.
        var bucketCounts: [String: Int] = [:]
        var coloredCount = 0
        var brightDesatCount = 0

        @inline(__always) func sample(x: Int, y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let idx = y * bytesPerRow + x * 4
            let r = Double(data[idx])
            let g = Double(data[idx + 1])
            let b = Double(data[idx + 2])
            let (h, s, v) = rgbToHsv(r: r, g: g, b: b)
            if s >= 30 && v >= 50 {
                if let bucket = hueToColorBucket(h: h) {
                    bucketCounts[bucket.name, default: 0] += 1
                    coloredCount += 1
                }
            } else if v >= 170 && s < 30 {
                brightDesatCount += 1
            }
        }

        // Border strips (top, bottom, left, right). Sample the outer
        // ~10% of each side, inset slightly from the very edge
        // (toploader edge / background bleed) and from the corners
        // (text). Reverted from a tighter-inset/higher-saturation
        // version (1.964) that classified too many cells as `nil`,
        // which silenced the color signal and made treatment
        // selection rely entirely on FP rank — unreliable for
        // treatments that share artwork.
        let topStrip    = Int(Double(height) * 0.04)..<Int(Double(height) * 0.16)
        let bottomStrip = Int(Double(height) * 0.84)..<Int(Double(height) * 0.96)
        let leftStrip   = Int(Double(width)  * 0.04)..<Int(Double(width)  * 0.13)
        let rightStrip  = Int(Double(width)  * 0.87)..<Int(Double(width)  * 0.96)
        let xCornerInset = max(1, Int(Double(width)  * 0.18))
        let yCornerInset = max(1, Int(Double(height) * 0.18))

        for y in topStrip {
            var x = xCornerInset
            while x < width - xCornerInset { sample(x: x, y: y); x += 3 }
        }
        for y in bottomStrip {
            var x = xCornerInset
            while x < width - xCornerInset { sample(x: x, y: y); x += 3 }
        }
        for x in leftStrip {
            var y = yCornerInset
            while y < height - yCornerInset { sample(x: x, y: y); y += 3 }
        }
        for x in rightStrip {
            var y = yCornerInset
            while y < height - yCornerInset { sample(x: x, y: y); y += 3 }
        }

        // Holographic: when colored samples are spread across ≥4
        // distinct buckets and no single bucket dominates (top
        // bucket < 35% of colored samples), the border is rainbow
        // — Logofoil, Grandma's Linoleum, Mixtape, etc.
        if coloredCount >= 60, bucketCounts.count >= 4 {
            let topShare = Double(bucketCounts.values.max() ?? 0) / Double(coloredCount)
            if topShare < 0.35 { return .holographic }
        }

        // Need a meaningful number of colored pixels for a confident
        // classification. Below this, fall back to white if mostly
        // bright-desaturated, else nil.
        guard coloredCount >= 40 else {
            return brightDesatCount > 200 ? .white : nil
        }

        // Pick the largest bucket that's at least 25% of colored
        // samples — protects against a tied histogram producing a
        // misleading winner.
        let sorted = bucketCounts.sorted { $0.value > $1.value }
        guard let top = sorted.first else { return nil }
        let topShare = Double(top.value) / Double(coloredCount)
        guard topShare >= 0.25 else {
            // No clear winner — could be holographic-ish or just
            // ambiguous. Don't claim a color.
            return nil
        }

        switch top.key {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "pink":   return .pink
        default:       return nil
        }
    }

    /// Map a treatment name to its expected border color bucket.
    /// Returns nil for treatments we can't reliably characterize
    /// (Plays, Hot Dog, Cyber, etc.) — those candidates just don't
    /// receive the color boost, no penalty.
    static func expectedColorBucket(for treatment: String) -> ColorBucket? {
        switch treatment.uppercased() {
        // Solid-color treatments
        case "FIRE TRACKS BATTLEFOIL":               return .orange
        case "BLIZZARD BATTLEFOIL":                  return .blue
        case "GREEN BATTLEFOIL":                     return .green
        case "RED BATTLEFOIL":                       return .red
        case "BLUE BATTLEFOIL":                      return .blue
        case "ORANGE BATTLEFOIL":                    return .orange
        case "PINK BATTLEFOIL":                      return .pink
        case "BUBBLE GUM BATTLEFOIL":                return .pink
        case "BUBBLE GUM BLAST":                     return .pink
        case "PINK BLAST":                           return .pink
        case "BLUE BLAST":                           return .blue
        case "GREEN BLAST":                          return .green
        case "ORANGE BLAST":                         return .orange
        case "SLIME BATTLEFOIL":                     return .green
        case "MIAMI ICE BATTLEFOIL":                 return .blue
        case "GRILLIN' BATTLEFOIL":                  return .orange
        case "CHILLIN' BATTLEFOIL":                  return .blue
        case "BLUE HEADLINES BATTLEFOIL":            return .blue
        case "RED HEADLINES BATTLEFOIL":             return .red
        case "ORANGE HEADLINES BATTLEFOIL":          return .orange
        case "GRAPE":                                return .purple
        case "SOUR APPLE":                           return .green
        case "BLUE RASPBERRY":                       return .blue
        case "INSPIRED INK BUBBLE GUM BATTLEFOIL":   return .pink

        // Holographic / rainbow / multicolor treatments
        case "GRANDMA'S LINOLEUM BATTLEFOIL":        return .holographic
        case "GREAT GRANDMA'S LINOLEUM BATTLEFOIL":  return .holographic
        case "LOGOFOIL":                             return .holographic
        case "MIXTAPE BATTLEFOIL":                   return .holographic
        case "80'S RAD BATTLEFOIL":                  return .holographic
        case "ICON BATTLEFOIL":                      return .holographic
        case "POWER GLOVE BATTLEFOIL":               return .holographic

        // Silver / white / neutral treatments
        case "BATTLEFOIL":                           return .white
        case "ALPHA BATTLEFOIL":                     return .white
        case "SILVER BATTLEFOIL":                    return .white
        case "SILVER BLAST":                         return .white
        case "HEADLINES BATTLEFOIL":                 return .white
        case "BASE SET":                             return .white
        case "PAPER":                                return .white
        case "PAPER SERIALIZED":                     return .white
        case "SUPERFOIL":                            return .white
        case "INSPIRED INK SUPERFOIL":               return .white
        case "INSPIRED INK METALLIC BATTLEFOIL":     return .white

        // Treatments we can't reliably color-classify — no boost.
        default: return nil
        }
    }

    // MARK: - Color math

    private static func rgbToHsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal
        let v = maxVal
        let s = maxVal == 0 ? 0 : (delta / maxVal) * 100
        var h: Double
        if delta == 0 {
            h = 0
        } else if maxVal == r {
            h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxVal == g {
            h = 60 * ((b - r) / delta + 2)
        } else {
            h = 60 * ((r - g) / delta + 4)
        }
        if h < 0 { h += 360 }
        return (h, s, v)
    }

    /// Standard deviation of hues on the circular [0, 360) domain.
    /// Naïve linear stddev would mishandle wraparound (e.g., hues
    /// near 350° and 10° are 20° apart, not 340°).
    private static func circularStdDev(hues: [Double]) -> Double {
        guard !hues.isEmpty else { return 0 }
        var x = 0.0, y = 0.0
        for h in hues {
            let rad = h * .pi / 180
            x += cos(rad)
            y += sin(rad)
        }
        let n = Double(hues.count)
        let r = sqrt(x * x + y * y) / n
        // Circular standard deviation in degrees. r near 1 = tight
        // cluster (low stddev); r near 0 = uniform around the circle
        // (max stddev ~81°). `Foundation.log` qualifier disambiguates
        // from this enum's `log(label:)` console-trace helper.
        let clampedR = min(max(r, 1e-9), 1.0)
        return sqrt(-2 * Foundation.log(clampedR)) * 180 / .pi
    }

    private static func hueToColorBucket(h: Double) -> ColorBucket? {
        // Pink range widened to 305–355° to catch bubble-gum / hot
        // pink (~330–350° hue) which previously fell into red. Red
        // narrowed to 0–10° / 355–360° accordingly. Without this
        // BGBF (Bubble Gum Battlefoil) borders consistently
        // misclassified as red and the wrong-color treatments
        // ended up in the picker.
        switch h {
        case 0..<10, 355..<360: return .red
        case 10..<40:           return .orange
        case 40..<70:           return .yellow
        case 70..<160:          return .green
        case 160..<260:         return .blue
        case 260..<305:         return .purple
        case 305..<355:         return .pink
        default:                return nil
        }
    }
}
