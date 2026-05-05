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
    /// Brief "Saved N to collection" toast after a quick-save in
    /// single-scan mode. nil = hidden.
    @State private var quickSaveToast: String?

    @State private var cameraPermission =
        AVCaptureDevice.authorizationStatus(for: .video)

    // Reference to the preview layer for ROI computation after layout
    @State private var previewLayer: AVCaptureVideoPreviewLayer?

    /// User-facing Grid scan flow (camera or photo-library input).
    /// Presented as a fullScreenCover when the user taps the GRID
    /// mode pill. Independent of the streaming AVFoundation pipeline.
    @State private var showGridScan = false
    /// Set to true by GridScanView's `onAddedToQueue` callback BEFORE
    /// it dismisses. Read in `.fullScreenCover(... onDismiss:)` so the
    /// queue-review sheet only opens AFTER the cover has fully closed
    /// — chained presentations don't work when the second presentation
    /// is set inside the first's lifetime.
    @State private var pendingQueueOpen = false

    /// Active walkthrough script — fires once on first scan-screen
    /// open per device. Re-launchable from the top-bar overflow Menu
    /// (DESIGN.md §6.10 re-launch rule). Role-aware via the factory
    /// in BOBAWalkthrough.Script.scannerOverview(...).
    @State private var walkthrough: BOBAWalkthrough.Script? = nil

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
        .onAppear  {
            setupScanner()
            // Fire the unified scanner walkthrough on first open.
            // Role + entry-context determine whether the Show-mode
            // step is appended.
            if walkthrough == nil
                && WalkthroughsManager.shared.shouldShow(.scannerOverview) {
                // Defer 250ms so the cardGuideFrame + bottomControls
                // mode pills lay out before the walkthrough captures
                // their anchors.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    walkthrough = .scannerOverview
                }
            }
        }
        .onDisappear {
            scanner.stop()
            chipDismissTask?.cancel()
            withAnimation { chipVisible = false }
        }
        .walkthroughOverlay($walkthrough)
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
        .sheet(isPresented: $showQueueView) {
            ScanQueueView()
        }
        .overlay(alignment: .top) {
            if let msg = quickSaveToast {
                HStack(spacing: 8) {
                    Image(systemName: msg.hasPrefix("Save failed")
                                       ? "exclamationmark.triangle.fill"
                                       : "checkmark.circle.fill")
                        .foregroundStyle(msg.hasPrefix("Save failed")
                                          ? Color(hex: "C0392B")
                                          : Color(hex: "4CAF50"))
                    Text(msg)
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.surface.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.md)
                                .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
                        )
                )
                .padding(.top, 110)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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

                // Card guide frame — also the walkthrough anchor for
                // the "viewfinder" step. Anchoring on the guide
                // (not the entire camera layer) puts the cyan ring
                // around the actual capture area users target.
                cardGuideFrame
                    .walkthroughAnchor("scanner.viewfinder")

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
        ZStack(alignment: .center) {
            BOBAWordmark()
                .frame(maxWidth: .infinity)

            HStack {
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
                    .walkthroughAnchor("scanner.queueButton")
                }
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
                ScanDetectionChipView(
                    card: card,
                    isSingleMode: !scanStore.isMultiCardMode,
                    onTap: {
                        selectedCard = card
                        if !scanStore.isMultiCardMode {
                            scanner.resetDetection()
                        }
                    },
                    onQuickSave: { quantity in
                        Task { await quickSaveToCollection(card: card, quantity: quantity) }
                    }
                )
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

            // Mode row — Single / Multi (+ Show when the user is a
            // streamer AND the scanner wasn't launched from the deck
            // builder). In a deck-builder session the destination is
            // always the in-progress deck (with optional collection
            // mirror) — Show Mode there has no meaningful destination.
            HStack {
                Spacer()
                modePill(for: .single, label: "SINGLE", icon: "rectangle.on.rectangle")
                modePill(for: .multi,  label: "MULTI",  icon: "rectangle.stack.fill")
                gridPill
                if auth.isStreamer && scanStore.source != .deckBuilder {
                    modePill(for: .show, label: "SHOW", icon: "dot.radiowaves.up.forward")
                        .walkthroughAnchor("scanner.showPill")
                }
            }
            // Leading padding gives the walkthrough spotlight ring
            // (anchor padded by ±8) clearance from the screen's left
            // edge — without it the ring's left edge sat at x=-8 and
            // got clipped.
            .padding(.leading, Design.Spacing.lg)
            .padding(.trailing, Design.Spacing.lg)
            .padding(.bottom, 90)
            .walkthroughAnchor("scanner.modePills")
        }
        .fullScreenCover(isPresented: $showGridScan, onDismiss: {
            // Restart the streaming scanner — it was paused below in
            // .onChange when the cover opened so UIImagePickerController
            // could acquire the camera hardware cleanly.
            scanner.start()
            // Open the queue-review sheet only after the fullScreenCover
            // dismissal animation has fully completed. Setting the sheet
            // binding inside the cover's lifetime (or in a Task.sleep
            // after dismiss()) silently no-ops because SwiftUI suppresses
            // overlapping presentations on the same host view.
            if pendingQueueOpen {
                pendingQueueOpen = false
                showQueueView = true
            }
        }) {
            GridScanView(onAddedToQueue: {
                pendingQueueOpen = true
            })
        }
        // Stop the streaming AVFoundation session whenever the Grid
        // cover is on top. Without this, two camera consumers fight
        // for the same hardware (FigCaptureSourceRemote err=-17281,
        // "Attempted to change to mode Portrait with an unsupported
        // device" in the console) and UIImagePickerController returns
        // a degraded image — handheld grid shots only resolved 1–2
        // cards out of 9 because of this contention.
        .onChange(of: showGridScan) { _, newValue in
            if newValue {
                scanner.stop()
            }
        }
    }

    /// GRID pill — same visual style as the other mode pills, but
    /// instead of switching scanStore.mode it presents GridScanView
    /// as a fullScreenCover. Single/Multi/Show stay live behind it.
    private var gridPill: some View {
        Button {
            showGridScan = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.3x3").font(.system(size: 12))
                Text("GRID").font(Design.Fonts.mono(11, weight: .bold)).tracking(0.5)
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, Design.Spacing.sm + 2)
            .padding(.vertical, Design.Spacing.sm - 1)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(Capsule().strokeBorder(
                        Color.white.opacity(0.25), lineWidth: 1))
            )
        }
    }

    /// One pill in the scanner's mode row. Tap selects that mode; the
    /// current selection is tinted orange. Show mode is streamer-only
    /// (the pill just doesn't render for other roles).
    private func modePill(for mode: ScanStore.Mode, label: String, icon: String) -> some View {
        let isSelected = scanStore.mode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scanStore.mode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(Design.Fonts.mono(11, weight: .bold)).tracking(0.5)
            }
            .foregroundStyle(isSelected ? Design.Colors.bobaOrange : .white.opacity(0.7))
            .padding(.horizontal, Design.Spacing.sm + 2)
            .padding(.vertical, Design.Spacing.sm - 1)
            .background(
                Capsule()
                    .fill(isSelected ? Design.Colors.bobaOrange.opacity(0.2) : Color.white.opacity(0.12))
                    .overlay(Capsule().strokeBorder(
                        isSelected ? Design.Colors.bobaOrange.opacity(0.6) : Color.white.opacity(0.25),
                        lineWidth: 1))
            )
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
        // Seed Vision with all card numbers as custom vocabulary.
        let numbers = cardStore.displayCards.map { $0.cardNumber.uppercased() }
        scanner.setCardNumbers(numbers)

        // Also seed the recognizer with hero + play names. Vision's
        // customWords nudges it toward known vocabulary when glyphs are
        // ambiguous, which is the wedge for the "MAHOMES → MERLOMES" and
        // "ROLLER DOGS truncated" misreads — the recognizer was inventing
        // plausible-but-wrong words because it had no signal that the
        // intended words were valid card vocabulary. Heroes + plays only:
        // sealed product names, set names, and treatment names are not
        // printed prominently on cards and would just dilute the boost.
        let names = scanVocabularyNames(from: cardStore.displayCards)
        scanner.setVocabularyNames(names)

        scanner.onCardObservation = { [self] observation in
            handleDetected(observation: observation)
        }
        scanner.start()
    }

    /// Collect the printed-text vocabulary that Vision should treat as
    /// known words. Hero names (the big top-left text on a Hero card)
    /// and Play card names (the title across the top of a Play). Each
    /// word is added separately AND each multi-word phrase is added as
    /// a single token, so Vision can match either tokenization. Capped
    /// at a generous limit just in case the customWords array has a
    /// soft size limit on older iOS versions.
    private func scanVocabularyNames(from cards: [Card]) -> [String] {
        var bag: Set<String> = []
        for card in cards {
            switch card.cardType {
            case "Hero":
                let h = card.hero.uppercased().trimmingCharacters(in: .whitespaces)
                if !h.isEmpty { bag.insert(h) }
                for w in h.components(separatedBy: .whitespaces) where w.count >= 3 {
                    bag.insert(w)
                }
            case "Play":
                let n = card.name.uppercased().trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { bag.insert(n) }
                for w in n.components(separatedBy: .whitespaces) where w.count >= 3 {
                    bag.insert(w)
                }
            default:
                continue
            }
        }
        return Array(bag)
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
        // Unified recognizer — same path Grid scan uses. FP + cardNumber
        // + hero name fused with hero-veto and confidence/margin gates.
        // Returns nil ("don't guess") when signals don't agree well
        // enough — the chip simply doesn't appear, and the scanner's
        // requireConsecutive gate retries on the next frame.
        Task { @MainActor in
            if let resolved = await ScanMatching.resolve(
                observation: observation,
                allCards:    cardStore.displayCards,
                label:       "live"
            ) {
                commitDetected(resolved)
            }
        }
    }

    /// Single commit path for a detected card. Assigns `detectedCard`,
    /// shows the chip, and (in multi mode) queues + schedules dismiss.
    /// Called either synchronously (no tiebreak) or from the async
    /// tiebreak Task — never both for the same observation.
    private func commitDetected(_ card: Card) {
        detectedCard = card
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            chipVisible = true
        }
        if scanStore.isMultiCardMode {
            scanStore.addToQueue(card)
            chipDismissTask?.cancel()
            chipDismissTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { chipVisible = false }
            }
        }
    }

    // MARK: - Quick-save (single scan)

    /// Single-scan quick-save: writes `quantity` user_card rows for
    /// the detected card to the user's Collection (designation
    /// .personal), dismisses the chip, and surfaces a brief toast.
    /// Triggered from the chip's "Add to Collection" button.
    private func quickSaveToCollection(card: Card, quantity: Int) async {
        let n = max(1, min(99, quantity))
        var firstError: String?
        for _ in 0..<n {
            let entry = NewUserCard(
                cardNumber: card.cardNumber,
                bobaId: card.id,
                designation: .personal
            )
            do { try await collectionStore.addCard(entry) }
            catch { if firstError == nil { firstError = error.localizedDescription } }
        }
        if let err = firstError {
            quickSaveToast = "Save failed: \(err)"
        } else {
            quickSaveToast = "Saved \(n) to collection"
        }
        // Dismiss chip + scanner detection so the user can scan the next card.
        withAnimation(.easeOut(duration: 0.25)) { chipVisible = false }
        scanner.softReset()
        // Auto-hide the toast after a moment.
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { quickSaveToast = nil }
            }
        }
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
