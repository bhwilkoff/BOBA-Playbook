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
        let fillFactor: CGFloat = 0.92
        let colSpacing = meanSpacing(of: colLanesLeftFirst) ?? (medianWidth  * 1.05)
        let rowSpacing = meanSpacing(of: rowLanesTopFirst)  ?? (medianHeight * 1.05)
        // Cell dimensions = max(anchor-derived, lane-derived).
        // Lane spacing × fillFactor gives a "fits the lane" bound.
        // Vision anchors are systematically smaller than the real
        // card (~22% under-detection), so anchor × 1.15 gives an
        // "at-least the visible card" lower bound. Take the larger
        // so we don't lose card edges when rows have gaps.
        var cardHeight = max(rowSpacing * fillFactor, medianHeight * 1.15)
        var cardWidth  = max(colSpacing * fillFactor, medianWidth  * 1.15)
        // But don't EXCEED lane spacing (would overlap neighbors).
        cardHeight = min(cardHeight, rowSpacing * 0.98)
        cardWidth  = min(cardWidth,  colSpacing * 0.98)
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

/// Multi-pass OCR strategy: try several enhancement chains, take
/// the first one that extracts a cardNumber. After all passes fail,
/// MERGE every pass's observations and re-run cardNumber extraction
/// on the union — sometimes pass A finds the prefix and pass B
/// finds the digits separately.
func ocrCrop(_ image: CGImage, catalog: Catalog, label: String? = nil) async -> OCRResult {
    let passes = [
        // Standard
        (mt: Float(0.015), c: Float(1.25), g: Float(0.65), s: Float(0.5)),
        // Aggressive small text
        (mt: Float(0.005), c: Float(1.6),  g: Float(0.55), s: Float(1.0)),
        // High contrast for low-contrast bare cards
        (mt: Float(0.008), c: Float(2.0),  g: Float(0.75), s: Float(1.5)),
        // Lower gamma — for bright cards where standard pass blows
        // out the highlights
        (mt: Float(0.01),  c: Float(1.4),  g: Float(0.85), s: Float(0.8)),
    ]
    var allResults: [OCRResult] = []
    for p in passes {
        let r = await runOCRPass(
            image: image, catalog: catalog,
            minTextHeight: p.mt, contrast: p.c, gamma: p.g, sharpen: p.s
        )
        if r.cardNumber != nil { return r }
        allResults.append(r)
    }
    // No single pass found a cardNumber. Try a region-focused OCR
    // pass: crop the bottom-left badge area where the tiny
    // cardNumbers live on First-Edition cards, upscale, blast
    // contrast, OCR.
    let focused = await runFocusedBottomLeftOCR(image: image, catalog: catalog, label: label)
    if focused.cardNumber != nil { return focused }
    allResults.append(focused)

    // No single pass found a cardNumber. Merge all observations
    // and try once more — maybe the prefix and digits came from
    // different passes.
    var merged: [(text: String, midX: CGFloat, midY: CGFloat, conf: Float)] = []
    for r in allResults { merged.append(contentsOf: r.observations) }
    let allText = merged.map { $0.text }.joined(separator: " ")
    let blText = merged.filter { $0.midX < 0.5 && $0.midY < 0.5 }
        .map { $0.text }
        .joined(separator: " ")
    let extracted = extractCardNumber(from: blText, catalog: catalog, allowPureNumber: true)
                 ?? extractCardNumber(from: allText, catalog: catalog, allowPureNumber: false)
    let topLeftText = merged.filter { $0.midX < 0.5 && $0.midY > 0.5 }
        .map { $0.text }.joined(separator: " ")
    var matched: CatalogEntry?
    var finalCardNumber: String? = extracted
    if let num = extracted {
        let candidates = catalog.cards.filter { $0.cardNumber.uppercased() == num }
        matched = bestMatch(candidates: candidates, allText: allText, topLeftText: topLeftText)
    }
    // Hero-name fallback: when no cardNumber could be extracted but
    // OCR did find a recognizable hero name (Wattage's tiny badge
    // number is OCR-unreadable but "WATTAGE" reads cleanly at the
    // top of the card), match by hero + treatment + element + power.
    // Catalog entries with a unique hero hit win immediately;
    // otherwise we score and pick the best.
    if matched == nil {
        if let heroMatch = matchByHero(allText: allText, topLeftText: topLeftText, catalog: catalog) {
            matched = heroMatch
            finalCardNumber = heroMatch.cardNumber
        }
    }
    return OCRResult(
        cardNumber: finalCardNumber,
        allText: allText,
        bottomLeftText: blText,
        matched: matched,
        observations: merged
    )
}

