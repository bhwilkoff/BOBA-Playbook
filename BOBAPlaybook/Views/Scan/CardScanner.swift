import AVFoundation
import Vision
import CoreImage
import Accelerate
import UIKit

// MARK: - ScanObservation

/// All text extracted from one scan cycle, split by card corner region.
///
/// `cgImage` is the cropped guide region from the frame that produced
/// this observation. Phase 2 image-similarity disambiguation reads from
/// it when OCR scoring is borderline. CGImage is immutable and Sendable
/// in Swift 6 — safe to ferry across actor boundaries.
struct ScanObservation: @unchecked Sendable {
    let cardNumber:   String   // primary identifier — bottom-left corner
    let rawName:      String   // top-left  — card title
    let rawPower:     String   // top-right — power number
    let rawVariation: String   // bottom-right — treatment / variation
    let fullText:     String   // all detected text joined
    let cgImage:      CGImage? // for image-similarity tiebreak (Phase 2)
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

    /// Concurrent queue for grid-mode OCR work. `processingQueue` is
    /// serial because live scan's `processFrame` mutates state
    /// (pendingCardNumber, consecutiveCount, missCount,
    /// lastReportedTime) and would race with itself if those calls
    /// ran concurrently. Grid scan is different: by the time
    /// `scanGridImage` is called the customWordsCache is fully
    /// populated (the caller drains via `awaitVocabularyReady`) and
    /// nothing further mutates it, so multiple grid-cell OCR passes
    /// can run on parallel threads safely. Without this lane all 9
    /// cells in a TaskGroup would serialize behind one another on
    /// the processing queue and the grid TaskGroup's parallelism
    /// would be effectively wasted on the OCR step.
    private let gridOCRQueue = DispatchQueue(
        label: "com.boba.scanner.grid-ocr",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Array form for Vision's `customWords` — card numbers only.
    private var cardNumbers: [String] = []
    /// Set form for O(1) catalog validation on every processed frame.
    private var cardNumberSet: Set<String> = []
    /// Card NAMES (heroes + play titles) — second source of customWords.
    /// Lets Vision lock onto "MAHOMES" instead of inventing "MERLOMES",
    /// "ROLLER DOGS" instead of arbitrary text, etc. Compiled into a
    /// merged customWords array on every request so the scanner can
    /// rebuild on the fly when the catalog finishes loading.
    private var vocabularyNames: [String] = []
    /// Memoized merged customWords array (numbers + names). Recomputed
    /// only when either source changes. Guards against per-frame
    /// allocation of a 17k-entry array.
    private var customWordsCache: [String] = []

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

    /// Strict: card format with an OPTIONAL separator — covers both the
    /// hyphenated catalog convention (BF-208, GLBF-276, ALTA-01) AND hyphen-less
    /// sets like Tecmo Bowl Edition (BF1, SF72, JE43), which the cards print and
    /// the catalog stores without a hyphen. The catalog-validation gate in
    /// extractCardNumber keeps the looser pattern from inventing numbers — only
    /// candidates present in cardNumberSet are returned. Verified on the real
    /// Vision pathway via tools/ocr_probe.swift against the Tecmo art: alpha
    /// card-number reads went 0→17 of 25, zero regression on hyphenated cards.
    private static let strictRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"#?([A-Z]{1,6}-?[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#
        )
    }()

    /// Permissive: allows spaces around the separator — common OCR artifact.
    /// "BF 208" and "BF — 208" both normalise to "BF-208".
    private static let permissiveRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"#?([A-Z]{1,6})\s*[-–—]\s*([A-Z]?\d{1,4}(?:[/\-]\d{1,4})?)"#
        )
    }()

    /// Letter→digit substitutions for OCR glyph confusions.
    ///
    /// Vision frequently misreads stylized digits as visually-similar
    /// letters: the leading "1" on a 1XX power becomes "I" or "l", "0"
    /// becomes "O", "5" becomes "S", "8" becomes "B". Catalog audit
    /// (see scripts/deep_ocr_pass.swift) confirmed this happens in
    /// hundreds of cards on stylized treatments. Without this layer
    /// the scanner can't match `"BLBF-I95"` against `"BLBF-195"` even
    /// though it's clearly the same card.
    ///
    /// Applied ONLY to the digit-side of a cardNumber (after the
    /// hyphen) and ONLY when all primary regex strategies have
    /// already failed — the strict and permissive regex paths run
    /// first on the raw text, so a clean read never reaches this
    /// layer. Letter-side substitution (e.g. "B" → "8" in a prefix)
    /// is intentionally NOT applied: it would corrupt valid prefixes
    /// like `"BLBF"` into `"8L8F"`.
    private static let digitSubs: [Character: Character] = [
        // Words are uppercased before substitution, so only uppercase
        // and symbol forms need entries here (lowercase forms will
        // never appear). Pipe `|` is a Vision-specific failure mode
        // for the digit "1" on certain stylized fonts.
        "I": "1", "L": "1", "|": "1",
        "O": "0",
        "S": "5",
        "B": "8",
    ]

    /// Apply letter→digit substitution to a string. Returns the
    /// substituted result and a flag indicating whether anything
    /// changed (callers skip the catalog lookup when no substitution
    /// occurred — saves a hash lookup on the common case).
    private static func substituteToDigits(_ s: String) -> (substituted: String, changed: Bool) {
        var changed = false
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if let sub = digitSubs[ch] {
                out.append(sub)
                changed = true
            } else {
                out.append(ch)
            }
        }
        return (out, changed)
    }

    /// Cyrillic homoglyph → Latin substitution. Vision occasionally
    /// outputs Cyrillic letters when its model is uncertain about
    /// stylized cards — "BHBF-57" reads as "ВЖBF-57" with cyrillic В
    /// (looks like Latin B) and Ж (no Latin equivalent). Normalizing
    /// the homoglyphs before regex extraction lets the catalog match
    /// these reads.
    private static let cyrillicSubs: [Character: Character] = [
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H",
        "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X", "У": "Y",
        "І": "I", "Ј": "J", "Ѕ": "S",
        // Lowercase cyrillic for completeness (uppercased upstream
        // strips most, but Ж/ж have no uppercase Latin equivalent).
        "а": "A", "е": "E", "о": "O", "р": "P", "с": "C", "у": "Y",
        "х": "X",
    ]

    private static func normalizeCyrillic(_ s: String) -> String {
        guard s.contains(where: { cyrillicSubs.keys.contains($0) }) else { return s }
        return String(s.map { cyrillicSubs[$0] ?? $0 })
    }

    /// Shared CIContext for one-shot CGImage rendering on commit.
    /// Single static instance avoids the per-render setup cost of the
    /// internal Metal command queue.
    private static let ciContext: CIContext = {
        CIContext(options: [.useSoftwareRenderer: false])
    }()

    // MARK: - Init

    override init() {
        super.init()
        configureCaptureSession()
    }

    // MARK: - Public API

    func setCardNumbers(_ numbers: [String]) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.cardNumbers   = numbers
            self.cardNumberSet = Set(numbers)
            self.rebuildCustomWordsCache()
        }
    }

    /// Seed Vision with hero + play card names. Improves OCR for cards
    /// whose printed text shares glyphs with adjacent vocabulary
    /// ("MAHOMES" was being read as "MERLOMES" before this; "ROLLER
    /// DOGS" was getting truncated). Names are uppercased, deduped,
    /// and any 2-or-fewer-character entries are dropped — Vision's
    /// vocab boost is meaningless for words shorter than that and
    /// just inflates the customWords array.
    func setVocabularyNames(_ names: [String]) {
        let cleaned = Array(Set(names
            .map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 }))
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.vocabularyNames = cleaned
            self.rebuildCustomWordsCache()
        }
    }

    private func rebuildCustomWordsCache() {
        // Numbers + names merged. Names go AFTER numbers so that if
        // Vision applies any internal ordering preference, identifiers
        // (which we want exact) win over generic vocabulary.
        if vocabularyNames.isEmpty {
            customWordsCache = cardNumbers
        } else {
            var merged = cardNumbers
            merged.append(contentsOf: vocabularyNames)
            customWordsCache = merged
        }
    }

    /// Wait for setCardNumbers + setVocabularyNames dispatches to drain
    /// off the processing queue. setX calls dispatch async; callers that
    /// need the customWordsCache populated before scanning (Grid scan)
    /// previously slept 200ms blindly. Submitting an empty no-op block
    /// after the setX calls and waiting for it lets us proceed exactly
    /// when vocab work completes — typically <30ms instead of 200ms.
    func awaitVocabularyReady() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            processingQueue.async { cont.resume() }
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
        let original = CIImage(cvPixelBuffer: pixelBuffer)
        let enhanced = original
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
        if !customWordsCache.isEmpty {
            request.customWords = customWordsCache
        }

        // Card-presence gate. The OCR + catalog-validation chain is
        // strong enough that random text on a computer screen, a
        // book, or a pile of paper will occasionally produce a
        // catalog-valid cardNumber (e.g. any 1-3 digit number that
        // happens to match a Base Set card) and silently commit a
        // phantom card to the queue. Requiring an actual card-shaped
        // rectangle in the frame eliminates that false-positive class
        // without weakening the OCR pipeline. The rectangle request
        // runs in the same VNImageRequestHandler pass as text
        // recognition, so the additional cost is small.
        //
        // Aspect 0.55-1.10 covers cards held portrait OR slightly
        // landscape-tilted; minimumSize 0.10 rejects detections of
        // tiny rectangles in background clutter; confidence 0.5
        // filters Vision's lowest-confidence guesses.
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.55
        rectRequest.maximumAspectRatio = 1.10
        rectRequest.minimumSize        = 0.10
        rectRequest.minimumConfidence  = 0.5
        rectRequest.maximumObservations = 8
        rectRequest.quadratureTolerance = 30

        let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
        guard (try? handler.perform([rectRequest, request])) != nil,
              let observations = request.results else { return }

        // No card-shaped rectangle in this frame → don't even
        // consider the OCR text. Reset the consecutive-match counter
        // so a future card has to confirm itself fresh, but DON'T
        // crash through the missCount path: a "no rectangle" frame
        // is a deliberately silent skip, not a noisy miss.
        let rects = rectRequest.results ?? []
        let hasCardShapedRect = rects.contains { obs in
            let bb = obs.boundingBox
            let area = bb.width * bb.height
            // Max area filter: if the rectangle fills more than ~85%
            // of the frame it's almost certainly the user's monitor,
            // desk surface, or a sheet of paper — not a card. Real
            // cards leave background visible on at least one side.
            guard area <= 0.85 else { return false }
            // ROI-aware containment: rectangle's center should land
            // inside the user's framing guide, so a card floating
            // outside the guide doesn't trigger a commit.
            let center = CGPoint(x: bb.midX, y: bb.midY)
            return regionOfInterest.contains(center)
        }
        guard hasCardShapedRect else {
            pendingCardNumber = nil
            consecutiveCount  = 0
            return
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

        // Render the ORIGINAL (pre-OCR-enhancement) frame to a CGImage
        // for image-similarity disambiguation. The enhanced version is
        // grayscale + gamma-lifted + sharpened — great for text but
        // would mismatch the full-color R2 thumbnails the index was
        // built from. Only rendered on commit, not on every frame —
        // costs ~5-10ms, paid at the once-per-2-seconds commit cadence
        // imposed by `reportCooldown`.
        let captured = CardScanner.ciContext
            .createCGImage(original, from: original.extent)

        let observation = ScanObservation(
            cardNumber:   number,
            rawName:      topLeft.joined(separator: " "),
            rawPower:     topRight.joined(separator: " "),
            rawVariation: bottomRight.joined(separator: " "),
            fullText:     fullText,
            cgImage:      captured
        )

        DispatchQueue.main.async { [weak self] in
            self?.onCardObservation?(observation)
        }
    }

    // MARK: - Card number extraction

    /// Extracts a card number from `text` using five strategies, in order:
    ///
    /// 1. Strict regex — exact prefixed format: BF-208, GLBF-276, RAD-104, ALTA-01.
    ///
    /// 2. Permissive regex — spaces/dashes around separator: "BF 208" → "BF-208".
    ///
    /// 3. Adjacent-word reconstruction — when OCR drops the hyphen entirely
    ///    ("BPL-5" read as two separate tokens "BPL" and "5"), iterate adjacent
    ///    word pairs and accept the FIRST combination that exists in the catalog.
    ///    This is the surgical fix for the Plays misreading-as-Heroes bug:
    ///    bottom-left of a Play card was producing words=["BPL","5"] which
    ///    fell through to step 4 and grabbed "5", silently routing to a Hero.
    ///
    /// 4. Pure-number catalog lookup (`catalogFallback: true`, bottom-left only)
    ///    handles sets like Griffey Edition whose base cards use plain integers.
    ///    REFUSES the match when an alphabetic neighbor word would have
    ///    formed a real card number with the digit — that signature means OCR
    ///    fragmented a real prefixed identifier and the bare number is a lie.
    ///
    /// 5. Letter→digit substitution — last-resort glyph-confusion recovery for
    ///    "BLBF-I95" → "BLBF-195", "I02" → "102", "BPL l3" → "BPL-13" etc.
    ///    Only substitutes characters in digit-side positions; never touches
    ///    a prefix (so "BLBF" stays "BLBF", not "8L8F"). Always validates
    ///    against the catalog set before returning. Catalog audit found
    ///    these confusions in hundreds of cards across stylized treatments.
    private func extractCardNumber(from rawText: String, catalogFallback: Bool) -> String? {
        // Pre-normalize Cyrillic homoglyphs that Vision sometimes
        // outputs on stylized cards. Without this, "ВЖBF-57" (cyrillic
        // V + Ж followed by Latin BF-57) doesn't match any English
        // regex; with it, "BЖBF-57" → no Ж sub but the В becomes B,
        // so we get "BЖBF-57"→Latin "BBF-57"-ish patterns the regex
        // can pick up. Cheap no-op when no cyrillic is present.
        let text = Self.normalizeCyrillic(rawText)
        let range = NSRange(text.startIndex..., in: text)

        // Catalog validation gate. When the cardNumberSet hasn't been
        // loaded yet (e.g. brief moment during scanner startup), accept
        // ANY regex match — that preserves the prior behavior. Once the
        // set is loaded, only return candidates that exist in it. This
        // unblocks the substitution path for cases like "BLBF-I95":
        // strict regex would otherwise match it as `[A-Z]?\d{1,4}` =
        // `I95` and return a non-existent cardNumber, blocking the
        // substitution layer below from ever getting a chance.
        func acceptable(_ s: String) -> Bool {
            cardNumberSet.isEmpty || cardNumberSet.contains(s)
        }

        // 1. Strict: exact format with hyphen
        if let match = Self.strictRegex.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text) {
            let candidate = String(text[r])
            if acceptable(candidate) { return candidate }
        }

        // 2. Permissive: spaces/dashes around separator
        if let match  = Self.permissiveRegex.firstMatch(in: text, range: range),
           let pRange = Range(match.range(at: 1), in: text),
           let nRange = Range(match.range(at: 2), in: text) {
            let candidate = "\(text[pRange])-\(text[nRange])"
            if acceptable(candidate) { return candidate }
        }

        // Tokenize once for steps 3 + 4.
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }
            .filter { !$0.isEmpty }

        // 3. Adjacent-word reconstruction — "BPL 5" → "BPL-5"
        //    Limited to 1–6 char alphabetic prefix + 1–4 char digit number,
        //    matching the strict regex's alphabet. Accept only if the
        //    combined form exists in the catalog — keeps this from
        //    inventing card numbers out of incidental adjacencies.
        if words.count >= 2 && !cardNumberSet.isEmpty {
            for i in 0..<(words.count - 1) {
                let p = words[i]
                let n = words[i + 1]
                guard p.count >= 1, p.count <= 6,
                      p.allSatisfy({ $0.isLetter })
                else { continue }
                // Try the raw number side first (preserves the strict
                // path), then the substituted form ("I3" → "13",
                // "1O2" → "102") to recover digit/letter glyph
                // confusions on the digit-side token.
                let rawDigits = n
                let (subDigits, changed) = Self.substituteToDigits(n)
                let candidates = changed ? [rawDigits, subDigits] : [rawDigits]
                for cand in candidates {
                    guard cand.count >= 1, cand.count <= 4,
                          cand.allSatisfy({ $0.isNumber })
                    else { continue }
                    // Try hyphenated (BF-4 — catalog convention) AND hyphen-less
                    // (BF4 — Tecmo convention); both validated against the catalog
                    // so an incidental adjacency can't invent a card number.
                    let hyph = "\(p)-\(cand)"
                    if cardNumberSet.contains(hyph) { return hyph }
                    let bare = "\(p)\(cand)"
                    if cardNumberSet.contains(bare) { return bare }
                }
            }
        }

        // 4. Pure-number catalog lookup — bottom-left quadrant only
        guard catalogFallback, !cardNumberSet.isEmpty else { return nil }

        // Pre-collect alphabetic neighbors (1–6 letters, all caps) from the
        // same text. If any of them combined with a candidate digit would
        // form a real card number, treat the digit as fragmented OCR and
        // refuse the bare-number commit — that's the Plays-as-Heroes path.
        let alphaNeighbors = words.filter { w in
            w.count >= 1 && w.count <= 6 && w.allSatisfy({ $0.isLetter })
        }

        for word in words {
            guard word.count >= 1, word.count <= 4,
                  word.allSatisfy({ $0.isNumber }),
                  cardNumberSet.contains(word)
            else { continue }

            let isFragmentedPrefix = alphaNeighbors.contains { p in
                cardNumberSet.contains("\(p)-\(word)")
            }
            if isFragmentedPrefix { continue }

            return word
        }

        // 5. Letter→digit substitution as last resort.
        //
        // Two shapes are tried:
        //   a) PREFIXED: a word that's `[A-Z]+-<rest>`. Substitute only
        //      the post-dash portion ("BLBF-I95" → "BLBF-195"). The
        //      pre-dash prefix is left intact — substituting it would
        //      corrupt valid prefixes like "BLBF" → "8L8F".
        //   b) PURE-DIGIT-LIKE: a word with no dash whose letters are
        //      all in the substitution map ("I02" → "102", "lO2" →
        //      "102"). Validates against the pure-number catalog so we
        //      don't invent random numerics.
        //
        // Catalog membership is the gate in both cases — we never
        // return a substituted form unless the catalog actually
        // contains it. This is a recovery path, not a fabrication path.
        for word in words {
            // (a) Prefixed shape with a dash.
            if let dashIdx = word.firstIndex(of: "-") {
                let prefix = String(word[..<dashIdx])
                guard prefix.count >= 1, prefix.count <= 6,
                      prefix.allSatisfy({ $0.isLetter })
                else { continue }
                let rest = String(word[word.index(after: dashIdx)...])
                let (subRest, changed) = Self.substituteToDigits(rest)
                guard changed else { continue }
                let combined = "\(prefix)-\(subRest)"
                if cardNumberSet.contains(combined) { return combined }
                continue
            }
            // (b) Pure-digit-like shape: must be 1–4 chars total, all
            //     either substitutable letters or digits already, and
            //     fully numeric AFTER substitution. Pure-number
            //     fallback already requires `catalogFallback`, so this
            //     branch inherits that gate.
            guard catalogFallback,
                  word.count >= 1, word.count <= 4
            else { continue }
            let allSubable = word.allSatisfy { ch in
                ch.isNumber || Self.digitSubs[ch] != nil
            }
            guard allSubable else { continue }
            // Require at least ONE original digit. Without this, hero-
            // name fragments like "BO" (B→8, O→0) would substitute to
            // "80" and falsely match a real cardNumber. Requiring a
            // real digit anchor confirms we're recovering a corrupted
            // numeric token, not converting a word.
            let hasOriginalDigit = word.contains { $0.isNumber }
            guard hasOriginalDigit else { continue }
            let (subbed, changed) = Self.substituteToDigits(word)
            guard changed,
                  subbed.allSatisfy({ $0.isNumber }),
                  cardNumberSet.contains(subbed)
            else { continue }
            // Same fragmented-prefix guard as step 4 — don't accept a
            // pure-number recovery if an alphabetic neighbor would
            // have formed a real prefixed cardNumber instead.
            let isFragmentedPrefix = alphaNeighbors.contains { p in
                cardNumberSet.contains("\(p)-\(subbed)")
            }
            if isFragmentedPrefix { continue }
            return subbed
        }

        return nil
    }

    /// Bare-digit cardNumber extraction that requires the digit to
    /// appear at least `minRepeats` times in the text. Used for the
    /// top-left quadrant fallback where the regular catalogFallback
    /// path is too loose (a single "18" near "CALIBER" was returning
    /// "18" as cn, triggering wrong-treatment scoring). When the
    /// SAME digit appears 2+ times — like "172 172" from a badge
    /// that bled into the topL crop — that's strong evidence the
    /// badge actually rendered there.
    private func extractRepeatedBareDigitCN(in text: String, minRepeats: Int) -> String? {
        let words = text.uppercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        var counts: [String: Int] = [:]
        for w in words {
            guard w.count >= 1, w.count <= 4, w.allSatisfy({ $0.isNumber }) else { continue }
            counts[w, default: 0] += 1
        }
        let qualified = counts.filter { $0.value >= minRepeats && cardNumberSet.contains($0.key) }
        return qualified.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Grid-mode OCR result

/// Output of `scanGridImage`. Carries every text observation from
/// the multi-pass OCR pipeline, plus the matched cardNumber when
/// extraction succeeded. The unified `ScanMatching.resolve` consumes
/// `topLeftText` for hero-veto and `cgImage` for FP, so a missing
/// cardNumber doesn't lose the cell — image + hero text alone can
/// still resolve it.
struct GridOCRResult: Sendable {
    let cardNumber: String?
    let allText: String
    let topLeftText: String
    let bottomLeftText: String
    let topRightText: String
    let bottomRightText: String
    let cgImage: CGImage?
}

// MARK: - Still-image scan path (used by Grid mode)

extension CardScanner {

    /// Run the OCR + cardNumber-extraction pipeline on a single
    /// pre-cropped UIImage. Used by Grid scan mode where the input
    /// has already been split into N card-shaped sub-images (via
    /// `GridCardDetector`) and each one needs to be OCR'd
    /// independently. No frame-stability check (we have one shot,
    /// not a stream) and no commit cooldown.
    ///
    /// The scanner instance must already be initialized with
    /// `setCardNumbers` and ideally `setVocabularyNames` so the
    /// catalog is loaded; otherwise extraction can only succeed
    /// via the strict regex path.
    ///
    /// Returns nil when no card number is extracted from the image.
    func scanStillImage(_ image: UIImage) async -> ScanObservation? {
        guard let ciImage = CIImage(image: image) else { return nil }
        // Pre-extract Sendable scalars; processingQueue is a serial
        // dispatch queue and we cap its capture.
        return await withCheckedContinuation { (cont: CheckedContinuation<ScanObservation?, Never>) in
            processingQueue.async { [weak self] in
                guard let self else { cont.resume(returning: nil); return }
                let result = self.runOCRSync(on: ciImage)
                cont.resume(returning: result)
            }
        }
    }

    /// Burst variant — same multi-pass OCR pipeline run on N frames
    /// of the same physical card cell, with cross-frame voting on
    /// top of the existing cross-pass voting. This is the still-
    /// image analog of the streaming scanner's `requireConsecutive
    /// = 2`: a cardNumber that only appears in one frame (often
    /// from a transient neighbor-crop bleed caused by hand shake)
    /// gets rejected when the other frames don't confirm it.
    ///
    /// Voting hierarchy:
    ///   • Each frame independently runs runMultiPassGridOCR (4
    ///     enhancement passes + per-frame voting).
    ///   • Across frames, the cardNumber that appeared in the most
    ///     frames wins (≥2 frames agreeing = strong signal).
    ///   • If no cardNumber was extracted from any frame, the text
    ///     observations from frame 0 are returned for hero-name
    ///     fallback in ScanMatching.
    ///
    /// Caller passes one crop per frame (same cellRect across all
    /// burst frames, cropped via GridCardDetector.cropFrame).
    func scanGridImageBurst(crops: [UIImage]) async -> GridOCRResult {
        guard !crops.isEmpty else {
            return GridOCRResult(
                cardNumber: nil, allText: "", topLeftText: "",
                bottomLeftText: "", topRightText: "",
                bottomRightText: "", cgImage: nil)
        }
        // Single-frame fallback — library picker path or burst fail.
        if crops.count == 1 {
            return await scanGridImage(crops[0])
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<GridOCRResult, Never>) in
            // Concurrent queue here too — multi-frame burst voting is
            // currently disabled (burstCount = 1) but the path is
            // kept ready for re-enablement; switching it to the
            // concurrent lane now keeps both branches consistent.
            gridOCRQueue.async { [weak self] in
                guard let self else {
                    cont.resume(returning: GridOCRResult(
                        cardNumber: nil, allText: "", topLeftText: "",
                        bottomLeftText: "", topRightText: "",
                        bottomRightText: "", cgImage: nil))
                    return
                }
                var perFrame: [GridOCRResult] = []
                var votes: [String: Int] = [:]
                for img in crops {
                    guard let ci = CIImage(image: img) else { continue }
                    // Same downsample-for-OCR / preserve-full-res-for-
                    // downstream-signals split as scanGridImage. Without
                    // this, burst OCR gets fed a downsampled CIImage but
                    // then ALSO returns a downsampled CGImage that
                    // corrupts BorderSignature.localVariance (smooths
                    // out the speckle pattern that distinguishes Icon
                    // Battlefoils from solid-color treatments).
                    let extent = ci.extent
                    let longSide = max(extent.width, extent.height)
                    let target: CGFloat = 1200
                    let ocrInput: CIImage = {
                        guard longSide > target else { return ci }
                        let scale = target / longSide
                        return ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    }()
                    let fullResCG = Self.ciContext.createCGImage(ci, from: ci.extent)
                    let result = self.runMultiPassGridOCR(ciImage: ocrInput,
                                                          capturedOverride: fullResCG)
                    perFrame.append(result)
                    if let cn = result.cardNumber {
                        votes[cn, default: 0] += 1
                    }
                }
                // Frame-level winner: cardNumber that appeared in
                // the most frames. Ties broken by capture order
                // (frame 0 wins).
                let frameWinner = votes
                    .max(by: { $0.value < $1.value })?.key
                if let winner = frameWinner,
                   let res = perFrame.first(where: { $0.cardNumber == winner }) {
                    cont.resume(returning: res)
                    return
                }
                // No cardNumber in any frame — return frame 0's
                // result so hero-name fallback in ScanMatching has
                // text observations to work with.
                cont.resume(returning: perFrame.first ?? GridOCRResult(
                    cardNumber: nil, allText: "", topLeftText: "",
                    bottomLeftText: "", topRightText: "",
                    bottomRightText: "", cgImage: nil))
            }
        }
    }

    /// Multi-pass Grid-mode OCR. Runs four enhancement variants then
    /// a focused bottom-left-badge pass for tiny low-contrast
    /// cardNumbers. Always returns a result (with cardNumber=nil
    /// when unrecoverable), so the caller can run hero-name
    /// fallback on the populated text fields. Each pass uses the
    /// same customWords vocab boost that streaming scan uses.
    func scanGridImage(_ image: UIImage) async -> GridOCRResult {
        guard let raw = CIImage(image: image) else {
            return GridOCRResult(cardNumber: nil, allText: "", topLeftText: "",
                                 bottomLeftText: "", topRightText: "",
                                 bottomRightText: "", cgImage: nil)
        }
        // Downsample cells whose long side exceeds ~1200px BEFORE
        // running multi-pass OCR. With a 3024x4032 source, each 3x3
        // cell crop is roughly 1000x1400 pixels — Vision's text
        // recognition cost scales with pixel count and these were
        // taking 800ms+ per pass at full res. Downsampling to ~1200
        // long side keeps card text comfortably readable (the focused
        // pass's 4× upscale gives plenty of detail for tiny badges)
        // while cutting per-pass time roughly in half.
        let ciImage: CIImage = {
            let extent = raw.extent
            let longSide = max(extent.width, extent.height)
            let target: CGFloat = 1200
            guard longSide > target else { return raw }
            let scale = target / longSide
            return raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }()
        // The CGImage returned in GridOCRResult flows into
        // observation.cgImage where ScanMatching reads it for FP
        // distance, cellColor bucket, AND BorderSignature. The
        // BorderSignature's localVariance metric is pixel-level —
        // downsampling smooths neighboring pixels and erases the
        // very speckle-pattern signal that distinguishes Icon
        // Battlefoils from solid-color treatments. Build `captured`
        // from the FULL-RES `raw` so the downstream signals see the
        // same pixels the CLI test harness sees on the same HEIC.
        let fullResCG = Self.ciContext.createCGImage(raw, from: raw.extent)
        return await withCheckedContinuation { (cont: CheckedContinuation<GridOCRResult, Never>) in
            // Concurrent queue: each grid cell's OCR runs on its own
            // thread instead of queueing behind every other cell.
            gridOCRQueue.async { [weak self] in
                guard let self else {
                    cont.resume(returning: GridOCRResult(
                        cardNumber: nil, allText: "", topLeftText: "",
                        bottomLeftText: "", topRightText: "",
                        bottomRightText: "", cgImage: nil))
                    return
                }
                let result = self.runMultiPassGridOCR(ciImage: ciImage,
                                                      capturedOverride: fullResCG)
                cont.resume(returning: result)
            }
        }
    }

    /// Multi-pass OCR with cross-pass voting. Each cell gets run
    /// through 4 enhancement variants (and optionally a focused-region
    /// pass for tiny badges); the cardNumber that appears in the most
    /// passes wins. This is the still-image analog of the streaming
    /// scanner's `requiredConsecutive = 2` — a single noisy pass
    /// (e.g. a misread pulling a number from a neighbor crop's edge)
    /// gets rejected when subsequent passes don't confirm it.
    ///
    /// Tier order:
    ///   1. Run all 4 enhancement passes; record each pass's
    ///      cardNumber extraction.
    ///   2. If ≥2 passes agree on a cardNumber → commit it
    ///      (high-confidence; matches streaming's stability bar).
    ///   3. If exactly 1 pass extracts → ALSO run the focused
    ///      bottom-left pass; if that confirms (or extracts the same
    ///      number) → commit. Otherwise pass the single-vote
    ///      cardNumber through and let `ScanMatching.resolve`'s
    ///      hero-veto + FP rank validate it (low-confidence).
    ///   4. If 0 passes extract → run the focused pass alone for
    ///      tiny stylized badges (Wattage 141 et al).
    ///   5. If still nothing → return all observations for
    ///      hero-name-only matching downstream.
    private func runMultiPassGridOCR(ciImage: CIImage,
                                     capturedOverride: CGImage? = nil) -> GridOCRResult {
        // captured is the CGImage that flows downstream into FP /
        // cellColor / BorderSignature. Default to the OCR-input CIImage
        // when no override is provided (camera-still single-frame path
        // where the source is already cell-sized). When the caller
        // specifies an override (scanGridImage's full-res path), use
        // that — preserves pixel-level signals against a downsampling
        // that's intentional for OCR but corrupts FP/border metrics.
        let captured = capturedOverride
            ?? Self.ciContext.createCGImage(ciImage, from: ciImage.extent)
        struct PassParams {
            let mt: Float, c: Float, g: Float, s: Float
        }
        let passes: [PassParams] = [
            PassParams(mt: 0.015, c: 1.25, g: 0.65, s: 0.5),  // standard (matches streaming)
            PassParams(mt: 0.005, c: 1.6,  g: 0.55, s: 1.0),  // small text
            PassParams(mt: 0.008, c: 2.0,  g: 0.75, s: 1.5),  // high contrast
            PassParams(mt: 0.01,  c: 1.4,  g: 0.85, s: 0.8),  // bright cards
        ]
        // Run the 4 enhancement passes SEQUENTIALLY, not in parallel.
        // Earlier versions parallelized these via DispatchGroup ("3-4×
        // speedup on A14+ hardware"), which was true measured in
        // isolation on a single cell. But the grid-scan TaskGroup
        // already runs 4 cells concurrently, so 4 cells × 4 parallel
        // passes = 16 Vision requests in flight — and the Neural
        // Engine serializes Vision internally regardless of how many
        // we throw at it. Under that contention each request stretched
        // from ~100ms to 500ms-1s+. Going sequential here drops
        // peak in-flight requests from 16 to 4 (one per cell) and
        // each request runs at full speed → faster overall. Also
        // adds a Tier 2 short-circuit: if 2 passes already agree on
        // a cardNumber, skip the remaining passes entirely.
        var passResults: [SinglePassResult] = []
        passResults.reserveCapacity(passes.count)
        var earlyVotes: [String: Int] = [:]
        for p in passes {
            let r = self.runSingleOCRPass(
                ciImage: ciImage,
                params: (mt: p.mt, c: p.c, g: p.g, s: p.s)
            )
            passResults.append(r)
            if let cn = r.cardNumber {
                earlyVotes[cn, default: 0] += 1
                // Short-circuit: 2 passes already agree, no need to
                // run the remaining passes — Tier 2 will pick this.
                if earlyVotes[cn]! >= 2 { break }
            }
        }

        var votes: [String: Int] = [:]
        var allObs: [(text: String, midX: CGFloat, midY: CGFloat)] = []
        let validResults = passResults
        for r in validResults {
            allObs.append(contentsOf: r.observations)
            if let cn = r.cardNumber {
                votes[cn, default: 0] += 1
            }
        }

        // Tier 2: stable agreement across ≥2 passes.
        let stable = votes.filter { $0.value >= 2 }
            .max(by: { $0.value < $1.value })?.key
        if let stable,
           let stablePass = validResults.first(where: { $0.cardNumber == stable }) {
            return makeResult(from: stablePass, cardNumber: stable, captured: captured)
        }

        // Tier 3: a single pass found a candidate. Try to corroborate
        // with the focused bottom-left pass before passing it through.
        let singleVotePass = validResults.first(where: { $0.cardNumber != nil })
        let focusResult = runFocusedBottomLeftPass(ciImage: ciImage)
        if let single = singleVotePass, let singleCN = single.cardNumber {
            // If the focused pass extracted the same number → strong.
            if let focus = focusResult, focus.cardNumber == singleCN {
                return makeResult(from: single, cardNumber: singleCN, captured: captured)
            }
            // If the focused pass extracted a DIFFERENT number → the
            // bottom-left badge says one thing and a regular pass says
            // another. Prefer the focused-region read (it sees only
            // the badge area, no neighbor crop bleed).
            if let focus = focusResult, let focusCN = focus.cardNumber,
               focusCN != singleCN {
                return makeResult(from: focus, cardNumber: focusCN, captured: captured)
            }
            // No focused-region confirmation; pass the single-vote
            // through. The unified resolve's hero-veto + FP rank
            // discard it if the printed hero on the card doesn't
            // agree.
            return makeResult(from: single, cardNumber: singleCN, captured: captured)
        }

        // Tier 4: no enhancement pass extracted; rely on focused pass.
        if let focus = focusResult, let focusCN = focus.cardNumber {
            return makeResult(from: focus, cardNumber: focusCN, captured: captured)
        }

        // Tier 5: nothing extracted. Aggregate all pass observations
        // for hero-name-only matching downstream.
        let allText = allObs.map { $0.text }.joined(separator: " ")
        let topLeftText = allObs.filter { $0.midX < 0.5 && $0.midY > 0.5 }
            .map { $0.text }.joined(separator: " ")
        let bottomLeftText = allObs.filter { $0.midX < 0.5 && $0.midY <= 0.5 }
            .map { $0.text }.joined(separator: " ")
        let topRightText = allObs.filter { $0.midX >= 0.5 && $0.midY > 0.5 }
            .map { $0.text }.joined(separator: " ")
        let bottomRightText = allObs.filter { $0.midX >= 0.5 && $0.midY <= 0.5 }
            .map { $0.text }.joined(separator: " ")
        return GridOCRResult(
            cardNumber: nil,
            allText: allText, topLeftText: topLeftText,
            bottomLeftText: bottomLeftText,
            topRightText: topRightText,
            bottomRightText: bottomRightText,
            cgImage: captured)
    }

    private func makeResult(
        from pass: SinglePassResult,
        cardNumber: String,
        captured: CGImage?
    ) -> GridOCRResult {
        GridOCRResult(
            cardNumber: cardNumber,
            allText: pass.allText,
            topLeftText: pass.topLeftText,
            bottomLeftText: pass.bottomLeftText,
            topRightText: pass.topRightText,
            bottomRightText: pass.bottomRightText,
            cgImage: captured
        )
    }

    private struct SinglePassResult {
        let cardNumber: String?
        let allText: String
        let topLeftText: String
        let topRightText: String
        let bottomLeftText: String
        let bottomRightText: String
        let observations: [(text: String, midX: CGFloat, midY: CGFloat)]
    }

    private func runSingleOCRPass(
        ciImage: CIImage, params: (mt: Float, c: Float, g: Float, s: Float)
    ) -> SinglePassResult {
        let enhanced = ciImage
            .applyingFilter("CIGammaAdjust", parameters: [ "inputPower": params.g ])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0),
                "inputContrast":   params.c,
            ])
            .applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius":    Float(2.5),
                "inputIntensity": params.s,
            ])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = ["en-US"]
        request.minimumTextHeight      = params.mt
        if !customWordsCache.isEmpty {
            request.customWords = customWordsCache
        }
        let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else {
            return SinglePassResult(cardNumber: nil, allText: "", topLeftText: "",
                                    topRightText: "", bottomLeftText: "",
                                    bottomRightText: "", observations: [])
        }
        var topLeft: [String] = [], topRight: [String] = []
        var bottomLeft: [String] = [], bottomRight: [String] = []
        var all: [String] = []
        var obsList: [(text: String, midX: CGFloat, midY: CGFloat)] = []
        for obs in observations {
            guard let cand = obs.topCandidates(1).first,
                  cand.confidence > 0.3 else { continue }
            let text = cand.string.uppercased()
            all.append(text)
            obsList.append((text, obs.boundingBox.midX, obs.boundingBox.midY))
            switch (obs.boundingBox.midX < 0.5, obs.boundingBox.midY > 0.5) {
            case (true,  true):  topLeft.append(text)
            case (false, true):  topRight.append(text)
            case (true,  false): bottomLeft.append(text)
            case (false, false): bottomRight.append(text)
            }
        }
        let allText = all.joined(separator: " ")
        let bottomLeftText = bottomLeft.joined(separator: " ")
        let extracted = extractCardNumber(from: bottomLeftText, catalogFallback: true)
                     ?? extractCardNumber(from: allText, catalogFallback: false)
        return SinglePassResult(
            cardNumber: extracted,
            allText: allText,
            topLeftText: topLeft.joined(separator: " "),
            topRightText: topRight.joined(separator: " "),
            bottomLeftText: bottomLeftText,
            bottomRightText: bottomRight.joined(separator: " "),
            observations: obsList)
    }

    /// Focused OCR on the bottom-left badge area where small stylized
    /// cardNumbers live on First-Edition cards.
    ///
    /// Reduced again — now 2×2 = 4 sequential attempts (down from
    /// the original 7×6 = 42 → 3×3 = 9). Per-cell measurement on a
    /// 9-card scan showed the focused fallback was the dominant
    /// variable cost when cells couldn't read their cardNumber from
    /// the main passes (~1.5s per `cn=NO` cell × 4-5 such cells per
    /// scan = 6-7s of focused work). Per-pass time also crept up
    /// across consecutive scans (~80ms → 125ms) — Neural Engine
    /// thermal throttling. The only way to keep performance steady
    /// across consecutive scans is to do less Vision work overall.
    ///
    /// 4 sequential attempts × ~100-150ms = ~400-600ms worst case
    /// (down from ~900ms with 9 attempts and ~4200ms with 42).
    private func runFocusedBottomLeftPass(ciImage: CIImage) -> SinglePassResult? {
        let extent = ciImage.extent
        // 2 crop shapes — the most reliable winners from prior trace
        // analysis. Dropped the "tight" shape (0.20×0.18) since the
        // balanced shape's wider radius captured those cases too.
        let cropFractions: [(xMax: CGFloat, yFrac: CGFloat)] = [
            (0.28, 0.20),  // balanced — the original "default"
            (0.50, 0.25),  // wider — for badges with longer text
        ]
        // 2 contrast variants — kept the bright + dark extremes;
        // dropped the balanced medium-contrast variant since the 4
        // main passes already cover medium-contrast space.
        let variants: [(c: Float, g: Float, s: Float)] = [
            (3.0, 1.50, 2.5),  // bright high-contrast
            (3.0, 0.50, 2.5),  // dark high-contrast
        ]
        for crop in cropFractions {
            let cropRect = CGRect(
                x: extent.minX,
                y: extent.minY,                    // CIImage Y goes up
                width:  extent.width  * crop.xMax,
                height: extent.height * crop.yFrac
            )
            let cropped = ciImage.cropped(to: cropRect)
                .applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey:       Float(4.0),
                    kCIInputAspectRatioKey: Float(1.0),
                ])
            for v in variants {
                let r = runSingleOCRPass(
                    ciImage: cropped,
                    params: (mt: 0.004, c: v.c, g: v.g, s: v.s)
                )
                if r.cardNumber != nil { return r }
            }
        }
        return nil
    }

    /// Synchronous OCR worker — must be called on `processingQueue`
    /// because it touches `cardNumberSet` and `customWordsCache`.
    /// Mirrors the per-frame logic from `processFrame` but skips the
    /// stability-counter and cooldown checks. Sentinel-only — do not
    /// call directly from outside the queue.
    private func runOCRSync(on ciImage: CIImage) -> ScanObservation? {
        // Same enhancement chain as processFrame — gamma lift + grayscale +
        // contrast + unsharp mask. Tuned for OCR on dark BoBA card art.
        let enhanced = ciImage
            .applyingFilter("CIGammaAdjust", parameters: [ "inputPower": Float(0.65) ])
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": Float(0.0),
                "inputContrast":   Float(1.25),
            ])
            .applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius":    Float(2.5),
                "inputIntensity": Float(0.5),
            ])

        let request = VNRecognizeTextRequest()
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = ["en-US"]
        // Whole image — Grid crops are already card-shaped, no ROI.
        request.regionOfInterest       = CGRect(x: 0, y: 0, width: 1, height: 1)
        request.minimumTextHeight      = 0.015
        if !customWordsCache.isEmpty {
            request.customWords = customWordsCache
        }

        let handler = VNImageRequestHandler(ciImage: enhanced, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return nil }

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

        let fullText        = all.joined(separator: " ")
        let bottomLeftText  = bottomLeft.joined(separator: " ")
        let bottomRightText = bottomRight.joined(separator: " ")
        let topLeftText     = topLeft.joined(separator: " ")

        // Multi-quadrant waterfall.
        //
        // Bottom quadrants get loose catalogFallback=true (bare-digit
        // catalog lookup OK because that's where the badge lives).
        //
        // topLeft uses catalogFallback=FALSE — bare digits there are
        // typically hero-name-area noise (e.g. "CALIBER 18 CALIBER"
        // returning "18" as cn and triggering wrong-treatment scoring).
        // BUT we then add a stricter `extractRepeatedBareDigitCN` pass
        // that accepts a bare digit ONLY if it appears 2+ times in
        // topLeft — that's the Ozzmosis-172 pattern where the badge
        // bled into topL ("172 172" both times).
        let extracted = extractCardNumber(from: bottomLeftText,  catalogFallback: true)
                     ?? extractCardNumber(from: bottomRightText, catalogFallback: true)
                     ?? extractCardNumber(from: topLeftText,     catalogFallback: false)
                     ?? extractRepeatedBareDigitCN(in: topLeftText, minRepeats: 2)
                     ?? extractCardNumber(from: fullText,        catalogFallback: false)

        guard let number = extracted,
              cardNumberSet.isEmpty || cardNumberSet.contains(number) else {
            return nil
        }

        // Render the (un-enhanced) image to CGImage for any future
        // image-similarity disambiguation step. Inexpensive at one
        // image per Grid cell, ~9 cells max per capture.
        let captured = Self.ciContext.createCGImage(ciImage, from: ciImage.extent)

        return ScanObservation(
            cardNumber:   number,
            rawName:      topLeft.joined(separator: " "),
            rawPower:     topRight.joined(separator: " "),
            rawVariation: bottomRight.joined(separator: " "),
            fullText:     fullText,
            cgImage:      captured
        )
    }
}

