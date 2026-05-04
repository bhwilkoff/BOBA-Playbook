// Recognizer CLI — full per-cell recognition for BOBA Playbook grid scans.
// Mirrors the iOS pipeline (detection + OCR + FP + ScanMatching scoring)
// in a standalone macOS tool so the matching logic can be iterated against
// real photos without round-tripping through Xcode every time.
//
// Build + run:
//   cd tools/RecognizerCLI
//   swiftc -O main.swift -o recognize -framework AppKit -framework Vision
//   ./recognize <image1.HEIC> [image2.HEIC ...]
//
// Outputs per-image: detected cells, OCR'd text per cell, top FP candidates,
// scored candidates with breakdown, the chosen card.

import Foundation
import Vision
import CoreImage
import ImageIO
import AppKit
import Accelerate

// MARK: - Catalog

struct Card: Decodable {
    let bobaId: String
    let cardNumber: String
    let hero: String         // empty string when JSON has null/missing
    let name: String         // empty string when JSON has null/missing
    let element: String?
    let treatment: String?
    let power: Int?
    let imageFile: String?
    let set: String          // "Griffey Edition" / "Alpha Update" / etc. — empty if missing
    let release: String      // "Griffey" / "Alpha Update" / etc. — empty if missing
    let cardType: String     // "Hero" / "Play" / "Hot Dog" / "Sealed Product"

    enum CodingKeys: String, CodingKey {
        case bobaId, cardNumber, hero, name, element, treatment, power, imageFile, set, release, cardType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bobaId      = try c.decode(String.self, forKey: .bobaId)
        cardNumber  = try c.decode(String.self, forKey: .cardNumber)
        hero        = (try? c.decodeIfPresent(String.self, forKey: .hero))      ?? ""
        name        = (try? c.decodeIfPresent(String.self, forKey: .name))      ?? ""
        element     = try? c.decodeIfPresent(String.self, forKey: .element)
        treatment   = try? c.decodeIfPresent(String.self, forKey: .treatment)
        power       = try? c.decodeIfPresent(Int.self,    forKey: .power)
        imageFile   = try? c.decodeIfPresent(String.self, forKey: .imageFile)
        set         = (try? c.decodeIfPresent(String.self, forKey: .set))       ?? ""
        release     = (try? c.decodeIfPresent(String.self, forKey: .release))   ?? ""
        cardType    = (try? c.decodeIfPresent(String.self, forKey: .cardType))  ?? ""
    }
}

let catalogPath = "/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/assets/data/cards.json"
let fpIndexPath = "/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/BOBAPlaybook/feature-prints.bin"

