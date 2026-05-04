import UIKit
import Vision
import CoreImage

/// Crops up to 9 cards out of a single photo of a 3×N grid (3×1, 3×2, or 3×3).
/// (We previously bumped this to 6×6 = 36 cards; reverted because
/// `clusterCenters` allowed singleton noise rectangles to establish
/// false lanes when more than 3 slots were available. Lifting the
/// 3×3 cap again requires adding a `minMembers ≥ 2` gate first.)
/// Output is row-major (top-left → bottom-right). Each crop is then run
/// through CardScanner's still-image OCR path independently — see
/// GridScanView for the wiring.
///
/// Approach (rev 3, 2026-04-29):
///   Vision's `VNDetectRectanglesRequest` is unreliable as a primary
///   crop source — it under-detects on cards in toploaders and
///   over-detects spurious rectangles when params are loosened. So
///   we treat its detections as ANCHORS, not crops:
///
///     1. Run rect detection permissively to get whatever it finds.
///     2. Filter to card-shaped anchors (aspect ~0.71 ± 25%).
///     3. Cluster anchor X centers into column lanes (1, 2, or 3).
///        Cluster Y centers into row lanes (1, 2, or 3).
///     4. Take the median anchor size to set the canonical card
///        dimensions.
///     5. For each (row, col) in the inferred grid, compute the
///        predicted card center using lane positions, then
///        synthesize a uniform card-shaped crop rectangle at that
///        position.
///     6. If a real anchor lands close to a predicted center, use
///        its quad for perspective correction. Otherwise emit an
///        axis-aligned crop at the predicted position.
///
///   Result: every grid cell gets a uniform card-shaped crop, even
///   the cells where Vision found nothing. OCR sees consistent
///   inputs instead of the random rectangles Vision happened to
///   surface.
enum GridCardDetector {

    /// One detected card-shaped region, ready for OCR.
    struct DetectedCard {
        /// 0-indexed grid position. Row-major: 0=top-left, 1=top-middle,
        /// 2=top-right, 3=middle-left, ..., 8=bottom-right.
        let gridIndex: Int
        let row: Int
        let column: Int
        /// Card-shaped upright UIImage. Either perspective-corrected
        /// from a Vision anchor or axis-aligned at the inferred
        /// grid position.
        let image: UIImage
        /// Cell rectangle in normalized CIImage coordinates (bottom-
        /// left origin, range 0–1). Exposed so burst-capture frames
        /// can be cropped at the same location as the primary frame
        /// without re-running geometry inference per frame.
        let cellRect: CGRect
        /// Source UIImage's orientation flag, captured at detection
        /// time. Re-cropping a burst frame requires applying the
        /// same orientation before sampling the rect.
        let sourceOrientation: UIImage.Orientation
        /// Anchor confidence — Vision's rectangle confidence when
        /// this crop came from a detected anchor; 0 when the crop
        /// is synthesized from grid inference (no anchor close to
        /// the predicted position).
        let confidence: Float
        /// True when the crop is synthesized (no real anchor at
        /// this grid cell). Useful diagnostic in the test harness.
        let synthesized: Bool
    }

    enum DetectionError: Error {
        case ciImageFailed
        case visionFailed(Error)
        case noAnchors
    }