// MARK: - FeaturePrintIndex (Phase 2 — image-similarity matching)
//
// Phase 1 (text OCR + customWords vocabulary boost + card-number
// fragment reconstruction) handles the common case. Phase 2 plugs in
// here for cases OCR can't solve:
//
//   • Light-foil Ice cards with text that's barely legible.
//   • Sleeved cards behind cloudy or non-flat sleeves.
//   • Sun glare / reflection that wipes the bottom-left identifier.
//   • Frames where the user gets the title but not the number.
//
// Strategy: ship a precomputed index of `VNFeaturePrintObservation`
// embeddings — one per card image on R2 — and at scan time generate an
// embedding from the captured camera frame and pick the nearest
// neighbor. Vision's `computeDistance(_:to:)` produces a comparable
// scalar; a small CLI on macOS using the same Vision API generates the
// index offline (~30 MB for 14.7k cards at 2KB/embedding).
//
// Index file format (proposed):
//   - 4 bytes magic "BFPI"
//   - 4 bytes uint32 version (1)
//   - 4 bytes uint32 entry count
//   - 4 bytes uint32 print byte length (Vision default 2048)
//   - For each entry:
//        - 2 bytes uint16 bobaId byte length
//        - N bytes  bobaId UTF-8
//        - K bytes  feature print data
//
// Inlined into CardScanner.swift (rather than a standalone file) to
// avoid Xcode synchronized-group flakiness — see DECISIONS.md / the
// Design.swift inlining note for the same reasoning.
//
// Hook point: `ScanView.handleDetected(observation:)` will consult the
// index when OCR confidence is borderline (no card number, multiple
// equally-scored candidates, or sub-threshold match score). Phase 2
// adds the call site; this stub is API surface only.

