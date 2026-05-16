import SwiftUI
import AVKit
import RealityKit
import UIKit

/// Full-screen sheet that lets a collector generate + share a 3D
/// "Hero Shot" video of one of their cards. Entry from Collection card
/// detail. iOS 18+ only — the toolbar button at the call site is gated
/// on `#available(iOS 18.0, *)`.
@available(iOS 18.0, *)
struct HeroShotView: View {
    let card: Card

    @Environment(\.dismiss) private var dismiss

    @State private var includeWatermark: Bool = true
    @State private var phase: Phase = .ready
    @State private var renderProgress: Double = 0
    @State private var renderedURL: URL?
    @State private var renderError: String?
    @State private var frontTexture: TextureResource?
    @State private var backTexture: TextureResource?
    /// Keep the rounded-corner UIImage of the front art around — the
    /// renderer needs it at scene-build time to extract a color palette
    /// and generate the IBL/backdrop environment.
    @State private var frontImage: UIImage?

    // User-customizable render options. Defaults: Reveal preset, 10s,
    // Entrance Spin, watermark on.
    @State private var arcPreset: HeroShotRenderer.ArcPreset = .reveal
    @State private var clipLength: TimeInterval = 10
    @State private var cardMotion: HeroShotRenderer.CardMotion = .entranceSpin

    /// Inline preview thumbnail — a single rendered frame of the FINAL
    /// hero pose so the user sees their composition before they
    /// commit to a 30s render. Recomputed (debounced) whenever
    /// preset / length / motion changes.
    @State private var previewFrame: UIImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var renderTask: Task<Void, Never>?
    @State private var showingShareSheet: Bool = false

    enum Phase: Equatable {
        case ready
        case rendering
        case finished
        case failed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.nearBlack.ignoresSafeArea()

