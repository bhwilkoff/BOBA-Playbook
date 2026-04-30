import SwiftUI
import UIKit
import PhotosUI

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
        let matched: Card?
        var includedInQueue: Bool = true
    }

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
                    await loadAndProcess(img)
                }
                photoPickerItem = nil
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { sourcePickerMode == .camera },
            set: { if !$0 && sourcePickerMode == .camera { sourcePickerMode = .none } }
        )) {
            CameraImagePicker { image in
                sourcePickerMode = .none
                if let image {
                    Task { await loadAndProcess(image) }
                }
            }
            .ignoresSafeArea()
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
            VStack(spacing: 0) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                Button {
                    Task { await processSourceImage() }
                } label: {
                    Text("Process")
                        .font(Design.Fonts.mono(14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Design.Colors.bobaOrange)
                }
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
            HStack {
                let matchCount = results.filter { $0.matched != nil }.count
                Text("\(matchCount)/\(results.count) identified")
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(.white)
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
    }

    private func resultCell(_ r: GridResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // Trading-card aspect ratio (~0.714) so the preview
                // matches the actual card shape rather than squaring
                // out into the grid cell.
                Image(uiImage: r.crop)
                    .resizable()
                    .aspectRatio(0.714, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm))
                if r.matched != nil {
                    Button {
                        toggleIncluded(r)
                    } label: {
                        Image(systemName: r.includedInQueue
                              ? "checkmark.circle.fill"
                              : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(
                                r.includedInQueue
                                ? Design.Colors.bobaCyan
                                : .white.opacity(0.7))
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .padding(4)
                }
            }
            if let card = r.matched {
                Text(card.cardNumber)
                    .font(Design.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(card.hero.isEmpty ? card.name : card.hero)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .lineLimit(1)
            } else {
                Text("Not identified")
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(.red)
            }
        }
        .padding(6)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
    }

    // MARK: - Pipeline

    private func loadAndProcess(_ image: UIImage) async {
        sourceImage = image
        await processSourceImage()
    }

    private func processSourceImage() async {
        guard let image = sourceImage else { return }
        // Camera-captured UIImages can carry an .right or .down
        // EXIF orientation while the underlying CGImage stays in
        // sensor (landscape) orientation. Re-render to a properly
        // upright UIImage before handing to the detector — Vision's
        // results then line up with the visible image regardless of
        // capture mode.
        let upright = image.orientationCorrected()
        sourceImage = upright
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
        try? await Task.sleep(nanoseconds: 200_000_000)

        let detected: [GridCardDetector.DetectedCard]
        do {
            detected = try await GridCardDetector.detect(in: upright)
        } catch {
            statusMessage = "Couldn't find any cards. Try a clearer photo."
            processing = false
            return
        }
        statusMessage = "Identifying \(detected.count) cards…"

        var out: [GridResult] = []
        for d in detected {
            let r = await scanner.scanGridImage(d.image)
            // resolveGrid handles cardNumber filter, FeaturePrintIndex
            // override (catches OCR misreads where the bare digit
            // matched the wrong card), and hero-name fallback in one
            // pass. Pass empty cardNumber when extraction failed —
            // the resolver still runs FP + hero fallback.
            let observation = ScanObservation(
                cardNumber:   r.cardNumber ?? "",
                rawName:      r.topLeftText,
                rawPower:     r.topRightText,
                rawVariation: r.bottomRightText,
                fullText:     r.allText,
                cgImage:      r.cgImage
            )
            let matched = await ScanMatching.resolveGrid(
                observation: observation,
                allCards:    cardStore.displayCards
            )
            out.append(GridResult(
                row: d.row, column: d.column,
                crop: d.image, matched: matched,
                includedInQueue: matched != nil))
        }
        results = out
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
    /// JPEG round-trip is the most reliable bake — it consistently
    /// produces a UIImage whose pixels match what's displayed on
    /// screen, across iOS versions and source apps. UIGraphicsImage-
    /// Renderer is kept as a fallback for the rare case where JPEG
    /// encoding fails (e.g., extremely large images on memory-tight
    /// devices).
    func orientationCorrected() -> UIImage {
        if imageOrientation == .up { return self }
        if let data = jpegData(compressionQuality: 0.95),
           let baked = UIImage(data: data) {
            return baked
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Camera image picker (UIImagePickerController wrapper)

/// Simple UIImagePickerController-backed camera capture. SwiftUI's
/// native PhotosPicker doesn't support camera input directly, so
/// we wrap UIKit for that path. Library selection uses
/// PhotosPicker on the parent view.
struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            onImage(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
            picker.dismiss(animated: true)
        }
    }
}
