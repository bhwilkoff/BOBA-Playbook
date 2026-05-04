#!/usr/bin/env swift
// Build a BFPI feature-print index for the BOBA Playbook iOS scanner.
//
// Walks a card catalog JSON, runs VNGenerateImageFeaturePrintRequest on
// each card's local thumbnail, and writes a binary index that the iOS
// app loads at scan time for image-similarity matching.
//
// Usage:
//   swift scripts/build_feature_print_index.swift \
//     --catalog "/path/to/cards.json" \
//     --thumbs  "/path/to/thumbs" \
//     --output  "BOBAPlaybook/feature-prints.bin" \
//     [--limit N] [--concurrency 4]
//
// File format v2 (little-endian, native iOS/macOS arm64 byte order):
//   magic        char[4]   "BFPI"
//   version      uint32    2
//   entryCount   uint32    N
//   elementCount uint32    floats per print (Vision Rev2: 768)
//   elementSize  uint32    1 = int8 with per-vector scale
//   For each entry:
//     idLen      uint16
//     id         char[idLen]      bobaId UTF-8
//     scale      float32          dequantize multiplier (max(|v|)/127)
//     bytes      int8[elementCount]  quantized values in [-127, 127]
//
// Quantization rationale: feature-print elements are small floats
// (typically [-0.1, 0.1]). Storing as Float32 wastes 24 bits of
// precision per element that's irrelevant for L2-rank ordering. Int8
// with per-vector scale recovers full dynamic range per print and
// shrinks the file 4x. Combined with `--multi-only` filtering (skip
// singletons that can't trigger tiebreak), the resulting bundle is
// ~7 MB instead of 48 MB.
//
// Distance computation on iOS dequantizes per-comparison: distance =
// sum((q[k] - scale * int8[k])^2). vDSP handles it efficiently.

import Foundation
import Vision
import CoreGraphics
import ImageIO

// MARK: - Args

struct Args {
    var catalog: String = ""
    var thumbsDir: String = ""
    var output: String = ""
    var limit: Int? = nil
    var concurrency: Int = 4
    var verbose: Bool = false
    /// When true, only cards whose cardNumber is shared with another
    /// card are indexed. This was the original tiebreaker-era default
    /// (BFPI v2 / 9,206 entries) — it assumed OCR alone resolved
    /// uniquely-numbered cards, and FP only ran on collision groups.
    ///
    /// As of the unified CardRecognizer (FP-primary), FP must cover
    /// every imaged card or the recognizer can't propose candidates
    /// for the majority of the catalog. Default flipped to false.
    /// Pass --multi-only to restore tiebreaker-only coverage.
    var multiOnly: Bool = false
}

