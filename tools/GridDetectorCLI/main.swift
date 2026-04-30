// Grid Detector CLI — standalone macOS tool for iterating on the grid
// card detector without going through Xcode Cloud. Loads a HEIC fixture,
// runs the same Vision pipeline as iOS, saves cropped cells to disk,
// prints stats. Vision API is identical between macOS and iOS so what
// works here ports cleanly back to BOBAPlaybook/Views/Scan/GridCardDetector.swift.
//
// Build + run:
//   cd Tools/GridDetectorCLI
//   swiftc -O main.swift -o grid_detector
//   ./grid_detector <image-path> [output-dir]
//
// Or use ../run_fixtures.sh to loop over all 4 bundled HEIC fixtures.

import Foundation
import Vision
import CoreImage
import ImageIO
import AppKit

// MARK: - Config (tunable per-run via env or CLI flags)

struct Params {
    var minimumConfidence: Float = 0.1
    var minimumAspectRatio: Float = 0.40
    var maximumAspectRatio: Float = 1.10
    var minimumSize: Float = 0.05
    var quadratureTolerance: Float = 45
    var maximumObservations: Int = 150
    var anchorAspectMin: CGFloat = 0.50
    var anchorAspectMax: CGFloat = 1.10
    var anchorMinSize: CGFloat = 0.10
    /// Max fraction of image area a single anchor can occupy. The whole
    /// grid sometimes gets detected as one big rectangle — filtering
    /// it out keeps the median card-size calculation honest. Single
    /// cards in a 3×3 take ~12% of area; 3×1 cards each take ~33%.
    /// 0.36 is generous enough for 3×1 + slight margins.
    var anchorMaxArea: CGFloat = 0.36
    var laneToleranceFactor: CGFloat = 0.5
    var maxLanes: Int = 3
    var bleed: CGFloat = 0.04
    /// Edge-enhance the source image before Vision sees it. Helps on
    /// bare cards on wood where the card-vs-table contrast is low.
    /// Disabled by default — Vision's internal preprocessing already
    /// handles toploader cases well; edge-enhance can hurt those.
    var edgeEnhance: Bool = false
}