func loadCatalog() -> [Card] {
    guard let data = FileManager.default.contents(atPath: catalogPath) else {
        FileHandle.standardError.write("Catalog not found at \(catalogPath)\n".data(using: .utf8)!)
        exit(1)
    }
    let dec = JSONDecoder()
    do {
        return try dec.decode([Card].self, from: data)
    } catch {
        FileHandle.standardError.write("Catalog decode failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - Feature Print Index (port of FeaturePrintIndex from CardScanner.swift)

final class FPIndex {
    private(set) var bobaIds: [String] = []
    private(set) var elementCount: Int = 0
    private(set) var entryCount: Int = 0
    private var flatVectors: [Float] = []

    func loadFromBundle() {
        guard let data = FileManager.default.contents(atPath: fpIndexPath) else {
            FileHandle.standardError.write("FP index not found at \(fpIndexPath)\n".data(using: .utf8)!)
            exit(1)
        }
        guard parse(bfpi: data) else {
            FileHandle.standardError.write("FP index parse failed\n".data(using: .utf8)!)
            exit(1)
        }
    }

    private func parse(bfpi data: Data) -> Bool {
        let headerLen = 4 + 4 * 4
        guard data.count >= headerLen else { return false }
        let magic = data.prefix(4)
        guard magic == Data("BFPI".utf8) else { return false }
        func readU32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        func readU16(_ offset: Int) -> UInt16 {
            data.withUnsafeBytes { raw in
                UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            }
        }
        let version = readU32(4)
        let entries = Int(readU32(8))
        let elementCount = Int(readU32(12))
        let elementSize = Int(readU32(16))
        guard entries > 0, elementCount > 0 else { return false }
        let isV2 = (version == 2 && elementSize == 1)
        guard isV2 else { return false }
        var ids: [String] = []
        ids.reserveCapacity(entries)
        var flat = [Float](repeating: 0, count: entries * elementCount)
        var cursor = headerLen
        for i in 0..<entries {
            guard cursor + 2 <= data.count else { return false }
            let idLen = Int(readU16(cursor)); cursor += 2
            guard cursor + idLen <= data.count else { return false }
            let idData = data.subdata(in: cursor..<(cursor + idLen))
            guard let id = String(data: idData, encoding: .utf8) else { return false }
            ids.append(id)
            cursor += idLen
            guard cursor + 4 + elementCount <= data.count else { return false }
            let scaleBits = readU32(cursor); cursor += 4
            let scale = Float(bitPattern: scaleBits)
            data.withUnsafeBytes { srcRaw in
                let i8Ptr = srcRaw.baseAddress!.advanced(by: cursor).assumingMemoryBound(to: Int8.self)
                flat.withUnsafeMutableBufferPointer { dst in
                    let dstPtr = dst.baseAddress!.advanced(by: i * elementCount)
                    vDSP_vflt8(i8Ptr, 1, dstPtr, 1, vDSP_Length(elementCount))
                    var s = scale
                    vDSP_vsmul(dstPtr, 1, &s, dstPtr, 1, vDSP_Length(elementCount))
                }
            }
            cursor += elementCount
        }
        self.bobaIds = ids
        self.flatVectors = flat
        self.elementCount = elementCount
        self.entryCount = entries
        return true
    }

    /// Returns full distance map (bobaId → L2-squared distance) for a query image.
    func distances(in cgImage: CGImage) -> [String: Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [:] }
        guard let query = request.results?.first as? VNFeaturePrintObservation,
              query.elementCount == elementCount,
              query.elementType == .float
        else { return [:] }
        var queryVec = [Float](repeating: 0, count: elementCount)
        let byteCount = elementCount * MemoryLayout<Float>.size
        guard query.data.count == byteCount else { return [:] }
        queryVec.withUnsafeMutableBufferPointer { dst in
            _ = query.data.copyBytes(to: dst)
        }
        var distances = [Float](repeating: 0, count: entryCount)
        let n = vDSP_Length(elementCount)
        flatVectors.withUnsafeBufferPointer { allBase in
            queryVec.withUnsafeBufferPointer { qBase in
                for i in 0..<entryCount {
                    var d: Float = 0
                    let entryStart = allBase.baseAddress!.advanced(by: i * elementCount)
                    vDSP_distancesq(qBase.baseAddress!, 1, entryStart, 1, &d, n)
                    distances[i] = d
                }
            }
        }
        var out: [String: Float] = [:]
        out.reserveCapacity(entryCount)
        for i in 0..<entryCount {
            if out[bobaIds[i]] == nil { out[bobaIds[i]] = distances[i] }
        }
        return out
    }
}

// MARK: - Image loading (HEIC → CGImage)

func loadCGImage(at path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, [
            kCGImageSourceShouldCache: false
          ] as CFDictionary)
    else { return nil }
    // Bake EXIF orientation into the pixels so downstream processing
    // sees a top-left-origin upright image.
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let ori = (props?[kCGImagePropertyOrientation] as? UInt32).flatMap { CGImagePropertyOrientation(rawValue: $0) } ?? .up
    if ori == .up { return img }
    let ci = CIImage(cgImage: img).oriented(ori)
    let ctx = CIContext()
    return ctx.createCGImage(ci, from: ci.extent)
}

// MARK: - GridCardDetector port

struct DetectedCell {
    let row: Int
    let column: Int
    let cellRect: CGRect       // normalized CIImage coords (bottom-left origin)
    let crop: CGImage           // axis-aligned crop ready for OCR + FP
}

enum GridDetector {
    static func detect(cgImage: CGImage) -> [DetectedCell] {
        let ci = CIImage(cgImage: cgImage)
        let observations = runRectangleRequest(ci: ci)

        let rawAnchors = observations.filter { obs in
            let aspect = obs.boundingBox.width / obs.boundingBox.height
            let area = obs.boundingBox.width * obs.boundingBox.height
            return aspect >= 0.50 && aspect <= 1.10
                && obs.boundingBox.width >= 0.10
                && obs.boundingBox.height >= 0.10
                && area <= 0.36
        }
        #if DEBUG_DETECT
        FileHandle.standardError.write("DETECT raw=\(observations.count) filtered=\(rawAnchors.count)\n".data(using: .utf8)!)
        for o in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            let bb = o.boundingBox
            let aspect = bb.width / bb.height
            let area = bb.width * bb.height
            let kept = (aspect >= 0.50 && aspect <= 1.10 && bb.width >= 0.10 && bb.height >= 0.10 && area <= 0.36) ? "KEPT" : "DROP"
            let line = String(format: "  %@ y=%.3f x=%.3f w=%.3f h=%.3f conf=%.2f aspect=%.2f area=%.3f\n", kept, bb.midY, bb.midX, bb.width, bb.height, o.confidence, aspect, area)
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
        #endif
        let deduped = dedupOverlapping(rawAnchors)
        guard !deduped.isEmpty else { return [] }

        // Two-pass refinement
        let anchors: [VNRectangleObservation]
        if let rough = GridGeometry.infer(from: deduped) {
            let cellTolerance = max(rough.medianWidth, rough.medianHeight) * 0.7
            let cleaned = deduped.filter { obs in
                rough.cells.contains { cell in
                    let dx = obs.boundingBox.midX - cell.center.x
                    let dy = obs.boundingBox.midY - cell.center.y
                    return (dx * dx + dy * dy).squareRoot() < cellTolerance
                }
            }
            anchors = cleaned.isEmpty ? deduped : cleaned
        } else {
            anchors = deduped
        }
        guard let geometry = GridGeometry.infer(from: anchors) else { return [] }

        var results: [DetectedCell] = []
        for cell in geometry.cells {
            guard let crop = axisAlignedCrop(ci: ci, cellRect: cell.rect) else { continue }
            results.append(DetectedCell(row: cell.row, column: cell.column, cellRect: cell.rect, crop: crop))
        }
        return results
    }

    private static func runRectangleRequest(ci: CIImage) -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.40
        request.maximumAspectRatio = 1.10
        request.minimumSize = 0.05
        request.minimumConfidence = 0.2
        request.maximumObservations = 150
        request.quadratureTolerance = 45
        let handler = VNImageRequestHandler(ciImage: ci, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return request.results ?? []
    }

    private static func dedupOverlapping(_ anchors: [VNRectangleObservation]) -> [VNRectangleObservation] {
        let sorted = anchors.sorted { $0.confidence > $1.confidence }
        var kept: [VNRectangleObservation] = []
        for a in sorted {
            let center = CGPoint(x: a.boundingBox.midX, y: a.boundingBox.midY)
            let isDup = kept.contains { other in
                abs(other.boundingBox.midX - center.x) < 0.05 &&
                abs(other.boundingBox.midY - center.y) < 0.05
            }
            if !isDup { kept.append(a) }
        }
        return kept
    }

    private static let ciContext = CIContext()

    private static func axisAlignedCrop(ci: CIImage, cellRect: CGRect) -> CGImage? {
        let extent = ci.extent
        let clamped = CGRect(
            x: max(cellRect.minX, 0),
            y: max(cellRect.minY, 0),
            width:  min(cellRect.width,  1 - max(cellRect.minX, 0)),
            height: min(cellRect.height, 1 - max(cellRect.minY, 0))
        )
        let pixelRect = CGRect(
            x: clamped.minX * extent.width  + extent.origin.x,
            y: clamped.minY * extent.height + extent.origin.y,
            width:  clamped.width  * extent.width,
            height: clamped.height * extent.height
        )
        let cropped = ci.cropped(to: pixelRect)
        return ciContext.createCGImage(cropped, from: pixelRect)
    }
}

// MARK: - GridGeometry (port of iOS struct)

struct GridGeometry {
    struct Cell {
        let row: Int
        let column: Int
        let center: CGPoint
        let rect: CGRect
    }
    let cells: [Cell]
    let medianWidth: CGFloat
    let medianHeight: CGFloat

    static func infer(from anchors: [VNRectangleObservation]) -> GridGeometry? {
        guard !anchors.isEmpty else { return nil }
        let widths = anchors.map { $0.boundingBox.width }.sorted()
        let heights = anchors.map { $0.boundingBox.height }.sorted()
        let medianWidth = widths[widths.count / 2]
        let medianHeight = heights[heights.count / 2]
        let xCenters = anchors.map { $0.boundingBox.midX }
        var columnLanes = clusterCenters(values: xCenters, tolerance: medianWidth * 0.5, maxLanes: 3)
        let yCenters = anchors.map { $0.boundingBox.midY }
        var rowLanes = clusterCenters(values: yCenters, tolerance: medianHeight * 0.5, maxLanes: 3)
        guard !columnLanes.isEmpty, !rowLanes.isEmpty else { return nil }
        let cardAspectRatio: CGFloat = 0.714
        let fillFactor: CGFloat = 0.92
        // Synthesize missing row/col lanes: when the detected lanes
        // have a regular spacing AND there's room above/below (or
        // left/right) for another lane within the image bounds, add
        // it. Recovers the dark top row in IMG_5232 where Vision
        // dropped half of the rectangles for low-contrast cards.
        // Synthesize ONLY when fewer than 3 lanes are detected and
        // the existing lanes have regular spacing AND there's room
        // for an additional lane that doesn't push past the image
        // bounds. Recovers IMG_5232's missing top dark row without
        // introducing phantom 4th lanes on already-complete 3x3 grids.
        if rowLanes.count == 2 {
            let sortedRows = rowLanes.sorted()
            let gap = sortedRows[1] - sortedRows[0]
            if gap > 0.05, gap < 0.6 {
                let top = sortedRows[1]
                let bottom = sortedRows[0]
                // Prefer adding above if possible — that's the
                // IMG_5232 dark-row case. Otherwise try below.
                if top + gap < 0.95 { rowLanes.append(top + gap) }
                else if bottom - gap > 0.05 { rowLanes.append(bottom - gap) }
            }
        }
        if columnLanes.count == 2 {
            let sortedCols = columnLanes.sorted()
            let gap = sortedCols[1] - sortedCols[0]
            if gap > 0.05, gap < 0.6 {
                let right = sortedCols[1]
                let left = sortedCols[0]
                if right + gap < 0.95 { columnLanes.append(right + gap) }
                else if left - gap > 0.05 { columnLanes.append(left - gap) }
            }
        }
        let rowLanesTopFirst = rowLanes.sorted(by: >)
        let colLanesLeftFirst = columnLanes.sorted()
        let colSpacing = meanSpacing(of: colLanesLeftFirst) ?? (medianWidth * 1.05)
        let rowSpacing = meanSpacing(of: rowLanesTopFirst) ?? (medianHeight * 1.05)
        var cardHeight = max(rowSpacing * fillFactor, medianHeight * 1.15)
        var cardWidth = max(colSpacing * fillFactor, medianWidth * 1.15)
        // Cap multiplier 0.92 (was 0.98) — leaves more margin
        // between adjacent cells so OCR doesn't pick up neighbor-
        // card text. The Wattage cell's botL had "HOOPIE" (the
        // card below) and topR had "90" (a neighbor's power)
        // because cells were sized too generously.
        cardHeight = min(cardHeight, rowSpacing * 0.92)
        cardWidth = min(cardWidth, colSpacing * 0.92)
        let measuredAspect = cardWidth / cardHeight
        if measuredAspect < 0.50 || measuredAspect > 1.00 {
            cardWidth = cardHeight * cardAspectRatio
        }
        if colLanesLeftFirst.count == 1 { cardWidth = max(cardWidth, medianWidth * 1.10) }
        if rowLanesTopFirst.count == 1 { cardHeight = max(cardHeight, medianHeight * 1.10) }
        var cells: [Cell] = []
        for (rowIdx, y) in rowLanesTopFirst.enumerated() {
            for (colIdx, x) in colLanesLeftFirst.enumerated() {
                let rect = CGRect(x: x - cardWidth/2, y: y - cardHeight/2, width: cardWidth, height: cardHeight)
                cells.append(Cell(row: rowIdx, column: colIdx, center: CGPoint(x: x, y: y), rect: rect))
            }
        }
        return GridGeometry(cells: cells, medianWidth: cardWidth, medianHeight: cardHeight)
    }

    private static func meanSpacing(of lanes: [CGFloat]) -> CGFloat? {
        guard lanes.count >= 2 else { return nil }
        let sorted = lanes.sorted()
        var gaps: [CGFloat] = []
        for i in 1..<sorted.count { gaps.append(sorted[i] - sorted[i-1]) }
        return gaps.reduce(0, +) / CGFloat(gaps.count)
    }

    private static func clusterCenters(values: [CGFloat], tolerance: CGFloat, maxLanes: Int) -> [CGFloat] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        var clusters: [[CGFloat]] = []
        for v in sorted {
            if let last = clusters.last, let lastEnd = last.last, (v - lastEnd) < tolerance {
                clusters[clusters.count - 1].append(v)
            } else {
                clusters.append([v])
            }
        }
        let keepers: [[CGFloat]]
        if clusters.count > maxLanes {
            keepers = clusters.sorted { $0.count > $1.count }.prefix(maxLanes).map { $0 }
        } else {
            keepers = clusters
        }
        return keepers.map { $0.reduce(0, +) / CGFloat($0.count) }
    }
}

// MARK: - OCR (simplified port of CardScanner runMultiPassGridOCR)

struct OCRResult {
    let cardNumber: String
    let topLeftText: String
    let topRightText: String
    let bottomLeftText: String
    let bottomRightText: String
    let fullText: String
}

