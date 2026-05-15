import SwiftUI
import UIKit

// MARK: - CardCropView (v2.216 — UIScrollView-based)
//
// In-app card cropper for the moderator add-card / edit-card flows.
// v2.213/14 tried to do pan + pinch + corner-resize in pure SwiftUI
// and the gesture-priority math was a losing battle. v2.215 tried
// UIImagePickerController's fixed-square crop and lost the 5:7
// requirement. v2.216 keeps the right tool for each job:
//
//   • IMAGE pan + zoom = UIScrollView. Apple's scroll view does
//     pinch + pan + bounce + momentum exactly the way iOS Photos
//     does — because it IS the thing iOS Photos uses. Zero
//     custom gesture math.
//   • CROP rectangle = SwiftUI overlay. Only the four corner
//     handles are hittable; everything else is .allowsHitTesting
//     (false) so taps fall through to the UIScrollView behind it.
//   • Defaults to 5:7 (cardWidth:cardHeight) but the user can
//     drag any corner to adjust freeform — a photo of a real card
//     is rarely perfect 5:7 and the moderator needs to dial in the
//     real edges.
//
// Confirm computes the crop in source pixel coords from the
// scroll view's zoomScale + contentOffset + image-view bounds and
// returns a tightly-cropped UIImage via CGImage.cropping.

struct CardCropView: View {
    let sourceImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    /// 5:7 = BoBA card aspect (width/height ≈ 0.714).
    private static let defaultAspect: CGFloat = 5.0 / 7.0

    // Scroll state — populated by the scroll-view coordinator each
    // gesture .ended frame. Used at confirm time to map crop-rect
    // container coords → source pixel coords. iOS 17+ @Observable
    // pattern so the file doesn't need to import Combine.
    @State private var scrollState = ScrollState()

    // Crop rect lives in CONTAINER (SwiftUI screen-space) coords.
    @State private var cropRect: CGRect = .zero
    @State private var containerSize: CGSize = .zero
    @State private var hasInitializedCrop = false

    // Corner drag state
    @State private var activeHandle: Handle? = nil
    @State private var dragStartRect: CGRect = .zero

    enum Handle { case topLeft, topRight, bottomLeft, bottomRight }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // 1. UIScrollView with the image — pan/pinch native.
                ZoomableImageScrollView(image: sourceImage, state: scrollState)
                    .ignoresSafeArea()

                // 2. Dim everything outside the crop rectangle.
                cropMask(in: geo.size)
                    .fill(Color.black.opacity(0.55))
                    .allowsHitTesting(false)

                // 3. Crop border + rule-of-thirds grid (visual only).
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .allowsHitTesting(false)

