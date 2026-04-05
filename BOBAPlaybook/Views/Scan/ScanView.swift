import SwiftUI
import AVFoundation
import UIKit

// Guide dimensions — standard trading card aspect ratio (5:7), fills ~77% of screen width
private let kGuideW: CGFloat = 300
private let kGuideH: CGFloat = 420

struct ScanView: View {
    @Environment(CardStore.self)      private var cardStore
    @Environment(ScanStore.self)      private var scanStore
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(AuthManager.self)    private var auth

    @State private var scanner         = CardScanner()
    @State private var detectedCard:    Card?
    @State private var chipVisible      = false
    @State private var selectedCard:    Card?
    @State private var showQueueView    = false
    @State private var chipDismissTask: Task<Void, Never>?

    @State private var cameraPermission =
        AVCaptureDevice.authorizationStatus(for: .video)

    // Reference to the preview layer for ROI computation after layout
    @State private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Body

    var body: some View {
        ZStack {
            switch cameraPermission {
            case .authorized:
                cameraLayer
            case .notDetermined:
                Color.black.ignoresSafeArea()
            default:
                permissionDeniedView
            }
        }
        .ignoresSafeArea()
        .onAppear  { setupScanner() }
        .onDisappear {
            scanner.stop()
            chipDismissTask?.cancel()
            withAnimation { chipVisible = false }
        }
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
        .sheet(isPresented: $showQueueView) {
            ScanQueueView()
        }
    }

    // MARK: - Camera layer