// MARK: - GridGeometry (mirrors iOS)

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

    /// Trading cards are 2.5×3.5 inches → aspect ratio 0.714 portrait.
    /// We treat this as a hard constraint, not an estimate. Every
    /// generated crop is sized to match exactly so OCR sees a
    /// proper card shape regardless of how Vision's anchors
    /// happened to fall.
    static let cardAspectRatio: CGFloat = 0.714

    static func infer(from anchors: [VNRectangleObservation], params: Params) -> GridGeometry? {
        guard !anchors.isEmpty else { return nil }
        let widths = anchors.map { $0.boundingBox.width }.sorted()
        let heights = anchors.map { $0.boundingBox.height }.sorted()
        let medianWidth = widths[widths.count / 2]
        let medianHeight = heights[heights.count / 2]

        let xCenters = anchors.map { $0.boundingBox.midX }
        let columnLanes = clusterCenters(
            values: xCenters,
            tolerance: medianWidth * params.laneToleranceFactor,
            maxLanes: params.maxLanes
        )
        let yCenters = anchors.map { $0.boundingBox.midY }
        let rowLanes = clusterCenters(
            values: yCenters,
            tolerance: medianHeight * params.laneToleranceFactor,
            maxLanes: params.maxLanes
        )
        guard !columnLanes.isEmpty, !rowLanes.isEmpty else { return nil }

        let rowLanesTopFirst = rowLanes.sorted(by: >)
        let colLanesLeftFirst = columnLanes.sorted()

        // Card dimensions derived from GRID LANE SPACING. This is
        // the most reliable signal we have:
        //   cardHeight = rowSpacing × fillFactor
        //   cardWidth  = colSpacing × fillFactor
        //
        // We deliberately DON'T enforce a strict 0.714 aspect ratio
        // here — perspective compression on tilted photos makes the
        // apparent card shape vary from the physical 2.5×3.5" ratio,
        // sometimes by as much as ±15%. Using both lane spacings
        // gives the crop the actual SHAPE of the cards as photographed.
        // The aspect ratio is checked only as a sanity bound: if the
        // computed crop drifts more than 30% from card aspect, we
        // assume one of the spacings is wrong and clamp.
        //
        // FILL_FACTOR = 0.98 — leaves a tiny gap so adjacent cards
        // don't bleed across cell boundaries.
        let fillFactor: CGFloat = 0.98
        let colSpacing = meanSpacing(of: colLanesLeftFirst) ?? (medianWidth  * 1.05)
        let rowSpacing = meanSpacing(of: rowLanesTopFirst)  ?? (medianHeight * 1.05)
        var cardHeight = rowSpacing * fillFactor
        var cardWidth  = colSpacing * fillFactor
        // Sanity: aspect should be in [0.5, 1.0] for cards photographed
        // roughly portrait. If wildly off, assume one spacing is wrong
        // and snap to aspect-ratio-derived width.
        let measuredAspect = cardWidth / cardHeight
        if measuredAspect < 0.50 || measuredAspect > 1.00 {
            cardWidth = cardHeight * cardAspectRatio
        }
        // For single-row/column inputs (only one lane in that axis,
        // so spacing was the fallback medianX × 1.05), the fallback
        // dimension can be too small. Inflate to at least anchor-
        // derived size.
        if colLanesLeftFirst.count == 1 {
            cardWidth = max(cardWidth, medianWidth * 1.10)
        }
        if rowLanesTopFirst.count == 1 {
            cardHeight = max(cardHeight, medianHeight * 1.10)
        }
        _ = cardAspectRatio  // kept for sanity-clamp branch above

        var cells: [Cell] = []
        for (rowIdx, y) in rowLanesTopFirst.enumerated() {
            for (colIdx, x) in colLanesLeftFirst.enumerated() {
                let rect = CGRect(
                    x: x - cardWidth  / 2,
                    y: y - cardHeight / 2,
                    width:  cardWidth,
                    height: cardHeight
                )
                cells.append(Cell(
                    row: rowIdx,
                    column: colIdx,
                    center: CGPoint(x: x, y: y),
                    rect: rect
                ))
            }
        }
        return GridGeometry(cells: cells, medianWidth: cardWidth, medianHeight: cardHeight)
    }

    /// Mean of adjacent-pair gaps in a sorted lane list. Returns nil
    /// for single-lane (no spacing to compute).
    private static func meanSpacing(of lanes: [CGFloat]) -> CGFloat? {
        guard lanes.count >= 2 else { return nil }
        let sorted = lanes.sorted()
        var gaps: [CGFloat] = []
        for i in 1..<sorted.count { gaps.append(sorted[i] - sorted[i - 1]) }
        return gaps.reduce(0, +) / CGFloat(gaps.count)
    }

    private static func clusterCenters(values: [CGFloat], tolerance: CGFloat, maxLanes: Int) -> [CGFloat] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        var clusters: [[CGFloat]] = []
        for v in sorted {
            if let last = clusters.last,
               let lastEnd = last.last,
               (v - lastEnd) < tolerance {
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
        return keepers.map { c in c.reduce(0, +) / CGFloat(c.count) }
    }
}

// MARK: - Detector

struct DetectionResult {
    let anchors: [VNRectangleObservation]
    let cells: [DetectedCell]
}

struct DetectedCell {
    let row: Int
    let column: Int
    let image: CGImage
    let confidence: Float
    let synthesized: Bool
}

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