func ocrCell(cgImage: CGImage, cardNumberSet: Set<String>, customWords: [String]) -> OCRResult {
    // Mirror iOS: downsample cells to 1200px max long-side before
    // OCR. Vision text recognition cost scales with pixel count;
    // for ~1000x1400 cell crops from 3024x4032 sources this halves
    // per-pass time while keeping card text comfortably readable.
    let raw = CIImage(cgImage: cgImage)
    let ci: CIImage = {
        let extent = raw.extent
        let longSide = max(extent.width, extent.height)
        let target: CGFloat = 1200
        guard longSide > target else { return raw }
        let scale = target / longSide
        return raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }()

    var allText: [String] = []
    var topLeft: [String] = [], topRight: [String] = [], bottomLeft: [String] = [], bottomRight: [String] = []

    // Multi-pass: 4 enhancement variants
    let passes: [(c: Float, g: Float, s: Float)] = [
        (1.25, 0.65, 0.5),
        (1.6, 0.55, 1.0),
        (2.0, 0.75, 1.5),
        (1.4, 0.85, 0.8),
    ]
    var votes: [String: Int] = [:]
    // Tier 2 short-circuit: stop running passes as soon as 2 agree
    // on the same cardNumber. Mirrors iOS optimization that cuts
    // average pass count by ~40% on clean cells.
    var earlyDone = false
    for params in passes {
        if earlyDone { break }
        let enhanced = ci
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": params.g])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0),
                "inputContrast": params.c,
            ])
            .applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": Float(2.5),
                "inputIntensity": params.s,
            ])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.015
        if !customWords.isEmpty { request.customWords = customWords }
        let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { continue }
        for obs in observations {
            guard let cand = obs.topCandidates(1).first, cand.confidence > 0.3 else { continue }
            let text = cand.string.uppercased()
            allText.append(text)
            switch (obs.boundingBox.midX < 0.5, obs.boundingBox.midY > 0.5) {
            case (true, true): topLeft.append(text)
            case (false, true): topRight.append(text)
            case (true, false): bottomLeft.append(text)
            case (false, false): bottomRight.append(text)
            }
        }
        // Multi-quadrant cn extraction. cardNumber badges live in
        // bottom-left on most cards but we've seen them surface in
        // other quadrants when the cell crop misaligns or when
        // unusual treatments place the badge elsewhere.
        //
        // catalogFallback=true is the LOOSE bare-digit-pure-number
        // lookup — when on, any bare digit run that matches a
        // catalog cardNumber gets returned as the cn. That's safe
        // for the bottom quadrants (where the badge lives) but
        // dangerous for top-left (which holds hero name + nearby
        // text). The IMG_5275 r2c0 Caliber regression was a
        // "CALIBER 18 CALIBER" topL extracting "18" as cn — pure
        // text artifact that then triggered cn_fuzzy_d2 (+0.30) for
        // the wrong Caliber treatment. Top-left now uses
        // catalogFallback=false: regex matches still try, but bare
        // digits don't.
        let cnSources: [(text: String, fallback: Bool)] = [
            (bottomLeft.joined(separator: " "),  true),
            (bottomRight.joined(separator: " "), true),
            (topLeft.joined(separator: " "),     false),
        ]
        var foundCn: String? = nil
        for src in cnSources {
            if let cn = extractCardNumber(from: src.text, catalogFallback: src.fallback, set: cardNumberSet) {
                foundCn = cn; break
            }
        }
        // Bare-digit topLeft fallback when the digit REPEATS. Cards
        // sometimes mis-frame so the badge text bleeds into the
        // top-left of the cell crop instead of the bottom-left
        // (Ozzmosis-172 case: topL = "172 172", botL empty). A
        // single bare digit there is noise (Caliber regression), but
        // the same digit appearing 2+ times in the topL strongly
        // implies the badge actually rendered there.
        if foundCn == nil {
            foundCn = extractRepeatedBareDigitCN(in: topLeft.joined(separator: " "),
                                                 set: cardNumberSet,
                                                 minRepeats: 2)
        }
        if foundCn == nil {
            // Last resort: full text with catalogFallback=false (no
            // pure-number lookup, but regex matches are still tried).
            foundCn = extractCardNumber(from: allText.joined(separator: " "), catalogFallback: false, set: cardNumberSet)
        }
        if let cn = foundCn {
            votes[cn, default: 0] += 1
            if votes[cn]! >= 2 { earlyDone = true }
        }
    }

    let stable = votes.filter { $0.value >= 2 }.max(by: { $0.value < $1.value })?.key
    let single = votes.max(by: { $0.value < $1.value })?.key
    var cn = stable ?? single ?? ""

    // Focused fallback: if no cardNumber yet, run 2 crops × 2
    // variants on the bottom-left badge area at 4× upscale. Mirrors
    // iOS's runFocusedBottomLeftPass after its reduction from
    // 9 attempts to 4 (1.991).
    if cn.isEmpty {
        let extent = ci.extent
        let cropFractions: [(xMax: CGFloat, yFrac: CGFloat)] = [
            (0.28, 0.20),
            (0.50, 0.25),
        ]
        let variants: [(c: Float, g: Float, s: Float)] = [
            (3.0, 1.50, 2.5),
            (3.0, 0.50, 2.5),
        ]
        outer: for crop in cropFractions {
            let cropRect = CGRect(
                x: extent.minX, y: extent.minY,
                width: extent.width * crop.xMax,
                height: extent.height * crop.yFrac
            )
            let cropped = ci.cropped(to: cropRect)
                .applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: Float(4.0),
                    kCIInputAspectRatioKey: Float(1.0),
                ])
            for v in variants {
                let enhanced = cropped
                    .applyingFilter("CIGammaAdjust", parameters: ["inputPower": v.g])
                    .applyingFilter("CIColorControls", parameters: [
                        "inputSaturation": Float(0.0),
                        "inputContrast": v.c,
                    ])
                    .applyingFilter("CIUnsharpMask", parameters: [
                        "inputRadius": Float(2.5),
                        "inputIntensity": v.s,
                    ])
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                request.minimumTextHeight = 0.004
                if !customWords.isEmpty { request.customWords = customWords }
                let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
                guard (try? handler.perform([request])) != nil,
                      let observations = request.results else { continue }
                let cellTexts = observations.compactMap {
                    $0.topCandidates(1).first.flatMap { $0.confidence > 0.3 ? $0.string.uppercased() : nil }
                }
                let joined = cellTexts.joined(separator: " ")
                if let extracted = extractCardNumber(from: joined, catalogFallback: true, set: cardNumberSet) {
                    cn = extracted
                    break outer
                }
            }
        }
    }

    // POWER-AREA FOCUSED PASS. The power value sits in the top-right
    // of every Hero / Hot Dog / Play card and is usually a 1-3 digit
    // number. Default Vision OCR sometimes misses it because the
    // glyph height is small relative to the cell, even though the
    // value is unmistakable visually. A 4× upscale on the top-right
    // corner specifically extracts digits that the main passes
    // missed. The captured power lets the resolver fire `power_match`
    // (+0.3) AND lets the candidate-seeding logic narrow further:
    // for r2c0 in IMG_5231 (Skuba 188, BRAWL element, power 115),
    // adding "115" to the OCR text routes the seeded BRAWL Base
    // Set Griffey candidates through power_match — Skuba 188 is
    // the only Griffey BRAWL Base Set card with power 115.
    let powerDigitsAlready = (topRight + topLeft + bottomLeft + bottomRight)
        .joined(separator: " ")
        .components(separatedBy: CharacterSet.decimalDigits.inverted)
        .compactMap { Int($0) }
        .filter { $0 >= 50 && $0 <= 200 }   // typical card power range
    if powerDigitsAlready.isEmpty {
        let extent = ci.extent
        // Top-right region: x from 0.65 to 1.0 (right 35%), y from
        // 0.78 to 1.0 (top 22%) — CIImage Y goes up so the "top" is
        // the high-Y region.
        let cropRect = CGRect(
            x: extent.minX + extent.width * 0.65,
            y: extent.minY + extent.height * 0.78,
            width:  extent.width  * 0.35,
            height: extent.height * 0.22
        )
        let cropped = ci.cropped(to: cropRect)
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: Float(4.0),
                kCIInputAspectRatioKey: Float(1.0),
            ])
        let powerVariants: [(c: Float, g: Float, s: Float)] = [
            (3.0, 0.55, 2.5),
            (3.0, 1.30, 2.5),
        ]
        for v in powerVariants {
            let enhanced = cropped
                .applyingFilter("CIGammaAdjust", parameters: ["inputPower": v.g])
                .applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": Float(0.0),
                    "inputContrast": v.c,
                ])
                .applyingFilter("CIUnsharpMask", parameters: [
                    "inputRadius": Float(2.5),
                    "inputIntensity": v.s,
                ])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.004
            let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observations = request.results else { continue }
            for obs in observations {
                guard let cand = obs.topCandidates(1).first,
                      cand.confidence > 0.3 else { continue }
                let text = cand.string.uppercased()
                topRight.append(text)
                allText.append(text)
            }
            // If we now have a plausible power digit, stop.
            let allTopR = topRight.joined(separator: " ")
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .filter { $0 >= 50 && $0 <= 200 }
            if !allTopR.isEmpty { break }
        }
    }

    return OCRResult(
        cardNumber: cn,
        topLeftText: topLeft.joined(separator: " "),
        topRightText: topRight.joined(separator: " "),
        bottomLeftText: bottomLeft.joined(separator: " "),
        bottomRightText: bottomRight.joined(separator: " "),
        fullText: allText.joined(separator: " ")
    )
}

let cyrillicSubs: [Character: Character] = [
    "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H",
    "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X", "У": "Y",
    "І": "I", "Ј": "J", "Ѕ": "S",
]
let digitSubs: [Character: Character] = ["I": "1", "L": "1", "|": "1", "O": "0", "S": "5", "B": "8"]

func normalizeCyrillic(_ s: String) -> String {
    guard s.contains(where: { cyrillicSubs.keys.contains($0) }) else { return s }
    return String(s.map { cyrillicSubs[$0] ?? $0 })
}

func substituteToDigits(_ s: String) -> (String, Bool) {
    var changed = false
    var out = ""
    for ch in s {
        if let sub = digitSubs[ch] { out.append(sub); changed = true } else { out.append(ch) }
    }
    return (out, changed)
}

