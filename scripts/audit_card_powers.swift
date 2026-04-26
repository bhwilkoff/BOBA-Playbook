#!/usr/bin/env swift
// OCR every Hero thumbnail to extract the printed power value, write
// per-bobaId results to a JSON file. Comparing the OCR output against
// `cards.json:power` is downstream (Python script consumes this).
//
// Why Swift on macOS: Vision (`VNRecognizeTextRequest`) gives much
// better results on these stylized card faces than Tesseract, and we
// already have the toolchain pattern from the feature-print indexer.
//
// Strategy:
//   1. Crop the top-right ~30% × ~25% of the image. The printed power
//      is the only large isolated digit token in that region — much
//      higher SNR than full-frame OCR (which picks up cardNumber,
//      year markings, ability text, etc.).
//   2. Run VNRecognizeTextRequest with custom vocab for plausible
//      power values (multiples of 5 from 55–250).
//   3. Pick the digit-only string with the highest confidence whose
//      integer value is in the plausible range.
//
// Usage:
//   swift scripts/audit_card_powers.swift \
//     --catalog "/path/to/cards.json" \
//     --thumbs  "/path/to/thumbs" \
//     --output  /tmp/power-ocr.json \
//     [--limit N] [--concurrency 4] [-v]
//
// Output JSON shape:
// {
//   "results": [
//     {"bobaId": "ABF-326-Dunker-...", "ocrPower": 140, "confidence": 0.97},
//     ...
//   ],
//   "skipped": [
//     {"bobaId": "...", "reason": "no_image|low_confidence|out_of_range"}
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
    var thumbsDir: String = ""
    /// Optional fallback directory of larger images. Used only when
    /// the primary (thumb) OCR pass misses a power — the larger image
    /// pays a higher per-call cost but recovers stylized cards where
    /// the small thumb's printed power glyph is too noisy for Vision.
    var fullsizeDir: String? = nil
    var output: String = ""
    var limit: Int? = nil
    var concurrency: Int = 4
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
        case "--thumbs":      a.thumbsDir = next()
        case "--fullsize":    a.fullsizeDir = next()
        case "--output":      a.output = next()
        case "--limit":       a.limit = Int(next())
        case "--concurrency": a.concurrency = max(1, Int(next()) ?? 4)
        case "-v", "--verbose": a.verbose = true
        case "-h", "--help":
            print("Usage: --catalog cards.json --thumbs thumbsDir --output out.json [--limit N] [--concurrency 4]")
            exit(0)
        default:
            fputs("Unknown flag: \(flag)\n", stderr); exit(2)
        }
        i += 1
    }
    if a.catalog.isEmpty || a.thumbsDir.isEmpty || a.output.isEmpty {
        fputs("--catalog, --thumbs, --output are required\n", stderr)
        exit(2)
    }
    return a
}

// MARK: - Catalog

struct Entry {
    let bobaId: String
    let imageFile: String
    let cardType: String
    let catalogPower: Int?
}

func loadCatalog(path: String) throws -> [Entry] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw NSError(domain: "OCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "catalog must be a JSON array"])
    }
    var seen: Set<String> = []
    var out: [Entry] = []
    for c in json {
        guard let bobaId = c["bobaId"] as? String, !bobaId.isEmpty,
              let imageFile = c["imageFile"] as? String, !imageFile.isEmpty,
              let cardType = c["cardType"] as? String,
              cardType == "Hero"   // power audit is Hero-only
        else { continue }
        if !seen.insert(bobaId).inserted { continue }
        let pow = c["power"] as? Int
        out.append(Entry(bobaId: bobaId, imageFile: imageFile,
                         cardType: cardType, catalogPower: pow))
    }
    return out
}

// MARK: - OCR

struct OCRResult {
    let bobaId: String
    let printedPower: Int?
    let confidence: Float
    let topCandidates: [String]   // for debugging
}

/// Plausible power values printed on BoBA cards: multiples of 5 from
/// 55 (Hot Dogs / sealed) up through 250. Used as Vision customWords
/// to nudge the recognizer toward valid card powers when a glyph is
/// borderline.
let PLAUSIBLE_POWERS: [String] = stride(from: 55, through: 250, by: 5).map { String($0) }

let cropRect: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.55, 0.0, 0.45, 0.30)
// (originX, originY in [0..1] image space, width, height) — image
// coordinates have origin at TOP-LEFT for our purposes; we'll convert
// to Vision's regionOfInterest (origin BOTTOM-LEFT) when applying.