func detect(in ciImage: CIImage, orientation: CGImagePropertyOrientation, params: Params) async throws -> DetectionResult {
    let oriented = ciImage.oriented(orientation)
    // Edge-enhance only the input to Vision; perspective correction +
    // crop output still come from the unaltered source so OCR sees
    // real card colors.
    let detectInput = params.edgeEnhance ? enhanceForEdges(ciImage) : ciImage
    let observations = try await runRectangleRequest(
        on: detectInput,
        orientation: orientation,
        params: params
    )
    let rawAnchors = observations.filter { obs in
        let aspect = obs.boundingBox.width / obs.boundingBox.height
        let area = obs.boundingBox.width * obs.boundingBox.height
        return aspect >= params.anchorAspectMin && aspect <= params.anchorAspectMax
            && obs.boundingBox.width >= params.anchorMinSize
            && obs.boundingBox.height >= params.anchorMinSize
            && area <= params.anchorMaxArea
    }
    // Dedupe overlapping anchors. When Vision finds the same card with
    // multiple confidences (or the toploader inner+outer rect), keep
    // the most confident one. Threshold = 5% of image dimensions —
    // tight enough to keep adjacent cards separate (their centers
    // sit ~33% apart in a 3×3 grid).
    let dedupedAnchors = dedupOverlappingAnchors(rawAnchors)
    // Two-pass refinement: first pass infers rough geometry from all
    // dedupedAnchors. We then drop anchors that fall outside any
    // predicted cell (those are usually wood-grain false positives
    // that pulled the lane centers off-axis) and re-infer using
    // only the clean ones. Without this, a single stray anchor on
    // the table can shift an entire row's predicted positions by
    // a few percent — enough to misalign the cropped cells.
    let anchors: [VNRectangleObservation]
    if let rough = GridGeometry.infer(from: dedupedAnchors, params: params) {
        let cellTolerance = max(rough.medianWidth, rough.medianHeight) * 0.7
        let cleaned = dedupedAnchors.filter { obs in
            let center = CGPoint(x: obs.boundingBox.midX, y: obs.boundingBox.midY)
            return rough.cells.contains { cell in
                distance(center, cell.center) < cellTolerance
            }
        }
        anchors = cleaned.isEmpty ? dedupedAnchors : cleaned
    } else {
        anchors = dedupedAnchors
    }
    guard !anchors.isEmpty else {
        return DetectionResult(anchors: [], cells: [])
    }
    guard let geometry = GridGeometry.infer(from: anchors, params: params) else {
        return DetectionResult(anchors: anchors, cells: [])
    }
    // ALWAYS use axis-aligned crops at lane-derived cell rects.
    // Why not perspective-correct from anchors?
    //   Vision's anchors are systematically smaller than the
    //   actual cards — bare-card photos showed anchor height
    //   0.21 vs measured card height 0.27, a 22% under-detection.
    //   Perspective-correcting from those anchors then clips the
    //   bottom-left of the card where the cardNumber lives.
    //   Lane intersections + lane-derived dimensions place the
    //   crop at the right CENTER and the right SIZE — even when
    //   no anchor exists for that cell.
    //   We lose perspective dewarping, but OCR tolerates ±5° of
    //   skew (verified on the toploader fixtures), and the
    //   alternative was "perfectly rectified but clipped" which
    //   was missing the cardNumber entirely.
    var cells: [DetectedCell] = []
    for cell in geometry.cells {
        // Note whether any real anchor sits near this cell — used
        // only for the synthesized/anchor-based label in the
        // harness, doesn't change crop behavior.
        let tolerance = geometry.medianWidth / 2
        let nearest = anchors.first { obs in
            let dx = obs.boundingBox.midX - cell.center.x
            let dy = obs.boundingBox.midY - cell.center.y
            return (dx * dx + dy * dy).squareRoot() < tolerance
        }
        if let cg = axisAlignedCrop(oriented: oriented, cellRect: cell.rect) {
            cells.append(DetectedCell(
                row: cell.row, column: cell.column,
                image: cg,
                confidence: nearest?.confidence ?? 0,
                synthesized: nearest == nil
            ))
        }
    }
    return DetectionResult(anchors: anchors, cells: cells)
}

func runRectangleRequest(
    on ciImage: CIImage,
    orientation: CGImagePropertyOrientation,
    params: Params
) async throws -> [VNRectangleObservation] {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[VNRectangleObservation], Error>) in
        let req = VNDetectRectanglesRequest { req, err in
            if let err { cont.resume(throwing: err); return }
            cont.resume(returning: (req.results as? [VNRectangleObservation]) ?? [])
        }
        req.minimumAspectRatio = params.minimumAspectRatio
        req.maximumAspectRatio = params.maximumAspectRatio
        req.minimumSize = params.minimumSize
        req.minimumConfidence = params.minimumConfidence
        req.maximumObservations = params.maximumObservations
        req.quadratureTolerance = params.quadratureTolerance
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
        do { try handler.perform([req]) }
        catch { cont.resume(throwing: error) }
    }
}

