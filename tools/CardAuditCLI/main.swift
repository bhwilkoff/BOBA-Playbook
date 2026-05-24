#!/usr/bin/env swift
//
// CardAuditCLI — Phase 2 of CARD_AUDIT_PIPELINE.md
//
// Reads every catalog card image from a local cache and extracts
// printed text fields via Vision (VNRecognizeTextRequest). Writes a
// structured per-card JSON for downstream reconciliation against
// cards.json.
//
// Extracted fields per card:
//   - cardNumber  (e.g. "ABF-248", "GGL-779")
//   - power       (Hero / HotDog — top-right large digit)
//   - name        (top-of-card large text — hero or play name)
//   - serial      (Inspired Ink hand-stamp like "001/005" or "/25")
//   - treatment   (bottom-strip treatment label, when printed)
//
// Why Swift Vision and not Tesseract / cloud OCR:
//   - Vision is the most accurate OCR pipeline we measured on BoBA's
//     stylized cards. The existing audit_card_powers.swift hits >90%
//     on Hero power with this approach.
//   - $0 cost vs ~$22 to Google Vision for the 16k catalog.
//   - Same toolchain pattern as scripts/audit_card_powers.swift and
//     tools/GridDetectorCLI / tools/RecognizerCLI.
//
// Usage:
//   swift tools/CardAuditCLI/main.swift \
//     --catalog assets/data/cards.json \
//     --cache   ~/.boba-card-audit/images \
//     --output  ~/.boba-card-audit/ocr_results.json \
//     [--limit N] [--concurrency 4] [--types Hero Play HotDog] [-v]
//
// Output JSON shape:
// {
//   "schema_version": 1,
//   "ran_at": "2026-05-24T15:30:00Z",
//   "elapsed_seconds": 142.3,
//   "results": [
//     {
//       "bobaId": "1-LeBoss-Base Set-First Edition",
//       "imageFile": "1-LeBoss-Base_Set-First_Edition.webp",
//       "cardType": "Hero",
//       "ocr": {
//         "cardNumber": { "value": "1",      "confidence": 0.97, "candidates": ["1","I"] },
//         "name":       { "value": "LeBoss", "confidence": 0.99 },
//         "power":      { "value": 135,      "confidence": 0.95 },
//         "serial":     { "value": null,     "confidence": 0.0 },
//         "treatment":  { "value": "Base Set", "confidence": 0.72 }
//       }
//     }
//   ]
// }

import Foundation
import Vision
import CoreGraphics
import CoreImage
import ImageIO

private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

// MARK: - Args

struct Args {
    var catalog: String = ""
    var cacheDir: String = ""
    var output: String = ""
    var limit: Int? = nil
    var concurrency: Int = 4
    var cardTypes: Set<String> = ["Hero", "Play", "HotDog"]  // Sealed Product excluded by default
    var verbose: Bool = false
}

func parseArgs() -> Args {
    var a = Args()
    let argv = CommandLine.arguments
    var i = 1
    while i < argv.count {
        let flag = argv[i]
        let next: () -> String = {
            i += 1
            guard i < argv.count else { fputs("Missing value for \(flag)\n", stderr); exit(2) }
            return argv[i]
        }
        switch flag {
        case "--catalog":     a.catalog = next()
        case "--cache":       a.cacheDir = next()
        case "--output":      a.output = next()
        case "--limit":       a.limit = Int(next())
        case "--concurrency": a.concurrency = max(1, Int(next()) ?? 4)
        case "--types":
            // Consume types until next flag or end.
            var types: [String] = []
            while i + 1 < argv.count && !argv[i + 1].hasPrefix("--") && !argv[i + 1].hasPrefix("-") {
                i += 1
                types.append(argv[i])
            }
            if !types.isEmpty { a.cardTypes = Set(types) }
        case "-v", "--verbose": a.verbose = true
        case "-h", "--help":
            print("Usage: swift tools/CardAuditCLI/main.swift --catalog PATH --cache DIR --output PATH [--limit N] [--concurrency 4] [--types Hero Play HotDog] [-v]")
            exit(0)
        default:
            fputs("Unknown flag: \(flag)\n", stderr); exit(2)
        }
        i += 1
    }
    if a.catalog.isEmpty || a.cacheDir.isEmpty || a.output.isEmpty {
        fputs("Required: --catalog, --cache, --output\n", stderr); exit(2)
    }
    return a
}

// MARK: - Catalog

struct Entry {
    let bobaId: String
    let imageFile: String
    let cardType: String
    let catalogPower: Int?
    let catalogName: String?
    let catalogCardNumber: String?
    let catalogElement: String?
    let catalogTreatment: String?
    let catalogIsInspiredInk: Bool?
}