                Path { p in
                    let r = cropRect
                    p.move(to: CGPoint(x: r.minX + r.width / 3, y: r.minY))
                    p.addLine(to: CGPoint(x: r.minX + r.width / 3, y: r.maxY))
                    p.move(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.minY))
                    p.addLine(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.maxY))
                    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height / 3))
                    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height / 3))
                    p.move(to: CGPoint(x: r.minX, y: r.minY + 2 * r.height / 3))
                    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * r.height / 3))
                }
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                .allowsHitTesting(false)

                // 4. Corner handles — the ONLY interactive overlay.
                cornerHandle(.topLeft,     at: CGPoint(x: cropRect.minX, y: cropRect.minY), in: geo.size)
                cornerHandle(.topRight,    at: CGPoint(x: cropRect.maxX, y: cropRect.minY), in: geo.size)
                cornerHandle(.bottomLeft,  at: CGPoint(x: cropRect.minX, y: cropRect.maxY), in: geo.size)
                cornerHandle(.bottomRight, at: CGPoint(x: cropRect.maxX, y: cropRect.maxY), in: geo.size)
            }
            .onAppear {
                containerSize = geo.size
                initializeCropRectIfNeeded(in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                containerSize = newSize
                if !hasInitializedCrop { initializeCropRectIfNeeded(in: newSize) }
            }
            .safeAreaInset(edge: .top) { hint }
            .safeAreaInset(edge: .bottom) { toolbar }
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Subviews

    private var hint: some View {
        Text("Pinch and drag the photo. Pull a corner to adjust the crop frame (defaults to 5:7).")
            .font(Design.Fonts.mono(11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.8))
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
                if let cropped = performCrop() { onConfirm(cropped) }
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
        ZStack {
            Circle()
                .fill(Design.Colors.bobaOrange)
                .frame(width: 22, height: 22)
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 22, height: 22)
        }
        .position(point)
        // 56pt hit area centered on the visible dot.
        .contentShape(Circle().inset(by: -17))
        .gesture(
            DragGesture(minimumDistance: 0)
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
                .onEnded { _ in activeHandle = nil }
        )
    }

    private func cropMask(in size: CGSize) -> Path {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addRect(cropRect)
        return path.normalized(eoFill: true)
    }

    // MARK: - Crop rect math

    private func initializeCropRectIfNeeded(in size: CGSize) {
        guard !hasInitializedCrop, size.width > 0, size.height > 0 else { return }
        // Largest 5:7 rect that fits with 32pt insets + chrome.
        let inset: CGFloat = 32
        let maxW = max(0, size.width  - inset * 2)
        let maxH = max(0, size.height - inset * 2 - 100)
        let aspect = Self.defaultAspect
        var w = maxW
        var h = w / aspect
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        cropRect = CGRect(
            x: (size.width  - w) / 2,
            y: (size.height - h) / 2,
            width: w, height: h
        )
        hasInitializedCrop = true
    }

    private func updatedRect(from start: CGRect, corner: Handle, translation: CGSize, inSize size: CGSize) -> CGRect {
        let minSize: CGFloat = 80
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY
        switch corner {
        case .topLeft:     minX = start.minX + translation.width; minY = start.minY + translation.height
        case .topRight:    maxX = start.maxX + translation.width; minY = start.minY + translation.height
        case .bottomLeft:  minX = start.minX + translation.width; maxY = start.maxY + translation.height
        case .bottomRight: maxX = start.maxX + translation.width; maxY = start.maxY + translation.height
        }
        minX = max(0, min(minX, size.width  - minSize))
        minY = max(0, min(minY, size.height - minSize))
        maxX = min(size.width,  max(maxX, minX + minSize))
        maxY = min(size.height, max(maxY, minY + minSize))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Performing the crop

    /// Map the crop rectangle from container coords → source pixel
    /// coords using the scroll view's current zoom + offset + image
    /// view bounds, then return the cropped UIImage.
    private func performCrop() -> UIImage? {
        guard cropRect.width > 0, cropRect.height > 0,
              let imageViewBounds = scrollState.imageViewBounds,
              let scrollFrame = scrollState.scrollFrame,
              imageViewBounds.width > 0, imageViewBounds.height > 0
        else { return sourceImage }

        let zoom    = scrollState.zoomScale
        let offset  = scrollState.contentOffset

        // The scroll view's frame in container coords might be inset
        // by safe areas — convert cropRect to scroll-bounds coords.
        let cropInScrollBounds = CGRect(
            x: cropRect.minX - scrollFrame.minX,
            y: cropRect.minY - scrollFrame.minY,
            width: cropRect.width,
            height: cropRect.height
        )

        // Scroll-bounds → content-space (already scaled by zoom).
        let contentMin = CGPoint(
            x: cropInScrollBounds.minX + offset.x,
            y: cropInScrollBounds.minY + offset.y
        )
        let contentMax = CGPoint(
            x: cropInScrollBounds.maxX + offset.x,
            y: cropInScrollBounds.maxY + offset.y
        )
        // Content-space → image-view's natural coords (zoom=1).
        let ivMin = CGPoint(x: contentMin.x / zoom, y: contentMin.y / zoom)
        let ivMax = CGPoint(x: contentMax.x / zoom, y: contentMax.y / zoom)
        // Image-view's natural bounds → source pixel coords.
        let pxScaleX = sourceImage.size.width  / imageViewBounds.width
        let pxScaleY = sourceImage.size.height / imageViewBounds.height
        var srcRect = CGRect(
            x: ivMin.x * pxScaleX,
            y: ivMin.y * pxScaleY,
            width:  (ivMax.x - ivMin.x) * pxScaleX,
            height: (ivMax.y - ivMin.y) * pxScaleY
        )
        // Convert points → pixels by the image's own scale (Retina).
        srcRect = CGRect(
            x: srcRect.minX * sourceImage.scale,
            y: srcRect.minY * sourceImage.scale,
            width:  srcRect.width  * sourceImage.scale,
            height: srcRect.height * sourceImage.scale
        )
        // Clamp to the image's pixel bounds.
        let imagePxBounds = CGRect(
            x: 0, y: 0,
            width:  sourceImage.size.width  * sourceImage.scale,
            height: sourceImage.size.height * sourceImage.scale
        )
        srcRect = srcRect.intersection(imagePxBounds)
        guard !srcRect.isNull, srcRect.width >= 1, srcRect.height >= 1 else { return sourceImage }

        let oriented = sourceImage.normalizedOrientation()
        guard let cg = oriented.cgImage,
              let cropped = cg.cropping(to: srcRect) else { return sourceImage }
        return UIImage(cgImage: cropped, scale: sourceImage.scale, orientation: .up)
    }
}