func perspectiveCorrect(oriented: CIImage, observation: VNRectangleObservation, bleed: CGFloat) -> CGImage? {
    let extent = oriented.extent
    let center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
    func bled(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + (p.x - center.x) * bleed, y: p.y + (p.y - center.y) * bleed)
    }
    func denorm(_ p: CGPoint) -> CIVector {
        let c = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        return CIVector(x: c.x * extent.width + extent.origin.x, y: c.y * extent.height + extent.origin.y)
    }
    let f = CIFilter(name: "CIPerspectiveCorrection")!
    f.setValue(oriented, forKey: kCIInputImageKey)
    f.setValue(denorm(bled(observation.topLeft)),     forKey: "inputTopLeft")
    f.setValue(denorm(bled(observation.topRight)),    forKey: "inputTopRight")
    f.setValue(denorm(bled(observation.bottomLeft)),  forKey: "inputBottomLeft")
    f.setValue(denorm(bled(observation.bottomRight)), forKey: "inputBottomRight")
    guard let out = f.outputImage else { return nil }
    return ciContext.createCGImage(out, from: out.extent)
}

func axisAlignedCrop(oriented: CIImage, cellRect: CGRect) -> CGImage? {
    let extent = oriented.extent
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
    let cropped = oriented.cropped(to: pixelRect)
    return ciContext.createCGImage(cropped, from: pixelRect)
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

func dedupOverlappingAnchors(_ anchors: [VNRectangleObservation]) -> [VNRectangleObservation] {
    let byConfidence = anchors.sorted { $0.confidence > $1.confidence }
    var kept: [VNRectangleObservation] = []
    for a in byConfidence {
        let center = CGPoint(x: a.boundingBox.midX, y: a.boundingBox.midY)
        let isDup = kept.contains { other in
            let dx = abs(other.boundingBox.midX - center.x)
            let dy = abs(other.boundingBox.midY - center.y)
            return dx < 0.05 && dy < 0.05
        }
        if !isDup { kept.append(a) }
    }
    return kept
}

/// Apply edge-enhancement preprocessing — gamma + saturation drop +
/// unsharp mask. Helps Vision find rectangles when the card edges
/// are low-contrast against the background (bare cards on a wood
/// table being the canonical case).
func enhanceForEdges(_ ciImage: CIImage) -> CIImage {
    return ciImage
        .applyingFilter("CIColorControls", parameters: [
            "inputContrast":   1.5,
            "inputSaturation": 0.3,
            "inputBrightness": 0.05,
        ])
        .applyingFilter("CIUnsharpMask", parameters: [
            "inputRadius":    4.0,
            "inputIntensity": 1.5,
        ])
}

// MARK: - OCR pipeline (mirrors CardScanner.scanStillImage)

struct CatalogEntry: Decodable {
    let cardNumber: String
    let hero: String?
    let name: String?
    let power: Int?
    let element: String?
}

struct Catalog {
    let cardNumbers: Set<String>
    let cards: [CatalogEntry]
    let allWords: [String]
}

func loadCatalog(_ path: String) throws -> Catalog {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let entries = try JSONDecoder().decode([CatalogEntry].self, from: data)
    let nums = Set(entries.map { $0.cardNumber.uppercased() })
    var words = Set<String>()
    for e in entries {
        if let h = e.hero, h.count >= 3 { words.insert(h.uppercased()) }
        if let n = e.name, n.count >= 3, n != e.hero { words.insert(n.uppercased()) }
    }
    return Catalog(cardNumbers: nums, cards: entries, allWords: Array(words))
}

struct OCRResult {
    let cardNumber: String?
    let allText: String
    let bottomLeftText: String
    let matched: CatalogEntry?
    let observations: [(text: String, midX: CGFloat, midY: CGFloat, conf: Float)]
}

func ocrCrop(_ image: CGImage, catalog: Catalog) async -> OCRResult {
    let ci = CIImage(cgImage: image)
        .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.65])
        .applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 0.0,
            "inputContrast":   1.25,
        ])
        .applyingFilter("CIUnsharpMask", parameters: [
            "inputRadius":    2.5,
            "inputIntensity": 0.5,
        ])
    return await withCheckedContinuation { (cont: CheckedContinuation<OCRResult, Never>) in
        let req = VNRecognizeTextRequest { req, _ in
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            var topLeft: [String] = [], bottomLeft: [String] = []
            var all: [String] = []
            var obsList: [(text: String, midX: CGFloat, midY: CGFloat, conf: Float)] = []
            for obs in observations {
                guard let cand = obs.topCandidates(1).first, cand.confidence > 0.3 else { continue }
                let text = cand.string.uppercased()
                all.append(text)
                obsList.append((text, obs.boundingBox.midX, obs.boundingBox.midY, cand.confidence))
                if obs.boundingBox.midY > 0.5 {
                    if obs.boundingBox.midX < 0.5 { topLeft.append(text) }
                } else {
                    if obs.boundingBox.midX < 0.5 { bottomLeft.append(text) }
                }
            }
            let allText = all.joined(separator: " ")
            let blText = bottomLeft.joined(separator: " ")
            let extracted = extractCardNumber(from: blText, catalog: catalog, allowPureNumber: true)
                         ?? extractCardNumber(from: allText, catalog: catalog, allowPureNumber: false)
            let topLeftText = topLeft.joined(separator: " ")
            let matched: CatalogEntry?
            if let num = extracted {
                let candidates = catalog.cards.filter { $0.cardNumber.uppercased() == num }
                matched = bestMatch(candidates: candidates, allText: allText, topLeftText: topLeftText)
            } else { matched = nil }
            cont.resume(returning: OCRResult(
                cardNumber:     extracted,
                allText:        allText,
                bottomLeftText: blText,
                matched:        matched,
                observations:   obsList
            ))
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        req.minimumTextHeight = 0.015
        if !catalog.cardNumbers.isEmpty {
            req.customWords = Array(catalog.cardNumbers) + catalog.allWords
        }
        let handler = VNImageRequestHandler(ciImage: ci, options: [:])
        try? handler.perform([req])
    }
}

