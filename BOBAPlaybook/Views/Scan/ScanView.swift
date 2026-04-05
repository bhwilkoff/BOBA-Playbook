import SwiftUI
import AVFoundation
import UIKit

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
        ZStack {
            // Live preview
            CameraPreviewView(session: scanner.captureSession)
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

            // Top controls
            VStack {
                topBar
                Spacer()
                bottomControls
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
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black)
                                .frame(width: 220, height: 308)
                        )
                        .compositingGroup()
                        .luminanceToAlpha()
                )

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    detectedCard != nil
                        ? Design.Colors.element(detectedCard!.element)
                        : Design.Colors.bobaOrange,
                    lineWidth: 2
                )
                .frame(width: 220, height: 308)
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
                        x: (i == 0 || i == 3) ? -100 : 100,
                        y: (i == 0 || i == 1) ? -144 :  144
                    )
            }
        }
        .frame(width: 220, height: 308)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Wordmark
            BOBAWordmark()

            Spacer()

            // Queue badge (multi mode only)
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
        .padding(.top, 56)   // safe area + status bar clearance
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
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.height > 40 {
                                withAnimation(.easeOut(duration: 0.25)) { chipVisible = false }
                                scanner.resetDetection()
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Mode toggle + hint
            HStack {
                // Aim hint
                Text(scanStore.isMultiCardMode ? "Cards queue automatically" : "Tap card to view details")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, Design.Spacing.lg)

                Spacer()

                // Multi/Single toggle
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
            .padding(.bottom, 90)   // tab bar (49) + home indicator (34) + margin
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
        scanner.configure()
        scanner.regionOfInterest = computeGuideROI()
        scanner.onCardObservation = { [self] (observation: ScanObservation) in
            handleDetected(observation: observation)
        }
        scanner.start()
    }

    /// Computes a generous regionOfInterest for Vision — centered on the card guide
    /// but expanded 25% on all sides to give OCR room to find the card number, which
    /// sits near the bottom edge of the guide. Uses Vision's bottom-left coordinate
    /// system (y increases upward).
    ///
    /// Falls back to the full frame if screen size is unavailable.
    private func computeGuideROI() -> CGRect {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.size ?? .zero
        guard screen.width > 0, screen.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        // Camera dimensions after portrait orientation correction
        let camW: CGFloat = 720
        let camH: CGFloat = 1280

        // Guide frame dimensions (must match cardGuideFrame in this file)
        let guideW: CGFloat = 220
        let guideH: CGFloat = 308

        // Expand guide bounds by 25% on each side to capture near-edge card text.
        let expandX = guideW * 0.25
        let expandY = guideH * 0.25
        let expandedW = guideW + expandX * 2
        let expandedH = guideH + expandY * 2
        let expandedLeft = (screen.width  - guideW) / 2 - expandX
        let expandedTop  = (screen.height - guideH) / 2 - expandY

        let camAspect    = camW / camH           // ≈ 0.5625
        let screenAspect = screen.width / screen.height

        let roiX: CGFloat
        let roiY: CGFloat
        let roiW: CGFloat
        let roiH: CGFloat

        if camAspect > screenAspect {
            // Camera wider than screen: fill by height, crop left & right.
            let displayedW = camW * (screen.height / camH)
            let xCrop      = (displayedW - screen.width) / 2
            roiX = (expandedLeft + xCrop) / displayedW
            roiW = expandedW / displayedW
            // Vision bottom-left origin: y = distance from bottom ÷ total height
            let bottomDist = screen.height - (expandedTop + expandedH)
            roiY = bottomDist / screen.height
            roiH = expandedH / screen.height
        } else {
            // Camera taller than screen: fill by width, crop top & bottom.
            let displayedH = camH * (screen.width / camW)
            let yCrop      = (displayedH - screen.height) / 2
            roiX = expandedLeft / screen.width
            roiW = expandedW / screen.width
            let bottomDist = screen.height - (expandedTop + expandedH)
            roiY = (bottomDist + yCrop) / displayedH
            roiH = expandedH / displayedH
        }

        func clamp(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
        return CGRect(x: clamp(roiX), y: clamp(roiY),
                      width: clamp(roiW), height: clamp(roiH))
    }

    // Minimum confidence score before a match is reported.
    // Score of 3 = power matched; 5 = power + 1 name word; etc.
    private let minimumScore = 3

    private func handleDetected(observation: ScanObservation) {
        print("SCAN▶︎ handleDetected: \(observation.cardNumber) | name='\(observation.rawName)' power='\(observation.rawPower)'")
        let candidates = cardStore.displayCards.filter {
            $0.cardNumber.uppercased() == observation.cardNumber
        }
        print("SCAN▶︎ candidates for \(observation.cardNumber): \(candidates.count)")
        guard !candidates.isEmpty else { return }

        let best: Card
        if candidates.count == 1 {
            // Unique card number — trust the OCR match directly.
            best = candidates[0]
            print("SCAN▶︎ unique match: \(best.name)")
        } else {
            // Multiple cards share this number (different variations).
            // Score each and pick the highest; require minimum confidence.
            let scored = candidates
                .map { (card: $0, score: matchScore($0, observation: observation)) }
                .filter { $0.score >= minimumScore }
            scored.forEach { print("SCAN▶︎   score \($0.score) → \($0.card.name)") }
            guard let top = scored.max(by: { $0.score < $1.score }) else {
                print("SCAN▶︎ \(candidates.count) candidates, all below minimumScore (\(minimumScore))")
                return
            }
            best = top.card
        }

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
    /// Each field is matched against its own quadrant (the corner where that text lives
    /// on a physical card). Falls back to fullText if a quadrant returned nothing.
    ///
    /// Scoring:
    ///   Power exact match      → +3  (top-right; large number, strong signal)
    ///   Name word match        → +2 per significant word >3 chars (top-left)
    ///   Variation keyword      → +2  (bottom-right; e.g. BATTLEFOIL, BLIZZARD)
    ///
    /// minimumScore = 3 requires at least the power to match (or 2+ name words).
    private func matchScore(_ card: Card, observation: ScanObservation) -> Int {
        var score = 0

        // Power — top-right quadrant, fall back to full text
        let powerText = observation.rawPower.isEmpty ? observation.fullText : observation.rawPower
        if let power = card.power {
            if extractIntegers(from: powerText).contains(power) { score += 3 }
        }

        // Name — top-left quadrant, fall back to full text
        let nameText  = observation.rawName.isEmpty ? observation.fullText : observation.rawName
        let nameWords = card.name.uppercased()
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 3 }
        score += nameWords.filter { nameText.contains($0) }.count * 2

        // Variation — bottom-right quadrant, fall back to full text
        let varText = observation.rawVariation.isEmpty ? observation.fullText : observation.rawVariation
        if let treatment = card.treatment, !treatment.isEmpty {
            let tWords = treatment.uppercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }
            if tWords.contains(where: { varText.contains($0) }) { score += 2 }
        }

        return score
    }

    /// Extracts all integers from a string (handles digit sequences only).
    private func extractIntegers(from text: String) -> Set<Int> {
        var result = Set<Int>()
        var current = ""
        for ch in text {
            if ch.isNumber {
                current.append(ch)
            } else {
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
            path.move(to:   CGPoint(x: 0, y: 12))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 12, y: 0))
        }
        .stroke(Design.Colors.bobaOrange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 12, height: 12)
    }
}