/// Hero-name fallback: search the catalog for entries whose hero
/// name (or `name`) appears as a word in the OCR text. Score the
/// candidates by treatment and element matches against the same
/// OCR text. Returns nil if no hero word produces any catalog hit.
///
/// Used by Grid mode when the cardNumber on a specific card is
/// physically unreadable (tiny low-contrast text on First-Edition
/// cards), but the hero name at the top of the card is large and
/// clearly OCR-recognizable.
func matchByHero(allText: String, topLeftText: String, catalog: Catalog) -> CatalogEntry? {
    // OCR words that could plausibly be hero names. Filter out
    // obvious non-hero noise (FIRST, EDITION, BATTLE, ARENA, etc.).
    let stopWords: Set<String> = [
        "FIRST", "EDITION", "EDITON", "EDTON", "EDITVON", "EDITIDN",
        "BATTLE", "ARENA", "BATTTE", "TARENA", "POWER", "ROOKIE",
        "INSPIRED", "INSPIREO", "BATTLEFOIL", "BATTL", "BATTI",
        "GLOW", "HEX", "FIRE", "ICE", "BRAWL", "STEEL", "SUPER",
        "GUM", "SUM", "FRE", "JACKSON", "JAEKSON", "JACISON",
        "IRIKSON", "IAIKSUN", "IKSUN", "RKSON", "BO",
        "COST", "PLAY", "REVEAL", "REWARD", "DISCARD", "REBATE",
        "SHUFFLE", "HAND", "DECK", "PLAYBOOK", "HERO", "HEROS",
    ]
    // Combine all text words; prefer top-left (hero name lives there)
    let allWords = allText
        .components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
        .filter { $0.count >= 4 && !stopWords.contains($0) }
    let topLeftWords = topLeftText
        .components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
        .filter { $0.count >= 4 && !stopWords.contains($0) }
    // Score every catalog entry by how many heroish words match.
    // We score across all OCR text but give triple weight to the
    // top-left region where the hero name is printed.
    var best: (entry: CatalogEntry, score: Int) = (catalog.cards[0], -1)
    for entry in catalog.cards {
        let hero = (entry.hero ?? entry.name ?? "").uppercased()
        guard hero.count >= 4 else { continue }
        var score = 0
        // Direct word match — both hero and OCR word must overlap
        for w in allWords {
            if heroWordMatch(hero, w) { score += 1 }
        }
        for w in topLeftWords {
            if heroWordMatch(hero, w) { score += 3 }
        }
        if score > best.score { best = (entry, score) }
    }
    return best.score >= 1 ? best.entry : nil
}

/// True when a hero name and an OCR word appear to refer to the
/// same hero. Handles common OCR mistakes: prefix overlap (≥4
/// chars), single-character substitution, and joined-word splits
/// (PBBuckets vs PB BUCKETS).
func heroWordMatch(_ hero: String, _ word: String) -> Bool {
    if hero == word { return true }
    if hero.contains(word) { return true }   // PB BUCKETS contains BUCKETS
    if word.contains(hero) { return true }
    // Prefix overlap (≥4 chars). Handles WAITAGE/WATTAGE,
    // BROCK/BROCKNESS, etc.
    let minLen = min(hero.count, word.count)
    guard minLen >= 4 else { return false }
    let heroPref = String(hero.prefix(minLen))
    let wordPref = String(word.prefix(minLen))
    if heroPref == wordPref { return true }
    // 1-character difference within ≥5 char overlap (catches
    // WAITAGE ↔ WATTAGE, IGBF ↔ BGBF).
    if minLen >= 5 {
        let heroArr = Array(hero.prefix(minLen))
        let wordArr = Array(word.prefix(minLen))
        let diffs = zip(heroArr, wordArr).filter { $0 != $1 }.count
        if diffs <= 1 { return true }
    }
    return false
}