func extractCardNumber(from text: String, catalog: Catalog, allowPureNumber: Bool) -> String? {
    func ok(_ s: String) -> Bool {
        catalog.cardNumbers.isEmpty || catalog.cardNumbers.contains(s)
    }
    // Substitute common digit-side glyph confusions: Đ→B, B→8, S→5,
    // I→1, l→1, O→0, D→0. Only applied to the digit half of a
    // candidate so we don't corrupt prefixes.
    func substituteDigits(_ s: String) -> String {
        var out = ""
        let map: [Character: Character] = [
            "Đ": "B", "B": "8", "S": "5", "I": "1", "l": "1",
            "O": "0", "D": "0", "Z": "2", "G": "6"
        ]
        for ch in s {
            if let r = map[ch] { out.append(r) } else { out.append(ch) }
        }
        return out
    }
    // Substitute letters in the PREFIX side that OCR commonly
    // misreads. D↔O is the highest-frequency confusion in BoBA
    // prefixes (OBF→DBF, HD→HO). Each entry is bidirectional —
    // try both orientations to recover the catalog cardNumber.
    func substitutePrefixVariants(_ s: String) -> [String] {
        // Pairs of mutually-confusable characters in prefix
        // position. Generates 2^N variants where N is how many
        // pair members the prefix contains.
        let pairs: [(Character, Character)] = [
            ("D", "O"),
            ("Đ", "B"),
            ("0", "O"),
            ("8", "B"),
            ("5", "S"),
            ("1", "I"),
            ("2", "Z"),
            ("6", "G"),
        ]
        // Find which positions have a swappable character
        var positions: [(Int, Character, Character)] = []
        for (i, ch) in s.enumerated() {
            for (a, b) in pairs {
                if ch == a { positions.append((i, a, b)); break }
                if ch == b { positions.append((i, b, a)); break }
            }
        }
        guard !positions.isEmpty else { return [s] }
        // Cap variants — 8 swap positions × 2 = 256 max,
        // but typical prefixes have ≤3 swaps so usually 8 variants.
        let maxBits = min(positions.count, 6)
        var out: [String] = []
        for mask in 0..<(1 << maxBits) {
            var arr = Array(s)
            for k in 0..<maxBits {
                if mask & (1 << k) != 0 {
                    let (idx, _, sub) = positions[k]
                    arr[idx] = sub
                }
            }
            out.append(String(arr))
        }
        return out
    }
    let range = NSRange(text.startIndex..., in: text)
    let strict = try! NSRegularExpression(
        pattern: #"#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#
    )
    if let m = strict.firstMatch(in: text, range: range),
       let r = Range(m.range(at: 1), in: text) {
        let cand = String(text[r])
        if ok(cand) { return cand }
    }
    let permissive = try! NSRegularExpression(
        pattern: #"([A-Z]{1,6})[\s\-]+([A-Z0-9]{1,5})"#
    )
    let perm = permissive.matches(in: text, options: [], range: range)
    for m in perm {
        if let pR = Range(m.range(at: 1), in: text),
           let nR = Range(m.range(at: 2), in: text) {
            let prefix = String(text[pR])
            let digits = String(text[nR])
            for prefixVariant in substitutePrefixVariants(prefix) {
                for digitsVariant in [digits, substituteDigits(digits)] {
                    let combined = "\(prefixVariant)-\(digitsVariant)"
                    if catalog.cardNumbers.contains(combined) { return combined }
                }
            }
        }
    }
    let words = text
        .components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
        .filter { !$0.isEmpty }
    // Prefix glyph-mangled form: word like "BGĐF-38" — try splitting
    // on dash, run prefix variants on the alphabetic side and digit
    // substitution on the numeric side.
    for w in words where w.contains("-") {
        let parts = w.split(separator: "-").map(String.init)
        guard parts.count == 2 else { continue }
        for prefixVariant in substitutePrefixVariants(parts[0]) {
            for digitsVariant in [parts[1], substituteDigits(parts[1])] {
                let combined = "\(prefixVariant)-\(digitsVariant)"
                if catalog.cardNumbers.contains(combined) { return combined }
            }
        }
    }
    if words.count >= 2, !catalog.cardNumbers.isEmpty {
        for i in 0..<(words.count - 1) {
            let p = words[i], n = words[i + 1]
            guard p.count >= 1, p.count <= 6,
                  p.allSatisfy({ $0.isLetter || "ĐO".contains($0) })
            else { continue }
            for prefixVariant in substitutePrefixVariants(p) {
                for digitsVariant in [n, substituteDigits(n)] {
                    let combined = "\(prefixVariant)-\(digitsVariant)"
                    if catalog.cardNumbers.contains(combined) { return combined }
                }
            }
        }
    }
    if allowPureNumber, !catalog.cardNumbers.isEmpty {
        for w in words {
            if w.count >= 1, w.count <= 4, w.allSatisfy({ $0.isNumber }),
               catalog.cardNumbers.contains(w) { return w }
            let subbed = substituteDigits(w)
            if subbed != w, subbed.count <= 4, subbed.allSatisfy({ $0.isNumber }),
               catalog.cardNumbers.contains(subbed) { return subbed }
        }
    }
    return nil
}