func loadCatalog(path: String, types: Set<String>) throws -> [Entry] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw NSError(domain: "CardAudit", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "catalog must be a JSON array"])
    }
    var seen: Set<String> = []
    var out: [Entry] = []
    for c in json {
        guard let bobaId = c["bobaId"] as? String, !bobaId.isEmpty,
              let imageFile = c["imageFile"] as? String, !imageFile.isEmpty,
              let cardType = c["cardType"] as? String,
              types.contains(cardType)
        else { continue }
        if !seen.insert(bobaId).inserted { continue }
        out.append(Entry(
            bobaId: bobaId,
            imageFile: imageFile,
            cardType: cardType,
            catalogPower: c["power"] as? Int,
            catalogName: (c["name"] as? String) ?? (c["hero"] as? String),
            catalogCardNumber: c["cardNumber"] as? String,
            catalogElement: c["element"] as? String,
            catalogTreatment: c["treatment"] as? String,
            catalogIsInspiredInk: c["isInspiredInk"] as? Bool
        ))
    }
    return out
}

// MARK: - OCR helpers

/// Image-coordinate Region of Interest (origin TOP-LEFT, [0..1]).
/// Converted to Vision's bottom-left ROI internally.
typealias ImageROI = (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)

/// Convert top-left normalized rect to Vision's bottom-left ROI.
func visionROI(from roi: ImageROI) -> CGRect {
    let visionY = 1.0 - (roi.y + roi.h)
    return CGRect(x: roi.x, y: visionY, width: roi.w, height: roi.h)
}

/// Region maps per card type. Values are normalized image-space
/// coordinates with origin TOP-LEFT. Tuned empirically on BoBA Hero
/// + Play + HotDog card layouts; iterate as pilot reveals misses.
enum CardRegion {
    case power
    case cardNumber
    case name
    case serial
    case treatment
    case element

    func roi(for cardType: String) -> ImageROI {
        switch (self, cardType) {
        // ── Hero ───────────────────────────────────────────────
        // Top-right power glyph. Iteration history:
        //  v1 (0.55, 0.00, 0.45, 0.30) — original. Dropped leading "1"
        //   on 3-digit powers (ABF-31-Pudge 180 → 80).
        //  v2 (0.45, 0.00, 0.55, 0.40) — too tall. Caught jersey
        //   numbers (141-Wattage 115 → 90 from his uniform).
        //  v3 (0.50, 0.00, 0.50, 0.30) — sweet spot empirically. Wide
        //   enough for leading "1"; short enough that body / jersey
        //   numbers stay below the crop. Pairs with the 2x upscale
        //   pass in extractPower to recover thin-stroke leading
        //   digits on stylized backgrounds.
        case (.power,       "Hero"):   return (0.50, 0.00, 0.50, 0.30)
        case (.cardNumber,  "Hero"):   return (0.00, 0.85, 0.55, 0.15)
        // Top-left name region. Iteration history:
        //  v1 (0.05, 0.00, 0.55, 0.20) — clipped leading letter on left-
        //    aligned names ("LUMBER" → "UMBER", "DOUBLECHECK" → "DOUBLECHECKR"
        //    from adjacent flame artifact). 3x upscale didn't help —
        //    the L was outside the crop.
        //  v2 (0.00, 0.00, 0.60, 0.20) — wider margin fixes both. Pair
        //    with 3x upscale in extractName to recover narrow-glyph names
        //    like "DR. J" where the J was beyond Vision's 1x resolution.
        case (.name,        "Hero"):   return (0.00, 0.00, 0.60, 0.20)
        // Top-right serial stamp on Inspired Ink Heroes — sits below
        // the power glyph, e.g. "15/25" on Eraser-Fire. Previous
        // (0.15, 0.55, 0.70, 0.30) was center-bottom and found
        // nothing on 100 IK samples (0% extraction rate). Visual
        // inspection of Eraser-Fire confirmed the /25 stamp is in
        // the top-right corner area, just below "POWER".
        case (.serial,      "Hero"):   return (0.55, 0.10, 0.45, 0.30)
        case (.treatment,   "Hero"):   return (0.00, 0.90, 1.00, 0.10)
        // Bottom-right weapon-label pill ("FIRE", "GLOW", "BRAWL", …).
        // v1 (0.55, 0.85, 0.45, 0.15) — caught newspaper-article body
        //   text on Blue Headlines Battlefoil cards alongside the
        //   ICE pill, drowning the canonical-element snap.
        // v2 (0.70, 0.88, 0.30, 0.12) — tightens to the corner-pill
        //   region. Skips body text on text-heavy treatments while
        //   still catching the canonical-element pill on plain cards.
        case (.element,     "Hero"):   return (0.70, 0.88, 0.30, 0.12)
        // ── Play ───────────────────────────────────────────────
        case (.power,       "Play"):   return (0.55, 0.00, 0.45, 0.20)  // DBS / cost
        case (.cardNumber,  "Play"):   return (0.00, 0.88, 0.55, 0.12)
        // Play name lives at the very top-LEFT, not top-center. The
        // previous x=0.10 origin clipped the first letter on every
        // Play in the validation pilot ("COPYCAT" → "OPYCAT",
        // "MY IDOL" → "IY IDOL"). Width drops to 0.50 because the
        // top-right corner of a Play has a "?" mystery icon + card
        // position counter that pollutes a wider crop.
        case (.name,        "Play"):   return (0.00, 0.00, 0.50, 0.18)
        case (.serial,      "Play"):   return (0.00, 0.00, 0.00, 0.00)  // n/a
        case (.treatment,   "Play"):   return (0.00, 0.92, 1.00, 0.08)
        // ── HotDog ─────────────────────────────────────────────
        case (.power,       "HotDog"): return (0.00, 0.00, 0.45, 0.20)  // cost top-left
        case (.cardNumber,  "HotDog"): return (0.00, 0.88, 0.55, 0.12)
        case (.name,        "HotDog"): return (0.10, 0.00, 0.80, 0.18)
        case (.serial,      "HotDog"): return (0.00, 0.00, 0.00, 0.00)
        case (.treatment,   "HotDog"): return (0.00, 0.92, 1.00, 0.08)
        case (.element,     "HotDog"): return (0.70, 0.88, 0.30, 0.12)
        case (.element,     "Play"):   return (0.70, 0.88, 0.30, 0.12)
        // ── Default fallback (also Sealed if it slips through) ─
        default:                       return (0.00, 0.00, 1.00, 1.00)
        }
    }
}

