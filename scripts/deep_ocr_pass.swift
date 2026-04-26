#!/usr/bin/env swift
// Targeted "deep" OCR pass for power values that the first audit
// couldn't resolve. Per-card budget is much higher: 10+ preprocessing
// variants, tight power-region crops, digit↔letter substitutions
// (I→1, O→0, l→1, S→5, B→8 — common OCR confusions on stylized
// BoBA glyphs), and consensus voting across passes.
//
// Inputs:
//   --catalog  cards.json — used to get imageFile + catalog hero per bobaId
//   --bobaIds  JSON file with `["bobaId1", "bobaId2", ...]` to re-OCR
//   --thumbs   thumbs dir
//   --fullsize images-optimized dir
//   --output   per-bobaId result JSON
//
// Output shape:
//   {"results": [
//     {"bobaId": "...", "ocrPower": 130, "votes": {"130": 6, "30": 2},
//      "passesWithHero": 5, "candidates": ["...", ...]}
//   ]}
//
// Strategy:
//   1. Load image (full-size if available, else thumb)
//   2. Run OCR over 8+ preprocessing variants
//   3. For each candidate string, extract power with leading/trailing
//      digit-runs PLUS a substitution pass (I→1 etc.)
//   4. Vote across all extractions
//   5. Bias toward votes that come from observations whose row also
//      contained the catalog hero name (proves the candidate is from
//      the right card)

import Foundation
import Vision
import CoreGraphics
import CoreImage
import ImageIO

private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

let PLAUSIBLE_POWERS: [String] = stride(from: 55, through: 250, by: 5).map { String($0) }

// Digit-letter normalization. Vision frequently misreads:
//   1 ↔ I, l (lowercase L)
//   0 ↔ O, o
//   5 ↔ S
//   8 ↔ B
// Apply substitutions before digit extraction.
let DIGIT_SUBS: [Character: Character] = [
    "I": "1", "l": "1",
    "O": "0", "o": "0",
    "S": "5",
    "B": "8",
]

func normalizeForDigits(_ s: String) -> String {
    var out = ""
    for ch in s {
        out.append(DIGIT_SUBS[ch] ?? ch)
    }
    return out
}

func leadingDigits(_ s: String, max: Int = 3) -> String {
    var out = ""
    for ch in s where ch.isNumber {
        out.append(ch); if out.count >= max { break }
    }
    return out
}
func trailingDigits(_ s: String, max: Int = 3) -> String {
    var out = ""
    for ch in s.reversed() where ch.isNumber {
        out.append(ch); if out.count >= max { break }
    }
    return String(out.reversed())
}

/// Extract every plausible power value from a candidate string,
/// applying digit-letter substitutions. Returns ALL extractions
/// (caller votes across them).
func extractPowers(_ raw: String) -> [Int] {
    var found: Set<Int> = []
    let variants = [raw, normalizeForDigits(raw)]
    for v in variants {
        for d in [leadingDigits(v, max: 3), leadingDigits(v, max: 2),
                  trailingDigits(v, max: 3), trailingDigits(v, max: 2)] {
            guard d.count >= 2, d.count <= 3,
                  let n = Int(d), n >= 55, n <= 250 else { continue }
            found.insert(n)
        }
    }
    return Array(found)
}

// MARK: - Args

struct Args {
    var catalog: String = ""
    var bobaIds: String = ""
    var thumbsDir: String = ""
    var fullsizeDir: String? = nil
    var output: String = ""
    var concurrency: Int = 4
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
        case "--bobaIds":     a.bobaIds = next()
        case "--thumbs":      a.thumbsDir = next()
        case "--fullsize":    a.fullsizeDir = next()
        case "--output":      a.output = next()
        case "--concurrency": a.concurrency = max(1, Int(next()) ?? 4)
        default: fputs("Unknown flag: \(flag)\n", stderr); exit(2)
        }
        i += 1
    }
    return a
}

// MARK: - Catalog

struct Entry {
    let bobaId: String
    let hero: String
    let imageFile: String
}

func loadCatalogSubset(catalogPath: String, bobaIds: Set<String>) throws -> [Entry] {
    let data = try Data(contentsOf: URL(fileURLWithPath: catalogPath))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    var out: [Entry] = []
    for c in json {
        guard let bid = c["bobaId"] as? String, bobaIds.contains(bid) else { continue }
        let hero = (c["hero"] as? String) ?? ""
        let imageFile = (c["imageFile"] as? String) ?? ""
        // Skip rows whose imageFile got cleared (wrong-image cleanup).
        guard !imageFile.isEmpty else { continue }
        out.append(Entry(bobaId: bid, hero: hero, imageFile: imageFile))
    }
    return out
}