func parseArgs() -> Args {
    var a = Args()
    let argv = CommandLine.arguments
    var i = 1
    while i < argv.count {
        let flag = argv[i]
        let next: () -> String = {
            i += 1
            guard i < argv.count else {
                fputs("Missing value for \(flag)\n", stderr)
                exit(2)
            }
            return argv[i]
        }
        switch flag {
        case "--catalog":     a.catalog = next()
        case "--thumbs":      a.thumbsDir = next()
        case "--output":      a.output = next()
        case "--limit":       a.limit = Int(next())
        case "--concurrency": a.concurrency = max(1, Int(next()) ?? 4)
        case "-v", "--verbose": a.verbose = true
        case "--all":           a.multiOnly = false  // legacy alias, default is now full coverage
        case "--multi-only":    a.multiOnly = true
        case "-h", "--help":
            print("""
            Usage: swift build_feature_print_index.swift \\
              --catalog cards.json --thumbs thumbsDir --output out.bin \\
              [--limit N] [--concurrency 4] [-v]
            """)
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

struct CardEntry {
    let bobaId: String
    let imageFile: String
}

struct LoadedCatalog {
    let entries: [CardEntry]
    let totalImaged: Int   // pre-filter count for reporting
}

func loadCatalog(path: String, multiOnly: Bool) throws -> LoadedCatalog {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw NSError(domain: "BFPI", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Catalog must be a JSON array"])
    }

    // First pass — count cardNumber occurrences (over imaged cards only).
    var cardNumberCounts: [String: Int] = [:]
    for c in json {
        guard let cn = c["cardNumber"] as? String, !cn.isEmpty else { continue }
        guard let f = c["imageFile"] as? String, !f.isEmpty else { continue }
        cardNumberCounts[cn, default: 0] += 1
    }

    // Second pass — emit only cards we actually want indexed.
    var seen: Set<String> = []
    var out: [CardEntry] = []
    var totalImaged = 0
    for c in json {
        guard let bobaId = c["bobaId"] as? String, !bobaId.isEmpty else { continue }
        guard let imageFile = c["imageFile"] as? String, !imageFile.isEmpty else { continue }
        guard let cn = c["cardNumber"] as? String, !cn.isEmpty else { continue }
        totalImaged += 1
        if !seen.insert(bobaId).inserted { continue }
        if multiOnly, (cardNumberCounts[cn] ?? 0) < 2 { continue }
        out.append(CardEntry(bobaId: bobaId, imageFile: imageFile))
    }
    return LoadedCatalog(entries: out, totalImaged: totalImaged)
}

// MARK: - Feature print

struct PrintResult {
    let bobaId: String
    let data: Data
    let elementCount: Int
    let elementSize: Int
}

enum PrintError: Error { case noResult, fileMissing, badImage }

func featurePrint(bobaId: String, imageURL: URL) throws -> PrintResult {
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        throw PrintError.fileMissing
    }
    let request = VNGenerateImageFeaturePrintRequest()
    // .scaleFit preserves the FULL card content by letterboxing the
    // 0.71-aspect card into a square (padding on the sides). The
    // alternative — .centerCrop, used through 1.949 — strips ~14%
    // off the top and bottom of the catalog image, removing the
    // border foil patterns and treatment-distinguishing badge
    // styling that's the only visual difference between same-hero
    // treatments (e.g., BLBF-786 Castler vs LOGO-786 Castler share
    // the same character art; only the borders differ). Without
    // those borders, FP's central artwork match couldn't tell
    // treatments apart.
    //
    // The iOS-side runtime must use the SAME crop option or query
    // vectors won't be comparable to indexed ones — see
    // FeaturePrintIndex.computeAllDistances in CardScanner.swift.
    request.imageCropAndScaleOption = .scaleFit
    // Pin to revision 2 (768-float embeddings, iOS 17+ / macOS 14+).
    // Pinning matters because the iOS-side reader has to use the same
    // model — different revisions produce incompatible vectors that
    // would silently mismatch dimensions and bypass disambiguation.
    request.revision = VNGenerateImageFeaturePrintRequestRevision2
    let handler = VNImageRequestHandler(url: imageURL, options: [:])
    try handler.perform([request])
    guard let fp = request.results?.first as? VNFeaturePrintObservation else {
        throw PrintError.noResult
    }
    let elementSize: Int
    switch fp.elementType {
    case .float:   elementSize = 4
    case .double:  elementSize = 8
    case .unknown: elementSize = 0
    @unknown default: elementSize = 0
    }
    guard elementSize > 0 else { throw PrintError.noResult }
    return PrintResult(
        bobaId: bobaId,
        data: fp.data,
        elementCount: fp.elementCount,
        elementSize: elementSize
    )
}

// MARK: - Output

/// Append a fixed-width little-endian integer to a buffer. We use
/// withUnsafeBytes on a local var rather than the deprecated
/// `Data(bytes: &x, count:)` which moved to a private API in Swift 6.
func appendLE<T>(_ value: T, to buf: inout Data) where T: FixedWidthInteger {
    var v = value.littleEndian
    withUnsafeBytes(of: &v) { buf.append(contentsOf: $0) }
}

/// Quantize a Float32 vector to int8 with a per-vector scale.
/// scale = max(|v|) / 127, q[i] = round(v[i] / scale). Decoded value
/// = scale * q[i]. Preserves L2-rank ordering well — within-vector
/// rounding error is sub-1% relative to the largest absolute element.
func quantize(_ floats: [Float]) -> (scale: Float, q: [Int8]) {
    var maxAbs: Float = 0
    for v in floats { let a = abs(v); if a > maxAbs { maxAbs = a } }
    // All-zero vector: scale = 0, all bytes 0. Distance still works.
    let scale: Float = maxAbs == 0 ? 0 : maxAbs / 127.0
    var q: [Int8] = []
    q.reserveCapacity(floats.count)
    if scale == 0 {
        q.append(contentsOf: repeatElement(0, count: floats.count))
    } else {
        let invScale = 1.0 / scale
        for v in floats {
            let scaled = (v * invScale).rounded()
            // Clamp guards against rounding edge cases at the
            // extremes (e.g. 127.5 → 128 which doesn't fit int8).
            let clamped = max(-127, min(127, scaled))
            q.append(Int8(clamped))
        }
    }
    return (scale, q)
}

func writeBFPI(prints: [PrintResult],
               elementCount: Int,
               to path: String) throws {
    var out = Data()
    out.append(contentsOf: Array("BFPI".utf8))
    appendLE(UInt32(2), to: &out)            // version 2 = int8 quantized
    appendLE(UInt32(prints.count), to: &out)
    appendLE(UInt32(elementCount), to: &out)
    appendLE(UInt32(1), to: &out)            // elementSize = 1 (int8)
    for p in prints {
        // Decode the source Float32 print bytes into a Swift [Float].
        precondition(p.data.count == elementCount * 4,
                     "Print byte size mismatch for \(p.bobaId)")
        var floats = [Float](repeating: 0, count: elementCount)
        floats.withUnsafeMutableBufferPointer { dst in
            _ = p.data.copyBytes(to: dst)
        }
        let (scale, q) = quantize(floats)

        let idBytes = Array(p.bobaId.utf8)
        appendLE(UInt16(idBytes.count), to: &out)
        out.append(contentsOf: idBytes)
        // Scale as Float32, little-endian. Use bitPattern → UInt32 to
        // route through the same little-endian writer.
        appendLE(scale.bitPattern, to: &out)
        // Int8 vector — bytes are sign-correct in two's complement.
        out.append(contentsOf: q.withUnsafeBytes { Array($0) })
    }
    try out.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

func runIndexer() async {
        let args = parseArgs()
        print("BFPI indexer")
        print("  catalog:    \(args.catalog)")
        print("  thumbs:     \(args.thumbsDir)")
        print("  output:     \(args.output)")
        print("  concurrency: \(args.concurrency)")

        let loaded: LoadedCatalog
        do {
            loaded = try loadCatalog(path: args.catalog, multiOnly: args.multiOnly)
        } catch {
            fputs("Catalog load failed: \(error)\n", stderr)
            exit(1)
        }
        let entries = loaded.entries
        let limited = args.limit.map { Array(entries.prefix($0)) } ?? entries
        let filterDesc = args.multiOnly ? "shared cardNumber only" : "all imaged"
        print("  entries: \(limited.count) (\(filterDesc); \(loaded.totalImaged) imaged total)")
        print()

        let thumbsURL = URL(fileURLWithPath: args.thumbsDir)
        let start = Date()
        var prints: [PrintResult] = []
        prints.reserveCapacity(limited.count)
        var skipped = 0
        var elementCount = 0
        var elementSize  = 0

        // Process in chunks to bound memory and surface progress.
        let chunk = max(1, args.concurrency)
        var idx = 0
        let total = limited.count
        while idx < total {
            let upper = min(idx + chunk, total)
            await withTaskGroup(of: Result<PrintResult, Error>.self) { group in
                for k in idx..<upper {
                    let e = limited[k]
                    let imageURL = thumbsURL.appendingPathComponent(e.imageFile)
                    group.addTask {
                        do {
                            return .success(try featurePrint(bobaId: e.bobaId, imageURL: imageURL))
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let p):
                        if elementCount == 0 {
                            elementCount = p.elementCount
                            elementSize  = p.elementSize
                        }
                        guard p.elementCount == elementCount,
                              p.elementSize  == elementSize
                        else {
                            skipped += 1
                            if args.verbose {
                                fputs("skip \(p.bobaId): \(p.elementCount)x\(p.elementSize) " +
                                      "(expected \(elementCount)x\(elementSize))\n", stderr)
                            }
                            break
                        }
                        prints.append(p)
                    case .failure(let err):
                        skipped += 1
                        if args.verbose {
                            fputs("skip: \(err)\n", stderr)
                        }
                    }
                }
            }
            idx = upper
            // Progress every ~250 entries or end.
            if idx % 250 == 0 || idx == total {
                let dt = Date().timeIntervalSince(start)
                let rate = dt > 0 ? Double(idx) / dt : 0
                let etaSec = rate > 0 ? Double(total - idx) / rate : 0
                let etaStr: String
                if etaSec >= 60 {
                    etaStr = String(format: "ETA %dm%02ds",
                                    Int(etaSec) / 60, Int(etaSec) % 60)
                } else {
                    etaStr = String(format: "ETA %ds", Int(etaSec))
                }
                print("  \(idx)/\(total) — \(String(format: "%.1f", rate))/s — " +
                      "\(prints.count) ok, \(skipped) skipped — \(etaStr)")
            }
        }

        print()
        print("Element count: \(elementCount), element size: \(elementSize)")
        print("Per-print bytes: \(elementCount * elementSize)")
        print("Total prints: \(prints.count) — skipped: \(skipped)")

        do {
            try writeBFPI(prints: prints,
                          elementCount: elementCount,
                          to: args.output)
        } catch {
            fputs("Write failed: \(error)\n", stderr)
            exit(1)
        }
        let outURL = URL(fileURLWithPath: args.output)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path),
           let size = attrs[.size] as? Int {
            print("Wrote \(size) bytes (\(String(format: "%.1f", Double(size) / 1_048_576)) MB) " +
                  "to \(args.output)")
        }
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "Total time: %.1fs", elapsed))
}

await runIndexer()