// MARK: - Scroll state (bridge UIKit ↔ SwiftUI)

/// Shared state object updated by ZoomableImageScrollView's
/// coordinator on every scroll/zoom change. CardCropView reads
/// these values at confirm time to compute the cropped image.
///
/// Uses the iOS 17+ `@Observable` macro (NOT `ObservableObject` +
/// `@Published`) so this file doesn't need to import Combine — the
/// older Combine-based pattern triggered a cascade of "missing
/// import of defining module 'Combine'" errors across the build
/// because the SwiftUI module forwards the @StateObject /
/// @ObservedObject types from Combine. @Observable lives entirely
/// in the Observation framework which SwiftUI re-exports.
@MainActor
@Observable
final class ScrollState {
    var zoomScale: CGFloat = 1.0
    var contentOffset: CGPoint = .zero
    var imageViewBounds: CGRect? = nil
    var scrollFrame: CGRect? = nil
}

// MARK: - ZoomableImageScrollView

/// UIScrollView with a UIImageView inside — gives us iOS-native
/// pinch-to-zoom + drag-to-pan + bounce. The user feels Photos.app
/// because this IS the same primitive Photos.app builds on.
private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage
    let state: ScrollState

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.bouncesZoom = true
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = false
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.maximumZoomScale = 6.0
        scroll.minimumZoomScale = 1.0  // updated in layoutSubviews once we know geometry
        scroll.decelerationRate = .fast

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll

        // Double-tap to toggle zoom (matches Photos.app feel).
        let dt = UITapGestureRecognizer(target: context.coordinator,
                                        action: #selector(Coordinator.handleDoubleTap(_:)))
        dt.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(dt)
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.layoutIfNeeded()
        DispatchQueue.main.async { context.coordinator.publishState() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state, image: image) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        let state: ScrollState
        let image: UIImage
        private var didInitialLayout = false

        init(state: ScrollState, image: UIImage) {
            self.state = state
            self.image = image
        }

        /// Size the imageView to the image's aspect-fit within the
        /// scrollview's bounds, and set the minimum/initial zoom so
        /// the whole image is visible without scrolling.
        func layoutIfNeeded() {
            guard let scroll = scrollView, let iv = imageView else { return }
            guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            if didInitialLayout { return }
            didInitialLayout = true

            let imageAspect  = image.size.width / image.size.height
            let scrollAspect = scroll.bounds.width / scroll.bounds.height
            let ivSize: CGSize
            if imageAspect > scrollAspect {
                ivSize = CGSize(width: scroll.bounds.width,
                                height: scroll.bounds.width / imageAspect)
            } else {
                ivSize = CGSize(width: scroll.bounds.height * imageAspect,
                                height: scroll.bounds.height)
            }
            iv.frame = CGRect(origin: .zero, size: ivSize)
            scroll.contentSize = ivSize
            scroll.minimumZoomScale = 1.0
            scroll.zoomScale = 1.0
            centerContent()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
            publishState()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishState()
        }

        /// Keep the image visually centered when zoomed out smaller
        /// than the scroll bounds — matches Photos.app feel.
        private func centerContent() {
            guard let scroll = scrollView, let iv = imageView else { return }
            let dx = max(0, (scroll.bounds.width  - iv.frame.width)  / 2)
            let dy = max(0, (scroll.bounds.height - iv.frame.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        func publishState() {
            guard let scroll = scrollView, let iv = imageView else { return }
            let zoom    = scroll.zoomScale
            let offset  = scroll.contentOffset
            let frame   = scroll.frame
            // The imageView's "natural" bounds (at zoom=1) are
            // iv.bounds.size if it hasn't been transformed by the
            // scroll view's zoom mechanism. UIScrollView changes the
            // imageView's frame to reflect zoom, so iv.bounds stays
            // the same size we set it to and frame.size scales.
            let ivNatural = iv.bounds
            // Schedule publish off the call stack to avoid SwiftUI
            // "modifying state during view update" warnings when the
            // initial layout call publishes mid-render.
            Task { @MainActor in
                state.zoomScale       = zoom
                state.contentOffset   = offset
                state.imageViewBounds = ivNatural
                state.scrollFrame     = frame
            }
        }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            let target: CGFloat
            if scroll.zoomScale > 1.01 {
                target = 1.0
            } else {
                target = min(3.0, scroll.maximumZoomScale)
            }
            scroll.setZoomScale(target, animated: true)
        }
    }
}

// MARK: - UIImage orientation normalization

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