// MARK: - Image preprocessing variants

func preprocessVariants(cgImage: CGImage) -> [(label: String, image: CGImage)] {
    let original = CIImage(cgImage: cgImage)
    var variants: [(String, CIImage)] = [
        ("original", original),
    ]

    // Gamma 0.65 + grayscale + contrast (matches scanner's standard pass)
    variants.append((
        "gamma065_gray_contrast",
        original
            .applyingFilter("CIGammaAdjust",   parameters: ["inputPower": Float(0.65)])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0), "inputContrast": Float(1.4),
            ])
            .applyingFilter("CIUnsharpMask",   parameters: [
                "inputRadius": Float(2.0), "inputIntensity": Float(0.6),
            ])
    ))

    // Heavier gamma for very dark cards
    variants.append((
        "gamma05_gray_contrast",
        original
            .applyingFilter("CIGammaAdjust",   parameters: ["inputPower": Float(0.5)])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0), "inputContrast": Float(1.6),
            ])
    ))

    // Inversion — works on white-power-on-dark cards
    variants.append((
        "inverted",
        original
            .applyingFilter("CIColorInvert", parameters: [:])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0), "inputContrast": Float(1.3),
            ])
    ))

    // High-contrast threshold-style
    variants.append((
        "high_contrast",
        original
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0),
                "inputContrast":   Float(2.5),
                "inputBrightness": Float(0.1),
            ])
    ))

    // Convert all CIImages to CGImages so they're cacheable.
    var out: [(String, CGImage)] = []
    for (label, ci) in variants {
        if let cg = ciContext.createCGImage(ci, from: ci.extent) {
            out.append((label, cg))
        }
    }
    return out
}

// MARK: - OCR passes

struct OCRObs {
    let candidate: String
    let confidence: Float
    let yMid: CGFloat
    let height: CGFloat
}

func runOCR(image: CGImage, level: VNRequestTextRecognitionLevel,
            roi: CGRect?) -> [OCRObs] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    request.customWords = PLAUSIBLE_POWERS
    request.minimumTextHeight = 0.02
    if let roi = roi { request.regionOfInterest = roi }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do { try handler.perform([request]) } catch { return [] }
    guard let observations = request.results else { return [] }
    var out: [OCRObs] = []
    for obs in observations {
        let yMid = (obs.boundingBox.minY + obs.boundingBox.maxY) / 2
        let height = obs.boundingBox.height
        for cand in obs.topCandidates(3) {
            out.append(OCRObs(
                candidate: cand.string,
                confidence: cand.confidence,
                yMid: yMid, height: height
            ))
        }
    }
    return out
}

// MARK: - Vote aggregation

struct Vote {
    var count: Int = 0
    var totalScore: Float = 0   // weighted score, higher = better
    var heroSeen: Bool = false  // any vote came from a pass that ALSO saw the hero
}

func deepOCR(imageURL: URL, hero: String) -> (power: Int?, votes: [Int: Vote], allCandidates: [String]) {
    guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return (nil, [:], []) }

    let variants = preprocessVariants(cgImage: cgImage)
    let rois: [CGRect?] = [nil,
                           CGRect(x: 0.45, y: 0.65, width: 0.55, height: 0.35),
                           CGRect(x: 0.55, y: 0.70, width: 0.45, height: 0.30)]

    var votes: [Int: Vote] = [:]
    var allCandidates: [String] = []

    let heroLower = hero.lowercased()
    let heroLetters = heroLower.filter { $0.isLetter }

    for (_, image) in variants {
        for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
            for roi in rois {
                let obs = runOCR(image: image, level: level, roi: roi)
                if obs.isEmpty { continue }
                // Did this pass see the hero name?
                var thisPassSawHero = false
                for o in obs {
                    let cl = o.candidate.lowercased()
                    let cLetters = cl.filter { $0.isLetter }
                    if heroLetters.count >= 3 &&
                       (cLetters.contains(heroLetters) || heroLetters.contains(cLetters)) {
                        thisPassSawHero = true
                    }
                }
                for o in obs {
                    allCandidates.append(o.candidate)
                    // Only consider top-half observations for power glyphs.
                    if o.yMid <= 0.5 { continue }
                    let yWeight = max(0, Float((o.yMid - 0.5) * 2))
                    let powers = extractPowers(o.candidate)
                    for p in powers {
                        // Score: confidence * yWeight * canonical * heightWeight.
                        let canonical: Float = (p % 5 == 0) ? 1.0 : 0.6
                        let heightWeight = Float(o.height) * 10
                        let score = o.confidence * yWeight * canonical *
                                    (0.5 + heightWeight) *
                                    (thisPassSawHero ? 1.5 : 1.0)
                        var v = votes[p] ?? Vote()
                        v.count += 1
                        v.totalScore += score
                        if thisPassSawHero { v.heroSeen = true }
                        votes[p] = v
                    }
                }
            }
        }
    }

    // Pick the winner: highest totalScore, with hero-seen as tiebreaker.
    let winner = votes
        .filter { $1.heroSeen }   // require at least one hero-seen vote
        .max(by: { $0.value.totalScore < $1.value.totalScore })?.key
    return (winner, votes, allCandidates)
}

