import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import Combine

/// User-facing Grid scan mode. Shows a single image (camera capture
/// or photo library selection) and runs it through the full Grid
/// pipeline: GridCardDetector → multi-pass OCR → catalog match
/// (number + Phase-2 image-similarity tiebreak + hero-name
/// fallback). Each detected card with a successful match is queued
/// to ScanStore so the existing Multi/Show queue interface can
/// review pricing and route to collection or show.
@MainActor
struct GridScanView: View {
    @Environment(\.dismiss)             private var dismiss
    @Environment(CardStore.self)        private var cardStore
    @Environment(ScanStore.self)        private var scanStore

    /// Callback the parent ScanView uses to open the existing queue
    /// review interface after the user confirms a Grid scan. Lets
    /// pricing + designation choices flow through the same UI as
    /// Multi/Show queues.
    let onAddedToQueue: () -> Void

    @State private var sourceImage: UIImage?
    @State private var sourcePickerMode: SourcePickerMode = .none
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var processing = false
    @State private var results: [GridResult] = []
    @State private var statusMessage = ""

    enum SourcePickerMode {
        case none, camera, library
    }

    struct GridResult: Identifiable {
        let id = UUID()
        let row: Int
        let column: Int
        let crop: UIImage
        /// Card's bounding box in normalized CIImage coordinates
        /// (bottom-left origin, range 0–1). Carried from the
        /// detector through to the pricing-overlay generator so the
        /// composer can stamp price pills at each card's position.
        let cellRect: CGRect
        /// The card the user has accepted for this cell. Initially set
        /// from `ScanMatching.Resolution.chosen`; can be overridden by
        /// the user via the disambiguation picker.
        var matched: Card?
        /// Top-5 candidates from the resolver, used to populate the
        /// disambiguation picker. Empty when the resolver couldn't
        /// produce any usable candidates (truly not detected).
        let candidates: [ScanMatching.PickerCandidate]
        var includedInQueue: Bool = true

        /// Auto-commit confidence as a 0–99 percentage. Computed from
        /// the score gap between the winner and the runner-up
        /// candidate — large margin → high confidence; tight margin
        /// (e.g. Wattage 141 vs ABF-616, two treatments of the same
        /// hero with shared artwork) → lower confidence. nil for
        /// uncommitted cells (needsPick / notDetected) where there's
        /// no chosen card to be confident about.
        ///
        /// Mapping: margin 0 → 50%, margin 1.0 → ~99%. Linear in
        /// between. The 50% floor reflects that a committed card
        /// already passed the kMinConfidence + kMinMargin gates in
        /// ScanMatching — it's never a coin flip.
        var confidencePercent: Int? {
            guard matched != nil, candidates.count >= 2 else { return nil }
            let margin = candidates[0].score - candidates[1].score
            return min(99, max(50, 50 + Int((margin * 50).rounded())))
        }

        /// Cell state for UI rendering:
        /// - `.committed` — resolver picked a card, ready to queue
        /// - `.needsPick` — resolver had candidates but no clear winner;
        ///                  user must tap to choose
        /// - `.notDetected` — no candidates at all (badge unreadable, OCR
        ///                    failed, FP missed, etc.)
        var state: CellState {
            if matched != nil { return .committed }
            if !candidates.isEmpty { return .needsPick }
            return .notDetected
        }
    }

    enum CellState {
        case committed
        case needsPick
        case notDetected
    }