/// Apply the standard pre-processing recipe that recovers stylized
/// BoBA card glyphs (Fire/Ice shimmer, foil sheen). Same filter
/// chain as audit_card_powers.swift::ocrPrintedPowerSlow.
func preprocessed(_ cgImage: CGImage) -> CGImage {
    let ci = CIImage(cgImage: cgImage)
        .applyingFilter("CIGammaAdjust",   parameters: ["inputPower": Float(0.65)])
        .applyingFilter("CIColorControls", parameters: [
            "inputSaturation": Float(0.0),
            "inputContrast":   Float(1.4),
        ])
        .applyingFilter("CIUnsharpMask",   parameters: [
            "inputRadius":    Float(2.0),
            "inputIntensity": Float(0.6),
        ])
    return ciContext.createCGImage(ci, from: ci.extent) ?? cgImage
}

/// Lanczos upscale by an integer factor. Standalone test confirmed
/// 2x upscale recovers the leading "1" Vision dropped on ABF-31-Pudge
/// (catalog 180, original-size OCR returned only "80"). Same upscale
/// also eliminates garbled digit-with-dashes candidates that mislead
/// the scoring on 142-Spider (catalog 115, original OCR returned a
/// spurious "13-0-0-3" alongside the correct "115").
///
/// Memory guard: skip if the upscaled buffer would exceed
/// MAX_UPSCALED_DIM in either dimension. Play cards on R2 are 745×1040
/// (vs Hero 678×947); 3x of 1040 = 3120, and three simultaneous
/// upscaled requests in Vision can OOM. Returning the source image is
/// a safe fallback — the OCR just doesn't get the extra resolution.
let MAX_UPSCALED_DIM = 2500
func upscaled(_ cgImage: CGImage, factor: Int) -> CGImage {
    let w = cgImage.width * factor
    let h = cgImage.height * factor
    if w > MAX_UPSCALED_DIM || h > MAX_UPSCALED_DIM {
        return cgImage
    }
    let ci = CIImage(cgImage: cgImage)
        .applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale":       Float(factor),
            "inputAspectRatio": Float(1.0),
        ])
    return ciContext.createCGImage(ci, from: ci.extent) ?? cgImage
}

/// Run a Vision text-recognition pass with custom vocab + ROI.
/// Returns observations sorted by confidence descending.
func runOCR(
    image: CGImage,
    roi: CGRect? = nil,
    customWords: [String] = [],
    minimumTextHeight: Float = 0.02,
    level: VNRequestTextRecognitionLevel = .accurate
) -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    if !customWords.isEmpty { request.customWords = customWords }
    request.minimumTextHeight = minimumTextHeight
    if let roi = roi { request.regionOfInterest = roi }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do { try handler.perform([request]) } catch { return [] }
    return request.results ?? []
}

// MARK: - Field extraction

struct FieldResult: Codable {
    let value: String?    // string for cardNumber/name/serial/treatment; stringified int for power
    let intValue: Int?    // populated for numeric fields
    let confidence: Float
    let candidates: [String]
}