// MARK: - Output

struct ResultRow: Codable {
    let bobaId: String
    let hero: String
    let ocrPower: Int?
    let votes: [String: Int]
    let allCandidates: [String]
}

// MARK: - Main

func runDeepPass() async {
    let args = parseArgs()
    print("Deep OCR pass")
    print("  catalog:  \(args.catalog)")
    print("  bobaIds:  \(args.bobaIds)")
    print("  thumbs:   \(args.thumbsDir)")
    if let f = args.fullsizeDir { print("  fullsize: \(f)") }
    print("  output:   \(args.output)")
    print()

    let bidsList: [String]
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: args.bobaIds))
        bidsList = (try JSONSerialization.jsonObject(with: data) as? [String]) ?? []
    } catch { fputs("Couldn't load bobaIds: \(error)\n", stderr); exit(1) }

    let entries: [Entry]
    do {
        entries = try loadCatalogSubset(catalogPath: args.catalog, bobaIds: Set(bidsList))
    } catch { fputs("Catalog load failed: \(error)\n", stderr); exit(1) }
    print("Resolved \(entries.count) of \(bidsList.count) bobaIds in catalog (skipped: cleared imageFile)")

    let thumbsURL = URL(fileURLWithPath: args.thumbsDir)
    let fullsizeURL = args.fullsizeDir.map { URL(fileURLWithPath: $0) }
    let start = Date()
    var rows: [ResultRow] = []
    let total = entries.count
    let chunk = max(1, args.concurrency)
    var idx = 0
    while idx < total {
        let upper = min(idx + chunk, total)
        await withTaskGroup(of: ResultRow?.self) { group in
            for k in idx..<upper {
                let e = entries[k]
                let thumbPath = thumbsURL.appendingPathComponent(e.imageFile)
                let fullPath  = fullsizeURL?.appendingPathComponent(e.imageFile)
                group.addTask {
                    let url: URL
                    if let f = fullPath, FileManager.default.fileExists(atPath: f.path) {
                        url = f
                    } else if FileManager.default.fileExists(atPath: thumbPath.path) {
                        url = thumbPath
                    } else { return nil }
                    let result = deepOCR(imageURL: url, hero: e.hero)
                    let votesDict = Dictionary(
                        uniqueKeysWithValues: result.votes.map { (String($0.key), $0.value.count) }
                    )
                    return ResultRow(
                        bobaId: e.bobaId, hero: e.hero,
                        ocrPower: result.power, votes: votesDict,
                        allCandidates: Array(result.allCandidates.prefix(15))
                    )
                }
            }
            for await r in group {
                if let r = r { rows.append(r) }
            }
        }
        idx = upper
        if idx % 25 == 0 || idx == total {
            let dt = Date().timeIntervalSince(start)
            let rate = dt > 0 ? Double(idx) / dt : 0
            let eta = rate > 0 ? Double(total - idx) / rate : 0
            print("  \(idx)/\(total) — \(String(format: "%.1f", rate))/s — ETA \(Int(eta))s")
        }
    }

    let out = ["results": rows.map {
        [
            "bobaId": $0.bobaId,
            "hero": $0.hero,
            "ocrPower": $0.ocrPower as Any,
            "votes": $0.votes,
            "allCandidates": $0.allCandidates,
        ] as [String: Any]
    }]
    let data = try! JSONSerialization.data(withJSONObject: out,
                                           options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: args.output))
    let withPower = rows.filter { $0.ocrPower != nil }.count
    print()
    print("Total: \(rows.count), with extracted power: \(withPower)")
    print("Wrote \(args.output)")
}

await runDeepPass()