/// Binarize an image: convert to pure black/white based on a
/// luminance threshold. Useful for tiny low-contrast badge text
/// where standard contrast adjustment isn't enough — pushes the
/// signal-to-noise ratio for OCR.
func binarize(_ image: CGImage, invert: Bool = false) -> CGImage? {
    let ci = CIImage(cgImage: image)
        .applyingFilter("CIColorControls", parameters: [
            "inputSaturation": Float(0.0),
            "inputContrast":   Float(1.5),
        ])
    // Custom kernel via CIFilter would be ideal; CICategoryColorEffect
    // includes CIColorPosterize which limits color levels. Posterize
    // to 2 levels = black/white.
    let posterized = ci.applyingFilter("CIColorPosterize", parameters: [
        "inputLevels": Float(2.0)
    ])
    let final: CIImage
    if invert {
        final = posterized.applyingFilter("CIColorInvert")
    } else {
        final = posterized
    }
    return ciContext.createCGImage(final, from: final.extent)
}

/// Focused OCR pass for tiny horizontal cardNumbers printed in
/// colored badge tabs at the very bottom-left of the card. Some
/// First-Edition cards (Wattage 141, PB Buckets 7) put the number
/// inside a small colored rectangle that's only ~20-30 pixels tall
/// in the original crop. Standard OCR's minimumTextHeight rejects
/// it, and contrast normalization across the whole card crop
/// doesn't bring out the tiny number.
///
/// Strategy:
///   1. Tight crop — just the bottom-left badge area (15% × 12%).
///   2. Upscale 4×. Vision's text recognizer is much more reliable
///      on text that's 5%+ of image height; upscaling makes the
///      tiny badge text effectively that size.
///   3. Run OCR with very small minimumTextHeight + heavy contrast.
func runFocusedBottomLeftOCR(
    image: CGImage, catalog: Catalog, label: String? = nil
) async -> OCRResult {
    // Try several crop sizes — different cards put the badge tab
    // at slightly different positions/widths. First match wins.
    let cropFractions: [(xMax: CGFloat, yMin: CGFloat, yMax: CGFloat)] = [
        (0.20, 0.85, 1.00),  // tight badge zone
        (0.28, 0.80, 1.00),  // a bit wider
        (0.40, 0.75, 1.00),  // generous
    ]
    var best: OCRResult?
    for frac in cropFractions {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // CGImage uses TOP-LEFT origin. yMin/yMax are fractions
        // from the top; for the BOTTOM badge area we want yMin
        // close to 0.85 and yMax = 1.00 (i.e., the bottom 15%
        // of the card).
        let rect = CGRect(
            x: 0,
            y: h * frac.yMin,
            width:  w * frac.xMax,
            height: h * (frac.yMax - frac.yMin)
        )
        guard let bl = image.cropping(to: rect),
              let scaled = upscale(bl, factor: 4.0) else { continue }
        if let label = label {
            writeJPEG(scaled, to: "/tmp/grid_out/focus_\(label)_x\(Int(frac.xMax*100))y\(Int(frac.yMin*100)).jpg")
        }
        // Try a range of enhancement variants. Different badge tabs
        // have different background colors / contrast directions:
        //   - Wattage 141: dark text on LIGHT grey badge → gamma > 1
        //   - PB Buckets 7: light text on ORANGE badge → gamma < 1
        //   - Some Hot Dog cards: white text on dark
        // Lower minimumTextHeight 0.03 → 0.008 because tiny badge
        // text after 4× upscale still measures ~2% of the image
        // height.
        let variants: [(c: Float, g: Float, s: Float)] = [
            (3.0, 1.50, 2.5),   // dark-on-light, darken
            (3.0, 0.50, 2.5),   // light-on-dark, lighten
            (2.0, 1.20, 1.5),   // mild dark-on-light
            (2.0, 0.80, 1.5),   // mild light-on-dark
            (4.0, 1.80, 3.0),   // extreme dark-on-light
            (4.0, 0.40, 3.0),   // extreme light-on-dark
        ]
        for v in variants {
            let r = await runOCRPass(
                image: scaled, catalog: catalog,
                minTextHeight: 0.008,
                contrast: v.c, gamma: v.g, sharpen: v.s
            )
            if r.cardNumber != nil { return r }
            if best == nil || r.observations.count > (best?.observations.count ?? 0) {
                best = r
            }
        }
        // Binarized variants — last resort for tiny low-contrast
        // badge text. Tries both polarities (dark text on light,
        // light text on dark).
        for invert in [false, true] {
            guard let bin = binarize(scaled, invert: invert) else { continue }
            if let label {
                writeJPEG(bin, to: "/tmp/grid_out/focus_\(label)_bin\(invert ? "Inv" : "").jpg")
            }
            let r = await runOCRPass(
                image: bin, catalog: catalog,
                minTextHeight: 0.008,
                contrast: 1.0, gamma: 1.0, sharpen: 0.0
            )
            if r.cardNumber != nil { return r }
            if best == nil || r.observations.count > (best?.observations.count ?? 0) {
                best = r
            }
        }
    }
    return best ?? OCRResult(cardNumber: nil, allText: "", bottomLeftText: "",
                             matched: nil, observations: [])
}

