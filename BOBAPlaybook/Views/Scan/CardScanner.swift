import AVFoundation
import Vision
import Foundation

// MARK: - ScanObservation

/// All text extracted from one scan cycle, split by card corner region.
/// `fullText` contains every word Vision found — used for matching when
/// a field doesn't land cleanly in its expected quadrant.
struct ScanObservation: Sendable {
    let cardNumber: String   // primary identifier — from bottom-left or full frame
    let rawName: String      // top-left region   — card title
    let rawPower: String     // top-right region  — power number
    let rawVariation: String // bottom-right      — treatment / variation
    let fullText: String     // all detected text joined
}

// MARK: - CardScanner

/// Manages the AVCaptureSession and Vision OCR pipeline for card scanning.
///
/// Thread model:
/// - `processingQueue` owns all AVFoundation and Vision work.
/// - `onCardObservation` is always dispatched to the main queue before calling.
/// - Mutable stability-tracking state is only accessed on `processingQueue`.
///
/// Swift 6: `@unchecked Sendable` — internal thread safety via serial `processingQueue`.
final class CardScanner: NSObject, @unchecked Sendable {

    // MARK: - Public

    /// Called on the main queue when a card has been stably detected.
    nonisolated(unsafe) var onCardObservation: ((ScanObservation) -> Void)?

    /// Normalized region of interest for Vision. Set before calling start().
    /// Defaults to the full frame.
    nonisolated(unsafe) var regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    let captureSession = AVCaptureSession()

    // MARK: - Private (all accessed only on processingQueue — safe via @unchecked Sendable)

    private let processingQueue = DispatchQueue(
        label: "com.bobaplaybook.scanner.processing",
        qos: .userInitiated
    )

    nonisolated(unsafe) private var pendingCardNumber: String?
    nonisolated(unsafe) private var consecutiveCount  = 0
    private let requiredConsecutive = 2
    nonisolated(unsafe) private var lastReportedTime: Date?
    private let reportCooldown: TimeInterval = 2.0

    // MARK: - Diagnostics (remove when scan is confirmed working)
    nonisolated(unsafe) private var diagFrameCount = 0

    private static let cardNumberRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#
        )
    }()

    // MARK: - Setup

    func configure() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input  = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
    }

    func start() {
        processingQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    func resetDetection() {
        processingQueue.async { [weak self] in
            self?.pendingCardNumber = nil
            self?.consecutiveCount  = 0
            self?.lastReportedTime  = nil
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CardScanner: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        diagFrameCount += 1
        let shouldLog = diagFrameCount % 60 == 1   // log once per ~2 sec at 30fps
        if shouldLog { print("SCAN▶︎ frame \(diagFrameCount), roi=\(regionOfInterest)") }

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            self?.processObservations(req)
        }
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = ["en-US"]
        request.minimumTextHeight      = 0.02   // catch small card numbers near bottom edge
        request.regionOfInterest       = regionOfInterest

        try? VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        ).perform([request])
    }

    private func processObservations(_ request: VNRequest) {
        let shouldLog = diagFrameCount % 60 == 1
        guard let obs = request.results as? [VNRecognizedTextObservation] else {
            if shouldLog { print("SCAN▶︎ no VNRecognizedTextObservation results") }
            return
        }
        if shouldLog { print("SCAN▶︎ \(obs.count) observations") }

        // Vision coordinates after orientation: .right correction:
        //   (0,0) = bottom-left   (1,1) = top-right   y increases upward
        //
        // Card corners (card centred in guide frame, ~x:0.22-0.78, y:0.32-0.68):
        //   name      → top-left    x < 0.5, y ≥ 0.5
        //   power     → top-right   x ≥ 0.5, y ≥ 0.5
        //   cardNum   → bot-left    x < 0.5, y < 0.5
        //   variation → bot-right   x ≥ 0.5, y < 0.5

        var topLeft:     [String] = []
        var topRight:    [String] = []
        var bottomLeft:  [String] = []
        var bottomRight: [String] = []
        var all:         [String] = []

        for ob in obs {
            guard let text = ob.topCandidates(1).first?.string, !text.isEmpty else { continue }
            let upper = text.uppercased()
            all.append(upper)

            let box = ob.boundingBox
            // Soft filter: exclude only extreme frame edges unlikely to be card text
            guard box.midX > 0.05 && box.midX < 0.95 &&
                  box.midY > 0.05 && box.midY < 0.95 else { continue }

            switch (box.midX < 0.5, box.midY >= 0.5) {
            case (true,  true):  topLeft.append(upper)
            case (false, true):  topRight.append(upper)
            case (true,  false): bottomLeft.append(upper)
            case (false, false): bottomRight.append(upper)
            }
        }

        let fullText       = all.joined(separator: " ")
        let bottomLeftText = bottomLeft.joined(separator: " ")

        if shouldLog {
            print("SCAN▶︎ fullText: \"\(fullText)\"")
            print("SCAN▶︎ bottomLeft: \"\(bottomLeftText)\"")
        }

        // Card number: bottom-left quadrant first, full frame as fallback
        guard let number = Self.extractCardNumber(from: bottomLeftText)
                        ?? Self.extractCardNumber(from: fullText) else {
            if shouldLog { print("SCAN▶︎ no card number matched regex in frame \(diagFrameCount)") }
            pendingCardNumber = nil
            consecutiveCount  = 0
            return
        }
        print("SCAN▶︎ card number candidate: \(number) (consecutive: \(consecutiveCount+1))")

        if number == pendingCardNumber {
            consecutiveCount += 1
        } else {
            pendingCardNumber = number
            consecutiveCount  = 1
        }

        guard consecutiveCount >= requiredConsecutive else { return }

        let now = Date()
        if let last = lastReportedTime, now.timeIntervalSince(last) < reportCooldown { return }
        lastReportedTime = now
        consecutiveCount = 0

        let observation = ScanObservation(
            cardNumber:   number,
            rawName:      topLeft.joined(separator: " "),
            rawPower:     topRight.joined(separator: " "),
            rawVariation: bottomRight.joined(separator: " "),
            fullText:     fullText
        )

        let handler = onCardObservation
        DispatchQueue.main.async { handler?(observation) }
    }

    private static func extractCardNumber(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = cardNumberRegex.firstMatch(in: text, range: range) else { return nil }
        return Range(match.range(at: 1), in: text).map { String(text[$0]) }
    }
}
