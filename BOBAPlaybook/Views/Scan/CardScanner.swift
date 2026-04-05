import AVFoundation
import Vision
import CoreImage

// MARK: - ScanObservation

/// All text extracted from one scan cycle, split by card corner region.
struct ScanObservation: Sendable {
    let cardNumber:   String   // primary identifier — bottom-left corner
    let rawName:      String   // top-left  — card title
    let rawPower:     String   // top-right — power number
    let rawVariation: String   // bottom-right — treatment / variation
    let fullText:     String   // all detected text joined
}

// MARK: - CardScanner

/// Manual AVFoundation + Vision pipeline.
///
/// Key design decisions:
///   • `usesLanguageCorrection = false` — prevents OCR from "correcting"
///     card identifiers like BF-208 into dictionary words.
///   • `customWords` — seeding Vision with all 17k card numbers as
///     domain vocabulary dramatically improves recognition accuracy.
///   • `regionOfInterest` — limits analysis to the card guide area.
///   • Catalog validation — extracted numbers must exist in the loaded catalog,
///     eliminating false positives from regex matches on non-card text.
///   • Pure-number fallback — Griffey Edition base cards use plain integers
///     (e.g. "102") with no alphabetic prefix; the regex cannot match these.
///     Bottom-left-only catalog lookup handles them safely.
///   • requiredConsecutive = 2 + miss counter — two consecutive catalog-valid
///     reads must agree; blurry frames (up to 3) don't reset confidence.
///   • Core Image preprocessing — grayscale + contrast + shadow lift improve
///     OCR on dark-background cards; highlight reduction helps with the
///     specular glare that appears when shooting straight down on glossy cards.
final class CardScanner: NSObject, @unchecked Sendable {

    // MARK: - Public

    var onCardObservation: ((ScanObservation) -> Void)?
    let captureSession = AVCaptureSession()

    // MARK: - Private — all mutable state accessed only on processingQueue

    private let processingQueue = DispatchQueue(
        label: "com.boba.scanner.processing",
        qos: .userInitiated
    )

    /// Array form for Vision's `customWords`.
    private var cardNumbers: [String] = []
    /// Set form for O(1) catalog validation on every processed frame.
    private var cardNumberSet: Set<String> = []

    private var regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    private var frameCounter      = 0
    private let frameSkip         = 5

    private var pendingCardNumber: String?
    private var consecutiveCount  = 0
    private let requiredConsecutive = 2   // two catalog-valid frames must agree

    private var missCount = 0
    private let maxMisses = 3             // tolerate 3 blurry/failed frames before reset

    private var lastReportedTime:  Date?
    private let reportCooldown:    TimeInterval = 2.0

    // MARK: - Regex