let strictRegex = try! NSRegularExpression(pattern: #"#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#)

func extractCardNumber(from rawText: String, catalogFallback: Bool, set cardNumberSet: Set<String>) -> String? {
    let text = normalizeCyrillic(rawText)
    let range = NSRange(text.startIndex..., in: text)
    func acceptable(_ s: String) -> Bool { cardNumberSet.contains(s) }
    if let match = strictRegex.firstMatch(in: text, range: range),
       let r = Range(match.range(at: 1), in: text) {
        let candidate = String(text[r])
        if acceptable(candidate) { return candidate }
    }
    let words = text.components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
        .filter { !$0.isEmpty }
    // Adjacent-word reconstruction
    if words.count >= 2 {
        for i in 0..<(words.count - 1) {
            let p = words[i], n = words[i + 1]
            guard p.count >= 1, p.count <= 6, p.allSatisfy({ $0.isLetter }) else { continue }
            let (subDigits, changed) = substituteToDigits(n)
            let candidates = changed ? [n, subDigits] : [n]
            for cand in candidates {
                guard cand.count >= 1, cand.count <= 4, cand.allSatisfy({ $0.isNumber }) else { continue }
                let combined = "\(p)-\(cand)"
                if acceptable(combined) { return combined }
            }
        }
    }
    // Single-token repair: tokens like "BF-BS" where the dash kept the
    // alpha tail glued on. Split on the first dash and substitute the
    // tail to digits before validating against the catalog.
    for word in words {
        guard let dashIdx = word.firstIndex(of: "-") else { continue }
        let head = String(word[..<dashIdx])
        let tail = String(word[word.index(after: dashIdx)...])
        guard head.count >= 1, head.count <= 6, head.allSatisfy({ $0.isLetter }) else { continue }
        guard tail.count >= 1, tail.count <= 4 else { continue }
        let (subDigits, changed) = substituteToDigits(tail)
        guard changed, subDigits.allSatisfy({ $0.isNumber }) else { continue }
        let combined = "\(head)-\(subDigits)"
        if acceptable(combined) { return combined }
    }
    // Pure-number fallback
    guard catalogFallback else { return nil }
    let alphaNeighbors = words.filter { w in w.count >= 1 && w.count <= 6 && w.allSatisfy({ $0.isLetter }) }
    for word in words {
        guard word.count >= 1, word.count <= 4,
              word.allSatisfy({ $0.isNumber }),
              cardNumberSet.contains(word) else { continue }
        let isFragmented = alphaNeighbors.contains { p in cardNumberSet.contains("\(p)-\(word)") }
        if !isFragmented { return word }
    }
    return nil
}

/// Bare-digit cardNumber extraction that requires the digit run to
/// appear at least `minRepeats` times in the text. Used for the
/// top-left quadrant where the regular catalogFallback path is too
/// loose (a single "18" near "CALIBER" was returning "18" as cn,
/// triggering wrong-treatment scoring). When the SAME digit appears
/// 2+ times — like "172 172" from a badge that bled into the topL
/// crop — that's strong evidence the badge actually rendered there.
func extractRepeatedBareDigitCN(in text: String, set cardNumberSet: Set<String>, minRepeats: Int) -> String? {
    let words = text.uppercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters) }
    var counts: [String: Int] = [:]
    for w in words {
        guard w.count >= 1, w.count <= 4, w.allSatisfy({ $0.isNumber }) else { continue }
        counts[w, default: 0] += 1
    }
    let qualified = counts.filter { $0.value >= minRepeats && cardNumberSet.contains($0.key) }
    return qualified.max(by: { $0.value < $1.value })?.key
}

// MARK: - Color signal (port of extractCellColorBucket)

struct ColorBucket: Equatable, Hashable {
    let name: String
    static let red = ColorBucket(name: "red")
    static let orange = ColorBucket(name: "orange")
    static let yellow = ColorBucket(name: "yellow")
    static let green = ColorBucket(name: "green")
    static let blue = ColorBucket(name: "blue")
    static let purple = ColorBucket(name: "purple")
    static let pink = ColorBucket(name: "pink")
    static let white = ColorBucket(name: "white")
    static let holographic = ColorBucket(name: "holographic")
}

func rgbToHsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
    let maxV = max(r, max(g, b))
    let minV = min(r, min(g, b))
    let delta = maxV - minV
    let v = maxV
    let s = maxV == 0 ? 0 : (delta / maxV) * 100
    var h: Double
    if delta == 0 { h = 0 }
    else if maxV == r { h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
    else if maxV == g { h = 60 * ((b - r) / delta + 2) }
    else { h = 60 * ((r - g) / delta + 4) }
    if h < 0 { h += 360 }
    return (h, s, v)
}

func hueToColorBucket(h: Double) -> ColorBucket? {
    switch h {
    case 0..<10, 355..<360: return .red
    case 10..<40: return .orange
    case 40..<70: return .yellow
    case 70..<160: return .green
    case 160..<260: return .blue
    case 260..<305: return .purple
    case 305..<355: return .pink
    default: return nil
    }
}

/// Border signature metrics. Sampled from the same border strips
/// extractCellColorBucket uses, but exposed for treatment-class
/// classification beyond the dominant-hue logic.
///
/// `localVariance`: average abs(luminance - prev neighbor) along the
/// scan direction. HIGH → textured/speckled border (Icon Battlefoil,
/// Mixtape, Logofoil, Grandma's Linoleum). LOW → solid/smooth border
/// (Base Set, Battlefoil, Alpha Battlefoil with uniform hue).
///
/// `desatRatio`: brightDesatCount / (brightDesatCount + coloredCount).
/// HIGH (>0.4) + HIGH localVariance → silver-speckle signature
/// (Icon Battlefoil, Logofoil, Power Glove).
///
/// `hueBuckets`: number of distinct color buckets present (≥1% share).
/// HIGH (≥4) → multi-hue holographic (Alpha, Mixtape, GGL, GLBF).
/// LOW (≤2) → single-color treatment.
struct BorderSignature {
    let localVariance: Float
    let desatRatio: Float
    let hueBuckets: Int
    let coloredCount: Int
    let brightDesatCount: Int
    let dominantHueShare: Float

    /// Threshold above which the border is dense-speckle textured
    /// (Icon Battlefoil / Power Glove signature). Empirically
    /// calibrated on the 7-image baseline: Icon Battlefoils with
    /// visible speckle pattern register 25-35; non-speckle treatments
    /// stay below 15. 18 is a safe separator.
    var localVarianceAboveSpeckleThreshold: Bool { localVariance >= 18.0 }
}

