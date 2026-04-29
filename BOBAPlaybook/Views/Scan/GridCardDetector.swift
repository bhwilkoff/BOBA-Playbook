import UIKit
import Vision
import CoreImage

/// Crops up to 9 cards out of a single photo of a 3×N grid (3×1, 3×2, or 3×3).
/// Output is row-major (top-left → bottom-right), perspective-corrected
/// to upright rectangles. Each crop is then run through CardScanner's
/// still-image OCR path independently — see GridScanView for the wiring.
///
/// Design constraints:
///   - The user is photographing physical cards laid on a table. Vision
///     framework's `VNDetectRectanglesRequest` finds card-shaped quads
///     directly; trading-card aspect ratio (2.5×3.5 = 0.71) is tight
///     enough that rectangle filtering rejects most non-card content.
///   - Cards in toploaders (clear plastic sleeves) project a slightly
///     larger rectangle than the card itself. We detect on the
///     toploader's outline and let the OCR pass tolerate the small
///     border — VNRecognizeTextRequest already shrugs off frame chrome.
///   - Photos can be taken at any angle; perspective correction is
///     applied so each crop is rectified before OCR.
///   - HEIC source images go through UIImage → CIImage cleanly without
///     extra format-specific handling.
enum GridCardDetector {

    /// One detected card-shaped region, ready for OCR.
    struct DetectedCard {
        /// 0-indexed grid position. Row-major: 0=top-left, 1=top-middle,
        /// 2=top-right, 3=middle-left, ..., 8=bottom-right. Skips
        /// indexes when fewer than 9 cards detected (e.g. a 3×2 grid
        /// produces gridIndex 0..5, all in the top two rows).
        let gridIndex: Int
        let row: Int
        let column: Int
        /// Perspective-corrected upright UIImage of just this card.
        let image: UIImage
        /// Original quad in normalized (0..1) image coords — useful for
        /// drawing the detected outline back over the source image.
        let quad: VNRectangleObservation
        /// Vision's rectangle-detection confidence (0..1). Surfaced so
        /// the test harness can correlate "OCR failed" cells with
        /// detector confidence to figure out whether OCR is failing
        /// on real cards or on weak/spurious detections.
        let confidence: Float
    }

    enum DetectionError: Error {
        case ciImageFailed
        case visionFailed(Error)
        case noRectangles
    }

    /// Detects up to 9 cards in `image` and returns them in row-major
    /// order. Throws when the input can't be converted to CIImage; an
    /// empty rectangle list returns `noRectangles` (the caller usually
    /// surfaces this as "couldn't find any cards — try again with
    /// better lighting").
    static func detect(in image: UIImage) async throws -> [DetectedCard] {
        guard let ciImage = CIImage(image: image) else {
            throw DetectionError.ciImageFailed
        }
        // Apply EXIF orientation so the detector sees the photo the way
        // the user shot it. Vision's normalized coords are top/bottom
        // sensitive to orientation; without this, a portrait photo
        // taken in landscape EXIF mode produces sideways crops.
        let orientation = cgImageOrientation(from: image.imageOrientation)

        let observations = try await runRectangleRequest(
            on: ciImage,
            orientation: orientation
        )
        guard !observations.isEmpty else { throw DetectionError.noRectangles }

        // Sort detected rectangles into 3-column grid order. Cluster
        // by Y first (rows), then sort columns within each row by X.
        let sorted = sortIntoGrid(observations)

        // Limit to 9 — the largest grid we promise to support — then
        // perspective-correct each. Order is preserved so gridIndex
        // matches the user's mental layout.
        var results: [DetectedCard] = []
        for (index, item) in sorted.prefix(9).enumerated() {
            if let cropped = perspectiveCorrect(
                ciImage: ciImage,
                observation: item.observation,
                orientation: orientation
            ) {
                results.append(DetectedCard(
                    gridIndex:  index,
                    row:        item.row,
                    column:     item.column,
                    image:      cropped,
                    quad:       item.observation,
                    confidence: item.observation.confidence
                ))
            }
        }
        return results
    }

    // MARK: - Vision request