    /// Strict: exact card format — BF-208, GLBF-276, ALTA-01, RAD-104
    private static let strictRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#
        )
    }()

    /// Permissive: allows spaces around the separator — common OCR artifact.
    /// "BF 208" and "BF — 208" both normalise to "BF-208".
    private static let permissiveRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"#?([A-Z]{1,6})\s*[-–—]\s*([A-Z]?\d{1,4}(?:[/\-]\d{1,4})?)"#
        )
    }()

    // MARK: - Init

    override init() {
        super.init()
        configureCaptureSession()
    }

    // MARK: - Public API

    func setCardNumbers(_ numbers: [String]) {
        processingQueue.async { [weak self] in
            self?.cardNumbers   = numbers
            self?.cardNumberSet = Set(numbers)
        }
    }

    func updateROI(previewLayer: AVCaptureVideoPreviewLayer, guideRect: CGRect) {
        let md = previewLayer.metadataOutputRectConverted(fromLayerRect: guideRect)
        let roi = CGRect(
            x: md.origin.x,
            y: 1 - md.origin.y - md.height,
            width: md.width,
            height: md.height
        )
        processingQueue.async { [weak self] in
            self?.regionOfInterest = roi
        }
    }

    func start() {
        processingQueue.async { [captureSession] in
            guard !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    func stop() {
        processingQueue.async { [captureSession] in
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    func resetDetection() {
        processingQueue.async { [weak self] in
            self?.pendingCardNumber = nil
            self?.consecutiveCount  = 0
            self?.missCount         = 0
            self?.lastReportedTime  = nil
        }
    }

    func softReset() {
        processingQueue.async { [weak self] in
            self?.pendingCardNumber = nil
            self?.consecutiveCount  = 0
            self?.missCount         = 0
        }
    }

    // MARK: - AVCaptureSession setup

    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input  = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { captureSession.commitConfiguration(); return }

        captureSession.addInput(input)

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration(); return
        }
        captureSession.addOutput(output)

        if let conn = output.connection(with: .video),
           conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }

        captureSession.commitConfiguration()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CardScanner: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % frameSkip == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer)
    }

    // MARK: - Frame processing

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Preprocessing pipeline (GPU-executed lazily inside VNImageRequestHandler):
        //
        // 1. Gamma 0.65 — applies the curve output = input^0.65, which lifts
        //    dark values non-linearly. A card background at luma 0.10 becomes
        //    ~0.22; text at luma 0.40 becomes ~0.57. Bright values (0.9+) barely
        //    move. This is the most effective single step for dark-background
        //    cards and costs nothing for light cards.
        //
        // 2. Grayscale — removes color-channel noise from OCR edge detection.
        //    Colored text (blue/purple on dark) is normalised to a single
        //    brightness channel that Vision's text detector handles uniformly.
        //
        // 3. Contrast 1.25 — amplifies the edge gap between text and background
        //    after the gamma lift has separated them.
        //
        // 4. Unsharp mask — sharpens edges in the image. Helps Vision detect
        //    text boundaries on cards that are slightly out of focus, and
        //    recovers edge detail after the gamma brightening softens contrast.
        let enhanced = CIImage(cvPixelBuffer: pixelBuffer)
            .applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": Float(0.65),            // lifts darks without blowing lights
            ])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0),        // grayscale
                "inputContrast":   Float(1.25),       // contrast amplification
            ])
            .applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius":    Float(2.5),         // neighbourhood for edge detection
                "inputIntensity": Float(0.5),         // moderate sharpening
            ])

        let request = VNRecognizeTextRequest()
        request.recognitionLevel          = .accurate
        request.usesLanguageCorrection    = false
        request.recognitionLanguages      = ["en-US"]
        request.regionOfInterest          = regionOfInterest
        request.minimumTextHeight         = 0.015   // smaller than default 1/32 ≈ 3.1%
        if !cardNumbers.isEmpty {
            request.customWords = cardNumbers
        }

        let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return }

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

        // Extract and validate card number.
        //
        // Bottom-left is tried first with catalogFallback=true so that
        // purely-numeric card numbers (Griffey Edition base cards: "1", "102",
        // etc.) are detected. These can never match the letter-prefix regex;
        // catalog lookup is the only way to identify them.
        //
        // Full-frame is the fallback WITHOUT pure-number lookup — matching any
        // 1-4 digit number across the whole frame would hit power values, years,
        // and other false positives.
        let extracted = extractCardNumber(from: bottomLeftText, catalogFallback: true)
                     ?? extractCardNumber(from: fullText,       catalogFallback: false)

        guard let number = extracted,
              cardNumberSet.isEmpty || cardNumberSet.contains(number) else {
            missCount += 1
            if missCount >= maxMisses {
                pendingCardNumber = nil
                consecutiveCount  = 0
                missCount         = 0
            }
            return
        }

        missCount = 0

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

        DispatchQueue.main.async { [weak self] in
            self?.onCardObservation?(observation)
        }
    }

    // MARK: - Card number extraction

    /// Extracts a card number from `text` using two strategies:
    ///
    /// 1. Regex matching (strict then permissive) — handles all standard prefixed
    ///    formats: BF-208, GLBF-276, RAD-104, ALTA-01, etc.
    ///
    /// 2. Pure-number catalog lookup (`catalogFallback: true`, bottom-left only) —
    ///    handles sets like Griffey Edition whose base cards use plain integers.
    ///    Only numbers present in `cardNumberSet` are accepted, preventing false
    ///    matches against power values, years, and other numeric text on the card.
    private func extractCardNumber(from text: String, catalogFallback: Bool) -> String? {
        let range = NSRange(text.startIndex..., in: text)

        // 1. Strict: exact format with hyphen
        if let match = Self.strictRegex.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }

        // 2. Permissive: spaces/dashes around separator
        if let match  = Self.permissiveRegex.firstMatch(in: text, range: range),
           let pRange = Range(match.range(at: 1), in: text),
           let nRange = Range(match.range(at: 2), in: text) {
            return "\(text[pRange])-\(text[nRange])"
        }

        // 3. Pure-number catalog lookup — bottom-left quadrant only
        guard catalogFallback, !cardNumberSet.isEmpty else { return nil }

        for word in text.components(separatedBy: .whitespaces) {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard !clean.isEmpty,
                  clean.count >= 1, clean.count <= 4,
                  clean.allSatisfy({ $0.isNumber }),
                  cardNumberSet.contains(clean)
            else { continue }
            return clean
        }

        return nil
    }
}