/// Pick the best candidate when multiple cards share a cardNumber.
/// Mirrors ScanMatching.bestMatch on iOS — scores each candidate by
/// hero/name presence in the OCR text + power match.
func bestMatch(candidates: [CatalogEntry], allText: String, topLeftText: String) -> CatalogEntry? {
    guard !candidates.isEmpty else { return nil }
    if candidates.count == 1 { return candidates[0] }
    func score(_ c: CatalogEntry) -> Int {
        var s = 0
        let full = allText
        // Hero / name match — strong signal
        if let hero = c.hero, !hero.isEmpty {
            s += heroNameScore(hero.uppercased(), in: full) * 5
            if !topLeftText.isEmpty {
                s += heroNameScore(hero.uppercased(), in: topLeftText) * 2
            }
        }
        if let name = c.name, !name.isEmpty,
           name.uppercased() != (c.hero ?? "").uppercased() {
            s += heroNameScore(name.uppercased(), in: full) * 3
        }
        if let power = c.power, extractIntegers(from: full).contains(power) {
            s += 3
        }
        if let element = c.element, full.contains(element.uppercased()) {
            s += 2
        }
        return s
    }
    return candidates.map { ($0, score($0)) }.max { $0.1 < $1.1 }?.0
}

func heroNameScore(_ name: String, in text: String) -> Int {
    if text.contains(name) { return 3 }
    let nameWords = name.components(separatedBy: .whitespaces).filter { $0.count >= 3 }
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

func extractIntegers(from text: String) -> Set<Int> {
    var result = Set<Int>(), current = ""
    for ch in text {
        if ch.isNumber { current.append(ch) }
        else { if let n = Int(current) { result.insert(n) }; current = "" }
    }
    if let n = Int(current) { result.insert(n) }
    return result
}

// MARK: - Image I/O

func loadImage(at path: String) -> (CIImage, CGImagePropertyOrientation)? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    // Read EXIF orientation from properties. HEIC from iPhones almost
    // always carries this — without it the detected coords come back
    // 90° off because Vision interprets the raw pixel buffer top-down.
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let exifOrient = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: exifOrient) ?? .up
    return (CIImage(cgImage: cg), orientation)
}