let PLAUSIBLE_POWERS: [String] = stride(from: 55, through: 250, by: 5).map { String($0) }
// Prefix-dash-number form (ABF-100, BHBF-37, CHILL-50). Pilot run showed
// the previous single-letter prefix tolerance produced false positives
// where Vision misread bare-digit cards like "115" as "T-15". Require
// prefix length ≥ 2 to drop those. Bare-number cardNumbers (1, 47, 100)
// aren't printed on Base Set art and are left to the catalog as
// authoritative — no OCR attempt for them.
let CARD_NUMBER_REGEX = #/([A-Z]{2,6})-?([A-Z]?\d{1,4})(?:[-/](\d{1,4}))?/#
let SERIAL_REGEX = #/(\d{1,3})\s*/\s*(\d{1,3})/#

/// Extract printed power (top-right large digit). Three-pass + voting.
///
/// Pass A — original image, ROI cropped, .accurate
/// Pass B — 2x Lanczos upscale, ROI cropped, .accurate
///   Pilot test confirmed 2x upscale recovers cards where Vision drops
///   a leading "1" on stylized power glyphs (e.g. ABF-31-Pudge "180"
///   → "80" without upscale).
/// Pass C — enhanced (gamma+contrast+unsharp) original, ROI cropped,
///   .accurate. Only consulted if A+B disagree.
///
/// Scoring: pure-digit candidates ("115") win heavily over candidates
/// where digits had to be extracted around non-digit noise
/// ("13-0-0-3" → 130). Without this preference, garbled candidates
/// tied at the same Vision confidence as clean ones and last-write-wins
/// produced false-positive mismatches on the pilot.
///
/// HIGH-CONFIDENCE returns: ≥2 passes agree on the same integer. Else
/// the result is downgraded (confidence × 0.6) so reconciliation routes
/// it to REVIEW instead of UPDATES.
func extractPower(originalImage: CGImage, enhancedImage: CGImage, cardType: String) -> FieldResult {
    let roi = visionROI(from: CardRegion.power.roi(for: cardType))
    let upscaledImage = upscaled(originalImage, factor: 2)

    func bestFrom(_ observations: [VNRecognizedTextObservation], collecting: inout [String]) -> (Int, Float)? {
        var best: (val: Int, score: Float)? = nil
        for obs in observations {
            for cand in obs.topCandidates(3) {
                let raw = cand.string.trimmingCharacters(in: .whitespacesAndNewlines)
                collecting.append(raw)
                // PURE-DIGIT candidates score 1.5x — they're clean
                // glyph reads, not digits-rescued-from-noise.
                let digitsOnly = raw.allSatisfy { $0.isNumber } && raw.count >= 2 && raw.count <= 3
                let cleanBonus: Float = digitsOnly ? 1.5 : 1.0
                for digits in [leadingDigits(raw), trailingDigits(raw)] {
                    guard digits.count >= 2, digits.count <= 3,
                          let val = Int(digits), val >= 55, val <= 250 else { continue }
                    let canonical: Float = (val % 5 == 0) ? 1.0 : 0.5
                    let score = cand.confidence * canonical * cleanBonus
                    if best == nil || score > best!.score { best = (val, score) }
                    break
                }
            }
        }
        return best
    }

    var allCands: [String] = []
    let passA = bestFrom(runOCR(image: originalImage, roi: roi,
                                customWords: PLAUSIBLE_POWERS),
                         collecting: &allCands)
    let passB = bestFrom(runOCR(image: upscaledImage, roi: roi,
                                customWords: PLAUSIBLE_POWERS),
                         collecting: &allCands)
    let passC = bestFrom(runOCR(image: enhancedImage, roi: roi,
                                customWords: PLAUSIBLE_POWERS),
                         collecting: &allCands)

    // Voting: tally agreements per integer value across passes.
    var votes: [Int: (count: Int, bestScore: Float)] = [:]
    for pass in [passA, passB, passC] {
        guard let p = pass else { continue }
        var entry = votes[p.0] ?? (0, 0)
        entry.count += 1
        entry.bestScore = max(entry.bestScore, p.1)
        votes[p.0] = entry
    }

    // Winner: most votes, ties broken by best score.
    let winner = votes.max { a, b in
        if a.value.count != b.value.count { return a.value.count < b.value.count }
        return a.value.bestScore < b.value.bestScore
    }

    guard let w = winner else {
        return FieldResult(value: nil, intValue: nil, confidence: 0, candidates: allCands)
    }
    let agreeCount = w.value.count
    // ≥2 passes agree → trust full score. Single-pass survivor →
    // downgrade so reconciliation flags it for human review.
    let confidence = agreeCount >= 2
        ? min(1.0, w.value.bestScore / 1.5)
        : min(0.6, w.value.bestScore / 1.5 * 0.6)
    return FieldResult(value: "\(w.key)", intValue: w.key,
                       confidence: confidence, candidates: allCands)
}