/// Back on MainActor. An earlier rev (1.981) tried marking this
/// `nonisolated` so grid-scan cells could query FP concurrently —
/// the theory was that 4 cells running FP queries in parallel would
/// be faster than serializing them on main. In practice the Neural
/// Engine serializes Vision requests internally regardless, AND the
/// concurrent FP queries competed with concurrent OCR requests for
/// the same NE — making BOTH slower. Serializing FP on main keeps
/// NE free for OCR most of the time.
@MainActor
final class FeaturePrintIndex {

    static let shared = FeaturePrintIndex()

    private(set) var isLoaded: Bool = false
    private(set) var entryCount: Int = 0
    private(set) var elementCount: Int = 0

    /// We can't reconstruct VNFeaturePrintObservation from serialized
    /// bytes — Vision does not expose an initializer. Instead the index
    /// stores raw float vectors and computes Euclidean distance manually
    /// via Accelerate. Vectors are stored in a SINGLE flat array
    /// (entries × elementCount floats) so vDSP can read directly into
    /// it without per-entry allocation, and bobaIds are stored in a
    /// parallel array indexed by entry number.
    private var bobaIds: [String] = []
    private var flatVectors: [Float] = []

    /// Load `feature-prints.bin` from the app bundle. Quietly no-ops if
    /// the file is missing (so debug builds without the index still
    /// run). Parses the BFPI v1 format produced by
    /// `scripts/build_feature_print_index.swift`.
    func loadFromBundle() async {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "feature-prints", withExtension: "bin") else {
            return
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        guard parse(bfpi: data) else {
            // Format mismatch — leave isLoaded false so the search path
            // returns empty and the OCR pipeline runs unaffected.
            bobaIds.removeAll(keepingCapacity: false)
            flatVectors.removeAll(keepingCapacity: false)
            entryCount = 0
            elementCount = 0
            return
        }
        isLoaded = true
    }

