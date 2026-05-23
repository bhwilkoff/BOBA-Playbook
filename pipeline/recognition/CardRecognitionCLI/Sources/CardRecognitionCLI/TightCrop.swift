// TightCrop.swift
//
// Pre-recognition tight-crop step. eBay / BV listing photos
// arrive at variable aspect ratios (0.467 – 1.333 observed) — far from
// the 5:7 (~0.715) physical card shape. The catalog's feature prints
// were built on tight 5:7 crops, so feeding loose photos into Vision FP
// reduces recognition accuracy AND produces visually-inconsistent
// images when shipped to R2.
//
// This module:
//   1. Runs VNDetectRectanglesRequest with single-card-tuned params
//      (mirrors the iOS CardScanner live-scan rect detection)
//   2. Picks the largest card-shaped rectangle by confidence × area
//   3. Uses CIPerspectiveCorrection to rectify to a tight 5:7 output
//   4. Auto-rotates to portrait if the source was laid landscape
//   5. Falls back to a center 5:7 crop if Vision finds no rectangle
//
// Output size: 700×980 (5:7 exact). High enough that downstream resize
// to the 1200-px production tier doesn't lose quality; small enough that
// the staged tight-crop file stays under 100 KB at JPEG-90.

import Foundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum TightCrop {

    /// Output dims for the tight crop. 700×980 = exact 5:7 portrait.
    /// Downstream Stage C resize handles the 1200-px production tier.
    static let outputWidth:  Int = 700
    static let outputHeight: Int = 980

    /// JPEG quality for the staging tight-crop file. 0.9 = visually
    /// indistinguishable from source at <100 KB per crop.
    static let jpegQuality: CGFloat = 0.9

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Run rect detection + perspective correction on `input`. Writes
    /// the tight-cropped JPEG to `outputURL`. Returns the dimensions
    /// of the input rectangle that was used (for diagnostics) or nil
    /// if we fell back to the center-crop path.
    static func tightCrop(input: CGImage, to outputURL: URL) -> CroppedImageInfo {
        // ─── Try Vision rectangle detection first ──
        let request = VNDetectRectanglesRequest()
        // Run Vision with permissive aspect — we'll filter to bare-card
        // shape AFTER detection, so we can also see the slab vs the
        // card inside it (Vision sometimes returns both for graded
        // PSA/BGS cases). The post-filter step picks the card-shaped
        // rect, not the slab.
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 1.50
        request.minimumSize        = 0.20
        request.minimumConfidence  = 0.4
        request.maximumObservations = 8
        request.quadratureTolerance = 30

        let handler = VNImageRequestHandler(cgImage: input, options: [:])
        var rectangles: [VNRectangleObservation] = []
        if (try? handler.perform([request])) != nil,
           let results = request.results {
            rectangles = results
        }

        // Pick the best rectangle: highest (confidence × area). Slab
        // detection happens AFTER perspective correction (via OCR on
        // the rectified top region) — aspect alone can't distinguish
        // slabs from cards because PSA/BGS/SGC slabs are all in the
        // 0.69-0.74 aspect range, identical to bare cards.
        let best = rectangles.max { a, b in
            let aArea = a.boundingBox.width * a.boundingBox.height
            let bArea = b.boundingBox.width * b.boundingBox.height
            return CGFloat(a.confidence) * aArea < CGFloat(b.confidence) * bArea
        }

        if let rect = best {
            if let cropped = perspectiveCorrect(input: input, observation: rect) {
                // Slab detection: the rectangle's outer aspect (~0.71)
                // is identical for a bare card and for a PSA/BGS/SGC
                // graded slab — both are 2.5×3.5-ish proportions. The
                // distinguishing signal is the GRADING LABEL inside
                // the top of the slab. OCR the top 25% of the
                // rectified image; if any grading-related keyword is
                // present, mark this candidate as slab_rejected so it
                // can't pass the AUTO gate (which requires
                // crop_method == 'vision_rect').
                let isSlab = detectSlab(in: cropped)
                writeJPEG(cropped, to: outputURL)
                return CroppedImageInfo(
                    method: isSlab ? .slabRejected : .visionRectangle,
                    sourceRectArea: Double(rect.boundingBox.width * rect.boundingBox.height),
                    sourceConfidence: rect.confidence
                )
            }
        }

        // ─── Fallback: center 5:7 crop ──
        // Better than emitting the loose source. Recognition quality on
        // these will be lower; we mark them so downstream stages can
        // route them differently if we ever care to.
        if let cropped = centerCrop57(input: input) {
            writeJPEG(cropped, to: outputURL)
            return CroppedImageInfo(
                method: .centerFallback,
                sourceRectArea: 0,
                sourceConfidence: 0
            )
        }

        // ─── Final fallback: write the source image unchanged ──
        // Should be exceedingly rare (only on bizarrely-shaped inputs);
        // ensures the pipeline never drops a candidate due to crop
        // failure.
        writeJPEG(input, to: outputURL)
        return CroppedImageInfo(
            method: .uncroppedFallback,
            sourceRectArea: 0,
            sourceConfidence: 0
        )
    }

    // MARK: - Slab detection
    //
    // PSA/BGS/SGC/CGC graded slabs have outer aspect (~0.71) identical
    // to a bare card, so rectangle-shape filtering can't tell them
    // apart. The reliable signal is the GRADING LABEL printed at the
    // top of the slab (PSA blue, BGS black, SGC white, etc.) — a tight
    // band of uppercase text declaring the grade.
    //
    // After perspective correction we OCR the top 25% of the rectified
    // image and check for any grading-language keyword. Hits → mark as
    // slab_rejected → can't pass the AUTO gate (which requires
    // crop_method == 'vision_rect').
    //
    // The keyword list intentionally includes both grading-company
    // names AND grade-vocabulary so we catch slabs even when the
    // company logo OCRs imperfectly. Edge cases that might falsely
    // hit (a card whose name contains "MINT" etc.) are extremely
    // rare in the BoBA catalog — the false-positive risk is much
    // lower than the cost of letting slabs through.

    private static let slabKeywords: [String] = [
        // Grading-company brands
        "PSA",  "BGS",  "SGC",  "CGC",  "BVG",  "TAG",
        "CCG",  "GMA",  "ISA",  "AGS",  "HGA",  "PGS",
        // Grade vocabulary
        "GEM MT",   "GEM-MT",   "GEM MINT",
        "MINT",     "NM-MT",    "NEAR MINT",
        "PRISTINE", "GRADED",   "AUTHENTIC",
        // Cert/population/subgrade text on slab labels
        "POPULATION", "SUBGRADE", "CENTERING",
        "SURFACE",    "EDGES",    "CORNERS",
    ]

    private static func detectSlab(in cgImage: CGImage) -> Bool {
        // Crop top 25% — grading labels live in the top band of slabs
        let topHeight = max(1, cgImage.height / 4)
        let topRect = CGRect(x: 0, y: 0, width: cgImage.width, height: topHeight)
        guard let topImage = cgImage.cropping(to: topRect) else { return false }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = ["en-US"]
        request.minimumTextHeight      = 0.02   // grading labels are decent-sized

        let handler = VNImageRequestHandler(cgImage: topImage, options: [:])
        do { try handler.perform([request]) } catch { return false }
        guard let results = request.results else { return false }

        // Concatenate all OCR text from the top region. Grading labels
        // are short uppercase strings split across multiple text
        // observations ("PSA" + "10" + "GEM MT" etc.); concatenation
        // catches multi-token matches like "GEM MT" that wouldn't
        // appear in a single observation.
        let allText = results
            .compactMap { $0.topCandidates(1).first?.string.uppercased() }
            .joined(separator: " ")

        for keyword in slabKeywords {
            if allText.contains(keyword) { return true }
        }
        return false
    }

    // MARK: - Perspective correction

    private static func perspectiveCorrect(
        input: CGImage,
        observation: VNRectangleObservation
    ) -> CGImage? {
        let imgW = CGFloat(input.width)
        let imgH = CGFloat(input.height)

        // Vision returns corners in normalized coords with BOTTOM-LEFT
        // origin. CIPerspectiveCorrection expects points in IMAGE coords
        // with bottom-left origin too — same convention, scale up.
        func toImagePoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * imgW, y: p.y * imgH)
        }
        let topLeft     = toImagePoint(observation.topLeft)
        let topRight    = toImagePoint(observation.topRight)
        let bottomLeft  = toImagePoint(observation.bottomLeft)
        let bottomRight = toImagePoint(observation.bottomRight)

        let ciImage = CIImage(cgImage: input)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }
        filter.setValue(ciImage,                  forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft),     forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight),    forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft),  forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let output = filter.outputImage else { return nil }

        // Render to a CGImage, then resize to exact 5:7. If the rectified
        // image is landscape (card was photographed sideways), rotate to
        // portrait first.
        guard let rendered = ciContext.createCGImage(output, from: output.extent) else {
            return nil
        }

        let portrait = (rendered.width >= rendered.height)
            ? rotate90(rendered) ?? rendered
            : rendered

        return resize(portrait, to: outputWidth, height: outputHeight)
    }

    // MARK: - Center crop fallback

    private static func centerCrop57(input: CGImage) -> CGImage? {
        let imgW = CGFloat(input.width)
        let imgH = CGFloat(input.height)
        let targetAR: CGFloat = CGFloat(outputWidth) / CGFloat(outputHeight)  // 0.7142...
        let sourceAR = imgW / imgH

        var cropW: CGFloat
        var cropH: CGFloat
        if sourceAR > targetAR {
            // Source is wider than 5:7 — crop horizontally
            cropH = imgH
            cropW = imgH * targetAR
        } else {
            // Source is narrower — crop vertically
            cropW = imgW
            cropH = imgW / targetAR
        }
        let x = (imgW - cropW) / 2
        let y = (imgH - cropH) / 2
        let rect = CGRect(x: x, y: y, width: cropW, height: cropH).integral
        guard let cropped = input.cropping(to: rect) else { return nil }
        return resize(cropped, to: outputWidth, height: outputHeight)
    }

    // MARK: - Helpers

    private static func rotate90(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        // CGImagePropertyOrientation.right = 90° clockwise (which gives
        // us portrait from landscape source where the top of the card
        // is on the right)
        let rotated = ci.oriented(.right)
        return ciContext.createCGImage(rotated, from: rotated.extent)
    }

    private static func resize(_ image: CGImage, to width: Int, height: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        let opts: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// Diagnostic info emitted to stderr per-candidate for observability.
struct CroppedImageInfo {
    enum Method: String {
        case visionRectangle    = "vision_rect"
        case centerFallback     = "center_57"
        case uncroppedFallback  = "uncropped"
        case slabRejected       = "slab_rejected"
    }
    let method: Method
    let sourceRectArea: Double      // 0..1 normalized; 0 if not vision_rect
    let sourceConfidence: Float     // 0..1; 0 if not vision_rect
}