                VStack(spacing: Design.Spacing.lg) {
                    previewBlock

                    Spacer(minLength: 0)

                    controlsBlock

                    primaryActionBlock
                        .padding(.horizontal, Design.Spacing.lg)
                        .padding(.bottom, Design.Spacing.lg)
                }
            }
            .navigationTitle("Hero Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        renderTask?.cancel()
                        dismiss()
                    }
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .task {
                async let front: Void = loadFrontTexture()
                async let back:  Void = loadBackTexture()
                _ = await (front, back)
                // Initial preview render once textures are loaded.
                schedulePreviewRender()
            }
            .onChange(of: arcPreset) { _, _ in schedulePreviewRender() }
            .onChange(of: clipLength) { _, _ in schedulePreviewRender() }
            .onChange(of: cardMotion) { _, _ in schedulePreviewRender() }
            .sheet(isPresented: $showingShareSheet) {
                if let renderedURL {
                    ActivityShareSheet(items: [renderedURL])
                }
            }
            .onDisappear {
                renderTask?.cancel()
            }
        }
    }

    // MARK: - Preview

    private var previewBlock: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Design.Colors.element(card.element).opacity(0.30),
                    Design.Colors.nearBlack
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 360)

            Group {
                if phase == .finished, let renderedURL {
                    VideoPlayer(player: AVPlayer(url: renderedURL))
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Design.Colors.bobaCyan.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                } else if let preview = previewFrame {
                    // Live preview of the hero pose — a single rendered
                    // frame at time = 0.95 * duration. Updates when the
                    // user picks a different preset / length / motion.
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Design.Colors.bobaCyan.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                } else {
                    // Fallback before textures load / before the first
                    // preview is rendered.
                    CardImageView(card: card, size: .full)
                        .aspectRatio(5.0 / 7.0, contentMode: .fit)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Design.Colors.bobaOrange.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsBlock: some View {
        VStack(spacing: Design.Spacing.md) {
            // STYLE — camera arc preset (Reveal / Showcase / Detail)
            VStack(alignment: .leading, spacing: 6) {
                Text("STYLE")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                Picker("Style", selection: $arcPreset) {
                    ForEach(HeroShotRenderer.ArcPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(phase == .rendering)
                Text(arcPreset.caption)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textSecondary.opacity(0.7))
                    .lineLimit(1)
            }

            // LENGTH — discrete chips (5 / 10 / 15 / 30 s)
            VStack(alignment: .leading, spacing: 6) {
                Text("LENGTH")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                Picker("Length", selection: $clipLength) {
                    Text("5s").tag(TimeInterval(5))
                    Text("10s").tag(TimeInterval(10))
                    Text("15s").tag(TimeInterval(15))
                    Text("30s").tag(TimeInterval(30))
                }
                .pickerStyle(.segmented)
                .disabled(phase == .rendering)
            }

            // MOTION — card motion (Static / Entrance Spin / Slow Rotate)
            VStack(alignment: .leading, spacing: 6) {
                Text("CARD MOTION")
                    .font(Design.Fonts.mono(10, weight: .bold))
                    .foregroundStyle(Design.Colors.textSecondary)
                Picker("Motion", selection: $cardMotion) {
                    ForEach(HeroShotRenderer.CardMotion.allCases) { motion in
                        Text(motion.displayName).tag(motion)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(phase == .rendering)
            }

            // WATERMARK toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOBA WATERMARK")
                        .font(Design.Fonts.mono(10, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                    Text("Anchored bottom-right of the video")
                        .font(Design.Fonts.mono(9))
                        .foregroundStyle(Design.Colors.textSecondary.opacity(0.7))
                }
                Spacer()
                Toggle("", isOn: $includeWatermark)
                    .labelsHidden()
                    .tint(Design.Colors.bobaCyan)
                    .disabled(phase == .rendering)
            }
            .padding(Design.Spacing.md)
            .background(RoundedRectangle(cornerRadius: 10).fill(Design.Colors.surface))
        }
        .padding(.horizontal, Design.Spacing.lg)
    }

    // MARK: - Primary CTA

    @ViewBuilder
    private var primaryActionBlock: some View {
        switch phase {
        case .ready:
            Button {
                startRender()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text("Create Hero Shot")
                        .font(Design.Fonts.display(16))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Design.Colors.bobaOrange)
                )
                .foregroundStyle(.white)
            }
            .disabled(frontTexture == nil)
            .opacity(frontTexture == nil ? 0.4 : 1.0)

        case .rendering:
            VStack(spacing: Design.Spacing.sm) {
                ProgressView(value: renderProgress)
                    .tint(Design.Colors.bobaCyan)
                Text(progressLabel)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

        case .finished:
            HStack(spacing: Design.Spacing.md) {
                Button {
                    resetToReady()
                } label: {
                    Text("Render Again")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Design.Colors.textSecondary.opacity(0.4), lineWidth: 1)
                        )
                        .foregroundStyle(Design.Colors.textPrimary)
                }

                Button {
                    showingShareSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                            .font(Design.Fonts.display(15))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Design.Colors.bobaOrange)
                    )
                    .foregroundStyle(.white)
                }
            }

        case .failed:
            VStack(spacing: Design.Spacing.sm) {
                if let renderError {
                    Text(renderError)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Color(hex: "FF6E6E"))
                        .multilineTextAlignment(.center)
                }
                Button {
                    resetToReady()
                } label: {
                    Text("Try Again")
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Design.Colors.bobaOrange)
                        )
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var progressLabel: String {
        let pct = Int((renderProgress * 100).rounded())
        return "Rendering \(card.hero.isEmpty ? card.name : card.hero) — \(pct)%"
    }

    // MARK: - Actions

    private func loadFrontTexture() async {
        // Force the full-resolution CDN URL — never the thumbnail. The
        // hero shot output frames the card large; the 1200px-max full
        // image is what reads as crisp at 1080×1920 portrait.
        guard let url = CDN.fullURL(for: card) else { return }
        struct LoadResult {
            let rounded: UIImage
            let texture: TextureResource?
        }
        let result: LoadResult? = await Task.detached(priority: .userInitiated) { () -> LoadResult? in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data)
            else { return nil }
            // Clip to rounded corners BEFORE generating the texture —
            // the alpha channel from the rounded-rect mask gives the
            // card its visible rounded shape. `MeshResource.generatePlane`
            // has a `cornerRadius:` parameter that's silently ignored on
            // iOS 17/18/26, so the mask must live in the texture.
            let rounded = BOBACardEntity.roundedCorners(image) ?? image
            let tex: TextureResource? = await MainActor.run {
                guard let cg = rounded.cgImage else { return nil as TextureResource? }
                let opts = TextureResource.CreateOptions(
                    semantic: .color,
                    mipmapsMode: .none
                )
                return try? TextureResource(image: cg, withName: nil, options: opts)
            }
            return LoadResult(rounded: rounded, texture: tex)
        }.value
        await MainActor.run {
            self.frontTexture = result?.texture
            self.frontImage = result?.rounded
        }
    }

    /// Bundled card-back PNG (same asset HouseOfCardsView uses). The
    /// back plane in the renderer is mounted with `R_x(-π/2) * R_y(π)`
    /// (math derived in HeroShotRenderer) so the image-V direction
    /// flips through to right-side-up. Source PNG used as-is — same
    /// rounded-corner clipping applies as the front.
    private func loadBackTexture() async {
        let tex: TextureResource? = await Task.detached(priority: .userInitiated) { () -> TextureResource? in
            guard
                let path = Bundle.main.url(forResource: "card-back", withExtension: "png"),
                let image = UIImage(contentsOfFile: path.path)
            else { return nil }
            let rounded = BOBACardEntity.roundedCorners(image) ?? image
            return await MainActor.run {
                guard let cg = rounded.cgImage else { return nil as TextureResource? }
                let opts = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
                return try? TextureResource(image: cg, withName: nil, options: opts)
            }
        }.value
        await MainActor.run {
            self.backTexture = tex
        }
    }

    /// Trigger a debounced preview render of the FINAL hero pose
    /// (time = 95% of duration). Cancels any in-flight preview so
    /// rapid picker changes don't queue up renders.
    private func schedulePreviewRender() {
        previewTask?.cancel()
        guard let texture = frontTexture, let image = frontImage else { return }
        let snapshotArc = arcPreset
        let snapshotLength = clipLength
        let snapshotMotion = cardMotion
        previewTask = Task { @MainActor in
            // Tiny debounce so quickly-tapping pickers doesn't fire
            // 4 renders.
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            do {
                let renderer = HeroShotRenderer()
                let config = HeroShotRenderer.Config(
                    card: card,
                    frontTexture: texture,
                    backTexture: backTexture,
                    frontImage: image,
                    includeWatermark: false,   // no watermark on preview
                    arc: snapshotArc,
                    cardMotion: snapshotMotion,
                    duration: snapshotLength
                )
                let frame = try await renderer.renderPreviewFrame(
                    config,
                    normalizedTime: 0.95
                )
                if Task.isCancelled { return }
                previewFrame = frame
            } catch {
                // Silent on preview failure — the static card image
                // fallback is fine. We don't want preview failures to
                // block the user from trying the full render.
            }
        }
    }

    private func startRender() {
        guard let texture = frontTexture, let image = frontImage else { return }
        phase = .rendering
        renderProgress = 0
        renderError = nil
        renderTask = Task { @MainActor in
            do {
                let renderer = HeroShotRenderer()
                let config = HeroShotRenderer.Config(
                    card: card,
                    frontTexture: texture,
                    backTexture: backTexture,
                    frontImage: image,
                    includeWatermark: includeWatermark,
                    arc: arcPreset,
                    cardMotion: cardMotion,
                    duration: clipLength
                )
                let url = try await renderer.render(config) { p in
                    renderProgress = p
                }
                renderedURL = url
                phase = .finished
            } catch is CancellationError {
                phase = .ready
            } catch {
                renderError = "Render failed: \(error.localizedDescription)"
                phase = .failed
            }
        }
    }

    private func resetToReady() {
        renderTask?.cancel()
        renderTask = nil
        renderedURL = nil
        renderError = nil
        renderProgress = 0
        phase = .ready
    }
}