    @State private var pickerCellID: GridResult.ID?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Grid Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
                if !results.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        let n = results.filter { $0.matched != nil && $0.includedInQueue }.count
                        Button("Add \(n) to Queue") { addToQueueAndClose() }
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .disabled(n == 0)
                    }
                }
            }
        }
        .photosPicker(
            isPresented: Binding(
                get: { sourcePickerMode == .library },
                set: { if !$0 && sourcePickerMode == .library { sourcePickerMode = .none } }
            ),
            selection: $photoPickerItem,
            matching: .images
        )
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    // Library path is single-frame — no burst available
                    // for previously-taken photos, so we pass [img] and
                    // the OCR pipeline degrades gracefully (no cross-
                    // frame voting, but still gets multi-pass voting).
                    await loadAndProcess(frames: [img])
                }
                photoPickerItem = nil
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { sourcePickerMode == .camera },
            set: { if !$0 && sourcePickerMode == .camera { sourcePickerMode = .none } }
        )) {
            // Direct AVFoundation capture — bypasses UIImagePickerController
            // entirely, which on triple-camera iPhones spammed
            // `FigCaptureSourceRemote err=-17281` and "unsupported device
            // (BackTriple)" errors and routinely returned a degraded image
            // that only resolved 1–2 cards out of 9. Once we have the
            // UIImage, the path is identical to the photo-library flow:
            // hand it to `loadAndProcess` → GridCardDetector → multi-pass
            // OCR → ScanMatching.resolve.
            GridCameraCaptureView { frames in
                sourcePickerMode = .none
                guard !frames.isEmpty else { return }
                Task { await loadAndProcess(frames: frames) }
            }
            // Intentionally NOT calling `.ignoresSafeArea()` here —
            // the camera preview inside the view ignores safe area
            // explicitly so it fills the screen edge-to-edge, but
            // the capture/cancel controls need to stay inside the
            // safe area or the cancel button hides under the
            // Dynamic Island / system clock. Pushing the whole
            // view past the safe area broke that.
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if processing {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .scaleEffect(1.5)
                Text(statusMessage)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(.white)
            }
        } else if !results.isEmpty {
            resultsView
        } else if let img = sourceImage {
            VStack(spacing: 12) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                if !statusMessage.isEmpty {
                    // Surfaces the post-failure reason ("Couldn't find
                    // any cards. Try a clearer photo.") so the user
                    // isn't staring at a Process button cycle that
                    // re-runs the same failing detection.
                    Text(statusMessage)
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                HStack(spacing: 12) {
                    Button {
                        // Reset and let the user pick another image.
                        sourceImage = nil
                        statusMessage = ""
                        results = []
                    } label: {
                        Text("Choose another")
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaCyan)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radius.md)
                                    .stroke(Design.Colors.bobaCyan, lineWidth: 1)
                            )
                    }
                    Button {
                        if let img = sourceImage {
                            Task { await processSourceFrames(frames: [img]) }
                        }
                    } label: {
                        Text(statusMessage.isEmpty ? "Process" : "Retry")
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Design.Colors.bobaOrange)
                            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        } else {
            sourcePromptView
        }
    }

    private var sourcePromptView: some View {
        VStack(spacing: 16) {
            cardShapedGridIcon
            Text("Photograph up to 9 cards in a 3×N grid.\nTake a new picture or choose one from your library.")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack(spacing: 12) {
                Button {
                    sourcePickerMode = .camera
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo").font(Design.Fonts.mono(13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Design.Colors.bobaOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                }
                Button {
                    sourcePickerMode = .library
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("From Library").font(Design.Fonts.mono(13, weight: .bold))
                    }
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Design.Colors.bobaCyan.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// 3×3 grid of cyan card-shaped rectangles. Replaces the SF Symbol
    /// `square.grid.3x3` so the prompt makes it visually clear we're
    /// photographing CARDS — the SF Symbol's square cells looked like
    /// generic boxes and didn't communicate the trading-card aspect.
    private var cardShapedGridIcon: some View {
        let cellW: CGFloat = 22
        let cellH: CGFloat = cellW / 0.714
        let spacing: CGFloat = 4
        return VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Design.Colors.bobaCyan)
                            .frame(width: cellW, height: cellH)
                    }
                }
            }
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                let matchCount = results.filter { $0.matched != nil }.count
                let needsPickCount = results.filter { $0.state == .needsPick }.count
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(matchCount)/\(results.count) identified")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(.white)
                    if needsPickCount > 0 {
                        Text("\(needsPickCount) need\(needsPickCount == 1 ? "s" : "") your pick")
                            .font(Design.Fonts.mono(11))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                }
                Spacer()
                Button("Re-scan") {
                    sourceImage = nil
                    results = []
                }
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.bobaCyan)
            }
            .padding()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(results) { r in resultCell(r) }
                }
                .padding()
            }
        }
        .sheet(item: pickerBinding) { r in
            CardDisambiguationSheet(
                cellCrop:   r.crop,
                candidates: r.candidates,
                currentMatch: r.matched,
                allCards:   cardStore.displayCards,
                onSelect:   { card in commitFromPicker(cellID: r.id, card: card) },
                onSkip:     { dismissPicker(forCellID: r.id) },
                onNone:     { rejectAllForCell(cellID: r.id) }
            )
        }
    }

    /// Maps the @State `pickerCellID` to the GridResult under the sheet.
    /// Using `Binding<GridResult?>` ensures the sheet binds to the
    /// current snapshot of the results array — when the user commits a
    /// pick we mutate `results[idx].matched` and the sheet auto-dismisses.
    private var pickerBinding: Binding<GridResult?> {
        Binding(
            get: {
                guard let id = pickerCellID else { return nil }
                return results.first(where: { $0.id == id })
            },
            set: { newValue in
                pickerCellID = newValue?.id
            }
        )
    }

    private func resultCell(_ r: GridResult) -> some View {
        Button {
            // Both committed cells (review/override) and needsPick
            // cells open the same picker. notDetected cells have
            // nothing to pick from — the button is still tappable
            // for consistency but no-ops.
            guard !r.candidates.isEmpty else { return }
            pickerCellID = r.id
        } label: {
            cellContent(r)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cellContent(_ r: GridResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: r.crop)
                    .resizable()
                    .aspectRatio(0.714, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                stateBadge(r)
                    .padding(4)
            }
            // Confidence pill above the cardNumber/hero label —
            // shown for committed cells so the user can see, at a
            // glance, how sure the resolver is. Color-coded:
            // ≥ 85% cyan, 70-84% orange, < 70% red. Below-70% reads
            // as "tap to review"; the resolver only commits cells
            // that pass kMinConfidence + kMinMargin so the floor is
            // 50%, never lower.
            if let pct = r.confidencePercent {
                HStack(spacing: 4) {
                    Image(systemName: confidenceIcon(pct))
                        .font(.system(size: 10, weight: .bold))
                    Text("\(pct)% match")
                        .font(Design.Fonts.mono(10, weight: .bold))
                }
                .foregroundStyle(confidenceColor(pct))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(confidenceColor(pct).opacity(0.14))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(confidenceColor(pct).opacity(0.35), lineWidth: 1)
                )
                .accessibilityLabel("Match confidence \(pct) percent. Tap card to review or change.")
            }
            stateLabel(r)
        }
        .padding(6)
        .background(cellBackground(r))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.md)
                .stroke(cellBorder(r), lineWidth: cellBorderWidth(r))
        )
    }

    private func confidenceColor(_ pct: Int) -> Color {
        if pct >= 85 { return Design.Colors.bobaCyan }
        if pct >= 70 { return Design.Colors.bobaOrange }
        return Color(red: 1.0, green: 0.36, blue: 0.36)
    }

    private func confidenceIcon(_ pct: Int) -> String {
        if pct >= 85 { return "checkmark.seal.fill" }
        if pct >= 70 { return "questionmark.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    @ViewBuilder
    private func stateBadge(_ r: GridResult) -> some View {
        switch r.state {
        case .committed:
            Button {
                toggleIncluded(r)
            } label: {
                Image(systemName: r.includedInQueue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(r.includedInQueue ? Design.Colors.bobaCyan : .white.opacity(0.7))
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
        case .needsPick:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Design.Colors.bobaOrange)
                .background(Circle().fill(.black.opacity(0.5)))
        case .notDetected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.red.opacity(0.85))
                .background(Circle().fill(.black.opacity(0.5)))
        }
    }

    @ViewBuilder
    private func stateLabel(_ r: GridResult) -> some View {
        switch r.state {
        case .committed:
            if let card = r.matched {
                Text(card.cardNumber)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .lineLimit(1)
            }
        case .needsPick:
            Text("Tap to choose")
                .font(Design.Fonts.mono(11, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .lineLimit(1)
            if let topHero = r.candidates.first?.card.hero, !topHero.isEmpty {
                Text(topHero)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            } else {
                Text("\(r.candidates.count) candidates")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .notDetected:
            Text("Not detected")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(.red)
        }
    }

    private func cellBackground(_ r: GridResult) -> Color {
        switch r.state {
        case .committed, .notDetected:
            return Color.white.opacity(0.05)
        case .needsPick:
            return Design.Colors.bobaOrange.opacity(0.08)
        }
    }

    private func cellBorder(_ r: GridResult) -> Color {
        r.state == .needsPick ? Design.Colors.bobaOrange.opacity(0.5) : .clear
    }

    private func cellBorderWidth(_ r: GridResult) -> CGFloat {
        r.state == .needsPick ? 1 : 0
    }

    // MARK: - Picker actions

    private func commitFromPicker(cellID: GridResult.ID, card: Card) {
        guard let idx = results.firstIndex(where: { $0.id == cellID }) else { return }
        results[idx].matched = card
        results[idx].includedInQueue = true
        pickerCellID = nil
    }

    private func dismissPicker(forCellID id: GridResult.ID) {
        pickerCellID = nil
    }

    private func rejectAllForCell(cellID: GridResult.ID) {
        guard let idx = results.firstIndex(where: { $0.id == cellID }) else { return }
        results[idx].matched = nil
        results[idx].includedInQueue = false
        pickerCellID = nil
    }

    // MARK: - Pipeline

    /// Burst-frame source images. `[0]` is the primary used for
    /// grid detection / preview display; subsequent frames feed
    /// cross-frame OCR voting (the still-image analog of the
    /// streaming scanner's requireConsecutive=2 stability bar).
    /// Library-picker selections call this with `[singleImage]`
    /// and degrade gracefully — multi-pass voting still applies
    /// per cell, just without the cross-frame layer.
    private func loadAndProcess(frames: [UIImage]) async {
        guard let primary = frames.first else { return }
        sourceImage = primary
        await processSourceFrames(frames: frames)
    }

    private func processSourceFrames(frames: [UIImage]) async {
        let tStart = Date()
        // Camera-captured UIImages can carry an .right or .down
        // EXIF orientation while the underlying CGImage stays in
        // sensor (landscape) orientation. Bake orientation on every
        // frame so the detector and per-frame crops both see upright
        // pixels.
        let upright = frames.map { $0.orientationCorrected() }
        let tOrient = Date()
        guard let primary = upright.first else { return }
        sourceImage = primary
        processing = true
        statusMessage = "Detecting cards…"

        let scanner = CardScanner()
        scanner.setCardNumbers(cardStore.displayCards.map { $0.cardNumber.uppercased() })
        let names = cardStore.displayCards.flatMap { card -> [String] in
            var out: [String] = []
            if !card.hero.isEmpty { out.append(card.hero) }
            if !card.name.isEmpty, card.name != card.hero { out.append(card.name) }
            return out
        }
        scanner.setVocabularyNames(names)
        await scanner.awaitVocabularyReady()
        let tVocab = Date()

        let detected: [GridCardDetector.DetectedCard]
        do {
            detected = try await GridCardDetector.detect(in: primary)
        } catch {
            statusMessage = "Couldn't find any cards. Try a clearer photo."
            processing = false
            return
        }
        let tDetect = Date()
        statusMessage = upright.count > 1
            ? "Identifying \(detected.count) cards across \(upright.count) frames…"
            : "Identifying \(detected.count) cards…"

        #if DEBUG
        let primaryW = Int(primary.size.width)
        let primaryH = Int(primary.size.height)
        print(String(format: "⏱  GRID start  primary=%dx%d  cells=%d", primaryW, primaryH, detected.count))
        print(String(format: "⏱  orient      %.0fms", tOrient.timeIntervalSince(tStart) * 1000))
        print(String(format: "⏱  vocab       %.0fms", tVocab.timeIntervalSince(tOrient) * 1000))
        print(String(format: "⏱  detect      %.0fms", tDetect.timeIntervalSince(tVocab) * 1000))
        #endif

        // Per-cell pipeline factored into a closure so we can run it
        // in parallel via TaskGroup. Each cell's work is independent
        // (its own crops, its own observation, its own resolver
        // call) — only the shared catalog / scanner / FP index are
        // accessed concurrently, all of which are read-only at this
        // point.
        let allCards = cardStore.displayCards
        let upright_ = upright

        @Sendable
        func processCell(_ d: GridCardDetector.DetectedCard) async -> GridResult {
            #if DEBUG
            let cellStart = Date()
            #endif
            var cellCrops: [UIImage] = [d.image]
            for f in upright_.dropFirst() {
                if let crop = GridCardDetector.cropFrame(
                    f, cellRect: d.cellRect,
                    orientation: d.sourceOrientation) {
                    cellCrops.append(crop)
                }
            }
            let r = await scanner.scanGridImageBurst(crops: cellCrops)
            #if DEBUG
            let afterOCR = Date()
            #endif
            let observation = ScanObservation(
                cardNumber:   r.cardNumber ?? "",
                rawName:      r.topLeftText,
                rawPower:     r.topRightText,
                rawVariation: r.bottomRightText,
                fullText:     r.allText,
                cgImage:      r.cgImage
            )
            let resolution = await ScanMatching.resolveDetailed(
                observation: observation,
                allCards:    allCards,
                label:       "cell r\(d.row)c\(d.column)"
            )
            #if DEBUG
            let afterResolve = Date()
            let cnFound = (r.cardNumber ?? "") != ""
            print(String(format: "⏱  cell r%dc%d  ocr=%.0fms  resolve=%.0fms  total=%.0fms  cn=%@",
                         d.row, d.column,
                         afterOCR.timeIntervalSince(cellStart) * 1000,
                         afterResolve.timeIntervalSince(afterOCR) * 1000,
                         afterResolve.timeIntervalSince(cellStart) * 1000,
                         cnFound ? "yes" : "NO"))
            #endif
            return GridResult(
                row: d.row, column: d.column,
                crop: d.image,
                cellRect: d.cellRect,
                matched: resolution.chosen,
                candidates: resolution.topCandidates,
                includedInQueue: resolution.chosen != nil)
        }

        // Sequential cell processing (concurrency = 1). Two prior
        // attempts at parallelism (4-way and 2-way) showed the same
        // pattern: the FIRST cell of a batch finished fast (~1s),
        // every subsequent cell in flight stretched to 5-10s. The
        // Neural Engine fully serializes Vision requests internally
        // — there's no actual hardware parallelism for OCR + FP,
        // and the overlap we hoped to get from CPU/GPU stages turns
        // into queue contention that makes individual requests
        // slower. Empirically, 9 × T_uncontended (~1s) beats
        // ⌈9/N⌉ × T_busy (5-8× T_uncontended) for any N > 1.
        let maxConcurrent = 1
        var indexed: [(index: Int, result: GridResult)] = []
        indexed.reserveCapacity(detected.count)
        await withTaskGroup(of: (Int, GridResult).self) { group in
            var inflight = 0
            var nextIdx = 0
            // Seed the group up to maxConcurrent.
            while inflight < maxConcurrent, nextIdx < detected.count {
                let i = nextIdx
                let d = detected[i]
                group.addTask { (i, await processCell(d)) }
                nextIdx += 1
                inflight += 1
            }
            // As each completes, queue the next.
            while let (i, res) = await group.next() {
                indexed.append((i, res))
                inflight -= 1
                if nextIdx < detected.count {
                    let i2 = nextIdx
                    let d = detected[i2]
                    group.addTask { (i2, await processCell(d)) }
                    nextIdx += 1
                    inflight += 1
                }
            }
        }
        // Restore detection order (the TaskGroup completes out of order).
        var orderedResults = indexed.sorted { $0.index < $1.index }.map { $0.result }

        // PASS 2: cross-cell SET context override. Tally the set of
        // confidently-committed cells across this scan; if there's
        // a clear majority (>= half of committed cells), use it as
        // a tiebreaker for cells where the top-2 candidates disagree
        // on set. People scan packs from a single release, so the
        // set of confident commits is a strong prior. Recovers
        // Ozzmosis-172 (Griffey) over Laviathan-172 (Alpha Update)
        // when same-cn-different-hero ties had no other tiebreaker.
        var setCounts: [String: Int] = [:]
        for r in orderedResults {
            if let m = r.matched { setCounts[m.set, default: 0] += 1 }
        }
        let majoritySet = setCounts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
        let totalCommitted = orderedResults.filter { $0.matched != nil }.count
        let setIsConfident = (majoritySet?.1 ?? 0) >= max(2, totalCommitted / 2 + 1)

        if let (majSet, _) = majoritySet, setIsConfident {
            for i in orderedResults.indices {
                guard !orderedResults[i].candidates.isEmpty else { continue }
                let top = orderedResults[i].candidates[0]
                guard top.card.set != majSet else { continue }
                // Look for a same-or-near-score candidate with the
                // majority set, within 0.5 of the top.
                for cand in orderedResults[i].candidates.dropFirst() {
                    if cand.card.set == majSet, (top.score - cand.score) <= 0.5 {
                        orderedResults[i].matched = cand.card
                        orderedResults[i].includedInQueue = true
                        break
                    }
                }
            }
        }
        results = orderedResults
        #if DEBUG
        let tEnd = Date()
        print(String(format: "⏱  GRID DONE   total=%.0fms  cells=%d  parallel-budget=%dms",
                     tEnd.timeIntervalSince(tStart) * 1000,
                     detected.count,
                     Int(tEnd.timeIntervalSince(tDetect) * 1000)))
        #endif
        processing = false
        statusMessage = ""
    }

    private func toggleIncluded(_ r: GridResult) {
        guard let idx = results.firstIndex(where: { $0.id == r.id }) else { return }
        results[idx].includedInQueue.toggle()
    }

    /// Add every checked result to the existing scanStore queue,
    /// then dismiss this Grid view and let the parent ScanView
    /// open the standard queue interface (where pricing shows up
    /// and the user picks collection vs show vs save-all).
    private func addToQueueAndClose() {
        // Default the queue to multi mode unless already in show
        // mode. Grid is fundamentally a "many cards at once" flow
        // so single mode would defeat the purpose.
        if scanStore.mode != .show {
            scanStore.mode = .multi
        }
        for r in results where r.includedInQueue {
            if let card = r.matched {
                scanStore.addToQueue(card)
            }
        }
        // Capture the source photo + per-cell rectangles for the
        // optional pricing-overlay generator that the queue UI shows
        // in Show mode. Only stash if at least one cell was committed
        // — otherwise there's nothing to overlay prices onto.
        if let photo = sourceImage {
            let cells: [ScanStore.GridScanContext.Cell] = results.compactMap { r -> ScanStore.GridScanContext.Cell? in
                guard r.includedInQueue, let card = r.matched else { return nil }
                return ScanStore.GridScanContext.Cell(
                    cardID: card.id,
                    cellRect: r.cellRect
                )
            }
            if !cells.isEmpty {
                scanStore.lastGridScanContext = ScanStore.GridScanContext(
                    sourcePhoto: photo,
                    cells: cells
                )
            }
        }
        // Signal the parent BEFORE dismissing — the parent's
        // `.fullScreenCover(... onDismiss:)` reads the flag we set
        // here AFTER the dismissal animation finishes, then opens
        // the queue-review sheet. Setting it inside our own dismiss
        // window (or via Task.sleep) silently no-ops because SwiftUI
        // suppresses overlapping presentations on the host view.
        onAddedToQueue()
        dismiss()
    }
}

// MARK: - UIImage orientation helper

extension UIImage {
    /// Re-render the image in `.up` orientation. UIImagePickerController
    /// (camera capture) returns images whose underlying CGImage is in
    /// raw sensor orientation (landscape) with EXIF metadata flagging
    /// .right; CIImage + Vision then process the raw pixels and ignore
    /// the metadata, which makes the detector think cards are sideways.
    ///
    /// Uses the LOSSLESS `CIImage.oriented + CIContext.createCGImage`
    /// path to match the CLI tool's pipeline (`tools/RecognizerCLI`).
    /// An earlier rev re-encoded via `jpegData(compressionQuality:0.95)`
    /// then re-decoded — convenient because UIImage(data:) bakes
    /// orientation into pixels, but the JPEG round-trip is LOSSY:
    /// for a HEIC source (compressed much more efficiently than JPEG),
    /// the round-trip degrades the pixels enough that Vision's text
    /// recognition and feature-print outputs differ from what the CLI
    /// gets for the same source file. That divergence caused borderline
    /// cells to commit to different cards on iOS vs CLI on identical
    /// HEIC inputs. CGImage + CIImage.oriented is byte-equivalent to
    /// the CLI's pipeline.
    func orientationCorrected() -> UIImage {
        if imageOrientation == .up { return self }
        if let cg = self.cgImage {
            let exifOri: CGImagePropertyOrientation = {
                switch imageOrientation {
                case .up:            return .up
                case .upMirrored:    return .upMirrored
                case .down:          return .down
                case .downMirrored:  return .downMirrored
                case .left:          return .left
                case .leftMirrored:  return .leftMirrored
                case .right:         return .right
                case .rightMirrored: return .rightMirrored
                @unknown default:    return .up
                }
            }()
            let ci = CIImage(cgImage: cg).oriented(exifOri)
            let ctx = CIContext()
            if let baked = ctx.createCGImage(ci, from: ci.extent) {
                return UIImage(cgImage: baked, scale: scale, orientation: .up)
            }
        }
        // Fallback for the rare case where the UIImage has no backing
        // CGImage (e.g., CIImage-backed only). UIGraphicsImageRenderer
        // bakes orientation via draw(in:) — also lossless.
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - AVFoundation still capture (replaces UIImagePickerController)

/// Direct AVFoundation camera UI for Grid mode. Replaces
/// UIImagePickerController because, on triple-camera iPhones, the
/// system picker fails to auto-select a usable lens — the console
/// fills with `Attempted to change to mode Portrait with an
/// unsupported device (BackTriple)` and `FigCaptureSourceRemote
/// err=-17281`, the camera takes 4–6 seconds to load, and the
/// returned UIImage is degraded enough that the Grid detector only
/// resolves 1–2 cards out of 9. Pinning explicitly to
/// `.builtInWideAngleCamera` (the standard 1× lens that every iPhone
/// model has) sidesteps the auto-select failure entirely. Same
/// device that `CardScanner` uses for streaming scans.
///
/// After capture, the UIImage flows into the same `loadAndProcess`
/// path as a photo-library selection — there's no separate camera-
/// only pipeline, which is what the user explicitly asked for.
struct GridCameraCaptureView: View {
    @StateObject private var camera = GridStillCamera()
    @State private var capturing = false
    @State private var failed = false
    /// Drives a white flash overlay that fires the moment the shutter
    /// button is tapped. AVCapturePhotoOutput with `.balanced` quality
    /// runs Deep Fusion + multi-frame noise reduction, which means
    /// ~500ms passes between the user's tap and the photo actually
    /// being captured. During that window the live preview keeps
    /// updating and the user — assuming the photo is already taken —
    /// often relaxes their grip, introducing motion blur in the
    /// final frame. The flash + a haptic + an AE/AF lock on tap make
    /// the capture feel instantaneous AND keep the optics frozen
    /// on the framing that was visible at tap time.
    @State private var flashOpacity: Double = 0
    /// Hands back the burst frames in capture order. The first
    /// non-nil frame is the "primary" used for grid detection;
    /// subsequent frames are used for cross-frame OCR voting.
    let onCaptured: ([UIImage]) -> Void
    /// Number of stills captured per shutter tap.
    ///
    /// Currently 1 — burst (3 frames) was tried in d6841d5 and
    /// regressed accuracy. Cross-frame OCR voting uses the cellRect
    /// from frame 0 to crop frames 1+2; even ~20px of hand shift
    /// between frames samples a slightly different physical region,
    /// pulling neighbor-card content into frames 1+2's bottom-left
    /// edges. Voting then CONFIRMS the wrong cardNumber with
    /// high confidence (the wrong number appears in 2/3 frames).
    ///
    /// Re-enabling burst requires per-frame grid detection so each
    /// frame's cell rects are aligned to its own pixel content.
    /// Single-frame multi-pass voting (within `runMultiPassGridOCR`)
    /// remains the proven stability bar for now.
    private let burstCount = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GridCameraPreviewView(session: camera.session)
                .ignoresSafeArea()
            // White flash overlay tied to flashOpacity. Animation
            // fires from 1.0 → 0.0 over ~180ms when shutter is tapped
            // — short enough not to obscure the shot, long enough
            // to register as "shutter fired".
            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)
            VStack {
                HStack {
                    Button {
                        onCaptured([])
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Close camera")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                if failed {
                    Text("Camera unavailable.\nUse 'From Library' instead.")
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 36)
                } else {
                    Button {
                        Task { await capture() }
                    } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle().fill(.white)
                                .frame(width: 64, height: 64)
                                .opacity(capturing ? 0.5 : 1.0)
                        }
                    }
                    .disabled(capturing)
                    .padding(.bottom, 36)
                }
            }
        }
        .task {
            // Authorization check + start. CardScanner already requests
            // camera access for the streaming scanner, so by the time
            // the user reaches Grid mode we're typically authorized —
            // but a fresh install via deep-link could land here without
            // permission, hence the explicit guard.
            let granted = await camera.ensureAuthorized()
            if granted {
                await camera.start()
            } else {
                failed = true
            }
        }
        .onDisappear {
            // Background-dispatched stop. AVCaptureSession.stopRunning
            // is a blocking call; running it on the main actor produces
            // the `unsafeForcedSync called from Swift Concurrent context`
            // warning seen previously.
            camera.stop()
        }
    }

    private func capture() async {
        guard !capturing else { return }
        capturing = true

        #if DEBUG
        let tTap = Date()
        #endif

        // Immediate sensory feedback so the user knows the shutter
        // fired RIGHT NOW, before Deep Fusion's ~500ms processing
        // window starts. Without these the live preview keeps
        // moving for half a second after the tap and users assume
        // the capture hasn't happened yet, often shifting the
        // framing or relaxing their grip — which introduces motion
        // blur in the captured frame.
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()
        haptic.impactOccurred()

        flashOpacity = 1.0
        withAnimation(.easeOut(duration: 0.18)) { flashOpacity = 0 }

        // Lock focus + exposure to whatever the optics had at the
        // moment of tap. AVCapturePhotoOutput's processing pipeline
        // takes ~500ms; without locking, continuous AF can drift
        // mid-capture and produce a slightly out-of-focus frame.
        // The view dismisses after onCaptured so we don't bother
        // unlocking — the device gets released when the session
        // tears down.
        await camera.lockExposureAndFocus()

        #if DEBUG
        let tLocked = Date()
        #endif

        let frames = await camera.captureBurst(count: burstCount)
        capturing = false

        #if DEBUG
        let tCaptured = Date()
        print(String(format: "📷 SHUTTER lock=%.0fms  capture=%.0fms  total=%.0fms",
                     tLocked.timeIntervalSince(tTap) * 1000,
                     tCaptured.timeIntervalSince(tLocked) * 1000,
                     tCaptured.timeIntervalSince(tTap) * 1000))
        #endif

        let valid = frames.compactMap { $0 }
        onCaptured(valid)
    }
}

/// Owns the AVCaptureSession + AVCapturePhotoOutput for the Grid
/// camera flow. Configured once on first start, reused for the
/// view's lifetime. All mutating access (session start/stop,
/// continuation install/resume) is funneled through a single
/// private serial queue so the main actor never blocks on
/// AVFoundation's blocking start/stop calls and the continuation
/// is never raced.
/// `nonisolated` is required because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — without it, the class
/// (and therefore its conformance to ObservableObject and any
/// callbacks it interacts with) inherits MainActor isolation, which
/// Swift 6 then refuses to bridge to AVFoundation's nonisolated
/// callback queues. All mutable state lives on `configQueue`, so the
/// class genuinely doesn't need MainActor.
nonisolated final class GridStillCamera: NSObject, ObservableObject, @unchecked Sendable {
    /// We don't broadcast any state to SwiftUI; this exists solely to
    /// satisfy `ObservableObject`, which `@StateObject` requires.
    /// Without a `@Published` property the protocol's default
    /// synthesis isn't generated, so we provide the publisher manually.
    let objectWillChange = ObservableObjectPublisher()
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let configQueue = DispatchQueue(
        label: "GridStillCamera.config", qos: .userInitiated)
    /// Both written and read only on `configQueue`.
    private var imageContinuation: CheckedContinuation<UIImage?, Never>?
    private var configured = false
    /// Retains the per-capture delegate so AVCapturePhotoOutput's
    /// weak hold doesn't drop it before didFinishProcessing fires.
    /// Cleared in the delegate callback. Typed as NSObject so we
    /// can hold either single or burst delegates here.
    private var activeDelegate: NSObject?

    func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default:             return false
        }
    }

    func start() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            configQueue.async { [self] in
                if !configured {
                    configureSessionOnQueue()
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
                cont.resume()
            }
        }
    }

    func stop() {
        configQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureStill() async -> UIImage? {
        // captureBurst returns [UIImage?]; .first gives UIImage?? —
        // flatMap collapses to UIImage?.
        let burst = await captureBurst(count: 1)
        return burst.first.flatMap { $0 }
    }

    /// Burst-capture `count` full-resolution stills back-to-back.
    /// Returns the array in capture order (frame 0 = first, etc).
    /// Failed individual captures are returned as nil entries so
    /// the caller can preserve frame indexing. The whole burst
    /// resolves once the last frame's delegate callback fires (or
    /// errors out) — no Task.sleep gaps; AVCapturePhotoOutput
    /// serializes captures internally on a `.photo`-preset session.
    ///
    /// Why burst (vs Live Photo extraction or video data output):
    /// each frame is full 12MP (4032×3024). Live Photo movies are
    /// 1080p at 15fps — too low-res for the small cardNumber
    /// badges in a 3×N grid where each cell is ~80–150px tall.
    /// Burst preserves resolution at the cost of ~500ms of wall-
    /// clock latency, which sits comfortably inside the user's
    /// processing tolerance.
    func captureBurst(count: Int) async -> [UIImage?] {
        guard count > 0 else { return [] }
        return await withCheckedContinuation { (cont: CheckedContinuation<[UIImage?], Never>) in
            configQueue.async { [self] in
                // Defensive: cancel any in-flight single capture.
                imageContinuation?.resume(returning: nil)
                imageContinuation = nil

                let delegate = BurstCaptureDelegate(expected: count) { [weak self] images in
                    guard let self else { return }
                    self.configQueue.async {
                        cont.resume(returning: images)
                        self.activeDelegate = nil
                    }
                }
                activeDelegate = delegate

                // Each capture needs a fresh AVCapturePhotoSettings —
                // reusing throws NSInvalidArgumentException. Prefer
                // `.speed` quality so the burst completes in ~500ms
                // instead of ~750ms with `.balanced` (default).
                for _ in 0..<count {
                    let settings = AVCapturePhotoSettings()
                    settings.flashMode = .auto
                    // `.balanced` (default) keeps deep fusion + multi-
                    // frame noise reduction enabled, which sharpens
                    // small printed text. `.speed` disables those and
                    // visibly hurt OCR recall on stylized cardNumber
                    // badges. The latency cost is acceptable —
                    // capture + processing is dominated by OCR, not
                    // by the photo pipeline.
                    settings.photoQualityPrioritization = .balanced
                    photoOutput.capturePhoto(with: settings, delegate: delegate)
                }
            }
        }
    }

    /// Must run on `configQueue`. Pins explicitly to the wide-angle
    /// camera — `.default(for: .video)` would pick the device's
    /// preferred virtual camera (Auto / Triple / Dual) which is
    /// exactly what breaks on Pro phones (BackTriple/BackAuto
    /// "Auto device unsupported" errors).
    private func configureSessionOnQueue() {
        guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
    }

    /// Freeze focus + exposure to whatever the optics had at the
    /// moment of call. Called immediately after the user taps the
    /// shutter, BEFORE `captureBurst` triggers AVCapturePhotoOutput.
    /// Without this lock, the ~500ms Deep Fusion processing window
    /// can cause continuous AF to drift mid-capture and produce a
    /// frame slightly out of focus relative to what the user saw
    /// when they tapped — the difference between "matched 8 of 9
    /// cards" and "matched 4 of 9".
    func lockExposureAndFocus() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            configQueue.async {
                guard let device = AVCaptureDevice.default(
                        .builtInWideAngleCamera, for: .video, position: .back)
                else { cont.resume(); return }
                do {
                    try device.lockForConfiguration()
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    if device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                    device.unlockForConfiguration()
                } catch { /* device may already be in use; non-fatal */ }
                cont.resume()
            }
        }
    }
}