/// Upscale a CGImage by `factor` using CILanczosScaleTransform —
/// gives better detail preservation than nearest-neighbor scaling
/// and makes small text more legible to OCR.
func upscale(_ image: CGImage, factor: CGFloat) -> CGImage? {
    let ci = CIImage(cgImage: image)
        .applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey:      Float(factor),
            kCIInputAspectRatioKey: Float(1.0),
        ])
    return ciContext.createCGImage(ci, from: ci.extent)
}

func runOCRPass(
    image: CGImage,
    catalog: Catalog,
    minTextHeight: Float,
    contrast: Float,
    gamma: Float,
    sharpen: Float
) async -> OCRResult {
    let ci = CIImage(cgImage: image)
        .applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
        .applyingFilter("CIColorControls", parameters: [
            "inputSaturation": Float(0.0),
            "inputContrast":   contrast,
        ])
        .applyingFilter("CIUnsharpMask", parameters: [
            "inputRadius":    Float(2.5),
            "inputIntensity": sharpen,
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
        req.minimumTextHeight = minTextHeight
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
        // For each character, list every plausible substitute (and
        // the char itself). Generates all combinations. The previous
        // pair-list approach broke on chars with multiple confusable
        // alternates: "I" could swap with "1" OR "B" but we only
        // generated one or the other depending on pair order, so
        // "IGBF" → "BGBF" never fired.
        let alternates: [Character: [Character]] = [
            "D": ["D", "O", "0"],
            "O": ["O", "D", "0"],
            "0": ["0", "O", "D"],
            "I": ["I", "1", "B", "L"],
            "1": ["1", "I", "L"],
            "L": ["L", "I", "1"],
            "B": ["B", "8", "Đ", "I"],
            "8": ["8", "B"],
            "Đ": ["Đ", "B"],
            "S": ["S", "5"],
            "5": ["5", "S"],
            "Z": ["Z", "2"],
            "2": ["2", "Z"],
            "G": ["G", "6"],
            "6": ["6", "G"],
            "Л": ["Л", "M"],
            "M": ["M", "N", "Л"],
            "N": ["N", "M"],
            "Q": ["Q", "O"],
        ]
        // Build per-position alternate lists. Chars not in the table
        // have just themselves.
        let perPosAlts: [[Character]] = s.map { ch in
            alternates[ch] ?? [ch]
        }
        // Cardinality cap — combinatorial explosion guard. With
        // typical 4-char prefix and ~3 alternates per char, max is
        // 81 variants. Capped at 256 just in case.
        var product = 1
        for alts in perPosAlts { product *= alts.count }
        guard product <= 256 else { return [s] }
        // Generate all combinations.
        var out: [[Character]] = [[]]
        for alts in perPosAlts {
            var next: [[Character]] = []
            for prev in out {
                for c in alts {
                    next.append(prev + [c])
                }
            }
            out = next
        }
        return out.map { String($0) }
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
                let r = await ocrCrop(cell.image, catalog: catalog,
                                       label: "\(basename)_r\(cell.row)c\(cell.column)")
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