    private static func runRectangleRequest(
        on ciImage: CIImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [VNRectangleObservation] {
        // First pass with reasonable confidence + a tight aspect-ratio
        // band. Only fall back when the primary pass returns fewer
        // rectangles than the largest grid we support (9). When
        // primary already finds 9+, the fallback would just inject
        // lower-quality rectangles that pollute downstream OCR —
        // observed in the 2026-04-29 fixture run where IMG_5229 went
        // from 9 detected → 9/9 detected but 4/9 matched because
        // a spurious mid-row rectangle clipped through two cards.
        let primary = try await performRectangleRequest(
            on: ciImage,
            orientation: orientation,
            minimumConfidence: 0.6,
            minimumAspectRatio: 0.50,
            maximumAspectRatio: 0.90,
            minimumSize: 0.05,
            quadratureTolerance: 30,
            maximumObservations: 30
        )
        if primary.count >= 9 {
            return primary
        }
        // Permissive fallback. Drops confidence to 0.3 and widens the
        // aspect-ratio window — picks up cards whose edges are low-
        // contrast against the background or whose perspective is
        // skewed enough to push them past the tight pass. Cards in
        // toploaders on glossy wood are the canonical failure mode
        // the first pass misses.
        let fallback = try await performRectangleRequest(
            on: ciImage,
            orientation: orientation,
            minimumConfidence: 0.3,
            minimumAspectRatio: 0.40,
            maximumAspectRatio: 1.00,
            minimumSize: 0.04,
            quadratureTolerance: 40,
            maximumObservations: 50
        )
        // Merge primary + fallback, deduplicating overlapping detections.
        // Primary's higher-confidence rectangles win ties via the
        // existing dedup pass downstream.
        return primary + fallback
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

    // MARK: - Grid sorting

    /// Cluster Y-positions into rows, then sort each row left-to-right.
    /// Vision returns observations in detector confidence order; we
    /// need them in reading order so each detected card's gridIndex
    /// matches the user's mental layout.
    private static func sortIntoGrid(
        _ observations: [VNRectangleObservation]
    ) -> [(observation: VNRectangleObservation, row: Int, column: Int)] {
        // Deduplicate — toploader-encased cards sometimes produce
        // overlapping inner+outer detections. Keep the higher-
        // confidence observation when two centers fall within 5% of
        // each other on both axes.
        let deduped = deduplicateOverlapping(observations)

        // Sort by Y descending. Vision normalized coords use the
        // bottom-left origin, so a higher Y means closer to the
        // top of the image — matching the user's "row 1" instinct.
        let byY = deduped.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        // Cluster into rows. Two observations belong to the same row
        // when their Y-centers are within `rowTolerance` of each
        // other. Tolerance is 0.10 (10% of image height) — wide
        // enough to absorb minor misalignment but tight enough to
        // distinguish three adjacent rows in a 3×3.
        let rowTolerance: CGFloat = 0.10
        var rows: [[VNRectangleObservation]] = []
        for obs in byY {
            if let lastRow = rows.last,
               let lastInRow = lastRow.first,
               abs(lastInRow.boundingBox.midY - obs.boundingBox.midY) < rowTolerance {
                rows[rows.count - 1].append(obs)
            } else {
                rows.append([obs])
            }
        }

        // Sort each row left-to-right and emit (observation, row, col).
        var output: [(observation: VNRectangleObservation, row: Int, column: Int)] = []
        for (rowIdx, row) in rows.enumerated() {
            let sortedCols = row.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
            for (colIdx, obs) in sortedCols.enumerated() {
                output.append((obs, rowIdx, colIdx))
            }
        }
        return output
    }

    private static func deduplicateOverlapping(
        _ observations: [VNRectangleObservation]
    ) -> [VNRectangleObservation] {
        // Keep observations sorted by descending confidence so the
        // higher-confidence one survives a duplicate pair. Threshold
        // tightened from 5% → 3% so the fallback (looser) pass's
        // rectangles aren't collapsed into the primary pass's
        // rectangles unless they're really at the same spot. In a
        // 3×3 grid each card center sits ~33% apart on each axis,
        // so 3% is comfortably tight enough to keep separate cards
        // separate but still merge inner/outer toploader detections.
        let byConfidence = observations.sorted { $0.confidence > $1.confidence }
        var kept: [VNRectangleObservation] = []
        for obs in byConfidence {
            let center = CGPoint(x: obs.boundingBox.midX, y: obs.boundingBox.midY)
            let isDuplicate = kept.contains { other in
                let dx = abs(other.boundingBox.midX - center.x)
                let dy = abs(other.boundingBox.midY - center.y)
                return dx < 0.03 && dy < 0.03
            }
            if !isDuplicate { kept.append(obs) }
        }
        return kept
    }

    // MARK: - Perspective correction

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Use the rectangle's four corners to perspective-correct it into
    /// an upright crop. Coordinates are denormalized to image space,
    /// then handed to CIPerspectiveCorrection. Each corner is pushed
    /// outward by `bleedPercent` along both axes so the OCR pass
    /// receives the full card edge — Vision's detected corners often
    /// land 1-2% inside the card border, which would otherwise clip
    /// the bottom-left card number we depend on for catalog lookup.
    private static func perspectiveCorrect(
        ciImage: CIImage,
        observation: VNRectangleObservation,
        orientation: CGImagePropertyOrientation
    ) -> UIImage? {
        // Apply EXIF orientation to the source so the corner points
        // (which are in the same orientation Vision reported) line
        // up with the pixel space CIPerspectiveCorrection samples.
        let oriented = ciImage.oriented(orientation)
        let extent = oriented.extent

        // 4% bleed = nudge each corner outward 4% of the rectangle
        // diagonal away from its center. Picked empirically: smaller
        // values still clipped card numbers on toploader-encased
        // cards (where the toploader inset eats a few percent of
        // the card edge); larger values started pulling neighboring
        // cards' edges into the crop.
        let bleed: CGFloat = 0.04
        let center = CGPoint(x: observation.boundingBox.midX,
                             y: observation.boundingBox.midY)
        func bled(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: p.x + (p.x - center.x) * bleed,
                y: p.y + (p.y - center.y) * bleed
            )
        }
        func denorm(_ p: CGPoint) -> CIVector {
            // Clamp to [0,1] before denorm so a card that already
            // sits flush against the image edge doesn't sample
            // beyond the source extent (which would produce black
            // bars and confuse OCR).
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
        guard let corrected = filter.outputImage else { return nil }
        guard let cgImage = ciContext.createCGImage(corrected, from: corrected.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Orientation

    /// Map UIImage.Orientation → CGImagePropertyOrientation. Vision
    /// uses the latter; UIImage carries the former. Without this
    /// translation, photos taken in portrait mode (which UIKit
    /// stamps as `.right`) get processed as if landscape — the
    /// detected rectangles come back rotated 90°.
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
}
