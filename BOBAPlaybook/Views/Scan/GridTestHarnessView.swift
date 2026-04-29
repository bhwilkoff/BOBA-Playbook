import SwiftUI
import UIKit

/// Verification view that loads the bundled HEIC test fixtures and
/// runs the full Grid pipeline (detector → still-image OCR → catalog
/// match) against each. Used to confirm "all 9 cards detected and
/// identified correctly across 4 fixtures" before promoting Grid
/// scan to a real mode in the user-facing scanner. Reachable via the
/// "GRID TEST HARNESS" button at the top of the Scan tab.
///
/// Strip the entry point + this file before App Store submission
/// once Grid mode is shipped — fixtures bundle ~10MB which we don't
/// want in release builds long-term.
///
/// Once the harness shows ≥36 of 36 (or ≥34 of 36 with documented
/// false-misses) across all four fixtures, flip the feature gate
/// in ScanView so users can access Grid scan mode.
@MainActor
struct GridTestHarnessView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CardStore.self) private var cardStore

    @State private var results: [FixtureResult] = []
    @State private var isRunning = false
    @State private var status: String = ""

    /// Fixture asset names (without extension). The bundle includes
    /// these as .HEIC files in BOBAPlaybook/Resources/GridTestFixtures/.
    /// HEIC is the iPhone-native format the production scan path will
    /// also receive, so testing against it directly catches any
    /// format-specific issues.
    private let fixtureNames = ["IMG_5229", "IMG_5230", "IMG_5231", "IMG_5232"]

    struct FixtureResult: Identifiable {
        let id = UUID()
        let fixtureName: String
        let sourceImage: UIImage
        let detectedCards: [DetectedResult]
        let totalDetected: Int
        let matchCount: Int
        let elapsedMs: Int
    }

    struct DetectedResult: Identifiable {
        let id = UUID()
        let gridIndex: Int
        let row: Int
        let column: Int
        let crop: UIImage
        let observation: ScanObservation?
        let matchedCard: Card?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryHeader
                    runButton

                    if results.isEmpty {
                        Text(isRunning
                             ? "Running detector against \(fixtureNames.count) fixtures…"
                             : "Tap the button above to run.")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    ForEach(results) { result in
                        fixtureSection(result)
                    }
                }
                .padding()
            }
            .navigationTitle("Grid Detector Test Harness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var summaryHeader: some View {
        let totalCards = results.reduce(0) { $0 + $1.totalDetected }
        let totalMatches = results.reduce(0) { $0 + $1.matchCount }
        let expected = fixtureNames.count * 9  // 36 total target
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(totalMatches)/\(totalCards) matched · \(totalCards)/\(expected) detected")
                .font(.system(.title3, design: .monospaced).weight(.bold))
            if !status.isEmpty {
                Text(status)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("Goal: 9 detected + matched per fixture (36 total).")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runButton: some View {
        Button {
            Task { await runAll() }
        } label: {
            HStack {
                if isRunning { ProgressView().controlSize(.small) }
                Text(isRunning ? "Running…" : "Run All Fixtures")
                    .font(.system(.body, design: .monospaced).weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(isRunning)
    }

    // MARK: - Per-fixture layout

    @ViewBuilder
    private func fixtureSection(_ result: FixtureResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.fixtureName)
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Text("\(result.matchCount)/\(result.totalDetected) matched · \(result.elapsedMs)ms")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Source thumbnail (small) so we can eyeball orientation/lighting
            Image(uiImage: result.sourceImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // 3-column grid of detected cards. Each cell shows the
            // crop on top and the matched card identification below.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(result.detectedCards) { detected in
                    detectedCardCell(detected)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func detectedCardCell(_ detected: DetectedResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(uiImage: detected.crop)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 110)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("[\(detected.row),\(detected.column)]")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let card = detected.matchedCard {
                    Text(card.cardNumber)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                    Text(card.hero.isEmpty ? card.name : card.hero)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else if let obs = detected.observation {
                    Text(obs.cardNumber)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    Text("no match")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text("OCR failed")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Pipeline

    private func runAll() async {
        isRunning = true
        results = []
        status = "Initializing scanner…"

        // Build a fresh CardScanner instance for the still-image path,
        // primed with the catalog so customWords + cardNumberSet are
        // populated for OCR.
        let scanner = CardScanner()
        let cardNumbers = cardStore.displayCards.map { $0.cardNumber.uppercased() }
        scanner.setCardNumbers(cardNumbers)
        let names = cardStore.displayCards.flatMap { card -> [String] in
            var out: [String] = []
            if !card.hero.isEmpty { out.append(card.hero) }
            if !card.name.isEmpty, card.name != card.hero { out.append(card.name) }
            return out
        }
        scanner.setVocabularyNames(names)
        // Give the scanner's processingQueue a moment to absorb the
        // setCardNumbers + setVocabularyNames calls (both are async
        // through the queue).
        try? await Task.sleep(nanoseconds: 200_000_000)

        for name in fixtureNames {
            status = "Processing \(name)…"
            guard let image = loadFixture(name: name) else {
                continue
            }
            let started = Date()
            let detected: [GridCardDetector.DetectedCard]
            do {
                detected = try await GridCardDetector.detect(in: image)
            } catch {
                status = "\(name): \(error)"
                continue
            }

            var perCard: [DetectedResult] = []
            for d in detected {
                let observation = await scanner.scanStillImage(d.image)
                let matched: Card? = {
                    guard let obs = observation else { return nil }
                    let candidates = cardStore.displayCards.filter {
                        $0.cardNumber.uppercased() == obs.cardNumber
                    }
                    return ScanMatching.bestMatch(observation: obs, candidates: candidates)
                }()
                perCard.append(DetectedResult(
                    gridIndex:  d.gridIndex,
                    row:        d.row,
                    column:     d.column,
                    crop:       d.image,
                    observation: observation,
                    matchedCard: matched
                ))
            }

            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            let matches = perCard.filter { $0.matchedCard != nil }.count
            results.append(FixtureResult(
                fixtureName:    name,
                sourceImage:    image,
                detectedCards:  perCard,
                totalDetected:  detected.count,
                matchCount:     matches,
                elapsedMs:      elapsedMs
            ))
        }

        status = "Done."
        isRunning = false
    }

    /// Load a HEIC fixture from the app bundle. Returns nil on
    /// missing or undecodable data — UIImage handles HEIC natively
    /// on iOS 17+.
    private func loadFixture(name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "HEIC"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else {
            return nil
        }
        return image
    }
}
