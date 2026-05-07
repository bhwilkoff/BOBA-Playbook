// main.swift
//
// CardRecognitionCLI — runs the iOS scanner's recognition pipeline
// against a batch of candidate images on a macos-15 GitHub Actions
// runner. The Python wrapper script (pipeline/scripts/stage_b_recognize.py)
// downloads images from R2 and feeds candidate paths in via JSONL on
// stdin (or --input file), then reads results from stdout (or --output
// file) and writes them back to Supabase.
//
// USAGE
//   cardreckon \
//       --cards-json   /path/to/display-cards.json \
//       --feature-prints /path/to/feature-prints.bin \
//       --input  candidates.jsonl \
//       --output results.jsonl
//
// INPUT FORMAT (one JSON object per line on stdin or in --input file):
//   {"id": "uuid-or-any-string", "image_path": "/abs/or/rel/path.jpg"}
//
// OUTPUT FORMAT (one JSON object per line on stdout or in --output):
//   {
//     "id": "uuid",
//     "recognized_boba_id": "A-100-Maverick--",   // null if no clear winner
//     "score":              1.85,                 // top candidate's raw score
//     "margin":             0.40,                 // gap to runner-up (different hero)
//     "top_candidates": [
//       {"boba_id": "A-100-Maverick--", "score": 1.85, "normalized": 1.0},
//       {"boba_id": "A-100-Maverick-Battlefoil-", "score": 1.45, "normalized": 0.78},
//       ...
//     ],
//     "ocr": {
//       "card_number_hint": "A-100",
//       "raw_name":         "MAVERICK",
//       "full_text":        "MAVERICK A-100 BATTLE 320 FIRE..."
//     },
//     "error":              null
//   }
//
// The `error` field is non-null on per-candidate failures (image won't
// load, Vision crashed, etc.); the rest of the line stays valid JSON
// so the Python wrapper can pipe results without parsing fallouts.

import Foundation

// MARK: - JSON shapes

private struct InputCandidate: Decodable {
    let id: String
    let image_path: String
}

private struct OutputTopCandidate: Encodable {
    let boba_id: String
    let score: Float
    let normalized: Double
}

private struct OutputOCR: Encodable {
    let card_number_hint: String
    let raw_name:         String
    let full_text:        String
}

private struct OutputCrop: Encodable {
    let path:       String       // local path where the tight crop was written
    let method:     String       // "vision_rect" | "center_57" | "uncropped"
    let confidence: Float        // 0..1 — Vision rect confidence; 0 on fallback
}

private struct OutputResult: Encodable {
    let id: String
    let recognized_boba_id: String?
    let score: Float?
    let margin: Float?
    let top_candidates: [OutputTopCandidate]
    let ocr: OutputOCR?
    let crop: OutputCrop?
    let error: String?
}

// MARK: - Argument parser (lightweight)

private struct Args {
    var cardsJsonPath:   String = ""
    var featurePrintsPath: String = ""
    var inputPath:       String? = nil   // nil → read stdin
    var outputPath:      String? = nil   // nil → write stdout

    static func parse() throws -> Args {
        var args = Args()
        var iter = CommandLine.arguments.dropFirst().makeIterator()
        while let flag = iter.next() {
            switch flag {
            case "--cards-json":
                guard let v = iter.next() else { throw CLIError.usage("--cards-json requires a value") }
                args.cardsJsonPath = v
            case "--feature-prints":
                guard let v = iter.next() else { throw CLIError.usage("--feature-prints requires a value") }
                args.featurePrintsPath = v
            case "--input":
                args.inputPath = iter.next()
            case "--output":
                args.outputPath = iter.next()
            case "-h", "--help":
                throw CLIError.usage("see header comment in main.swift for full usage")
            default:
                throw CLIError.usage("unknown flag: \(flag)")
            }
        }
        if args.cardsJsonPath.isEmpty {
            throw CLIError.usage("missing --cards-json")
        }
        if args.featurePrintsPath.isEmpty {
            throw CLIError.usage("missing --feature-prints")
        }
        return args
    }
}

private enum CLIError: Error {
    case usage(String)
    case file(String)
}

// MARK: - Entry

@main
struct CardRecognitionCLI {