/// Pull the best-scoring power value out of a list of observations.
/// Scoring: confidence × y_position × canonical-multiple-of-5.
func scoreObservations(_ observations: [VNRecognizedTextObservation]) -> OCRResult? {
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
    var allCandidates: [String] = []
    var best: (val: Int, score: Float, conf: Float)? = nil
    for obs in observations {
        let yMid = (obs.boundingBox.minY + obs.boundingBox.maxY) / 2
        let height = obs.boundingBox.height
        let yWeight = max(0, Float((yMid - 0.5) * 2))
        if yWeight <= 0 { continue }
        for cand in obs.topCandidates(3) {
            let raw = cand.string.trimmingCharacters(in: .whitespacesAndNewlines)
            allCandidates.append(raw)
            for digits in [leadingDigits(raw), trailingDigits(raw)] {
                guard digits.count >= 2, digits.count <= 3,
                      let val = Int(digits), val >= 55, val <= 250
                else { continue }
                let canonical: Float = (val % 5 == 0) ? 1.0 : 0.7
                let heightWeight = Float(height) * 10
                let score = cand.confidence * yWeight * canonical * (0.5 + heightWeight)
                if best == nil || score > best!.score {
                    best = (val, score, cand.confidence)
                }
                break
            }
        }
    }
    if let b = best {
        return OCRResult(bobaId: "", printedPower: b.val,
                         confidence: b.conf, topCandidates: allCandidates)
    }
    return OCRResult(bobaId: "", printedPower: nil,
                     confidence: 0, topCandidates: allCandidates)
}

/// Single-pass OCR: full-frame .accurate on the source image with the
/// PLAUSIBLE_POWERS custom-words boost. Cheap and catches the 90%+
/// case. Caller falls back to `ocrPrintedPowerSlow` only when this
/// returns nil (no in-range digit token surfaced).
func ocrPrintedPowerFast(imageURL: URL) -> OCRResult? {
    guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    request.customWords = PLAUSIBLE_POWERS
    request.minimumTextHeight = 0.02
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do { try handler.perform([request]) } catch { return nil }
    return scoreObservations(request.results ?? [])
}

/// Heavy-weight multi-pass OCR for cards the fast path misses.
/// Preprocessed image, top-right crop, and a .fast model pass —
/// pays ~5x more time per call but recovers the stylized prints.
func ocrPrintedPowerSlow(imageURL: URL) -> OCRResult? {
    guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }

    // Build a preprocessed CGImage: stylized BoBA cards with high-
    // contrast art (Fire/Ice color blocks) often hide the printed
    // power glyph from Vision's accurate recognizer. Lifting darks +
    // dropping saturation + amplifying contrast normalizes the
    // power digits enough that Vision finds them reliably.
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
    let enhanced = ciContext.createCGImage(ci, from: ci.extent) ?? cgImage

    func runPass(image: CGImage, roi: CGRect?) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = PLAUSIBLE_POWERS
        request.minimumTextHeight = 0.02
        if let roi = roi { request.regionOfInterest = roi }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return request.results ?? []
    }

    func runFast(image: CGImage, roi: CGRect?) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = PLAUSIBLE_POWERS
        request.minimumTextHeight = 0.02
        if let roi = roi { request.regionOfInterest = roi }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return request.results ?? []
    }

    var observations: [VNRecognizedTextObservation] = []
    observations.append(contentsOf: runPass(image: cgImage,  roi: nil))
    observations.append(contentsOf: runPass(image: enhanced, roi: nil))
    observations.append(contentsOf: runPass(image: enhanced,
                        roi: CGRect(x: 0.55, y: 0.65, width: 0.45, height: 0.35)))
    // .fast pass on the original — different model, sometimes catches
    // glyphs the .accurate pass dismisses on stylized art.
    observations.append(contentsOf: runFast(image: cgImage, roi: nil))
    observations.append(contentsOf: runFast(image: enhanced, roi: nil))

    return scoreObservations(observations)
}

// MARK: - Output

struct ResultRow: Codable {
    let bobaId: String
    let ocrPower: Int?
    let confidence: Float
    let catalogPower: Int?
    let candidates: [String]
}

struct AuditOutput: Codable {
    let total: Int
    let withPower: Int
    let mismatches: Int
    let lowConfidence: Int
    let noPower: Int
    let results: [ResultRow]
}

// MARK: - Main