/// Extract printed cardNumber (e.g. "ABF-248"). Bottom-left region.
func extractCardNumber(originalImage: CGImage, cardType: String, expectedPrefix: String? = nil) -> FieldResult {
    let roi = visionROI(from: CardRegion.cardNumber.roi(for: cardType))
    // Bias vocab with the expected prefix if we have one (from the
    // imageFile name); helps Vision pick canonical glyphs over noise.
    let vocab = expectedPrefix.map { [$0] } ?? []
    let observations = runOCR(image: originalImage, roi: roi, customWords: vocab)
    var all: [String] = []
    var best: (String, Float)? = nil
    for obs in observations {
        for cand in obs.topCandidates(3) {
            let raw = cand.string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            all.append(raw)
            // Match a cardNumber-shaped token anywhere in the candidate.
            if let m = raw.firstMatch(of: CARD_NUMBER_REGEX) {
                let prefix = String(m.output.1)
                let body = String(m.output.2)
                let combined = "\(prefix)-\(body)"
                let score = cand.confidence
                if best == nil || score > best!.1 {
                    best = (combined, score)
                }
            }
        }
    }
    if let b = best {
        return FieldResult(value: b.0, intValue: nil, confidence: b.1, candidates: all)
    }
    return FieldResult(value: nil, intValue: nil, confidence: 0, candidates: all)
}

/// Subtitle words that appear next to the hero name in the name
/// region but are NOT the hero name. Any observation that's just one
/// of these strings (or starts with one) loses scoring weight so the
/// title text wins. Empirically gathered from BoBA card scans.
let NAME_SUBTITLE_BLOCKLIST: Set<String> = [
    "FIRST EDITION", "2026 EDITION", "FIRST", "EDITION",
    "DEBUT", "FOUNDING HERO", "COVER HERO", "UNMASKED",
    "ALL-STAR", "FOUNDING", "COVER", "HERO",
]

/// Patterns (not exact-match) that flag observations as non-name
/// metadata. Newspaper-style "NO. 313" series indicator on BHBF cards
/// + power glyphs that leak into the name region get filtered here.
let NAME_NON_NAME_REGEX: [Regex<AnyRegexOutput>] = {
    let patterns = [
        "^NO[.,]?\\s*\\d+",          // "NO. 313" on BHBF cards
        "^\\d{2,3}$",                // power glyph (115, 180)
        "^\\d+/\\d+$",               // serial fragment leak
    ]
    return patterns.compactMap { try? Regex($0) }
}()

func isNonNamePattern(_ s: String) -> Bool {
    for re in NAME_NON_NAME_REGEX {
        if (try? re.firstMatch(in: s.uppercased())) != nil { return true }
    }
    return false
}

/// Strip OCR-introduced punctuation that appears around hero names
/// (Vision sometimes adds leading periods, trailing dashes, or
/// "»" / "•" characters from neighboring graphics). Internal periods
/// preserved (Dr. J's "DR.J" reads through).
func cleanName(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripChars = CharacterSet(charactersIn: ".-–—•»«•·▸▶◆■□★*†‡¶")
    // Strip leading + trailing junk repeatedly until stable.
    var prev = ""
    while s != prev {
        prev = s
        s = s.trimmingCharacters(in: stripChars)
              .trimmingCharacters(in: .whitespaces)
    }
    return s
}