func writeJPEG(_ cgImage: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let rep = NSBitmapImageRep(cgImage: cgImage)
    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
        try? data.write(to: url)
    }
}

// MARK: - Annotated source image (overlay anchors + cells)

func writeAnnotatedSource(
    ciImage: CIImage,
    orientation: CGImagePropertyOrientation,
    anchors: [VNRectangleObservation],
    cells: [GridGeometry.Cell],
    cellResults: [DetectedCell],
    to path: String
) {
    let oriented = ciImage.oriented(orientation)
    guard let cg = ciContext.createCGImage(oriented, from: oriented.extent) else { return }
    let w = cg.width, h = cg.height
    let bytesPerRow = w * 4
    guard let ctx = CGContext(
        data: nil,
        width: w, height: h,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Vision normalized coords: bottom-left origin. CGContext uses
    // bottom-left too by default, so normalized → pixels is direct.
    func pixelRect(_ norm: CGRect) -> CGRect {
        CGRect(x: norm.minX * CGFloat(w), y: norm.minY * CGFloat(h),
               width: norm.width * CGFloat(w), height: norm.height * CGFloat(h))
    }
    // Line width scales with image size — 4K HEICs need ~50px lines
    // to be visible without zooming.
    let lw = max(CGFloat(min(w, h)) / 80, 8)
    // Anchors in semi-transparent green fill (so missed cells stand
    // out as untouched).
    ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.25).cgColor)
    ctx.setStrokeColor(NSColor.systemGreen.cgColor)
    ctx.setLineWidth(lw)
    for a in anchors {
        let r = pixelRect(a.boundingBox)
        ctx.fill(r)
        ctx.stroke(r)
    }
    // Predicted grid cells in cyan (synthesized) / orange (anchor-based)
    for cell in cellResults {
        let geom = cells.first { $0.row == cell.row && $0.column == cell.column }
        guard let geom else { continue }
        ctx.setStrokeColor(cell.synthesized ? NSColor.systemCyan.cgColor : NSColor.systemOrange.cgColor)
        ctx.setLineWidth(lw * 1.5)
        ctx.stroke(pixelRect(geom.rect))
    }
    if let out = ctx.makeImage() {
        writeJPEG(out, to: path)
    }
}

// MARK: - Entry