    private var cameraLayer: some View {
        GeometryReader { geo in
            ZStack {
                // Live preview
                CameraPreviewView(session: scanner.captureSession) { layer in
                    previewLayer = layer
                    updateROI(in: geo)
                }
                .ignoresSafeArea()

                // Gradient vignette — top and bottom
                VStack {
                    LinearGradient(
                        colors: [.black.opacity(0.65), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 140)
                    .ignoresSafeArea()
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 220)
                }

                // Card guide frame
                cardGuideFrame

                // Scan hint — tilting the phone deflects specular glare on glossy cards
                Text("TILT PHONE SLIGHTLY FOR GLOSSY CARDS")
                    .font(Design.Fonts.mono(9))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.0)
                    .offset(y: kGuideH / 2 + 18)

                // Top controls
                VStack {
                    topBar
                    Spacer()
                    bottomControls
                }
            }
        }
    }

    // MARK: - Card guide frame

    private var cardGuideFrame: some View {
        ZStack {
            // Dimmed area outside the guide
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .mask(
                    Rectangle()
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.black)
                                .frame(width: kGuideW, height: kGuideH)
                        )
                        .compositingGroup()
                        .luminanceToAlpha()
                )

            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    detectedCard != nil
                        ? Design.Colors.element(detectedCard!.element)
                        : Design.Colors.bobaOrange,
                    lineWidth: 2
                )
                .frame(width: kGuideW, height: kGuideH)
                .shadow(
                    color: (detectedCard != nil
                        ? Design.Colors.element(detectedCard!.element)
                        : Design.Colors.bobaOrange).opacity(0.5),
                    radius: 10
                )
                .animation(.easeInOut(duration: 0.3), value: detectedCard?.element)

            // Corner accent marks
            ForEach(0..<4, id: \.self) { i in
                CornerMark()
                    .rotationEffect(.degrees(Double(i) * 90))
                    .offset(
                        x: (i == 0 || i == 3) ? -(kGuideW / 2 - 10) :  (kGuideW / 2 - 10),
                        y: (i == 0 || i == 1) ? -(kGuideH / 2 - 10) :  (kGuideH / 2 - 10)
                    )
            }
        }
        .frame(width: kGuideW, height: kGuideH)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            BOBAWordmark()
            Spacer()
            if scanStore.isMultiCardMode && scanStore.queueCount > 0 {
                Button { showQueueView = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                        Text("\(scanStore.queueCount)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(2)
                            .background(Design.Colors.bobaOrange)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, 56)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: Design.Spacing.md) {

            // Detection chip — swipe down to dismiss
            if chipVisible, let card = detectedCard {
                ScanDetectionChipView(card: card) {
                    selectedCard = card
                    if !scanStore.isMultiCardMode {
                        scanner.resetDetection()
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if value.translation.height > 30 {
                                withAnimation(.easeOut(duration: 0.25)) { chipVisible = false }
                                scanner.softReset()
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Mode toggle + hint
            HStack {
                Text(scanStore.isMultiCardMode ? "Cards queue automatically" : "Tap card to view details")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, Design.Spacing.lg)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scanStore.isMultiCardMode.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scanStore.isMultiCardMode
                              ? "rectangle.stack.fill"
                              : "rectangle.on.rectangle")
                            .font(.system(size: 13))
                        Text(scanStore.isMultiCardMode ? "MULTI" : "SINGLE")
                            .font(Design.Fonts.mono(12, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(scanStore.isMultiCardMode
                                     ? Design.Colors.bobaOrange
                                     : .white.opacity(0.7))
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(scanStore.isMultiCardMode
                                  ? Design.Colors.bobaOrange.opacity(0.2)
                                  : Color.white.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        scanStore.isMultiCardMode
                                            ? Design.Colors.bobaOrange.opacity(0.6)
                                            : Color.white.opacity(0.25),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .padding(.trailing, Design.Spacing.lg)
            }
            .padding(.bottom, 90)
        }
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 52))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Camera Access Required")
                .font(Design.Fonts.display(18))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Open Settings to allow BOBA Playbook to use the camera.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xxl)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(Design.Fonts.mono(14, weight: .bold))
            .foregroundStyle(Design.Colors.bobaOrange)
            .padding(.horizontal, Design.Spacing.xl)
            .padding(.vertical, Design.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.bobaOrange.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                        .strokeBorder(Design.Colors.bobaOrange.opacity(0.4)))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.nearBlack)
    }

    // MARK: - Scanner setup

    private func setupScanner() {
        switch cameraPermission {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                    if granted { configureAndStart() }
                }
            }
        default:
            break
        }
    }

    private func configureAndStart() {
        // Seed Vision with all card numbers as custom vocabulary
        let numbers = cardStore.displayCards.map { $0.cardNumber.uppercased() }
        scanner.setCardNumbers(numbers)

        scanner.onCardObservation = { [self] observation in
            handleDetected(observation: observation)
        }
        scanner.start()
    }

    private func updateROI(in geo: GeometryProxy) {
        guard let layer = previewLayer else { return }
        let guideRect = CGRect(
            x: (geo.size.width  - kGuideW) / 2,
            y: (geo.size.height - kGuideH) / 2,
            width:  kGuideW,
            height: kGuideH
        )
        scanner.updateROI(previewLayer: layer, guideRect: guideRect)
    }

    // MARK: - Detection handling

    private func handleDetected(observation: ScanObservation) {
        let candidates = cardStore.displayCards.filter {
            $0.cardNumber.uppercased() == observation.cardNumber
        }
        guard !candidates.isEmpty else { return }

        let scored = candidates
            .map { (card: $0, score: matchScore($0, observation: observation)) }
        guard let best = scored.max(by: { $0.score < $1.score })?.card else { return }

        detectedCard = best

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            chipVisible = true
        }

        if scanStore.isMultiCardMode {
            scanStore.addToQueue(best)
            chipDismissTask?.cancel()
            chipDismissTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { chipVisible = false }
            }
        }
    }

    /// Scores how well a card matches the OCR observation using per-quadrant text.
    ///
    /// Design note: when multiple cards share the same card number AND power
    /// (e.g. RAD-352 Brockness and RAD-352 Spider, both 120), the hero name
    /// is the only reliable differentiator. The old scoring only checked the
    /// top-left quadrant for the name — which is unreliable on dark cards —
    /// and weighted it below power, so ties were effectively random.
    ///
    /// Now: hero/name match searches ALL quadrant text with prefix-aware fuzzy
    /// matching (handles partial OCR reads like "BROCK" → "BROCKNESS"), is
    /// weighted above power, and element match adds a tiebreaker.
    private func matchScore(_ card: Card, observation: ScanObservation) -> Int {
        var score = 0
        let full = observation.fullText

        // --- Power match (+3) ---
        let powerText = observation.rawPower.isEmpty ? full : observation.rawPower
        if let power = card.power, extractIntegers(from: powerText).contains(power) {
            score += 3
        }

        // --- Hero / name match (+5 per word) — searched across ALL quadrant text ---
        // This is the primary differentiator for same-number cards. We search
        // fullText rather than just the top-left quadrant because:
        //   • OCR quadrant boundaries shift on dark cards and angled shots
        //   • The card name can bleed into adjacent quadrant regions
        // Prefix-aware matching handles partial reads ("BROCK" matches "BROCKNESS").
        score += heroNameScore(card.hero, in: full) * 5
        if card.name.uppercased() != card.hero.uppercased() {
            score += heroNameScore(card.name, in: full) * 3
        }

        // Top-left quadrant bonus — name in the expected position is stronger signal
        if !observation.rawName.isEmpty {
            score += heroNameScore(card.hero, in: observation.rawName) * 2
        }

        // --- Element match (+2) ---
        // Element text (FIRE, ICE, HEX…) often appears on the card face and
        // can differentiate cards that share a number but have different elements.
        if full.contains(card.element.uppercased()) {
            score += 2
        }

        // --- Treatment / variation match (+1 per word) ---
        let varText = observation.rawVariation.isEmpty ? full : "\(observation.rawVariation) \(full)"
        if let treatment = card.treatment, !treatment.isEmpty {
            let tWords = treatment.uppercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }
            score += tWords.filter { varText.contains($0) }.count
        }

        return score
    }

    /// Scores how well `name` appears in `text`. Returns a count used as a
    /// multiplier in `matchScore`.
    ///
    /// Strategy (in priority order):
    ///   1. Full-phrase match — "AIR ACE" found verbatim → returns 3 immediately.
    ///      Fast, unambiguous, handles multi-word names correctly.
    ///   2. Word-level match — for each word in the name (≥3 chars):
    ///        • Long words (≥5 chars): prefix-aware — "BROCK" matches "BROCKNESS"
    ///          to handle OCR truncation.
    ///        • Short words (3–4 chars): exact match only — "AIR", "ACE", "REX"
    ///          are too short for safe prefix matching but still meaningful.
    ///
    /// The old implementation required ≥5-char words, which silently dropped
    /// both words of "AIR ACE" and made it score 0, losing to any other card
    /// that happened to share its number and power.
    private func heroNameScore(_ name: String, in text: String) -> Int {
        let upperName = name.uppercased()

        // 1. Full phrase — definitive, return immediately
        if text.contains(upperName) { return 3 }

        // 2. Word-level
        let nameWords = upperName.components(separatedBy: .whitespaces).filter { $0.count >= 3 }
        guard !nameWords.isEmpty else { return 0 }

        let textWords = text.components(separatedBy: .whitespaces)
        var matches = 0
        for nw in nameWords {
            for tw in textWords where tw.count >= 3 {
                if nw.count >= 5 {
                    // Prefix match for longer words handles truncated OCR reads
                    let (shorter, longer) = nw.count <= tw.count ? (nw, tw) : (tw, nw)
                    if shorter.count >= 5, longer.hasPrefix(shorter) {
                        matches += 1; break
                    }
                } else if nw == tw {
                    // Short words need exact match to avoid false positives
                    matches += 1; break
                }
            }
        }
        return matches
    }

    private func extractIntegers(from text: String) -> Set<Int> {
        var result = Set<Int>()
        var current = ""
        for ch in text {
            if ch.isNumber { current.append(ch) }
            else {
                if let n = Int(current) { result.insert(n) }
                current = ""
            }
        }
        if let n = Int(current) { result.insert(n) }
        return result
    }
}

// MARK: - Corner mark accent

private struct CornerMark: View {
    var body: some View {
        Path { path in
            path.move(to:    CGPoint(x: 0, y: 14))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(Design.Colors.bobaOrange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .frame(width: 14, height: 14)
    }
}
