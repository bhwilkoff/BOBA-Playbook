import SwiftUI
import UIKit
import PhotosUI

/// User-facing Grid scan mode. Shows a single image (camera capture
/// or photo library selection) and runs it through the full Grid
/// pipeline: GridCardDetector → multi-pass OCR → catalog match
/// (number + Phase-2 image-similarity tiebreak + hero-name
/// fallback). Each detected card with a successful match is queued
/// to ScanStore so it can be saved alongside Single/Multi mode
/// scans.
@MainActor
struct GridScanView: View {
    @Environment(\.dismiss)             private var dismiss
    @Environment(CardStore.self)        private var cardStore
    @Environment(ScanStore.self)        private var scanStore

    @State private var sourceImage: UIImage?
    @State private var sourcePickerMode: SourcePickerMode = .none
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var processing = false
    @State private var results: [GridResult] = []
    @State private var statusMessage = ""

    enum SourcePickerMode: Identifiable {
        case none, camera, library
        var id: Int {
            switch self {
            case .none:    return 0
            case .camera:  return 1
            case .library: return 2
            }
        }
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
                        Button("Add All") { queueMatchedResults() }
                            .foregroundStyle(Design.Colors.bobaCyan)
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
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.bobaCyan)
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
                Image(uiImage: r.crop)
                    .resizable()
                    .scaledToFit()
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
        processing = true
        statusMessage = "Detecting cards…"

        // Prepare scanner with catalog vocab — same setup the
        // streaming scanner uses so customWords and cardNumberSet
        // are populated before any pass runs.
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
            detected = try await GridCardDetector.detect(in: image)
        } catch {
            statusMessage = "Couldn't find any cards. Try a clearer photo."
            processing = false
            return
        }
        statusMessage = "Identifying \(detected.count) cards…"

        var out: [GridResult] = []
        for d in detected {
            let r = await scanner.scanGridImage(d.image)
            var matched: Card?
            if let cn = r.cardNumber {
                let observation = ScanObservation(
                    cardNumber:   cn,
                    rawName:      r.topLeftText,
                    rawPower:     r.topRightText,
                    rawVariation: r.bottomRightText,
                    fullText:     r.allText,
                    cgImage:      r.cgImage
                )
                let candidates = cardStore.displayCards.filter {
                    $0.cardNumber.uppercased() == cn
                }
                matched = await ScanMatching.resolve(
                    observation: observation,
                    candidates:  candidates
                )
            }
            if matched == nil {
                matched = ScanMatching.matchByHero(
                    allText:     r.allText,
                    topLeftText: r.topLeftText,
                    candidates:  cardStore.displayCards
                )
            }
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

    private func queueMatchedResults() {
        for r in results where r.includedInQueue {
            if let card = r.matched {
                scanStore.addToQueue(card)
            }
        }
        dismiss()
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