/// AVCapturePhotoCaptureDelegate for burst captures. Accumulates N
/// processed photos and fires `onComplete([UIImage?])` once the
/// expected count is reached. Implemented as a standalone
/// nonisolated class because `GridStillCamera` is implicitly
/// @MainActor (project default) and Swift 6 disallows passing a
/// MainActor-isolated delegate into AVFoundation's nonisolated
/// callback queues.
///
/// AVCapturePhotoOutput delivers `didFinishProcessingPhoto`
/// callbacks in capture submission order on a `.photo` preset
/// session, so we just append and only need a counter for
/// completion. Failed individual captures are appended as nil so
/// the caller can preserve indexing.
private nonisolated final class BurstCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let expected: Int
    private let onComplete: ([UIImage?]) -> Void
    private let queue = DispatchQueue(label: "BurstCaptureDelegate.accumulator")
    private var images: [UIImage?] = []
    private var fired = false

    init(expected: Int, onComplete: @escaping ([UIImage?]) -> Void) {
        self.expected = expected
        self.onComplete = onComplete
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Use `cgImageRepresentation()` instead of
        // `fileDataRepresentation()` to avoid the JPEG re-encode.
        //
        // fileDataRepresentation() defaults to JPEG (lossy at any
        // quality < 1.0; quality is implementation-defined and not
        // overridable here). Decoding that JPEG back into a UIImage
        // gives us pixels that differ from what Vision sees on the
        // raw HEIC equivalent — enough that OCR + feature-print
        // signatures shift on borderline cells, and library-mode
        // scans of the same scene produced different commits than
        // camera-mode scans.
        //
        // cgImageRepresentation() returns the raw decoded pixels
        // AFTER all of AVFoundation's per-photo processing (Deep
        // Fusion, multi-frame noise reduction, etc.) but BEFORE any
        // file-format compression. Combined with manual orientation
        // baking via CIImage.oriented (matching `orientationCorrected`
        // and the CLI's pipeline), the camera and library paths now
        // hand identical pixels to downstream OCR/FP for the same
        // physical scene.
        let image: UIImage? = {
            guard error == nil, let cg = photo.cgImageRepresentation() else { return nil }
            let exifOriRaw = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32 ?? 1
            let exifOri = CGImagePropertyOrientation(rawValue: exifOriRaw) ?? .up
            if exifOri == .up { return UIImage(cgImage: cg) }
            let ci = CIImage(cgImage: cg).oriented(exifOri)
            let ctx = CIContext()
            if let baked = ctx.createCGImage(ci, from: ci.extent) {
                return UIImage(cgImage: baked)
            }
            // Fallback: return UIImage with orientation flag set.
            // Downstream `orientationCorrected()` will bake it
            // losslessly via the same CIImage path.
            let uiOri: UIImage.Orientation = {
                switch exifOri {
                case .up: return .up
                case .upMirrored: return .upMirrored
                case .down: return .down
                case .downMirrored: return .downMirrored
                case .left: return .left
                case .leftMirrored: return .leftMirrored
                case .right: return .right
                case .rightMirrored: return .rightMirrored
                @unknown default: return .up
                }
            }()
            return UIImage(cgImage: cg, scale: 1.0, orientation: uiOri)
        }()
        queue.async { [self] in
            guard !fired else { return }
            images.append(image)
            if images.count >= expected {
                fired = true
                onComplete(images)
            }
        }
    }
}

