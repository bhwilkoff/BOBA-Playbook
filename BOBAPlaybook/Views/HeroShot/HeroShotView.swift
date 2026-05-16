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
            }
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
                } else {
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOBA PLAYBOOK WATERMARK")
                        .font(Design.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                    Text("Anchored bottom-right of the video")
                        .font(Design.Fonts.mono(10))
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

            // Hero-shot info row
            HStack(spacing: Design.Spacing.md) {
                pill("9:16")
                pill("60 FPS")
                pill("5 SEC")
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.xs)
        }
        .padding(.horizontal, Design.Spacing.lg)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(Design.Fonts.mono(10, weight: .bold))
            .foregroundStyle(Design.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().strokeBorder(Design.Colors.textSecondary.opacity(0.3), lineWidth: 1))
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
        guard let url = CDN.fullURL(for: card) ?? CDN.thumbURL(for: card) else { return }
        let texture: TextureResource? = await Task.detached(priority: .userInitiated) { () -> TextureResource? in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data)
            else { return nil }
            return await MainActor.run {
                guard let cg = image.cgImage else { return nil as TextureResource? }
                let opts = TextureResource.CreateOptions(semantic: .color)
                return try? TextureResource(image: cg, withName: nil, options: opts)
            }
        }.value
        await MainActor.run {
            self.frontTexture = texture
        }
    }

    /// Bundled card-back PNG (same asset HouseOfCardsView uses). The
    /// back plane in the renderer is mounted with a `-π/2` X rotation
    /// that already flips its V axis, so no compensating image rotation
    /// is needed when the source PNG is bundled as-is.
    private func loadBackTexture() async {
        let tex: TextureResource? = await Task.detached(priority: .userInitiated) { () -> TextureResource? in
            guard
                let path = Bundle.main.url(forResource: "card-back", withExtension: "png"),
                let image = UIImage(contentsOfFile: path.path),
                let cg = image.cgImage
            else { return nil }
            return await MainActor.run {
                let opts = TextureResource.CreateOptions(semantic: .color)
                return try? TextureResource(image: cg, withName: nil, options: opts)
            }
        }.value
        await MainActor.run {
            self.backTexture = tex
        }
    }

    private func startRender() {
        guard let texture = frontTexture else { return }
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
                    includeWatermark: includeWatermark
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
