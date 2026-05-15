import SwiftUI
import UIKit

// MARK: - CardCropView
//
// In-app card image cropper. Takes a picked UIImage, lets the user
// pinch + drag the image behind a crop overlay, and produces a
// cropped UIImage on confirm.
//
// Defaults to the 5:7 BoBA card aspect (matches CachedAsyncCardImage
// and CollectionCardDetailView's display aspect). Corner-handle drags
// adjust the crop rectangle freeform from there — a photo of a real
// card is rarely a perfect 5:7 because the camera is slightly tilted,
// the card is off-axis, the surrounding bezel intrudes, etc. The
// freeform handles let the moderator dial the crop in to whatever
// the source image actually shows.
//
// Apple frameworks only (project rule per CLAUDE.md). No
// third-party packages. Math:
//   - The source image is rendered .scaledToFit() inside the
//     container, then scaleEffect(imageScale) + offset(imageOffset)
//     applies the pan/zoom transform.
//   - The crop rectangle lives in CONTAINER coordinates.
//   - On confirm, we map the crop rectangle's container coords back
//     to SOURCE-image coords and use CGImage.cropping(to:) to
//     extract the cropped portion at full resolution.

struct CardCropView: View {
    let sourceImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    /// 5:7 = BoBA card aspect (width/height ≈ 0.714).
    private static let defaultAspect: CGFloat = 5.0 / 7.0

    // MARK: Image transform (pinch + drag the picked image behind the crop)
    @State private var imageScale: CGFloat = 1.0
    @State private var accumulatedScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    // MARK: Crop rect (in container points, centered initially)
    @State private var cropRect: CGRect = .zero
    @State private var containerSize: CGSize = .zero
    @State private var hasInitializedCrop = false

    // MARK: Corner-handle drag state
    @State private var activeHandle: Handle? = nil
    @State private var dragStartRect: CGRect = .zero