/// AVCaptureVideoPreviewLayer wrapper. Backing layer is set as the
/// view's main layer (via `layerClass`) so the preview fills the
/// view bounds automatically without manual frame management on
/// rotation or layout changes.
struct GridCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - CardDisambiguationSheet
//
// Presented as a sheet from GridScanView when the user taps a cell.
// Shows the captured cell crop alongside the resolver's top candidates
// so the user can confirm or override the system's pick. Inlined here
// (rather than its own file) per DECISIONS.md #031 — Xcode's
// PBXFileSystemSynchronizedRootGroup intermittently fails to pick up
// new Swift files. Co-locating with GridScanView keeps things robust.

struct CardDisambiguationSheet: View {
    let cellCrop: UIImage
    let candidates: [ScanMatching.PickerCandidate]
    /// The currently-committed match for this cell (nil if needsPick).
    /// Drives the "BEST" pill on the matching row when reviewing.
    let currentMatch: Card?
    /// Full catalog — used to power the manual-search escape hatch
    /// for cells where no signal surfaces the right card (Skuba 68
    /// case: empty cn, no hero in OCR, FP doesn't have it in top).
    let allCards: [Card]
    let onSelect: (Card) -> Void
    let onSkip: () -> Void
    let onNone: () -> Void

    @Environment(\.dismiss)             private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNS
    @State private var showManualSearch = false