/// Extract the printed name (Hero / Play / HotDog) — top-left large
/// text. Pilot showed Vision's bounding-box height per observation is
/// reliably ~2x for the title vs subtitle ("LUMBER" h=0.21 vs "FIRST
/// EDITION" h=0.10), so prefer-larger-glyph is the dominant signal.
///
/// Three-pass + voting (same pattern as extractPower):
/// Pass A — original, .accurate
/// Pass B — 2x upscale, .accurate (recovers narrow glyphs)
/// Pass C — 3x upscale, .accurate (recovers very narrow glyphs like
///   the "J" of "DR. J" that 1x and 2x drop)
///
/// Within each pass, the title observation is picked by:
///   (a) skipping known subtitle words ("FIRST EDITION", "DEBUT", …)
///   (b) preferring the TALLEST glyph (height-of-boundingBox)
///   (c) preferring the TOPMOST observation (max-Y in Vision coords)
///   (d) cleaning OCR-introduced junk punctuation around the value
///
/// HIGH confidence requires ≥2 passes to converge on the same
/// cleaned string (case-insensitive); single-pass survivors get
/// downgraded to 0.6 so they land in REVIEW not UPDATES.
func extractName(originalImage: CGImage, cardType: String, customNames: [String]) -> FieldResult {
    let roi = visionROI(from: CardRegion.name.roi(for: cardType))

    func pickFromObservations(_ observations: [VNRecognizedTextObservation],
                              collecting: inout [String]) -> (value: String, score: Float)? {
        var best: (value: String, score: Float)? = nil
        for obs in observations {
            for cand in obs.topCandidates(3) {
                let raw = cand.string.trimmingCharacters(in: .whitespacesAndNewlines)
                collecting.append(raw)
                let cleaned = cleanName(raw)
                if cleaned.count < 2 { continue }
                if cleaned.allSatisfy({ $0.isNumber }) { continue }
                let upper = cleaned.uppercased()
                // Skip pure subtitle / set-tag noise.
                if NAME_SUBTITLE_BLOCKLIST.contains(upper) { continue }
                // Skip newspaper-style "NO. 313" indicator + power
                // / serial digits that leak into the name region.
                if isNonNamePattern(upper) { continue }
                // Subtitle observations often have "DEBUT" or "EDITION"
                // as suffix; downweight rather than skip outright.
                let containsSubtitleSuffix = NAME_SUBTITLE_BLOCKLIST.contains { upper.hasSuffix(" \($0)") }
                let subtitlePenalty: Float = containsSubtitleSuffix ? 0.3 : 1.0
                // Hero / Play names sit at the TOP-LEFT of the name
                // region. The Blue Headlines Battlefoil series puts a
                // "NO. 313" indicator at TOP-RIGHT — same height +
                // confidence as the name, so without left-bias the
                // wrong one wins. Prefer observations whose midX is
                // closer to the left edge of the cropped region.
                let height = Float(obs.boundingBox.height)
                let topness = Float(obs.boundingBox.maxY)
                let midX = Float(obs.boundingBox.midX)
                let leftness = max(0.2, 1.0 - midX)  // floor at 0.2 so right-aligned names still get scored
                let score = cand.confidence * height * 10 * topness * leftness * subtitlePenalty
                if best == nil || score > best!.score {
                    best = (cleaned, score)
                }
            }
        }
        return best
    }

    var allCands: [String] = []
    let passA = pickFromObservations(
        runOCR(image: originalImage, roi: roi,
               customWords: customNames, minimumTextHeight: 0.04),
        collecting: &allCands)
    let passB = pickFromObservations(
        runOCR(image: upscaled(originalImage, factor: 2), roi: roi,
               customWords: customNames, minimumTextHeight: 0.04),
        collecting: &allCands)
    let passC = pickFromObservations(
        runOCR(image: upscaled(originalImage, factor: 3), roi: roi,
               customWords: customNames, minimumTextHeight: 0.04),
        collecting: &allCands)

    // Voting: case-insensitive cleaned-string equality.
    var votes: [String: (count: Int, bestScore: Float, original: String)] = [:]
    for pass in [passA, passB, passC] {
        guard let p = pass else { continue }
        let key = p.value.uppercased()
        var entry = votes[key] ?? (0, 0, p.value)
        entry.count += 1
        if p.score > entry.bestScore {
            entry.bestScore = p.score
            entry.original = p.value
        }
        votes[key] = entry
    }
    guard let winner = votes.max(by: { a, b in
        if a.value.count != b.value.count { return a.value.count < b.value.count }
        return a.value.bestScore < b.value.bestScore
    }) else {
        return FieldResult(value: nil, intValue: nil, confidence: 0, candidates: allCands)
    }
    let agreeCount = winner.value.count
    let baseScore = winner.value.bestScore / 1.5  // normalize toward [0,1]
    let confidence: Float = agreeCount >= 2
        ? min(1.0, baseScore)
        : min(0.6, baseScore * 0.6)
    return FieldResult(value: winner.value.original, intValue: nil,
                       confidence: confidence, candidates: allCands)
}

/// Extract Inspired Ink serial stamp (e.g. "001/005", "23/50").
/// Center / lower-center region. Most cards return null (no stamp).
/// Hero-only — Play / HotDog / Sealed Product don't carry IK serials.
/// Returning empty avoids feeding Vision a zero-area ROI (crashes the
/// framework, takes the whole audit run with it).
func extractSerial(originalImage: CGImage, enhancedImage: CGImage, cardType: String) -> FieldResult {
    if cardType != "Hero" {
        return FieldResult(value: nil, intValue: nil, confidence: 0, candidates: [])
    }
    let roi = visionROI(from: CardRegion.serial.roi(for: cardType))
    // The hand-stamp is small + low-contrast — try enhanced first.
    var observations = runOCR(image: enhancedImage, roi: roi)
    if observations.isEmpty {
        observations += runOCR(image: originalImage, roi: roi)
    }
    var all: [String] = []
    var best: (String, Int, Int, Float)? = nil  // text, numerator, denom, conf
    for obs in observations {
        for cand in obs.topCandidates(3) {
            let raw = cand.string.trimmingCharacters(in: .whitespacesAndNewlines)
            all.append(raw)
            if let m = raw.firstMatch(of: SERIAL_REGEX) {
                guard let num = Int(m.output.1), let den = Int(m.output.2) else { continue }
                // Only accept canonical Inspired Ink denominators.
                guard [5, 10, 25, 50].contains(den), num >= 1, num <= den else { continue }
                let score = cand.confidence
                let combined = "\(num)/\(den)"
                if best == nil || score > best!.3 {
                    best = (combined, num, den, score)
                }
            }
        }
    }
    if let b = best {
        return FieldResult(value: b.0, intValue: b.2, confidence: b.3, candidates: all)
    }
    return FieldResult(value: nil, intValue: nil, confidence: 0, candidates: all)
}