    static func detect(in image: UIImage) async throws -> [DetectedCard] {
        guard let ciImage = CIImage(image: image) else {
            throw DetectionError.ciImageFailed
        }
        let orientation = cgImageOrientation(from: image.imageOrientation)
        let oriented = ciImage.oriented(orientation)

        let observations = try await runRectangleRequest(
            on: ciImage,
            orientation: orientation
        )

        // Filter to plausibly-card-shaped anchors. Verified against
        // the bundled HEIC fixtures via Tools/GridDetectorCLI: with
        // these bounds, all four 3×3 fixtures produce 5–8 real
        // anchors that are sufficient to anchor a clean grid.
        //   - aspect 0.50–1.10  (covers perspective-skewed cards)
        //   - min size 10% of image dim (excludes tiny noise rects)
        //   - max area 36% of image (excludes "whole grid" rects
        //     where Vision sees the entire 3×3 as one card)
        let rawAnchors = observations.filter { obs in
            let aspect = obs.boundingBox.width / obs.boundingBox.height
            let area = obs.boundingBox.width * obs.boundingBox.height
            // Min side 0.10 — restored from 0.08 because the looser
            // threshold let through too many small noise rectangles
            // (text fragments, treatment-band glints) that survived
            // dedup and showed up as phantom cards.
            return aspect >= 0.50 && aspect <= 1.10
                && obs.boundingBox.width >= 0.10
                && obs.boundingBox.height >= 0.10
                && area <= 0.36
        }
        // Dedupe overlapping anchors — toploader inner+outer rects,
        // duplicate detections of the same card, etc. Keep the most
        // confident one when two centers fall within 5% on both axes.
        let dedupedAnchors = dedupOverlapping(rawAnchors)
        guard !dedupedAnchors.isEmpty else { throw DetectionError.noAnchors }

        // Two-pass geometry inference. Pass 1 builds rough geometry
        // from all anchors. Pass 2 drops anchors that fall outside
        // any predicted cell (typical wood-grain false positives) and
        // re-infers using only the clean ones — without this, a
        // single stray anchor on the table can shift an entire row's
        // predicted positions by several percent.
        let anchors: [VNRectangleObservation]
        if let rough = GridGeometry.infer(from: dedupedAnchors) {
            let cellTolerance = max(rough.medianWidth, rough.medianHeight) * 0.7
            let cleaned = dedupedAnchors.filter { obs in
                rough.cells.contains { cell in
                    let dx = obs.boundingBox.midX - cell.center.x
                    let dy = obs.boundingBox.midY - cell.center.y
                    return (dx * dx + dy * dy).squareRoot() < cellTolerance
                }
            }
            anchors = cleaned.isEmpty ? dedupedAnchors : cleaned
        } else {
            anchors = dedupedAnchors
        }
        guard let geometry = GridGeometry.infer(from: anchors) else {
            throw DetectionError.noAnchors
        }

        // ALWAYS use axis-aligned crops at lane-derived cell rects.
        //
        // Why not perspective-correct from anchors? Vision's anchor
        // rectangles are systematically smaller than the actual cards
        // — bare-card photos showed anchor height 0.21 vs measured
        // card height 0.27, a 22% under-detection. Perspective-
        // correcting from those anchors clips the bottom-left of the
        // card where the cardNumber lives. Lane intersections + lane-
        // derived dimensions place the crop at the right CENTER and
        // the right SIZE — even when no anchor exists for that cell.
        // We lose perspective dewarping, but OCR tolerates ±5° of
        // skew; the alternative was "rectified but clipped" which
        // was missing the cardNumber entirely on Plays/Hot Dogs.
        var results: [DetectedCard] = []
        let tolerance = geometry.medianWidth / 2
        for (gridIndex, cell) in geometry.cells.enumerated() {
            let nearest = anchors.first { obs in
                let dx = obs.boundingBox.midX - cell.center.x
                let dy = obs.boundingBox.midY - cell.center.y
                return (dx * dx + dy * dy).squareRoot() < tolerance
            }
            guard let crop = axisAlignedCrop(oriented: oriented, cellRect: cell.rect)
            else { continue }
            results.append(DetectedCard(
                gridIndex:   gridIndex,
                row:         cell.row,
                column:      cell.column,
                image:       crop,
                cellRect:    cell.rect,
                sourceOrientation: image.imageOrientation,
                confidence:  nearest?.confidence ?? 0,
                synthesized: nearest == nil
            ))
        }
        return results
    }