@main
struct GridDetectorCLI {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write("usage: grid_detector <image-path> [output-dir]\n".data(using: .utf8)!)
            exit(2)
        }
        let imagePath = args[1]
        let outputDir = args.count >= 3 ? args[2] : "/tmp/grid_out"
        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true
        )
        guard let (ciImage, orientation) = loadImage(at: imagePath) else {
            FileHandle.standardError.write("failed to load image: \(imagePath)\n".data(using: .utf8)!)
            exit(3)
        }
        let basename = (imagePath as NSString).lastPathComponent.replacingOccurrences(of: ".HEIC", with: "")
        var params = Params()
        // Optional flags after image-path / output-dir. Order doesn't
        // matter; `--enhance` toggles the edge-enhance preprocessing.
        for a in args.dropFirst(2) where a.hasPrefix("--") {
            switch a {
            case "--enhance":  params.edgeEnhance = true
            case "--no-area":  params.anchorMaxArea = 1.0
            case "--debug":
                // Pull out all the stops — show every plausible
                // rectangle so we can see WHY cards aren't being found.
                params.minimumConfidence = 0.1
                params.minimumAspectRatio = 0.30
                params.maximumAspectRatio = 1.20
                params.minimumSize = 0.02
                params.maximumObservations = 200
                params.quadratureTolerance = 45
                params.anchorAspectMin = 0.30
                params.anchorAspectMax = 1.20
                params.anchorMaxArea = 1.0
            default: break
            }
        }
        let started = Date()
        let result = try await detect(in: ciImage, orientation: orientation, params: params)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        // Re-infer geometry for annotation rendering (cheap).
        let geometry = GridGeometry.infer(from: result.anchors, params: params)

        print("=== \(basename) ===")
        print("anchors=\(result.anchors.count) cells=\(result.cells.count) elapsed=\(ms)ms")
        for a in result.anchors {
            print(String(format: "  anchor x=%.2f y=%.2f w=%.2f h=%.2f conf=%.2f",
                         a.boundingBox.midX, a.boundingBox.midY,
                         a.boundingBox.width, a.boundingBox.height,
                         a.confidence))
        }

        // Load catalog if present so we can run the full OCR + match
        // pipeline locally. Falls back to detection-only output when
        // the bundle JSON is missing.
        let catalogPath = "../../BOBAPlaybook/display-cards.json"
        let catalog = (try? loadCatalog(catalogPath))
                   ?? (try? loadCatalog("BOBAPlaybook/display-cards.json"))
        var matched = 0
        if let catalog {
            for cell in result.cells {
                let r = await ocrCrop(cell.image, catalog: catalog)
                let label = cell.synthesized ? "GRID" : String(format: "%.2f", cell.confidence)
                let status: String
                if let m = r.matched {
                    let hero = m.hero ?? m.name ?? "?"
                    status = "✓ \(r.cardNumber!) \(hero)"
                    matched += 1
                } else if let num = r.cardNumber {
                    status = "△ \(num) (no catalog match)"
                } else {
                    status = "✗ no number  bl=\"\(r.bottomLeftText.prefix(40))\"  all=\"\(r.allText.prefix(80))\""
                }
                print("  [\(cell.row),\(cell.column)] \(label)  \(status)")
                // For failed cells, print every OCR observation with
                // its position so we can see WHERE the cardNumber-like
                // text actually lives on the card. Helps figure out
                // whether the crop is positioned wrong vs. the
                // cardNumber is just unrecognizable.
                if r.matched == nil {
                    for o in r.observations {
                        print(String(format: "       obs: \"%@\" @ (%.2f, %.2f) conf=%.2f",
                                     o.text, o.midX, o.midY, o.conf))
                    }
                }
            }
            print("matched=\(matched)/\(result.cells.count)")
        }

        // Save crops
        for cell in result.cells {
            let label = cell.synthesized ? "GRID" : String(format: "anchor%.2f", cell.confidence)
            let outPath = "\(outputDir)/\(basename)__r\(cell.row)c\(cell.column)_\(label).jpg"
            writeJPEG(cell.image, to: outPath)
        }
        writeAnnotatedSource(
            ciImage: ciImage,
            orientation: orientation,
            anchors: result.anchors,
            cells: geometry?.cells ?? [],
            cellResults: result.cells,
            to: "\(outputDir)/\(basename)__annotated.jpg"
        )
        print("output → \(outputDir)/\(basename)__*.jpg")
    }
}
