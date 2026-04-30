import UIKit
import Vision
import CoreImage

/// Crops up to 9 cards out of a single photo of a 3×N grid (3×1, 3×2, or 3×3).
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

        // Generate uniform card-shaped crops at each predicted cell.
        var results: [DetectedCard] = []
        for (gridIndex, cell) in geometry.cells.enumerated() {
            // Find the closest anchor to this cell's predicted
            // center. If it's within tolerance, use its quad for
            // perspective correction (preserves any tilt visible
            // in the photo). Otherwise axis-align — still gives
            // OCR a card-shaped crop at the right spot.
            let nearestAnchor = anchors.min { lhs, rhs in
                let l = CGPoint(x: lhs.boundingBox.midX, y: lhs.boundingBox.midY)
                let r = CGPoint(x: rhs.boundingBox.midX, y: rhs.boundingBox.midY)
                return distance(l, cell.center) < distance(r, cell.center)
            }
            // Tolerance = half the median card half-width. Anything
            // farther than that is "too far to count as the same
            // card" and we use the synthesized axis-aligned crop.
            let tolerance = geometry.medianWidth / 2
            let crop: UIImage?
            let confidence: Float
            let synthesized: Bool
            if let anchor = nearestAnchor,
               distance(CGPoint(x: anchor.boundingBox.midX, y: anchor.boundingBox.midY), cell.center) < tolerance {
                crop = perspectiveCorrect(
                    oriented: oriented,
                    observation: anchor,
                    bleed: 0.04
                )
                confidence = anchor.confidence
                synthesized = false
            } else {
                crop = axisAlignedCrop(
                    oriented: oriented,
                    cellRect: cell.rect
                )
                confidence = 0
                synthesized = true
            }
            guard let crop else { continue }
            results.append(DetectedCard(
                gridIndex:   gridIndex,
                row:         cell.row,
                column:      cell.column,
                image:       crop,
                confidence:  confidence,
                synthesized: synthesized
            ))
        }
        return results
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
            minimumConfidence: 0.1,
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

        // 2. Cluster X-centers into 1, 2, or 3 column lanes. We
        //    cap at 3 columns because that's the largest grid the
        //    feature spec supports. Tolerance scales with the
        //    median card width — two anchors are in the same
        //    column lane when their X-centers are within half a
        //    card width.
        let xCenters = anchors.map { $0.boundingBox.midX }
        let columnLanes = clusterCenters(
            values: xCenters,
            tolerance: medianWidth * 0.5,
            maxLanes: 3
        )
        // 3. Cluster Y-centers into row lanes (1..3).
        let yCenters = anchors.map { $0.boundingBox.midY }
        let rowLanes = clusterCenters(
            values: yCenters,
            tolerance: medianHeight * 0.5,
            maxLanes: 3
        )

        guard !columnLanes.isEmpty, !rowLanes.isEmpty else { return nil }

        // 4. Card dimensions — derived from grid spacing, not from
        //    individual Vision anchors. Anchors are noisy: partial
        //    detections come back smaller than the real card; the
        //    "whole grid" detection gets filtered. Lane spacing
        //    averages over many anchors and is much more stable.
        //
        //    Trading cards are 2.5×3.5" → aspect ratio 0.714. We
        //    treat that as a HARD CONSTRAINT — every synthesized
        //    crop is sized to match exactly so OCR sees a properly
        //    proportioned card regardless of which anchors Vision
        //    happened to find.
        let cardAspectRatio: CGFloat = 0.714
        let fillFactor:      CGFloat = 0.95
        let rowLanesTopFirst = rowLanes.sorted(by: >)
        let colLanesLeftFirst = columnLanes.sorted()
        let colSpacing = meanSpacing(of: colLanesLeftFirst) ?? (medianWidth  * 1.05)
        let rowSpacing = meanSpacing(of: rowLanesTopFirst)  ?? (medianHeight * 1.05)
        // Row spacing is perpendicular to the cards' long axis and
        // less affected by perspective compression than column
        // spacing — use it as the primary height anchor, then
        // derive width from the aspect ratio.
        let cardHeight = rowSpacing * fillFactor
        var cardWidth  = cardHeight * cardAspectRatio
        // If aspect-ratio width exceeds available column spacing,
        // the grid is unusually tight — clamp so adjacent cells
        // don't overlap.
        cardWidth = min(cardWidth, colSpacing * fillFactor)

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