    var body: some View {
        VStack(spacing: 0) {
            header
            cropPreview
            candidateList
            actionBar
        }
        .background(Color(red: 0.031, green: 0.031, blue: 0.063).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .sheet(isPresented: $showManualSearch) {
            ManualCardSearchSheet(
                allCards: allCards,
                onSelect: { card in
                    showManualSearch = false
                    commit(card)
                }
            )
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(currentMatch == nil ? "Pick the right card" : "Review or change")
                .font(Design.Fonts.display(18))
                .foregroundStyle(.white)
            Text("\(candidates.count) candidate\(candidates.count == 1 ? "" : "s") · tap one to confirm")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var cropPreview: some View {
        Image(uiImage: cellCrop)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    private var candidateList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, candidate in
                    candidateRow(candidate, isTopChoice: idx == 0)
                        .onTapGesture { commit(candidate.card) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func candidateRow(_ c: ScanMatching.PickerCandidate, isTopChoice: Bool) -> some View {
        let isCurrentMatch = currentMatch?.id == c.card.id

        HStack(spacing: 14) {
            CardImageView(card: c.card, size: .thumb)
                .frame(width: 56, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.card.hero.isEmpty ? c.card.name : c.card.hero)
                        .font(Design.Fonts.display(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isCurrentMatch {
                        pill("CURRENT", background: Design.Colors.bobaCyan)
                    } else if isTopChoice {
                        pill("BEST", background: Design.Colors.bobaOrange)
                    }
                }
                Text(c.card.cardNumber)
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Text(c.card.treatment ?? "Base Set")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)
            ConfidenceBars(score: c.normalizedScore)
        }
        .padding(12)
        .background(rowBackground(isTopChoice: isTopChoice, isCurrentMatch: isCurrentMatch))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(rowBorder(isTopChoice: isTopChoice, isCurrentMatch: isCurrentMatch), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.card.hero), \(c.card.cardNumber), \(c.card.treatment ?? "")")
        .accessibilityHint(isCurrentMatch ? "Currently selected. Double-tap to keep."
                           : (isTopChoice ? "Best match. Double-tap to select." : "Double-tap to select."))
    }

    private func rowBackground(isTopChoice: Bool, isCurrentMatch: Bool) -> Color {
        if isCurrentMatch { return Design.Colors.bobaCyan.opacity(0.12) }
        if isTopChoice    { return Design.Colors.bobaOrange.opacity(0.10) }
        return Color.white.opacity(0.05)
    }

    private func rowBorder(isTopChoice: Bool, isCurrentMatch: Bool) -> Color {
        if isCurrentMatch { return Design.Colors.bobaCyan.opacity(0.6) }
        if isTopChoice    { return Design.Colors.bobaOrange.opacity(0.5) }
        return Color.white.opacity(0.08)
    }

    private func pill(_ text: String, background: Color) -> some View {
        Text(text)
            .font(Design.Fonts.mono(9, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(background)
            .clipShape(Capsule())
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            // Search button on its own row — this is the escape
            // hatch for cells where the right card isn't in the
            // resolver's top-8 candidates (Skuba 68 case: no cn,
            // no hero in OCR, FP doesn't surface it). Full-catalog
            // search lets the user type the hero name or cardNumber
            // directly.
            Button {
                showManualSearch = true
            } label: {
                Label("Search the catalog", systemImage: "magnifyingglass")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .background(Design.Colors.bobaCyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Design.Colors.bobaCyan.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button {
                    onNone()
                    dismiss()
                } label: {
                    Label("None of these", systemImage: "xmark")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    onSkip()
                    dismiss()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.black)
                        .background(Design.Colors.bobaOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func commit(_ card: Card) {
        if reduceMotion {
            onSelect(card); dismiss()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                onSelect(card); dismiss()
            }
        }
    }
}

// MARK: - ManualCardSearchSheet
//
// Last-resort escape hatch presented when the user taps "Search the
// catalog" in the disambiguation sheet. Shows a search field over the
// full display catalog so the user can type a hero name or
// cardNumber and pick exactly the card they're looking at — for
// cells like Skuba 68 where no signal in the image surfaces the
// right card in the resolver's top-8 candidates.

private struct ManualCardSearchSheet: View {
    let allCards: [Card]
    let onSelect: (Card) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFieldFocused: Bool

    private var filteredCards: [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.uppercased()
        // Score-and-rank: cardNumber prefix > hero prefix > hero contains
        // > cardNumber contains. Cap to 60 results so the list stays
        // scrollable on a half-sheet.
        var scored: [(Card, Int)] = []
        for c in allCards {
            let cn = c.cardNumber.uppercased()
            let hero = c.hero.uppercased()
            let name = c.name.uppercased()
            var score = 0
            if cn.hasPrefix(q)   { score = 100 }
            else if hero.hasPrefix(q) { score = 80 }
            else if name.hasPrefix(q) { score = 70 }
            else if hero.contains(q)  { score = 50 }
            else if name.contains(q)  { score = 40 }
            else if cn.contains(q)    { score = 30 }
            if score > 0 { scored.append((c, score)) }
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(60)
            .map { $0.0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if query.isEmpty {
                    emptyHint
                } else if filteredCards.isEmpty {
                    noResults
                } else {
                    resultsList
                }
            }
            .background(Color(red: 0.031, green: 0.031, blue: 0.063).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("Search catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { searchFieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.5))
            TextField("Hero name or card number", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .focused($searchFieldFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.25))
            Text("Type a hero name or card number")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.25))
            Text("No cards match \"\(query)\"")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredCards) { card in
                    Button { onSelect(card) } label: { resultRow(card) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func resultRow(_ card: Card) -> some View {
        HStack(spacing: 12) {
            CardImageView(card: card, size: .thumb)
                .frame(width: 48, height: 67)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(card.cardNumber)
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaCyan)
                Text(card.treatment ?? "Base Set")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ConfidenceBars: View {
    let score: Double  // 0…1
    var filled: Int { max(1, min(5, Int((score * 5).rounded(.up)))) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Design.Colors.bobaCyan : .white.opacity(0.15))
                    .frame(width: 3, height: 14)
            }
        }
    }
}