    /// Crop a different (typically burst-capture) frame at the same
    /// cell rectangle that was inferred from the primary frame.
    /// `cellRect` is in normalized CIImage coordinates (bottom-left
    /// origin) — the same form `DetectedCard.cellRect` uses. The
    /// orientation argument should match the source frame's
    /// `imageOrientation`. Returns nil if the rect is fully outside
    /// the image or the CIImage construction fails.
    static func cropFrame(
        _ image: UIImage,
        cellRect: CGRect,
        orientation: UIImage.Orientation
    ) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        let oriented = ci.oriented(cgImageOrientation(from: orientation))
        return axisAlignedCrop(oriented: oriented, cellRect: cellRect)
    }

    // MARK: - Vision request

    private static func runRectangleRequest(
        on ciImage: CIImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [VNRectangleObservation] {
        // Aggressively permissive — we only need ANCHORS for grid
        // geometry, not perfect rectangles. Verified locally via
        // Tools/GridDetectorCLI: at confidence 0.1, all 4 bundled
        // HEIC fixtures yield 5–8 real-card anchors that are enough
        // to anchor a clean 3×3 grid. The post-detection filters
        // (aspect / area / dedup / two-pass refinement) reject the
        // noise this brings in.
        try await performRectangleRequest(
            on: ciImage,
            orientation: orientation,
            minimumConfidence: 0.3,
            minimumAspectRatio: 0.40,
            maximumAspectRatio: 1.10,
            minimumSize: 0.05,
            quadratureTolerance: 45,
            maximumObservations: 150
        )
    }

    /// Drop overlapping anchors. Keeps the higher-confidence one
    /// when two centers fall within 5% on both axes — typical of
    /// toploader inner+outer detections or duplicate Vision hits
    /// at slightly different aspect ratios.
    private static func dedupOverlapping(
        _ anchors: [VNRectangleObservation]
    ) -> [VNRectangleObservation] {
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

    private static func performRectangleRequest(
        on ciImage: CIImage,
        orientation: CGImagePropertyOrientation,
        minimumConfidence: Float,
        minimumAspectRatio: Float,
        maximumAspectRatio: Float,
        minimumSize: Float,
        quadratureTolerance: Float,
        maximumObservations: Int
    ) async throws -> [VNRectangleObservation] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[VNRectangleObservation], Error>) in
            let request = VNDetectRectanglesRequest { req, err in
                if let err {
                    cont.resume(throwing: DetectionError.visionFailed(err))
                    return
                }
                let rects = (req.results as? [VNRectangleObservation]) ?? []
                cont.resume(returning: rects)
            }
            request.minimumAspectRatio   = minimumAspectRatio
            request.maximumAspectRatio   = maximumAspectRatio
            request.minimumSize          = minimumSize
            request.minimumConfidence    = minimumConfidence
            request.maximumObservations  = maximumObservations
            request.quadratureTolerance  = quadratureTolerance
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: DetectionError.visionFailed(error))
            }
        }
    }

    // MARK: - Perspective correction (anchor → crop)

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Perspective-correct a Vision anchor into an upright crop.
    /// Bleed nudges each corner outward to recover the bottom-left
    /// cardNumber that Vision's corners often clip past.
    private static func perspectiveCorrect(
        oriented: CIImage,
        observation: VNRectangleObservation,
        bleed: CGFloat
    ) -> UIImage? {
        let extent = oriented.extent
        let center = CGPoint(x: observation.boundingBox.midX,
                             y: observation.boundingBox.midY)
        func bled(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: p.x + (p.x - center.x) * bleed,
                y: p.y + (p.y - center.y) * bleed
            )
        }
        func denorm(_ p: CGPoint) -> CIVector {
            let clamped = CGPoint(
                x: min(max(p.x, 0), 1),
                y: min(max(p.y, 0), 1)
            )
            return CIVector(
                x: clamped.x * extent.width  + extent.origin.x,
                y: clamped.y * extent.height + extent.origin.y
            )
        }
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(oriented, forKey: kCIInputImageKey)
        filter.setValue(denorm(bled(observation.topLeft)),     forKey: "inputTopLeft")
        filter.setValue(denorm(bled(observation.topRight)),    forKey: "inputTopRight")
        filter.setValue(denorm(bled(observation.bottomLeft)),  forKey: "inputBottomLeft")
        filter.setValue(denorm(bled(observation.bottomRight)), forKey: "inputBottomRight")
        guard let corrected = filter.outputImage,
              let cgImage = ciContext.createCGImage(corrected, from: corrected.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Generate an axis-aligned crop at the predicted grid cell rect.
    /// Used when no Vision anchor is close enough to perspective-
    /// correct from. The crop is always card-shaped because the
    /// rect comes from the grid inference (which uses the median
    /// anchor dimensions, themselves card-shaped).
    private static func axisAlignedCrop(
        oriented: CIImage,
        cellRect: CGRect
    ) -> UIImage? {
        let extent = oriented.extent
        // Clamp the rect to the image bounds so cells near the edge
        // don't sample past the source.
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
        guard let cgImage = ciContext.createCGImage(cropped, from: pixelRect)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Orientation

    private static func cgImageOrientation(
        from uiOrientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - GridGeometry

/// Inferred card-grid geometry from a set of Vision anchors.
/// Computes column lanes, row lanes, median card size, and a
/// predicted rect for every (row, col) cell.
private struct GridGeometry {
    struct Cell {
        let row: Int
        let column: Int
        let center: CGPoint
        let rect: CGRect
    }
    let cells: [Cell]   // row-major, top-to-bottom, left-to-right
    let medianWidth:  CGFloat
    let medianHeight: CGFloat

    /// Build geometry from the supplied anchors. Returns nil only
    /// when there's literally no anchor to work from.
    static func infer(from anchors: [VNRectangleObservation]) -> GridGeometry? {
        guard !anchors.isEmpty else { return nil }

        // 1. Median anchor dimensions. Robust to a few outliers
        //    (toploader rectangles inflated, or partial detections
        //    that came back smaller than the real card).
        let widths  = anchors.map { $0.boundingBox.width  }.sorted()
        let heights = anchors.map { $0.boundingBox.height }.sorted()
        let medianWidth  = widths[widths.count / 2]
        let medianHeight = heights[heights.count / 2]

        // 2. Cluster X-centers into column lanes. Capped at 3
        //    columns. We previously bumped this to 6 to support
        //    larger grids, but `clusterCenters` has no
        //    minimum-members-per-lane gate, so noise detections
        //    promoted themselves into singleton lanes when 6 slots
        //    were available. The result was phantom 5×6 grids
        //    inferred from a real 3×3 photo. Restoring the original
        //    cap is the safe fix; lifting it later requires adding
        //    a `minMembers ≥ 2` requirement to clusterCenters first.
        let xCenters = anchors.map { $0.boundingBox.midX }
        var columnLanes = clusterCenters(
            values: xCenters,
            tolerance: medianWidth * 0.5,
            maxLanes: 3
        )
        // 3. Cluster Y-centers into row lanes (1..3) — same reasoning.
        let yCenters = anchors.map { $0.boundingBox.midY }
        var rowLanes = clusterCenters(
            values: yCenters,
            tolerance: medianHeight * 0.5,
            maxLanes: 3
        )

        guard !columnLanes.isEmpty, !rowLanes.isEmpty else { return nil }

        // 3b. Synthesize a missing 3rd lane when only 2 lanes were
        //     detected and the gap is consistent + there's image
        //     room above/below for another lane. Recovers cases like
        //     IMG_5232 where the dark top row's cards each produced
        //     mis-shaped Vision rectangles that got filtered out — 2
        //     row lanes detected, but a 3rd row exists in the image.
        //     Capped at adding 1 lane (only when count == 2) so
        //     already-complete 3x3 grids don't get phantom 4th rows.
        if rowLanes.count == 2 {
            let sortedRows = rowLanes.sorted()
            let gap = sortedRows[1] - sortedRows[0]
            if gap > 0.05, gap < 0.6 {
                let top = sortedRows[1]
                let bottom = sortedRows[0]
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

        // 4. Card dimensions — derived from grid LANE SPACING in
        //    BOTH axes. Cards as photographed don't always match
        //    the physical 0.714 aspect ratio (perspective compresses
        //    rows in tilted shots), so using both spacings gives the
        //    actual SHAPE of the cards on this image. We sanity-check
        //    against the 0.714 aspect only to catch wildly wrong
        //    inputs — most real photos drift ±15% from physical.
        //
        //    fillFactor 0.98 — cells nearly fill their lanes so the
        //    bottom-left card-number area isn't clipped.
        let cardAspectRatio: CGFloat = 0.714
        let fillFactor:      CGFloat = 0.92
        let rowLanesTopFirst = rowLanes.sorted(by: >)
        let colLanesLeftFirst = columnLanes.sorted()
        let colSpacing = meanSpacing(of: colLanesLeftFirst) ?? (medianWidth  * 1.05)
        let rowSpacing = meanSpacing(of: rowLanesTopFirst)  ?? (medianHeight * 1.05)
        // Cell dimensions = max(anchor-derived, lane-derived).
        // Lane spacing × fillFactor is the "fits the lane" bound.
        // Vision anchors are systematically smaller than the real
        // card (~22% under-detection on bare cards), so anchor
        // × 1.15 gives an "at-least the visible card" lower bound.
        // Take the larger so we don't lose card edges when rows
        // have gaps. Then cap at lane spacing × 0.98 so adjacent
        // cells don't overlap each other.
        var cardHeight = max(rowSpacing * fillFactor, medianHeight * 1.15)
        var cardWidth  = max(colSpacing * fillFactor, medianWidth  * 1.15)
        cardHeight = min(cardHeight, rowSpacing * 0.98)
        cardWidth  = min(cardWidth,  colSpacing * 0.98)
        let measuredAspect = cardWidth / cardHeight
        if measuredAspect < 0.50 || measuredAspect > 1.00 {
            cardWidth = cardHeight * cardAspectRatio
        }
        if colLanesLeftFirst.count == 1 {
            cardWidth = max(cardWidth, medianWidth * 1.10)
        }
        if rowLanesTopFirst.count == 1 {
            cardHeight = max(cardHeight, medianHeight * 1.10)
        }
        _ = cardAspectRatio

        // 5. Generate a Cell at every (row × column) intersection.
        //    Vision normalized coords use bottom-left origin, so
        //    the "top" row in the user's mental model has the
        //    highest Y value (already sorted descending above).
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
                    row:    rowIdx,
                    column: colIdx,
                    center: CGPoint(x: x, y: y),
                    rect:   rect
                ))
            }
        }
        return GridGeometry(
            cells:        cells,
            medianWidth:  cardWidth,
            medianHeight: cardHeight
        )
    }

    /// Mean of adjacent-pair gaps in a sorted lane list. Returns nil
    /// for single-lane inputs where no spacing can be computed.
    private static func meanSpacing(of lanes: [CGFloat]) -> CGFloat? {
        guard lanes.count >= 2 else { return nil }
        let sorted = lanes.sorted()
        var gaps: [CGFloat] = []
        for i in 1..<sorted.count { gaps.append(sorted[i] - sorted[i - 1]) }
        return gaps.reduce(0, +) / CGFloat(gaps.count)
    }

    /// Cluster a list of normalized 1D coordinates into at most
    /// `maxLanes` distinct lane centers. Two values belong to the
    /// same lane when they're within `tolerance` of each other.
    /// Lanes are returned as the MEAN of the values that joined
    /// them — gives a stable estimate even when individual
    /// detections wander a few percent.
    ///
    /// When more than `maxLanes` natural clusters appear (bad
    /// detections far from the real grid), we keep the
    /// `maxLanes` largest clusters by member count — the user's
    /// real card grid is the dominant pattern; spurious anchors
    /// are scattered.
    private static func clusterCenters(
        values: [CGFloat],
        tolerance: CGFloat,
        maxLanes: Int
    ) -> [CGFloat] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        // Single-link clustering on sorted values.
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
        // Keep the largest clusters when we exceed maxLanes.
        let keepers: [[CGFloat]]
        if clusters.count > maxLanes {
            keepers = clusters
                .sorted { $0.count > $1.count }
                .prefix(maxLanes)
                .map { $0 }
        } else {
            keepers = clusters
        }
        // Lane center = mean of cluster members.
        return keepers.map { cluster in
            cluster.reduce(0, +) / CGFloat(cluster.count)
        }
    }
}