    /// Search the index for the closest matching cards to a camera
    /// frame. Returns up to `topK` (bobaId, distance) pairs sorted by
    /// ascending distance. Lower distance = more similar.
    func searchNearest(in cgImage: CGImage,
                       topK: Int = 5) async -> [(bobaId: String, distance: Float)] {
        let all = await computeAllDistances(in: cgImage)
        guard !all.isEmpty else { return [] }
        var indexed = (0..<all.count).map { (i: $0, d: all[$0]) }
        indexed.sort { $0.d < $1.d }
        return indexed.prefix(topK).map { (bobaIds[$0.i], $0.d) }
    }

    /// One Vision feature-print pass + every-entry distance. Produces a
    /// dictionary keyed by bobaId. Used by `CardRecognizer` so it can
    /// fuse FP signal with OCR/hero signals — including looking up the
    /// distance to a specific hero's variants regardless of where they
    /// land in the global rank.
    ///
    /// `searchNearest` is now a thin wrapper around this. Returns an
    /// empty dictionary if Vision can't produce a print or the index
    /// dimensions don't match.
    func distances(in cgImage: CGImage) async -> [String: Float] {
        let all = await computeAllDistances(in: cgImage)
        guard !all.isEmpty else { return [:] }
        var out: [String: Float] = [:]
        out.reserveCapacity(all.count)
        for i in 0..<all.count {
            // First-occurrence wins on duplicate bobaIds (the indexer
            // dedupes, but this is still the safe behavior).
            if out[bobaIds[i]] == nil { out[bobaIds[i]] = all[i] }
        }
        return out
    }