func extractBorderSignature(cgImage: CGImage) -> BorderSignature? {
    let width = cgImage.width
    let height = cgImage.height
    guard width >= 40, height >= 40 else { return nil }
    let bytesPerRow = width * 4
    var data = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: &data, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var bucketCounts: [String: Int] = [:]
    var coloredCount = 0
    var brightDesatCount = 0
    var totalSampled = 0
    var varianceSum: Float = 0
    var varianceCount = 0

    let topStrip = Int(Double(height) * 0.04)..<Int(Double(height) * 0.16)
    let bottomStrip = Int(Double(height) * 0.84)..<Int(Double(height) * 0.96)
    let leftStrip = Int(Double(width) * 0.04)..<Int(Double(width) * 0.13)
    let rightStrip = Int(Double(width) * 0.87)..<Int(Double(width) * 0.96)
    let xCornerInset = max(1, Int(Double(width) * 0.18))
    let yCornerInset = max(1, Int(Double(height) * 0.18))

    @inline(__always) func sampleAndScan(xs: [Int], ys: [Int]) {
        // For each row in ys, scan across xs and compute neighbor diff.
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
                totalSampled += 1
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
    sampleAndScan(xs: xRange, ys: Array(topStrip).filter { $0 % 3 == 0 })
    sampleAndScan(xs: xRange, ys: Array(bottomStrip).filter { $0 % 3 == 0 })
    sampleAndScan(xs: Array(leftStrip).filter { $0 % 3 == 0 }, ys: yRange)
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

func extractCellColorBucket(cgImage: CGImage) -> ColorBucket? {
    let width = cgImage.width
    let height = cgImage.height
    guard width >= 20, height >= 20 else { return nil }
    let bytesPerRow = width * 4
    var data = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: &data, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

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

    let topStrip = Int(Double(height) * 0.04)..<Int(Double(height) * 0.16)
    let bottomStrip = Int(Double(height) * 0.84)..<Int(Double(height) * 0.96)
    let leftStrip = Int(Double(width) * 0.04)..<Int(Double(width) * 0.13)
    let rightStrip = Int(Double(width) * 0.87)..<Int(Double(width) * 0.96)
    let xCornerInset = max(1, Int(Double(width) * 0.18))
    let yCornerInset = max(1, Int(Double(height) * 0.18))

    for y in topStrip { var x = xCornerInset; while x < width - xCornerInset { sample(x: x, y: y); x += 3 } }
    for y in bottomStrip { var x = xCornerInset; while x < width - xCornerInset { sample(x: x, y: y); x += 3 } }
    for x in leftStrip { var y = yCornerInset; while y < height - yCornerInset { sample(x: x, y: y); y += 3 } }
    for x in rightStrip { var y = yCornerInset; while y < height - yCornerInset { sample(x: x, y: y); y += 3 } }

    if coloredCount >= 60, bucketCounts.count >= 4 {
        let topShare = Double(bucketCounts.values.max() ?? 0) / Double(coloredCount)
        if topShare < 0.35 { return .holographic }
    }

    guard coloredCount >= 40 else {
        return brightDesatCount > 200 ? .white : nil
    }
    let sorted = bucketCounts.sorted { $0.value > $1.value }
    guard let top = sorted.first else { return nil }
    let topShare = Double(top.value) / Double(coloredCount)
    guard topShare >= 0.25 else { return nil }
    switch top.key {
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    default: return nil
    }
}

func expectedColorBucket(for treatment: String) -> ColorBucket? {
    switch treatment.uppercased() {
    case "FIRE TRACKS BATTLEFOIL": return .orange
    case "BLIZZARD BATTLEFOIL": return .blue
    case "GREEN BATTLEFOIL": return .green
    case "RED BATTLEFOIL": return .red
    case "BLUE BATTLEFOIL": return .blue
    case "ORANGE BATTLEFOIL": return .orange
    case "PINK BATTLEFOIL": return .pink
    case "BUBBLE GUM BATTLEFOIL": return .pink
    case "BUBBLE GUM BLAST": return .pink
    case "PINK BLAST": return .pink
    case "BLUE BLAST": return .blue
    case "GREEN BLAST": return .green
    case "ORANGE BLAST": return .orange
    case "SLIME BATTLEFOIL": return .green
    case "MIAMI ICE BATTLEFOIL": return .blue
    case "GRILLIN' BATTLEFOIL": return .orange
    case "CHILLIN' BATTLEFOIL": return .blue
    case "BLUE HEADLINES BATTLEFOIL": return .blue
    case "RED HEADLINES BATTLEFOIL": return .red
    case "ORANGE HEADLINES BATTLEFOIL": return .orange
    case "GRAPE": return .purple
    case "SOUR APPLE": return .green
    case "BLUE RASPBERRY": return .blue
    case "INSPIRED INK BUBBLE GUM BATTLEFOIL": return .pink
    case "GRANDMA'S LINOLEUM BATTLEFOIL": return .holographic
    case "GREAT GRANDMA'S LINOLEUM BATTLEFOIL": return .holographic
    case "LOGOFOIL": return .holographic
    case "MIXTAPE BATTLEFOIL": return .holographic
    case "80'S RAD BATTLEFOIL": return .holographic
    case "ICON BATTLEFOIL": return .holographic
    case "POWER GLOVE BATTLEFOIL": return .holographic
    case "BATTLEFOIL": return .white
    case "ALPHA BATTLEFOIL": return .white
    case "SILVER BATTLEFOIL": return .white
    case "SILVER BLAST": return .white
    case "HEADLINES BATTLEFOIL": return .white
    case "BASE SET": return .white
    case "PAPER": return .white
    case "PAPER SERIALIZED": return .white
    case "SUPERFOIL": return .white
    case "INSPIRED INK SUPERFOIL": return .white
    case "INSPIRED INK METALLIC BATTLEFOIL": return .white
    default: return nil
    }
}

// MARK: - ScanMatching scoring (port)

func heroIdentity(_ card: Card) -> String {
    let h = card.hero.uppercased().trimmingCharacters(in: .whitespaces)
    return h.isEmpty ? card.name.uppercased().trimmingCharacters(in: .whitespaces) : h
}

let stopWords: Set<String> = [
    "FIRST", "EDITION", "EDITON", "EDTON", "EDITVON", "EDITIDN",
    "BATTLE", "ARENA", "BATTTE", "TARENA", "POWER", "ROOKIE",
    "INSPIRED", "INSPIREO", "BATTLEFOIL", "BATTL", "BATTI",
    // Common OCR misreads of BATTLE / ARENA that otherwise leak into
    // hero matching via heroWordMatches' 1-char-diff tolerance and
    // falsely trigger heroes like "BATTLE BACK" / "DUMPSTER BATTLE".
    "BAITLE", "BAITTI", "BAITTLE", "BATILE", "BATIL", "BATT",
    "AREMA", "ABENA", "AREWA", "ARENG", "AREN", "ABENA", "AREWG",
    "GLOW", "HEX", "FIRE", "ICE", "BRAWL", "STEEL", "SUPER",
    "GUM", "FRE", "JACKSON", "JAEKSON", "JACISON", "IRIKSON",
    "IAIKSUN", "IKSUN", "BO", "COST", "PLAY", "REVEAL",
    "DISCARD", "REBATE", "SHUFFLE", "HAND", "DECK", "PLAYBOOK",
    "HERO", "HEROS",
]

func heroWordMatches(_ hero: String, _ word: String) -> Bool {
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

func heroNameScore(_ name: String, in text: String) -> Int {
    let upper = name.uppercased()
    if text.contains(upper) { return 3 }
    let nameWords = upper.components(separatedBy: .whitespaces).filter { $0.count >= 3 }
    guard !nameWords.isEmpty else { return 0 }
    let textWords = text.components(separatedBy: .whitespaces)
    var matches = 0
    for nw in nameWords {
        for tw in textWords where tw.count >= 3 {
            if nw.count >= 5 {
                let (shorter, longer) = nw.count <= tw.count ? (nw, tw) : (tw, nw)
                if shorter.count >= 5, longer.hasPrefix(shorter) { matches += 1; break }
            } else if nw == tw {
                matches += 1; break
            }
        }
    }
    return matches
}

func heroIdentitiesInTopLeft(allCards: [Card], topLeftText: String) -> Set<String> {
    guard !topLeftText.isEmpty else { return [] }
    let words = topLeftText.components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
        .filter { $0.count >= 4 && !stopWords.contains($0) }
    guard !words.isEmpty else { return [] }
    var seen: Set<String> = []
    var matched: Set<String> = []
    for card in allCards {
        let hero = card.hero.uppercased()
        guard hero.count >= 4 else { continue }
        let ident = heroIdentity(card)
        if seen.contains(ident) { continue }
        seen.insert(ident)
        for w in words where heroWordMatches(hero, w) { matched.insert(ident); break }
    }
    return matched
}

func extractCardNumberPrefixes(from text: String) -> Set<String> {
    let upper = text.uppercased()
    guard !upper.isEmpty else { return [] }
    let pattern = #"\b([A-Z]{2,5})[A-Z0-9]?[\s-]+\d{1,4}\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var prefixes: Set<String> = []
    let range = NSRange(upper.startIndex..., in: upper)
    regex.enumerateMatches(in: upper, range: range) { match, _, _ in
        guard let match = match, let r = Range(match.range(at: 1), in: upper) else { return }
        prefixes.insert(String(upper[r]))
    }
    return prefixes
}

func extractCardNumberFullPatterns(from text: String) -> Set<String> {
    let upper = text.uppercased()
    guard !upper.isEmpty else { return [] }
    let pattern = #"\b([A-Z][A-Z0-9]{0,4})[\s-]+(\d{1,4})\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var patterns: Set<String> = []
    let range = NSRange(upper.startIndex..., in: upper)
    regex.enumerateMatches(in: upper, range: range) { match, _, _ in
        guard let match = match,
              let pr = Range(match.range(at: 1), in: upper),
              let dr = Range(match.range(at: 2), in: upper) else { return }
        patterns.insert("\(upper[pr])-\(upper[dr])")
    }
    return patterns
}

func levenshtein(_ a: String, _ b: String) -> Int {
    let aChars = Array(a), bChars = Array(b)
    if aChars.isEmpty { return bChars.count }
    if bChars.isEmpty { return aChars.count }
    var prev = Array(0...bChars.count)
    var curr = Array(repeating: 0, count: bChars.count + 1)
    for i in 1...aChars.count {
        curr[0] = i
        for j in 1...bChars.count {
            let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[bChars.count]
}

func extractIntegers(from text: String) -> Set<Int> {
    var result = Set<Int>()
    var current = ""
    for ch in text {
        if ch.isNumber { current.append(ch) }
        else { if let n = Int(current) { result.insert(n) }; current = "" }
    }
    if let n = Int(current) { result.insert(n) }
    return result
}

struct Scored {
    let card: Card
    let total: Float
    let signals: [(name: String, weight: Float)]
}

func countOccurrences(of needle: String, in haystack: String) -> Int {
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
/// (insert I), "ICE" → "HCE" (substitute H for I), "STEEL" → "STEEI"
/// (substitute I for L), etc. Uses element length as a guard
/// against pure-word coincidences (any 3-char fragment can be
/// d=1 from "ICE" by accident).
func elementFuzzyContains(_ haystack: String, element: String) -> Bool {
    guard element.count >= 3 else { return false }
    // Tokenize haystack into letter-only words of plausible length.
    let tokens = haystack.components(separatedBy: CharacterSet.alphanumerics.inverted)
        .map { $0.uppercased() }
        .filter { $0.count >= max(2, element.count - 1) && $0.count <= element.count + 2 }
    for tok in tokens {
        if levenshtein(tok, element) <= 1 { return true }
    }
    return false
}

func countFuzzyElementOccurrences(in haystack: String, element: String) -> Int {
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

func scoreCandidate(
    _ card: Card,
    obs: OCRResult,
    fpRankIndex: [String: Int],
    fpDistance: [String: Float],
    strongHeroIdentities: Set<String>,
    topLeftHeroIdentities: Set<String>,
    ocrTreatmentPrefixes: Set<String>,
    ocrFullPatterns: Set<String>,
    cellColorBucket: ColorBucket?,
    heroSuffixHits: Set<String>,
    borderSig: BorderSignature?
) -> Scored {
    var signals: [(String, Float)] = []
    var total: Float = 0

    if let r = fpRankIndex[card.bobaId] {
        let w = max(0, 1.0 - Float(r) * 0.08)
        if w > 0 { total += w; signals.append(("fp_rank_\(r)", w)) }
    }
    // Tiny continuous FP-distance bonus to break ties between two
    // candidates that otherwise score identically (e.g., Ozzmosis-172
    // vs Laviathan-172 — same cn, same element, same hero_implied).
    // Capped tiny so it doesn't disturb real signals.
    if let d = fpDistance[card.bobaId] {
        let bonus = max(0, min(0.05, (1.0 - d) * 0.1))
        if bonus > 0 { total += bonus; signals.append(("fp_proximity", bonus)) }
    }

    let cardCN = card.cardNumber.uppercased()
    let cn = obs.cardNumber.uppercased()
    let cardCNIsBare = !cardCN.contains("-")
    var cnFired = false
    if !cn.isEmpty, cardCN == cn {
        let isBare = cn.allSatisfy { $0.isNumber }
        // Bare cardNumbers (Base Set "172") are noisy — OCR often
        // confuses single tokens like "BO" → "80". But when the
        // extracted cn appears MULTIPLE times in the OCR text
        // (Ozzmosis "172 172 2026 172"), it's a high-confidence
        // signal worth treating as cn_exact (1.5). A single
        // occurrence stays at 0.6.
        var w: Float = isBare ? 0.6 : 1.5
        if isBare {
            let occurrences = countOccurrences(of: cn, in: obs.fullText)
            if occurrences >= 2 { w = 1.5 }
        }
        total += w
        signals.append((isBare ? "cn_exact_bare" : "cn_exact", w))
        cnFired = true
    }
    if !cnFired {
        var bestDist = 3
        for pattern in ocrFullPatterns {
            let d = levenshtein(cardCN, pattern)
            if d < bestDist { bestDist = d }
        }
        if !cn.isEmpty {
            let d = levenshtein(cardCN, cn)
            if d < bestDist { bestDist = d }
        }
        if bestDist <= 1 { total += 1.2; signals.append(("cn_fuzzy_d\(bestDist)", 1.2)); cnFired = true }
        else if bestDist == 2 {
            // For bare-digit cardCNs (Base Set), d=2 means we match
            // only 1 of ~3 digits — way too loose. Drop the weight
            // to keep these from competing with cn_exact matches.
            let w: Float = cardCNIsBare ? 0.3 : 1.0
            total += w; signals.append(("cn_fuzzy_d2", w)); cnFired = true
        }
    }
    if !cnFired, !cn.isEmpty {
        let digits = cn.reversed().prefix(while: { $0.isNumber })
        let suffix = String(digits.reversed())
        if !suffix.isEmpty {
            // For prefixed cardCNs (e.g., "BF-188") match "-188".
            // For bare-digit cardCNs (e.g., "188") match "188" itself
            // when the OCR cn is shorter (truncated read of "188" → "8").
            let prefixedSuffix = cardCN.hasSuffix("-" + suffix)
            let bareSuffix = cardCNIsBare && cardCN != suffix && cardCN.hasSuffix(suffix) && cardCN.count > suffix.count
            if prefixedSuffix || bareSuffix {
                total += 0.4
                signals.append(("cn_suffix", 0.4))
                cnFired = true
            }
        }
    }

    let heroAtTop = heroNameScore(card.hero, in: obs.topLeftText)
    let heroAnywhere = heroNameScore(card.hero, in: obs.fullText)
    if heroAtTop > 0 { total += 1.5; signals.append(("hero_topleft", 1.5)) }
    else if heroAnywhere > 0 { total += 0.6; signals.append(("hero_anywhere", 0.6)) }
    else if strongHeroIdentities.contains(heroIdentity(card)) {
        total += 1.0; signals.append(("hero_inferred", 1.0))
    }
    else if cnFired, signals.contains(where: { $0.0 == "cn_exact" || $0.0 == "cn_exact_bare" }) {
        // cn matched exactly but the FP/topLeft hero list pointed
        // somewhere else. Only grant the implied bonus when the
        // topLeft hero set is silent — if topLeft clearly named a
        // hero (Hoopie, Discard Rebate), trust that over a noisy
        // bare-digit cn read of a different hero.
        let topLeftSilent = topLeftHeroIdentities.isEmpty
        let topLeftAgrees = topLeftHeroIdentities.contains(heroIdentity(card))
        if topLeftSilent || topLeftAgrees {
            total += 1.0; signals.append(("hero_implied_by_cn", 1.0))
        }
    }

    // Hero veto suppresses cards whose hero doesn't match the
    // FP-majority / topLeft-detected hero list. But when OCR reads
    // the cardNumber EXACTLY for this card (Ozzmosis-172 case where
    // FP-majority is Big-Z but OCR clearly reads "172"), cn_exact is
    // the stronger signal and should override the veto.
    var cnExactFired = false
    for s in signals {
        if s.0 == "cn_exact" || s.0 == "cn_exact_bare" { cnExactFired = true; break }
    }
    let heroMatched = strongHeroIdentities.contains(heroIdentity(card))
    let shouldVeto = !strongHeroIdentities.isEmpty && !heroMatched && !cnExactFired
    if shouldVeto {
        total -= 2.0; signals.append(("hero_veto", -2.0))
    }

    if !cnFired, !ocrTreatmentPrefixes.isEmpty {
        let dashIdx = cardCN.firstIndex(of: "-")
        let cardPrefix = dashIdx.map { String(cardCN[..<$0]) } ?? ""
        if !cardPrefix.isEmpty, cardPrefix.allSatisfy({ $0.isLetter }) {
            let matches = ocrTreatmentPrefixes.contains { ocr in
                cardPrefix.contains(ocr) || ocr.contains(cardPrefix)
            }
            if matches { total += 0.5; signals.append(("treatment_prefix", 0.5)) }
        }
    }

    // Element word match — exact OR fuzzy. Vision occasionally
    // misreads element badge text on stylized treatments: "BRAWL"
    // → "BRAWIL", "ICE" → "HCE", "STEEL" → "STEEI", etc. A 1-char
    // edit-distance match against the catalog element vocabulary
    // recovers these without false-firing on unrelated text.
    var elementWordFired = false
    if let element = card.element, !element.isEmpty {
        let upperElem = element.uppercased()
        let upperFull = obs.fullText.uppercased()
        if upperFull.contains(upperElem) {
            total += 0.2; signals.append(("element_word", 0.2))
            elementWordFired = true
        } else if elementFuzzyContains(upperFull, element: upperElem) {
            total += 0.15; signals.append(("element_word_fuzzy", 0.15))
            elementWordFired = true
        }
    }
    // Combined bonus: when OCR captured the card's element 2+ times
    // (strong element signal) AND the cardCN ends with the OCR cn
    // (Skuba-188 case where OCR truncated "188" → "8"), lift the
    // candidate enough to crack the picker top-8 alongside the
    // cn_exact bare matches. Bare-cardCN suffix specifically — for
    // prefixed cardCNs the cn_exact / cn_fuzzy chain already covers
    // the right cases.
    if elementWordFired,
       cardCNIsBare,
       !cn.isEmpty,
       cardCN != cn,
       cardCN.hasSuffix(cn),
       let element = card.element {
        let upperFull = obs.fullText.uppercased()
        let upperElem = element.uppercased()
        let elementCount = countOccurrences(of: upperElem, in: upperFull)
                         + countFuzzyElementOccurrences(in: upperFull, element: upperElem)
        if elementCount >= 2 {
            total += 0.6; signals.append(("cn_suffix_element", 0.6))
        }
    }

    if let treatment = card.treatment, !treatment.isEmpty {
        let words = treatment.uppercased().components(separatedBy: .whitespaces).filter { $0.count > 3 }
        let hits = words.filter { obs.fullText.contains($0) }.count
        if hits > 0 {
            let w = min(0.3, Float(hits) * 0.1)
            total += w; signals.append(("treatment_word_x\(hits)", w))
        }
    }

    let powerText = obs.topRightText.isEmpty ? obs.fullText : obs.topRightText
    if let power = card.power, extractIntegers(from: powerText).contains(power) {
        total += 0.3; signals.append(("power_match", 0.3))
    }

    if let cellColor = cellColorBucket,
       let treatment = card.treatment,
       let expected = expectedColorBucket(for: treatment),
       expected == cellColor {
        total += 0.3; signals.append(("treatment_color_\(cellColor.name)", 0.3))
    }

    // BORDER SPECKLE SIGNATURE.
    // High pixel-to-pixel luminance variance in the border samples
    // indicates a fine-grained speckled foil treatment — distinctively
    // characteristic of Icon Battlefoils and Power Glove Battlefoils
    // (small icon shapes embedded in metallic foil at high spatial
    // frequency). Other "holographic" treatments (Mixtape, 80's Rad,
    // Linoleum, Logofoil) have larger pattern features that are
    // smooth at the pixel-pair level (localVar < 15 in baseline).
    //
    // Empirical threshold from baseline: Icon Battlefoils observed
    // with localVar 25-35 when speckle is visible in the photo
    // (Doublecheck IBF-291 = 35.3, Forcefield IBF-191 = 25.9).
    // Other 61 baseline cells stay <15. Threshold of 18 keeps margin
    // of safety against treatment misclassification.
    if let sig = borderSig, sig.localVarianceAboveSpeckleThreshold,
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

    // HERO + DIGIT-SUFFIX RECOVERY BONUS. Fires when this card's
    // hero matches the strong-hero set AND its cardNumber ends with
    // one of the digit suffixes Vision picked up from the badge area
    // (where the prefix letters were misread as digits and couldn't
    // be reverse-substituted). Equivalent in strength to a confirmed
    // partial cn — strong enough to outrank a same-hero FP rank-0
    // wrong-treatment match by ~0.5.
    if !heroSuffixHits.isEmpty,
       strongHeroIdentities.contains(heroIdentity(card)) {
        let cardCN = card.cardNumber.uppercased()
        for suffix in heroSuffixHits {
            if cardCN.hasSuffix("-" + suffix) || cardCN == suffix {
                total += 0.7
                signals.append(("hero_suffix_recovery", 0.7))
                break
            }
        }
    }

    return Scored(card: card, total: total, signals: signals)
}

// MARK: - Resolve

let kMinConfidence: Float = 1.4
let kMinMargin: Float = 0.3

struct Resolution {
    let chosen: Card?
    let topCandidates: [Scored]
    let strongHeroes: Set<String>
    let cellColor: ColorBucket?
    let fpTop5: [(bobaId: String, distance: Float)]
    let fpAllDistances: [String: Float]
}

func resolveDetailed(
    obs: OCRResult,
    cellCrop: CGImage,
    allCards: [Card],
    cardsById: [String: Card],
    fpIndex: FPIndex
) -> Resolution {
    let fpDistance = fpIndex.distances(in: cellCrop)
    let fpRanked = fpDistance.sorted { $0.value < $1.value }.map { $0.key }
    let fpTop5: [(String, Float)] = fpRanked.prefix(5).compactMap { id in
        if let d = fpDistance[id] { return (id, d) }
        return nil
    }

    let cellColorBucket = extractCellColorBucket(cgImage: cellCrop)
    let borderSig = extractBorderSignature(cgImage: cellCrop)
    let ocrTreatmentPrefixes = extractCardNumberPrefixes(from: obs.fullText)
    var ocrFullPatterns = extractCardNumberFullPatterns(from: obs.fullText)
    if !obs.cardNumber.isEmpty {
        ocrFullPatterns.insert(obs.cardNumber.uppercased())
    }

    let topLeftHeroIdentities = heroIdentitiesInTopLeft(allCards: allCards, topLeftText: obs.topLeftText)
    var strongHeroIdentities = topLeftHeroIdentities
    // FP-majority hero
    if fpRanked.count >= 2,
       let topId = fpRanked.first,
       let topCard = cardsById[topId] {
        let topHero = heroIdentity(topCard)
        var topHeroCount = 1
        for id in fpRanked.prefix(3).dropFirst() {
            if let card = cardsById[id], heroIdentity(card) == topHero { topHeroCount += 1 }
        }
        if topHeroCount >= 2 { strongHeroIdentities.insert(topHero) }
    }

    var candidateIds: Set<String> = []
    for id in fpRanked.prefix(50) { candidateIds.insert(id) }
    let cn = obs.cardNumber.uppercased()
    if !cn.isEmpty {
        for c in allCards where c.cardNumber.uppercased() == cn {
            candidateIds.insert(c.bobaId)
        }
    }
    if !cn.isEmpty, cn.allSatisfy({ $0.isNumber }) {
        let suffix = "-" + cn
        for c in allCards where c.cardNumber.uppercased().hasSuffix(suffix) {
            candidateIds.insert(c.bobaId)
        }
    }
    // Element-filtered bare-suffix expansion: when OCR captures a
    // confident element word (>= 2 mentions) AND a short bare-digit
    // cn (1-2 chars), seed cards whose cardCN ends with that suffix
    // and matches the element. Recovers cases where OCR truncated
    // a cardNumber (Skuba "188" → "8") — the catalog only has 6
    // Base Set BRAWL cards ending in "8", so the picker pool stays
    // tractable but Skuba 188 becomes selectable.
    if !cn.isEmpty, cn.allSatisfy({ $0.isNumber }), cn.count <= 2 {
        let allElements = ["FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER"]
        let upperFull = obs.fullText.uppercased()
        let strongElement = allElements.first {
            countOccurrences(of: $0, in: upperFull) + countFuzzyElementOccurrences(in: upperFull, element: $0) >= 2
        }
        if let element = strongElement {
            for c in allCards {
                guard let cardElement = c.element, cardElement.uppercased() == element else { continue }
                let cardCN = c.cardNumber.uppercased()
                let cardCNIsBare = !cardCN.contains("-")
                if cardCNIsBare && cardCN.hasSuffix(cn) {
                    candidateIds.insert(c.bobaId)
                }
            }
        }
    }
    // ELEMENT + NO-CN SEEDING. When OCR captures NO usable
    // cardNumber but DOES capture a confident element word (≥2
    // exact OR fuzzy mentions in any quadrant), AND there's no
    // strong hero either, surface ALL Base Set cards of that
    // element + the majority release as candidates. Pure
    // recovery for cells where the badge is unreadable but the
    // element badge bled through (Skuba 188 case: empty cn,
    // empty botL, but topR repeated "BRAWIL Ç BRAWIL Ç BRAWIL"
    // — clearly BRAWL element). Without this, Skuba 188 is
    // never even a candidate.
    if cn.isEmpty {
        let allElements = ["FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER"]
        let upperFull = obs.fullText.uppercased()
        let strongElement = allElements.first {
            countOccurrences(of: $0, in: upperFull) + countFuzzyElementOccurrences(in: upperFull, element: $0) >= 2
        }
        if let element = strongElement {
            for c in allCards {
                guard let cardElement = c.element, cardElement.uppercased() == element else { continue }
                guard c.treatment == "Base Set" else { continue }
                candidateIds.insert(c.bobaId)
            }
        }
    }
    if !strongHeroIdentities.isEmpty {
        let heroVariants = allCards.filter { strongHeroIdentities.contains(heroIdentity($0)) }
        let ranked = heroVariants.sorted {
            (fpDistance[$0.bobaId] ?? .greatestFiniteMagnitude) <
            (fpDistance[$1.bobaId] ?? .greatestFiniteMagnitude)
        }
        for c in ranked.prefix(20) { candidateIds.insert(c.bobaId) }
    }

    // HERO + DIGIT-SUFFIX RECOVERY. When the badge in the bottom-
    // left has a token like "80F-72" — where the digit suffix "72"
    // is clean but the prefix "80F" is OCR's misread of letters
    // (R→8, B→0 confusions Vision makes on stylized treatment
    // badges) — extract the suffix and look for catalog cards
    // matching the strong hero whose cardNumber ends in that
    // suffix. Maverick photo whose botL read "80F-72" in fact had
    // RBF-72 (Red Battlefoil) as the printed cardNumber.
    var heroSuffixHits: Set<String> = []  // suffixes that matched a hero variant
    if !strongHeroIdentities.isEmpty {
        let suffixPattern = try! NSRegularExpression(pattern: #"[A-Z0-9]{1,6}-(\d{1,4})"#)
        let botText = "\(obs.bottomLeftText) \(obs.bottomRightText)".uppercased()
        let range = NSRange(botText.startIndex..., in: botText)
        var foundSuffixes: Set<String> = []
        suffixPattern.enumerateMatches(in: botText, range: range) { m, _, _ in
            if let m, let r = Range(m.range(at: 1), in: botText) {
                foundSuffixes.insert(String(botText[r]))
            }
        }
        for suffix in foundSuffixes {
            let target = "-" + suffix
            for c in allCards
            where strongHeroIdentities.contains(heroIdentity(c))
              && c.cardNumber.uppercased().hasSuffix(target) {
                candidateIds.insert(c.bobaId)
                heroSuffixHits.insert(suffix)
            }
        }
    }
    if let cellColor = cellColorBucket, !strongHeroIdentities.isEmpty {
        let colorMatched = allCards.filter { card in
            guard strongHeroIdentities.contains(heroIdentity(card)),
                  let treatment = card.treatment,
                  let expected = expectedColorBucket(for: treatment)
            else { return false }
            return expected == cellColor
        }
        let ranked = colorMatched.sorted {
            (fpDistance[$0.bobaId] ?? .greatestFiniteMagnitude) <
            (fpDistance[$1.bobaId] ?? .greatestFiniteMagnitude)
        }
        for c in ranked.prefix(20) { candidateIds.insert(c.bobaId) }
    }

    let candidates = candidateIds.compactMap { cardsById[$0] }
    guard !candidates.isEmpty else {
        return Resolution(chosen: nil, topCandidates: [], strongHeroes: strongHeroIdentities, cellColor: cellColorBucket, fpTop5: fpTop5, fpAllDistances: fpDistance)
    }

    let fpRankIndex: [String: Int] = Dictionary(uniqueKeysWithValues: fpRanked.enumerated().map { ($1, $0) })
    let scored = candidates.map { card in
        scoreCandidate(card, obs: obs, fpRankIndex: fpRankIndex,
                       fpDistance: fpDistance,
                       strongHeroIdentities: strongHeroIdentities,
                       topLeftHeroIdentities: topLeftHeroIdentities,
                       ocrTreatmentPrefixes: ocrTreatmentPrefixes,
                       ocrFullPatterns: ocrFullPatterns,
                       cellColorBucket: cellColorBucket,
                       heroSuffixHits: heroSuffixHits,
                       borderSig: borderSig)
    }
    // Pre-sort: total descending, then FP distance ascending. The FP
    // tiebreaker only matters when two candidates score identically
    // (Ozzmosis-172 vs Laviathan-172 — same hero, same element, same
    // bare cn, both fired cn_exact_bare + hero_implied_by_cn). The
    // closer one in feature-print space wins because that's our only
    // remaining signal of which artwork is actually in the cell.
    let ranked = scored.sorted { (a, b) -> Bool in
        if a.total != b.total { return a.total > b.total }
        let aDist = fpDistance[a.card.bobaId] ?? .greatestFiniteMagnitude
        let bDist = fpDistance[b.card.bobaId] ?? .greatestFiniteMagnitude
        return aDist < bDist
    }
    let chosen: Card?
    if let top = ranked.first, top.total >= kMinConfidence {
        if ranked.count >= 2 {
            let nextDifferentHero = ranked.dropFirst().first { entry in
                heroIdentity(entry.card) != heroIdentity(top.card)
            }
            if let other = nextDifferentHero {
                let margin = top.total - other.total
                // Tie-break for cn_exact-only collisions: when top
                // and runner-up both fired cn_exact (any flavor) AND
                // both have the SAME card.cardNumber (cn-collision —
                // Ozzmosis vs Laviathan both have cn=172), the tie
                // is genuinely between two cards with the same
                // catalog number. The FP-distance pre-sort above
                // already picked the closer one; bypass the margin
                // gate so we commit instead of returning nil.
                let topFiredCN = top.signals.contains { $0.0 == "cn_exact" || $0.0 == "cn_exact_bare" }
                let otherFiredCN = other.signals.contains { $0.0 == "cn_exact" || $0.0 == "cn_exact_bare" }
                let sameCardCN = top.card.cardNumber.uppercased() == other.card.cardNumber.uppercased()
                if topFiredCN && otherFiredCN && sameCardCN {
                    chosen = top.card
                } else if margin < kMinMargin {
                    chosen = nil
                } else {
                    chosen = top.card
                }
            } else { chosen = top.card }
        } else { chosen = top.card }
    } else { chosen = nil }
    return Resolution(chosen: chosen, topCandidates: Array(ranked.prefix(8)),
                      strongHeroes: strongHeroIdentities, cellColor: cellColorBucket, fpTop5: fpTop5, fpAllDistances: fpDistance)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: \(args[0]) <image1.HEIC> [image2.HEIC ...]")
    exit(1)
}
let imagePaths = Array(args.dropFirst())

print("Loading catalog...")
let catalog = loadCatalog()
let cardsById = Dictionary(uniqueKeysWithValues: catalog.map { ($0.bobaId, $0) })
let cardNumberSet = Set(catalog.map { $0.cardNumber.uppercased() })
let names: Set<String> = {
    var s = Set<String>()
    for c in catalog {
        if c.hero.count >= 3 { s.insert(c.hero.uppercased()) }
        if c.name.count >= 3, c.name != c.hero { s.insert(c.name.uppercased()) }
    }
    return s
}()
let customWords = Array(cardNumberSet) + Array(names)
print("Loaded \(catalog.count) cards, \(cardNumberSet.count) unique cardNumbers, \(names.count) names")

print("Loading FP index...")
let fpIndex = FPIndex()
fpIndex.loadFromBundle()
print("Loaded \(fpIndex.entryCount) FP entries (\(fpIndex.elementCount) dims)")

print()
for path in imagePaths {
    print("================================================================================")
    print("IMAGE: \(path)")
    print("================================================================================")
    guard let cgImage = loadCGImage(at: path) else {
        print("FAILED TO LOAD")
        continue
    }
    let tStart = Date()
    let cells = GridDetector.detect(cgImage: cgImage)
    let tDetect = Date()
    print(String(format: "Detected %d cells  (detect=%.0fms)",
                 cells.count, tDetect.timeIntervalSince(tStart) * 1000))
    print()

    // PASS 1: resolve every cell independently. Collect results so
    // we can compute cross-cell context (majority set / release) for
    // pass 2 tiebreaking.
    struct CellRun {
        let cell: DetectedCell
        let label: String
        let ocr: OCRResult
        let res: Resolution
        let ocrMs: Double
        let resolveMs: Double
    }
    var cellRuns: [CellRun] = []
    for cell in cells {
        let label = "r\(cell.row)c\(cell.column)"
        let tCellStart = Date()
        let ocr = ocrCell(cgImage: cell.crop, cardNumberSet: cardNumberSet, customWords: customWords)
        let tAfterOCR = Date()
        let res = resolveDetailed(obs: ocr, cellCrop: cell.crop, allCards: catalog, cardsById: cardsById, fpIndex: fpIndex)
        let tAfterResolve = Date()
        cellRuns.append(CellRun(
            cell: cell, label: label, ocr: ocr, res: res,
            ocrMs:    tAfterOCR.timeIntervalSince(tCellStart) * 1000,
            resolveMs: tAfterResolve.timeIntervalSince(tAfterOCR) * 1000
        ))
    }

    // PASS 2 PREP: tally majority set + release across confidently-
    // committed cells (chosen != nil with score margin). The grid
    // scanner is almost always pointed at cards from a single
    // release because that's how people pull packs — so the set/
    // release of cells we're SURE about is a strong prior for cells
    // we're uncertain about. Ozzmosis-172 (Griffey) vs Laviathan-172
    // (Alpha Update) — same cn, same element, same power, same
    // treatment — only set distinguishes them, and the other 6
    // resolved cells in IMG_5231 are all Griffey, so Ozzmosis is
    // the right pick.
    var setCounts: [String: Int] = [:]
    var releaseCounts: [String: Int] = [:]
    for r in cellRuns {
        if let chosen = r.res.chosen {
            setCounts[chosen.set, default: 0] += 1
            releaseCounts[chosen.release, default: 0] += 1
        }
    }
    let majoritySet     = setCounts.max(by: { $0.value < $1.value }).map     { ($0.key, $0.value) }
    _ = releaseCounts // kept for future per-release tiebreaking
    let totalCommitted  = cellRuns.filter { $0.res.chosen != nil }.count
    let setIsConfident  = (majoritySet?.1 ?? 0) >= max(2, totalCommitted / 2 + 1)

    if let m = majoritySet, setIsConfident {
        print("Context: majoritySet=\(m.0) (\(m.1)/\(totalCommitted) committed cells)")
        print()
    }

    for r in cellRuns {
        // PASS 2 RE-PICK: when the top candidate doesn't match the
        // majority set BUT a same-hero (or close-score) candidate
        // does, swap. Threshold: runner-up must be within 0.5 of
        // top — wider than the original kMinMargin=0.3 so we'll
        // override even cn_exact-driven commits when set context
        // strongly disagrees.
        var finalChosen = r.res.chosen
        var setOverride: String? = nil
        if let (majSet, _) = majoritySet, setIsConfident, !r.res.topCandidates.isEmpty {
            let top = r.res.topCandidates[0]
            if top.card.set != majSet {
                // Look for a runner-up that DOES match the majority
                // set, within 0.5 of the top score.
                for cand in r.res.topCandidates.dropFirst() {
                    if cand.card.set == majSet, (top.total - cand.total) <= 0.5 {
                        finalChosen = cand.card
                        setOverride = "set-context: \(top.card.bobaId) → \(cand.card.bobaId) (set match \(majSet))"
                        break
                    }
                }
            }
        }
        let finalCnFound = !r.ocr.cardNumber.isEmpty
        FileHandle.standardError.write(String(format: "⏱  cell %@  ocr=%.0fms  resolve=%.0fms  total=%.0fms  cn=%@\n",
                     r.label, r.ocrMs, r.resolveMs, r.ocrMs + r.resolveMs,
                     finalCnFound ? "yes" : "NO").data(using: .utf8)!)

        print("--- cell \(r.label) ---")
        print("  OCR cn:       \"\(r.ocr.cardNumber)\"")
        print("  OCR topL:     \"\(r.ocr.topLeftText)\"")
        print("  OCR topR:     \"\(r.ocr.topRightText)\"")
        print("  OCR botL:     \"\(r.ocr.bottomLeftText)\"")
        print("  Cell color:   \(r.res.cellColor?.name ?? "nil")")
        print("  Strong heroes: [\(r.res.strongHeroes.sorted().joined(separator: ", "))]")
        print("  FP top-5:")
        for (i, e) in r.res.fpTop5.enumerated() {
            let card = cardsById[e.bobaId]
            let heroLabel = card.map { "\($0.hero) [\($0.cardNumber) \($0.treatment ?? "Base Set")]" } ?? "?"
            print(String(format: "    %d  d=%.4f  %@  %@", i, e.distance, e.bobaId as NSString, heroLabel as NSString))
        }
        print("  Top scored:")
        for (i, s) in r.res.topCandidates.prefix(8).enumerated() {
            let breakdown = s.signals.map { "\($0.name)\($0.weight >= 0 ? "+" : "")\(String(format: "%.2f", $0.weight))" }.joined(separator: " ")
            let fpD = r.res.fpAllDistances[s.card.bobaId].map { String(format: "fpd=%.4f", $0) } ?? "fpd=?"
            print(String(format: "    %d  total=%.2f  %@  %@  %@  set=%@", i, s.total, s.card.bobaId as NSString, breakdown as NSString, fpD as NSString, s.card.set as NSString))
        }
        if let so = setOverride { print("  Override: \(so)") }
        print("  Chosen: \(finalChosen?.bobaId ?? "nil")")
        print()
    }
    let tEnd = Date()
    FileHandle.standardError.write(String(format: "⏱  IMAGE %@: total=%.0fms  cells=%d\n",
                 (path as NSString).lastPathComponent,
                 tEnd.timeIntervalSince(tStart) * 1000,
                 cells.count).data(using: .utf8)!)
}