    enum Handle { case topLeft, topRight, bottomLeft, bottomRight }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Source image with pinch + drag transform.
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(imageScale)
                    .offset(imageOffset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    imageScale = max(0.25, min(8.0, accumulatedScale * value))
                                }
                                .onEnded { _ in
                                    accumulatedScale = imageScale
                                },
                            DragGesture()
                                .onChanged { value in
                                    imageOffset = CGSize(
                                        width:  accumulatedOffset.width  + value.translation.width,
                                        height: accumulatedOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    accumulatedOffset = imageOffset
                                }
                        )
                    )

                // Dim everything outside the crop rectangle.
                cropMask(in: geo.size)
                    .fill(Color.black.opacity(0.6))
                    .allowsHitTesting(false)

                // Crop overlay border + corner handles.
                ZStack {
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                    // Grid lines (rule of thirds) — visual aid only.
                    Path { p in
                        let r = cropRect
                        // Vertical thirds
                        p.move(to: CGPoint(x: r.minX + r.width / 3, y: r.minY))
                        p.addLine(to: CGPoint(x: r.minX + r.width / 3, y: r.maxY))
                        p.move(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.minY))
                        p.addLine(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.maxY))
                        // Horizontal thirds
                        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height / 3))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height / 3))
                        p.move(to: CGPoint(x: r.minX, y: r.minY + 2 * r.height / 3))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * r.height / 3))
                    }
                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                    .allowsHitTesting(false)

                    cornerHandle(.topLeft,     at: CGPoint(x: cropRect.minX, y: cropRect.minY), in: geo.size)
                    cornerHandle(.topRight,    at: CGPoint(x: cropRect.maxX, y: cropRect.minY), in: geo.size)
                    cornerHandle(.bottomLeft,  at: CGPoint(x: cropRect.minX, y: cropRect.maxY), in: geo.size)
                    cornerHandle(.bottomRight, at: CGPoint(x: cropRect.maxX, y: cropRect.maxY), in: geo.size)
                }
            }
            .onAppear {
                containerSize = geo.size
                initializeCropRectIfNeeded(in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                containerSize = newSize
                if !hasInitializedCrop {
                    initializeCropRectIfNeeded(in: newSize)
                }
            }
            .safeAreaInset(edge: .bottom) {
                toolbar
            }
            .safeAreaInset(edge: .top) {
                hint
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Subviews

    private var hint: some View {
        Text("Pinch + drag the photo behind the frame. Pull the corners to fine-tune.")
            .font(Design.Fonts.mono(11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { onCancel() } label: {
                Text("Cancel")
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            Spacer()
            Button {
                onConfirm(performCrop())
            } label: {
                Text("Use Crop")
                    .font(Design.Fonts.mono(14, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Design.Colors.bobaOrange))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func cornerHandle(_ corner: Handle, at point: CGPoint, in size: CGSize) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .position(point)
            // Generous hit area to make the small visible dot easy
            // to grab on touch. Apple's HIG suggests ≥ 44pt min for
            // touch targets.
            .contentShape(Circle().inset(by: -22))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if activeHandle == nil {
                            activeHandle = corner
                            dragStartRect = cropRect
                        }
                        cropRect = updatedRect(
                            from: dragStartRect,
                            corner: corner,
                            translation: value.translation,
                            inSize: size
                        )
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
    }

    private func cropMask(in size: CGSize) -> Path {
        // Even-odd fill: outer rectangle minus inner crop rectangle.
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addRect(cropRect)
        return path.normalized(eoFill: true)
    }

    // MARK: - Crop rect initialization + resize math

    private func initializeCropRectIfNeeded(in size: CGSize) {
        guard !hasInitializedCrop, size.width > 0, size.height > 0 else { return }
        // Pick the largest 5:7 rectangle that fits the container with
        // 24pt insets on every side — leaves room for the corner
        // handles to be grabbed and the toolbar to not occlude.
        let inset: CGFloat = 32
        let maxW = max(0, size.width  - inset * 2)
        let maxH = max(0, size.height - inset * 2 - 100)  // toolbar + hint chrome
        let aspect = Self.defaultAspect
        var w = maxW
        var h = w / aspect
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        cropRect = CGRect(
            x: (size.width - w) / 2,
            y: (size.height - h) / 2,
            width: w,
            height: h
        )
        hasInitializedCrop = true
    }

    /// Resize the crop rect when a corner is dragged. The OPPOSITE
    /// corner stays pinned; the dragged corner follows the finger
    /// (clamped to a minimum size + the container bounds).
    private func updatedRect(from start: CGRect, corner: Handle, translation: CGSize, inSize size: CGSize) -> CGRect {
        let minSize: CGFloat = 80   // can't shrink below this — handles would overlap
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY
        switch corner {
        case .topLeft:
            minX = start.minX + translation.width
            minY = start.minY + translation.height
        case .topRight:
            maxX = start.maxX + translation.width
            minY = start.minY + translation.height
        case .bottomLeft:
            minX = start.minX + translation.width
            maxY = start.maxY + translation.height
        case .bottomRight:
            maxX = start.maxX + translation.width
            maxY = start.maxY + translation.height
        }
        // Clamp to container.
        minX = max(0, min(minX, size.width - minSize))
        minY = max(0, min(minY, size.height - minSize))
        maxX = min(size.width,  max(maxX, minX + minSize))
        maxY = min(size.height, max(maxY, minY + minSize))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Crop math: container → source-image coordinates

    private func performCrop() -> UIImage {
        guard cropRect.width > 0, cropRect.height > 0,
              containerSize.width > 0, containerSize.height > 0
        else { return sourceImage }

        // Where does the image actually live on screen after
        // scaledToFit + scaleEffect + offset?
        let sourcePxSize = CGSize(
            width:  sourceImage.size.width  * sourceImage.scale,
            height: sourceImage.size.height * sourceImage.scale
        )
        // .scaledToFit base size in container coords (BEFORE our scale).
        let containerAspect = containerSize.width / containerSize.height
        let imageAspect = sourceImage.size.width / sourceImage.size.height
        let baseSize: CGSize
        if imageAspect > containerAspect {
            baseSize = CGSize(width: containerSize.width,
                              height: containerSize.width / imageAspect)
        } else {
            baseSize = CGSize(width: containerSize.height * imageAspect,
                              height: containerSize.height)
        }
        // After scaleEffect:
        let scaled = CGSize(width: baseSize.width * imageScale,
                            height: baseSize.height * imageScale)
        // Image center in container coords (scaleEffect pivots on the
        // image's center, which is the container's center BEFORE offset).
        let imageCenter = CGPoint(
            x: containerSize.width  / 2 + imageOffset.width,
            y: containerSize.height / 2 + imageOffset.height
        )
        let imageOrigin = CGPoint(
            x: imageCenter.x - scaled.width  / 2,
            y: imageCenter.y - scaled.height / 2
        )

        // Translate cropRect (container coords) → source-image pixel coords.
        let scaleX = sourcePxSize.width  / scaled.width
        let scaleY = sourcePxSize.height / scaled.height
        var srcRect = CGRect(
            x: (cropRect.minX - imageOrigin.x) * scaleX,
            y: (cropRect.minY - imageOrigin.y) * scaleY,
            width:  cropRect.width  * scaleX,
            height: cropRect.height * scaleY
        )
        // Clamp to source bounds (avoid CGImage.cropping(to:)
        // returning nil for out-of-bounds).
        let sourceBounds = CGRect(origin: .zero, size: sourcePxSize)
        srcRect = srcRect.intersection(sourceBounds)
        guard !srcRect.isNull, srcRect.width >= 1, srcRect.height >= 1 else {
            return sourceImage
        }

        // CGImage.cropping operates in the ORIGINAL image's coordinate
        // space — orientation-agnostic for our purposes since the
        // PhotosPicker hands back orientation-corrected images. Still,
        // we re-bake orientation through CIImage.oriented(...) before
        // cropping in case the source UIImage carries a non-up
        // orientation flag.
        let oriented = sourceImage.normalizedOrientation()
        guard let cgImage = oriented.cgImage,
              let cropped = cgImage.cropping(to: srcRect) else {
            return sourceImage
        }
        return UIImage(cgImage: cropped, scale: 1.0, orientation: .up)
    }
}

// MARK: - UIImage orientation normalization

private extension UIImage {
    /// Re-draws the image into a fresh CGContext so the resulting
    /// UIImage has imageOrientation == .up. Necessary because the
    /// downstream CGImage.cropping math assumes the pixel buffer
    /// matches the visible orientation. Cheap for sub-12MP photos.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