    /// Internal: run Vision + return the distance vector indexed by
    /// entry. Empty array on any failure (index not loaded, Vision
    /// error, dimension mismatch, etc.) — callers degrade gracefully.
    private func computeAllDistances(in cgImage: CGImage) async -> [Float] {
        guard isLoaded, entryCount > 0 else { return [] }

        let request = VNGenerateImageFeaturePrintRequest()
        // .scaleFit must match the indexer (scripts/build_feature_print_index.swift).
        // Switched from .centerCrop in 1.950 — see the comment there for why
        // (treatment-distinguishing borders were getting cropped off).
        request.imageCropAndScaleOption = .scaleFit
        // Match the indexer's revision exactly. Different revisions
        // produce incompatible vectors; without this pin a future iOS
        // default revision change would silently fall through.
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        guard let query = request.results?.first as? VNFeaturePrintObservation,
              query.elementCount == elementCount,
              query.elementType == .float
        else { return [] }

        // Pull the query into a plain [Float].
        var queryVec = [Float](repeating: 0, count: elementCount)
        let byteCount = elementCount * MemoryLayout<Float>.size
        guard query.data.count == byteCount else { return [] }
        queryVec.withUnsafeMutableBufferPointer { dst in
            _ = query.data.copyBytes(to: dst)
        }

        // Compute L2-squared distance from query to each entry. Use
        // vDSP_distancesq for batched per-entry distance — the absence
        // of a square root preserves ordering, which is all we need
        // for top-K. (The CLI doesn't normalize, so we don't either.)
        var distances = [Float](repeating: 0, count: entryCount)
        let n = vDSP_Length(elementCount)
        flatVectors.withUnsafeBufferPointer { allBase in
            queryVec.withUnsafeBufferPointer { qBase in
                for i in 0..<entryCount {
                    var d: Float = 0
                    let entryStart = allBase.baseAddress!.advanced(by: i * elementCount)
                    vDSP_distancesq(qBase.baseAddress!, 1,
                                    entryStart, 1,
                                    &d, n)
                    distances[i] = d
                }
            }
        }
        return distances
    }