/// Canonical weapon / element labels printed on every BoBA card,
/// bottom-right corner. UPPERCASE per DECISIONS.md #010. Used both
/// as OCR custom-words bias and as the allowed-values whitelist for
/// extractElement.
let CANONICAL_ELEMENTS: [String] = [
    "FIRE", "ICE", "HEX", "GLOW", "STEEL", "BRAWL", "GUM", "SUPER", "NONE",
]

/// Extract the printed weapon / element label. Same multi-pass +
/// voting pattern as power / name. Vision sees these labels clearly
/// (large uppercase white text on tinted-pill background) so a single
/// pass is usually enough — the upscale fallback handles edge cases
/// where shimmer makes the text low-contrast.
func extractElement(originalImage: CGImage, enhancedImage: CGImage, cardType: String) -> FieldResult {
    let roi = visionROI(from: CardRegion.element.roi(for: cardType))

    func pickElement(_ observations: [VNRecognizedTextObservation],
                     collecting: inout [String]) -> (String, Float)? {
        var best: (value: String, score: Float)? = nil
        for obs in observations {
            for cand in obs.topCandidates(3) {
                let raw = cand.string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                collecting.append(raw)
                // Snap to the closest canonical element by exact or
                // suffix / prefix match. Vision sometimes returns
                // "FIRE." / "FIRE!" / "*FIRE" — accept those.
                for el in CANONICAL_ELEMENTS {
                    if raw == el || raw.hasSuffix(el) || raw.hasPrefix(el) {
                        let score = cand.confidence
                        if best == nil || score > best!.score {
                            best = (el, score)
                        }
                        break
                    }
                }
            }
        }
        return best
    }

    var all: [String] = []
    let passA = pickElement(runOCR(image: originalImage, roi: roi,
                                   customWords: CANONICAL_ELEMENTS),
                            collecting: &all)
    let passB = pickElement(runOCR(image: upscaled(originalImage, factor: 2), roi: roi,
                                   customWords: CANONICAL_ELEMENTS),
                            collecting: &all)
    let passC = pickElement(runOCR(image: enhancedImage, roi: roi,
                                   customWords: CANONICAL_ELEMENTS),
                            collecting: &all)
    var votes: [String: (count: Int, score: Float)] = [:]
    for pass in [passA, passB, passC] {
        guard let p = pass else { continue }
        var e = votes[p.0] ?? (0, 0)
        e.count += 1
        e.score = max(e.score, p.1)
        votes[p.0] = e
    }
    guard let winner = votes.max(by: { a, b in
        if a.value.count != b.value.count { return a.value.count < b.value.count }
        return a.value.score < b.value.score
    }) else {
        return FieldResult(value: nil, intValue: nil, confidence: 0, candidates: all)
    }
    let confidence: Float = winner.value.count >= 2
        ? winner.value.score
        : min(0.6, winner.value.score * 0.6)
    return FieldResult(value: winner.key, intValue: nil,
                       confidence: confidence, candidates: all)
}

// Treatment intentionally NOT extracted via OCR. Pilot run showed the
// bottom strip is dominated by the "©20XX BO JACKSON BATTLE ARENA"
// trademark text, with the treatment label rarely printed in legible
// form. Treatment IS encoded reliably elsewhere though:
//   - cardNumber prefix (ABF- = Alpha Battlefoil, BHBF- = Blue
//     Battlefoil, GGL- = Great Grandma's Linoleum, etc.)
//   - visual border / foil pattern (Phase 3 — classify_card_visuals)
// Reconciliation derives treatment from those signals.

// MARK: - Digit helpers

func leadingDigits(_ s: String) -> String {
    var out = ""
    for ch in s where ch.isNumber {
        out.append(ch); if out.count >= 3 { break }
    }
    return out
}

func trailingDigits(_ s: String) -> String {
    var out = ""
    for ch in s.reversed() where ch.isNumber {
        out.append(ch); if out.count >= 3 { break }
    }
    return String(out.reversed())
}

// MARK: - Per-card audit

struct OCRPayload: Codable {
    let cardNumber: FieldResult
    let name: FieldResult
    let power: FieldResult
    let serial: FieldResult
    let element: FieldResult
    // treatment omitted — see extractTreatment comment block above.
}

