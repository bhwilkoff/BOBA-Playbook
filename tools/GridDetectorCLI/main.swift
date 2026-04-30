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
        var cells: [Cell] = []
        for (rowIdx, y) in rowLanesTopFirst.enumerated() {
            for (colIdx, x) in colLanesLeftFirst.enumerated() {
                let rect = CGRect(
                    x: x - medianWidth / 2,
                    y: y - medianHeight / 2,
                    width:  medianWidth,
                    height: medianHeight
                )
                cells.append(Cell(
                    row: rowIdx,
                    column: colIdx,
                    center: CGPoint(x: x, y: y),
                    rect: rect
                ))
            }
        }
        return GridGeometry(cells: cells, medianWidth: medianWidth, medianHeight: medianHeight)
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
    var cells: [DetectedCell] = []
    let tolerance = geometry.medianWidth / 2
    for cell in geometry.cells {
        let nearest = anchors.min { lhs, rhs in
            let l = CGPoint(x: lhs.boundingBox.midX, y: lhs.boundingBox.midY)
            let r = CGPoint(x: rhs.boundingBox.midX, y: rhs.boundingBox.midY)
            return distance(l, cell.center) < distance(r, cell.center)
        }
        if let nearest,
           distance(CGPoint(x: nearest.boundingBox.midX, y: nearest.boundingBox.midY), cell.center) < tolerance {
            if let cg = perspectiveCorrect(oriented: oriented, observation: nearest, bleed: params.bleed) {
                cells.append(DetectedCell(
                    row: cell.row, column: cell.column,
                    image: cg, confidence: nearest.confidence, synthesized: false
                ))
                continue
            }
        }
        if let cg = axisAlignedCrop(oriented: oriented, cellRect: cell.rect) {
            cells.append(DetectedCell(
                row: cell.row, column: cell.column,
                image: cg, confidence: 0, synthesized: true
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
        for a in result.anchors.prefix(20) {
            let aspect = a.boundingBox.width / a.boundingBox.height
            print(String(format: "  anchor conf=%.2f aspect=%.2f x=%.2f y=%.2f w=%.2f h=%.2f",
                         a.confidence, aspect,
                         a.boundingBox.midX, a.boundingBox.midY,
                         a.boundingBox.width, a.boundingBox.height))
        }
        // Save crops
        for cell in result.cells {
            let label = cell.synthesized ? "GRID" : String(format: "anchor%.2f", cell.confidence)
            let outPath = "\(outputDir)/\(basename)__r\(cell.row)c\(cell.column)_\(label).jpg"
            writeJPEG(cell.image, to: outPath)
        }
        // Annotated source overlay
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