    // MARK: - Parser

    private func parse(bfpi data: Data) -> Bool {
        let headerLen = 4 + 4 * 4
        guard data.count >= headerLen else { return false }
        let magic = data.prefix(4)
        guard magic == Data("BFPI".utf8) else { return false }

        // `loadUnaligned` is the alignment-safe primitive — the BFPI
        // format interleaves variable-length bobaId strings with raw
        // numeric blocks, so most read offsets aren't aligned to the
        // type's natural size. `assumingMemoryBound` would be UB even
        // though Apple Silicon tolerates the access at runtime.
        func readU32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                UInt32(littleEndian:
                    raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        func readU16(_ offset: Int) -> UInt16 {
            data.withUnsafeBytes { raw in
                UInt16(littleEndian:
                    raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            }
        }
        let version      = readU32(4)
        let entries      = Int(readU32(8))
        let elementCount = Int(readU32(12))
        let elementSize  = Int(readU32(16))
        guard entries > 0, elementCount > 0 else { return false }
        // v1 = Float32 raw, v2 = int8 + per-vector Float32 scale.
        let isV1 = (version == 1 && elementSize == 4)
        let isV2 = (version == 2 && elementSize == 1)
        guard isV1 || isV2 else { return false }

        let perEntryFloats = elementCount
        var ids: [String] = []
        ids.reserveCapacity(entries)
        var flat = [Float](repeating: 0, count: entries * perEntryFloats)

        var cursor = headerLen
        for i in 0..<entries {
            guard cursor + 2 <= data.count else { return false }
            let idLen = Int(readU16(cursor)); cursor += 2
            guard cursor + idLen <= data.count else { return false }
            let idData = data.subdata(in: cursor..<(cursor + idLen))
            guard let id = String(data: idData, encoding: .utf8) else { return false }
            ids.append(id)
            cursor += idLen

            let dstStart = i * perEntryFloats

            if isV1 {
                let printBytes = perEntryFloats * 4
                guard cursor + printBytes <= data.count else { return false }
                // memcpy-style copy — alignment-safe.
                data.withUnsafeBytes { srcRaw in
                    flat.withUnsafeMutableBufferPointer { dst in
                        let dstPtr = UnsafeMutableRawPointer(dst.baseAddress!)
                            .advanced(by: dstStart * 4)
                        let srcPtr = srcRaw.baseAddress!.advanced(by: cursor)
                        dstPtr.copyMemory(from: srcPtr, byteCount: printBytes)
                    }
                }
                cursor += printBytes
            } else {
                // v2: read scale (Float32 little-endian) then int8 vector.
                guard cursor + 4 + perEntryFloats <= data.count else { return false }
                let scaleBits = readU32(cursor); cursor += 4
                let scale = Float(bitPattern: scaleBits)
                // Dequantize int8 → Float32 in place. This uses
                // vDSP_vflt8 (signed int8 → float) followed by
                // vDSP_vsmul (× scale) — a single linear pass per
                // vector, batched by Accelerate.
                data.withUnsafeBytes { srcRaw in
                    let i8Ptr = srcRaw.baseAddress!.advanced(by: cursor)
                        .assumingMemoryBound(to: Int8.self)
                    flat.withUnsafeMutableBufferPointer { dst in
                        let dstPtr = dst.baseAddress!.advanced(by: dstStart)
                        vDSP_vflt8(i8Ptr, 1, dstPtr, 1, vDSP_Length(perEntryFloats))
                        var s = scale
                        vDSP_vsmul(dstPtr, 1, &s, dstPtr, 1, vDSP_Length(perEntryFloats))
                    }
                }
                cursor += perEntryFloats
            }
        }

        self.bobaIds = ids
        self.flatVectors = flat
        self.entryCount = entries
        self.elementCount = elementCount
        return true
    }
}