func runAudit() async {
    let args = parseArgs()
    print("BoBA card power audit")
    print("  catalog:    \(args.catalog)")
    print("  thumbs:     \(args.thumbsDir)")
    print("  output:     \(args.output)")
    print("  concurrency: \(args.concurrency)")

    let entries: [Entry]
    do { entries = try loadCatalog(path: args.catalog) }
    catch { fputs("Catalog load failed: \(error)\n", stderr); exit(1) }
    let limited = args.limit.map { Array(entries.prefix($0)) } ?? entries
    print("  Hero entries with imageFile: \(limited.count) (of \(entries.count))")
    print()

    let thumbsURL = URL(fileURLWithPath: args.thumbsDir)
    let fullsizeURL = args.fullsizeDir.map { URL(fileURLWithPath: $0) }
    let start = Date()
    var rows: [ResultRow] = []
    rows.reserveCapacity(limited.count)
    var skippedNoFile = 0
    var lowConfCount = 0
    var noPowerCount = 0
    var mismatches = 0
    let total = limited.count

    let chunk = max(1, args.concurrency)
    var idx = 0
    while idx < total {
        let upper = min(idx + chunk, total)
        await withTaskGroup(of: ResultRow?.self) { group in
            for k in idx..<upper {
                let e = limited[k]
                let thumbURL = thumbsURL.appendingPathComponent(e.imageFile)
                let fullURL  = fullsizeURL?.appendingPathComponent(e.imageFile)
                group.addTask {
                    guard FileManager.default.fileExists(atPath: thumbURL.path) else { return nil }
                    // Fast path: thumb + .accurate full-frame.
                    var ocr = ocrPrintedPowerFast(imageURL: thumbURL)
                    // Fallback to slow multi-pass when fast missed.
                    if ocr?.printedPower == nil {
                        ocr = ocrPrintedPowerSlow(imageURL: thumbURL)
                    }
                    // Final fallback: same slow pipeline on the full-
                    // size image (more pixels for the recognizer to
                    // resolve stylized power glyphs from).
                    if ocr?.printedPower == nil, let f = fullURL,
                       FileManager.default.fileExists(atPath: f.path) {
                        ocr = ocrPrintedPowerSlow(imageURL: f)
                    }
                    return ResultRow(
                        bobaId: e.bobaId,
                        ocrPower: ocr?.printedPower,
                        confidence: ocr?.confidence ?? 0,
                        catalogPower: e.catalogPower,
                        candidates: ocr?.topCandidates ?? []
                    )
                }
            }
            for await result in group {
                guard let r = result else { skippedNoFile += 1; continue }
                if r.ocrPower == nil { noPowerCount += 1 }
                if r.confidence > 0 && r.confidence < 0.5 { lowConfCount += 1 }
                if let ocr = r.ocrPower, let cat = r.catalogPower, ocr != cat {
                    mismatches += 1
                }
                rows.append(r)
            }
        }
        idx = upper
        if idx % 250 == 0 || idx == total {
            let dt = Date().timeIntervalSince(start)
            let rate = dt > 0 ? Double(idx) / dt : 0
            let etaSec = rate > 0 ? Double(total - idx) / rate : 0
            let etaStr = etaSec >= 60
                ? String(format: "ETA %dm%02ds", Int(etaSec) / 60, Int(etaSec) % 60)
                : String(format: "ETA %ds", Int(etaSec))
            print("  \(idx)/\(total) — \(String(format: "%.1f", rate))/s — " +
                  "mismatches=\(mismatches) lowConf=\(lowConfCount) noPwr=\(noPowerCount) — \(etaStr)")
        }
    }

    print()
    print("Total entries:       \(rows.count)")
    print("Missing thumb files: \(skippedNoFile)")
    print("OCR returned no power: \(noPowerCount)")
    print("Low-confidence:      \(lowConfCount)")
    print("Mismatches:          \(mismatches)")
    let elapsed = Date().timeIntervalSince(start)
    print(String(format: "Elapsed: %.1fs", elapsed))

    let out = AuditOutput(
        total: rows.count,
        withPower: rows.filter { $0.ocrPower != nil }.count,
        mismatches: mismatches,
        lowConfidence: lowConfCount,
        noPower: noPowerCount,
        results: rows
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(out)
        try data.write(to: URL(fileURLWithPath: args.output))
        print("Wrote \(args.output) (\(data.count) bytes)")
    } catch {
        fputs("Write failed: \(error)\n", stderr); exit(1)
    }
}

await runAudit()