struct ResultRow: Codable {
    let bobaId: String
    let imageFile: String
    let cardType: String
    let ocr: OCRPayload
}

struct AuditOutput: Codable {
    let schemaVersion: Int
    let ranAt: String
    let elapsedSeconds: Double
    let total: Int
    let results: [ResultRow]
}

func auditOne(entry: Entry, cacheDir: URL, customNames: [String]) -> ResultRow? {
    let imageURL = cacheDir.appendingPathComponent(entry.imageFile)
    guard FileManager.default.fileExists(atPath: imageURL.path),
          let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let original = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    let enhanced = preprocessed(original)

    // Pull the expected cardNumber prefix from the imageFile to bias
    // the cardNumber recognizer toward the canonical glyphs.
    let prefix: String? = {
        guard let dash = entry.imageFile.firstIndex(of: "-") else { return nil }
        let head = entry.imageFile[..<dash]
        return head.allSatisfy({ $0.isLetter }) ? String(head) : nil
    }()

    let payload = OCRPayload(
        cardNumber: extractCardNumber(originalImage: original, cardType: entry.cardType, expectedPrefix: prefix),
        name:       extractName(originalImage: original, cardType: entry.cardType, customNames: customNames),
        power:      extractPower(originalImage: original, enhancedImage: enhanced, cardType: entry.cardType),
        serial:     extractSerial(originalImage: original, enhancedImage: enhanced, cardType: entry.cardType),
        element:    extractElement(originalImage: original, enhancedImage: enhanced, cardType: entry.cardType)
    )

    return ResultRow(
        bobaId: entry.bobaId,
        imageFile: entry.imageFile,
        cardType: entry.cardType,
        ocr: payload
    )
}

// MARK: - Main

func runAudit() async {
    let args = parseArgs()
    print("BOBA card-art audit (CardAuditCLI)")
    print("  catalog:     \(args.catalog)")
    print("  cache:       \(args.cacheDir)")
    print("  output:      \(args.output)")
    print("  types:       \(args.cardTypes.sorted().joined(separator: ", "))")
    print("  concurrency: \(args.concurrency)")

    let entries: [Entry]
    do { entries = try loadCatalog(path: args.catalog, types: args.cardTypes) }
    catch { fputs("Catalog load failed: \(error)\n", stderr); exit(1) }
    let limited = args.limit.map { Array(entries.prefix($0)) } ?? entries
    print("  entries:     \(limited.count) of \(entries.count) catalog rows with imageFile")
    print()

    // Build a vocab list of names from the catalog so the name-extractor
    // gets canonical-glyph hints. Dedup + sort for stable ordering.
    var nameSet: Set<String> = []
    for e in entries {
        if let n = e.catalogName, !n.isEmpty { nameSet.insert(n) }
    }
    let customNames = Array(nameSet).sorted()

    let cacheURL = URL(fileURLWithPath: (args.cacheDir as NSString).expandingTildeInPath)
    let start = Date()
    var rows: [ResultRow] = []
    rows.reserveCapacity(limited.count)
    var skippedNoFile = 0
    let total = limited.count

    let chunk = max(1, args.concurrency)
    var idx = 0
    while idx < total {
        let upper = min(idx + chunk, total)
        await withTaskGroup(of: ResultRow?.self) { group in
            for k in idx..<upper {
                let e = limited[k]
                group.addTask {
                    return auditOne(entry: e, cacheDir: cacheURL, customNames: customNames)
                }
            }
            for await result in group {
                if let r = result { rows.append(r) }
                else { skippedNoFile += 1 }
            }
        }
        idx = upper
        if idx % 100 == 0 || idx == total {
            let dt = Date().timeIntervalSince(start)
            let rate = dt > 0 ? Double(idx) / dt : 0
            let etaSec = rate > 0 ? Double(total - idx) / rate : 0
            print("  \(idx)/\(total) — \(String(format: "%.1f", rate))/s — ETA \(Int(etaSec))s — missing=\(skippedNoFile)")
        }
    }

    let elapsed = Date().timeIntervalSince(start)
    print()
    print("Total processed:     \(rows.count)")
    print("Missing image files: \(skippedNoFile)")
    print(String(format: "Elapsed: %.1fs", elapsed))

    let fmt = ISO8601DateFormatter()
    let out = AuditOutput(
        schemaVersion: 1,
        ranAt: fmt.string(from: Date()),
        elapsedSeconds: elapsed,
        total: rows.count,
        results: rows
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(out)
        let outURL = URL(fileURLWithPath: (args.output as NSString).expandingTildeInPath)
        try data.write(to: outURL)
        print("Wrote \(outURL.path) (\(data.count) bytes)")
    } catch {
        fputs("Write failed: \(error)\n", stderr); exit(1)
    }
}

await runAudit()
