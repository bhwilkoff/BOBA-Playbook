// VisionOCR.swift
//
// Still-image OCR adapter. Reads a CGImage already cropped to a single
// card (5:7 portrait) and produces a ScanObservation by running
// VNRecognizeTextRequest and splitting the recognized text into corner
// quadrants matching the iOS CardScanner pipeline.
//
// This file is NEW (not mirrored). The iOS CardScanner ties OCR to live
// AVCaptureSession frames; we don't have or want that on the CLI side.
// Only the still-image OCR path is needed: the candidate images coming
// from R2 staging are already cropped + oriented + ready for Vision.

import Foundation
import Vision
import CoreImage
import CoreGraphics

enum VisionOCR {

    /// Run text recognition on `cgImage` and emit a ScanObservation
    /// with text split by corner quadrant. Quadrant logic mirrors
    /// CardScanner's iOS path:
    ///   • Vision returns boundingBox in normalized coords with
    ///     bottom-left origin
    ///   • midX < 0.5 → left half;     midY > 0.5 → top half
    ///   • → topLeft / topRight / bottomLeft / bottomRight
    ///
    /// `customWords` is the catalog's full cardNumberSet — passed to
    /// VNRecognizeTextRequest so OCR's language model biases toward
    /// known card numbers like "BLBF-208" rather than substituting
    /// dictionary words. Match the iOS behavior exactly.
    static func ocr(cgImage: CGImage,
                    customWords: [String]) -> ScanObservation {

        let request = VNRecognizeTextRequest()
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = ["en-US"]
        request.minimumTextHeight      = 0.015
        if !customWords.isEmpty {
            request.customWords = customWords
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ScanObservation(
                cardNumber:   "",
                rawName:      "",
                rawPower:     "",
                rawVariation: "",
                fullText:     "",
                cgImage:      cgImage
            )
        }

        guard let observations = request.results else {
            return ScanObservation(
                cardNumber:   "",
                rawName:      "",
                rawPower:     "",
                rawVariation: "",
                fullText:     "",
                cgImage:      cgImage
            )
        }

        var topLeft:     [String] = []
        var topRight:    [String] = []
        var bottomLeft:  [String] = []
        var bottomRight: [String] = []
        var all:         [String] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first,
                  candidate.confidence > 0.3 else { continue }
            let text = candidate.string.uppercased()
            all.append(text)

            switch (obs.boundingBox.midX < 0.5, obs.boundingBox.midY > 0.5) {
            case (true,  true):  topLeft.append(text)
            case (false, true):  topRight.append(text)
            case (true,  false): bottomLeft.append(text)
            case (false, false): bottomRight.append(text)
            }
        }

        let fullText       = all.joined(separator: " ")
        let bottomLeftText = bottomLeft.joined(separator: " ")

        // Pass bottom-left text as `cardNumber`. ScanMatching does its
        // own regex extraction + Levenshtein fuzzing from `fullText`,
        // so we don't need to pre-validate here. The hint helps when
        // the catalog cardNumber appears cleanly in the bottom-left.
        return ScanObservation(
            cardNumber:   bottomLeftText,
            rawName:      topLeft.joined(separator: " "),
            rawPower:     topRight.joined(separator: " "),
            rawVariation: bottomRight.joined(separator: " "),
            fullText:     fullText,
            cgImage:      cgImage
        )
    }

    /// Convenience: load an image file from disk and produce its
    /// CGImage. Returns nil on any read or decode failure.
    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return cg
    }
}
