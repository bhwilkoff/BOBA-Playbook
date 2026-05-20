import Foundation
import UIKit
import RealityKit
import SwiftUI

/// Headless entrypoint that drives `HeroShotRenderer.renderComparisonGrid`
/// from outside the UI so the 4 front-material variants can be iterated
/// on without manual taps. Activated by env var `BOBA_HERO_SHOT_CLI=1`
/// (set via `xcrun simctl launch ... --console-pty`).
///
/// Output: `BOBA_HERO_SHOT_OUT_DIR` (default `/tmp/hero-shot-variants/`)
///   - `grid.png` — 2×2 comparison sheet labeled A/B/C/D
///   - `done` — sentinel file the driver script polls for
///
/// Optional env vars:
///   - `BOBA_HERO_SHOT_BOBA_ID` — pick a specific card; default = first card with imageFile
///   - `BOBA_HERO_SHOT_ARC` — `reveal` / `showcase` / `detail` / `techDemo` (default reveal)
///
/// Lives behind `#if DEBUG` so it ships only in Debug builds.
@available(iOS 18.0, *)
@MainActor
enum HeroShotCLIRunner {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["BOBA_HERO_SHOT_CLI"] == "1"
    }

    /// Run the comparison-grid render, write the PNG to disk, exit(0).
    /// Errors land in `error.txt` next to the output dir. Never throws —
    /// the runner is best-effort and must terminate the process so the
    /// driver script doesn't hang.
    static func run(cardStore: CardStore) async {
        let env = ProcessInfo.processInfo.environment
        // Simulators sandbox /tmp inside the device container — the
        // host can't read it. Write to the app's Documents dir
        // instead; the driver script resolves the host path via
        // `xcrun simctl get_app_container <udid> <bundle> data`.
        // BOBA_HERO_SHOT_OUT_DIR can still override (e.g. for
        // on-device runs where /tmp shipping isn't applicable).
        let outDir: String
        if let override = env["BOBA_HERO_SHOT_OUT_DIR"] {
            outDir = override
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory,
                                                in: .userDomainMask).first!
            outDir = docs.appendingPathComponent("hero-shot-variants").path
        }
        let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: outURL,
                                                 withIntermediateDirectories: true)
        print("[HeroShotCLI] output dir: \(outDir)")

        do {
            try await runInner(cardStore: cardStore, outURL: outURL, env: env)
            try? "ok".write(to: outURL.appendingPathComponent("done"),
                            atomically: true, encoding: .utf8)
            print("[HeroShotCLI] grid written to \(outURL.path)/grid.png")
        } catch {
            let msg = "[HeroShotCLI] FAILED: \(error)"
            print(msg)
            try? msg.write(to: outURL.appendingPathComponent("error.txt"),
                           atomically: true, encoding: .utf8)
            try? "fail".write(to: outURL.appendingPathComponent("done"),
                              atomically: true, encoding: .utf8)
        }

        // Hard exit. We're a headless tool — the SwiftUI scene never
        // needs to come up.
        exit(0)
    }

    private static func runInner(cardStore: CardStore,
                                 outURL: URL,
                                 env: [String: String]) async throws {
        // Phase 1 of cardStore loads cards-head.json synchronously in init,
        // so we have at least 500 cards available immediately. Phase 2
        // (full catalog) may still be loading — head is enough for the
        // comparison grid. Pick a card.
        let targetBobaId = env["BOBA_HERO_SHOT_BOBA_ID"]
        guard let card = pickCard(from: cardStore.displayCards,
                                  bobaId: targetBobaId) else {
            throw RunnerError.noCard
        }
        print("[HeroShotCLI] using card: \(card.bobaId) \(card.displayName)")

        guard let fullURL = CDN.fullURL(for: card) else {
            throw RunnerError.noImageFile(card.bobaId)
        }
        let (data, _) = try await URLSession.shared.data(from: fullURL)
        guard let raw = UIImage(data: data) else { throw RunnerError.imageDecode }
        guard let rounded = BOBACardEntity.roundedCorners(raw) else {
            throw RunnerError.imageDecode
        }

        // Build TextureResources on the main actor.
        guard let frontCG = rounded.cgImage else { throw RunnerError.imageDecode }
        let frontTex = try await TextureResource(
            image: frontCG, withName: nil,
            options: TextureResource.CreateOptions(semantic: .color,
                                                   mipmapsMode: .allocateAndGenerateAll))

        // Card back — bundled PNG.
        let backTex: TextureResource? = {
            guard
                let path = Bundle.main.url(forResource: "card-back", withExtension: "png"),
                let img = UIImage(contentsOfFile: path.path),
                let backRounded = BOBACardEntity.roundedCorners(img),
                let backCG = backRounded.cgImage
            else { return nil }
            return try? TextureResource(
                image: backCG, withName: nil,
                options: TextureResource.CreateOptions(semantic: .color,
                                                       mipmapsMode: .none))
        }()

        let arc: HeroShotRenderer.ArcPreset = HeroShotRenderer.ArcPreset(
            rawValue: env["BOBA_HERO_SHOT_ARC"] ?? "reveal") ?? .reveal

        let renderer = HeroShotRenderer()
        let config = HeroShotRenderer.Config(
            card: card,
            frontTexture: frontTex,
            backTexture: backTex,
            frontImage: rounded,
            includeWatermark: false,
            arc: arc,
            cardMotion: .static,    // single frame; motion doesn't matter
            duration: 10.0,
            fps: 60,
            size: CGSize(width: 1080, height: 1920),
            bitrate: 12_000_000,
            frontVariant: .holofoilLit   // overridden per-tile by grid renderer
        )

        let gridImage = try await renderer.renderComparisonGrid(config)
        guard let png = gridImage.pngData() else { throw RunnerError.pngEncode }
        let dst = outURL.appendingPathComponent("grid.png")
        try png.write(to: dst, options: .atomic)
    }

    private static func pickCard(from cards: [Card], bobaId: String?) -> Card? {
        if let bobaId = bobaId,
           let match = cards.first(where: { $0.bobaId == bobaId }) {
            return match
        }
        // Default: first card with a non-empty imageFile (head usually
        // hits a real card on the first match).
        return cards.first(where: { !($0.imageFile ?? "").isEmpty })
    }

    enum RunnerError: Error, CustomStringConvertible {
        case noCard
        case noImageFile(String)
        case imageDecode
        case pngEncode

        var description: String {
            switch self {
            case .noCard: return "no card found in cardStore"
            case .noImageFile(let id): return "card \(id) has no imageFile"
            case .imageDecode: return "card image decode / rounded-corner failed"
            case .pngEncode: return "PNG encode failed"
            }
        }
    }
}