    @MainActor
    static func main() async {
        do {
            let args = try Args.parse()
            try await run(args)
        } catch let CLIError.usage(msg) {
            FileHandle.standardError.write(Data("usage error: \(msg)\n".utf8))
            exit(64)
        } catch {
            FileHandle.standardError.write(Data("fatal: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func run(_ args: Args) async throws {
        // ─── Load catalog ─────────────────────────────────────────────
        let cardsURL = URL(fileURLWithPath: args.cardsJsonPath)
        guard let cardsData = try? Data(contentsOf: cardsURL) else {
            throw CLIError.file("cannot read \(args.cardsJsonPath)")
        }
        let allCards: [Card]
        do {
            allCards = try JSONDecoder().decode([Card].self, from: cardsData)
        } catch {
            throw CLIError.file("cards.json decode failed: \(error)")
        }
        FileHandle.standardError.write(
            Data("loaded \(allCards.count) cards from \(args.cardsJsonPath)\n".utf8)
        )

        // ─── Load feature-prints index ────────────────────────────────
        let fpURL = URL(fileURLWithPath: args.featurePrintsPath)
        FeaturePrintIndex.shared.load(from: fpURL)
        guard FeaturePrintIndex.shared.isLoaded else {
            throw CLIError.file("feature-prints.bin failed to load (path=\(args.featurePrintsPath))")
        }
        FileHandle.standardError.write(
            Data("loaded feature prints: \(FeaturePrintIndex.shared.entryCount) entries × \(FeaturePrintIndex.shared.elementCount) dims\n".utf8)
        )

        // ─── Build OCR custom-words list (catalog cardNumbers) ────────
        // Mirrors CardScanner's customWords behavior: feeding known
        // identifiers to VNRecognizeTextRequest biases its language
        // model toward exact reads of "BLBF-208" rather than dictionary
        // substitutions.
        let customWords = Array(Set(allCards.map { $0.cardNumber }))

        // ─── Open input + output streams ──────────────────────────────
        let input: FileHandle = try {
            if let path = args.inputPath {
                guard let h = FileHandle(forReadingAtPath: path) else {
                    throw CLIError.file("cannot open input \(path)")
                }
                return h
            }
            return FileHandle.standardInput
        }()

        let output: FileHandle = try {
            if let path = args.outputPath {
                FileManager.default.createFile(atPath: path, contents: nil)
                guard let h = FileHandle(forWritingAtPath: path) else {
                    throw CLIError.file("cannot open output \(path)")
                }
                return h
            }
            return FileHandle.standardOutput
        }()

        // ─── Process candidates one line at a time ───────────────────
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        var processed = 0
        let inputText = String(data: input.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in inputText.split(separator: "\n", omittingEmptySubsequences: true) {
            let result = await processOne(
                line: String(line),
                allCards: allCards,
                customWords: customWords
            )
            let data = try encoder.encode(result)
            output.write(data)
            output.write(Data("\n".utf8))
            processed += 1

            if processed % 25 == 0 {
                FileHandle.standardError.write(
                    Data("  processed \(processed) candidates\n".utf8)
                )
            }
        }
        FileHandle.standardError.write(
            Data("done. processed \(processed) candidates total.\n".utf8)
        )
    }

    // MARK: - Per-candidate processing

    @MainActor
    private static func processOne(
        line: String,
        allCards: [Card],
        customWords: [String]
    ) async -> OutputResult {

        let candidate: InputCandidate
        do {
            candidate = try JSONDecoder().decode(InputCandidate.self, from: Data(line.utf8))
        } catch {
            return OutputResult(
                id: "<unparseable>",
                recognized_boba_id: nil,
                score: nil, margin: nil,
                top_candidates: [], ocr: nil,
                crop: nil,
                error: "input line not valid JSON: \(error)"
            )
        }

        let imageURL = URL(fileURLWithPath: candidate.image_path)
        guard let cgImage = VisionOCR.loadImage(at: imageURL) else {
            return OutputResult(
                id: candidate.id,
                recognized_boba_id: nil,
                score: nil, margin: nil,
                top_candidates: [], ocr: nil,
                crop: nil,
                error: "image file unreadable or undecodable: \(candidate.image_path)"
            )
        }

        // Tight-crop step: use Vision rect detection + perspective
        // correction to produce a tight 5:7 portrait. Recognition runs
        // on the rectified crop so OCR + FP see the same kind of pixels
        // the catalog feature-print index was built from.
        // Output JPEG sits next to the input (id-tight.jpg) and Stage B
        // uploads it to R2 staging/tight-crops/.
        let tightCropURL = imageURL
            .deletingPathExtension()
            .appendingPathExtension("tight.jpg")
        let cropInfo = TightCrop.tightCrop(input: cgImage, to: tightCropURL)
        let cropOut = OutputCrop(
            path: tightCropURL.path,
            method: cropInfo.method.rawValue,
            confidence: cropInfo.sourceConfidence
        )

        // Reload the rectified image as a CGImage. This is the input
        // we feed Vision OCR + ScanMatching — NOT the original.
        let recognitionImage = VisionOCR.loadImage(at: tightCropURL) ?? cgImage

        // Run OCR + build observation on the tight crop
        let observation = VisionOCR.ocr(cgImage: recognitionImage, customWords: customWords)

        // Resolve to a card via ScanMatching (the heavy scoring + hero
        // veto + confidence/margin gates live inside)
        let resolution = await ScanMatching.resolveDetailed(
            observation: observation,
            allCards: allCards,
            label: "candidate \(candidate.id)"
        )

        // Margin to next-different-hero candidate (replicates the
        // resolver's internal margin gate so downstream consumers see
        // why a candidate was AUTO vs REVIEW vs QUARANTINE)
        let topCardsForMargin = resolution.topCandidates.prefix(8)
        var margin: Float? = nil
        if let top = topCardsForMargin.first,
           let runnerUp = topCardsForMargin.dropFirst().first(where: { $0.card.hero != top.card.hero }) {
            margin = top.score - runnerUp.score
        }

        let topOut: [OutputTopCandidate] = resolution.topCandidates
            .prefix(8)
            .map { OutputTopCandidate(
                boba_id: $0.id,
                score: $0.score,
                normalized: $0.normalizedScore
            )}

        return OutputResult(
            id: candidate.id,
            recognized_boba_id: resolution.chosen?.id,
            score: resolution.topCandidates.first?.score,
            margin: margin,
            top_candidates: topOut,
            ocr: OutputOCR(
                card_number_hint: observation.cardNumber,
                raw_name:         observation.rawName,
                full_text:        observation.fullText
            ),
            crop: cropOut,
            error: nil
        )
    }
}
