import SwiftUI
import UIKit

// MARK: - CardCropView (v2.218 — pure UIKit under the hood)
//
// Previous attempts (v2.213 / .214 / .216) all mixed SwiftUI gesture
// overlays with a UIScrollView. The SwiftUI overlays would block
// touches from reaching the scroll view no matter how aggressively
// I used `.allowsHitTesting(false)` — the user could never
// pinch-zoom inside the crop area or grab the corners.
//
// The actual answer is what iOS Photos does internally: build the
// WHOLE crop UI in UIKit. UIScrollView handles pan/zoom/pinch
// natively. An overlay UIView draws the dim + border + grid AND
// hosts four corner-handle UIViews. The overlay's `hitTest(_:with:)`
// returns the corner handle if a touch lands within one — otherwise
// returns nil, which makes the OS deliver the touch to the next
// view down (the scroll view), letting Apple's gesture stack handle
// the pan/zoom unmolested.
//
// SwiftUI does nothing here except wrap the whole controller as a
// UIViewControllerRepresentable.

struct CardCropView: UIViewControllerRepresentable {
    let sourceImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CardCropViewController {
        CardCropViewController(
            image: sourceImage,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    func updateUIViewController(_ uiViewController: CardCropViewController, context: Context) {}
}

// MARK: - CardCropViewController

final class CardCropViewController: UIViewController, UIScrollViewDelegate {

    // MARK: Inputs

    private let sourceImage: UIImage
    private let onConfirm: (UIImage) -> Void
    private let onCancel: () -> Void

    // MARK: Subviews

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlay = CardCropOverlayView()
    private let cancelButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    /// Toolbar height reserved at the bottom so the crop rect's
    /// initial frame doesn't fall under it.
    private let toolbarHeight: CGFloat = 64
    private let hintHeight: CGFloat = 40

    // MARK: Init

    init(image: UIImage, onConfirm: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.sourceImage = image
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 1. Scroll view with the image — full screen, native pan/zoom.
        scrollView.delegate = self
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.maximumZoomScale = 6.0
        scrollView.minimumZoomScale = 1.0
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.image = sourceImage
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        scrollView.addSubview(imageView)

        // 2. Overlay covering the whole screen ABOVE the scroll view.
        //    Its hitTest passes touches through unless they land on
        //    one of the four corner handles.
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        view.addSubview(overlay)

        // 3. Hint label across the top.
        hintLabel.text = "Pinch and drag the photo. Pull a corner to adjust the crop."
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        hintLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        // 4. Bottom toolbar — two buttons, no chrome.
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        cancelButton.layer.cornerRadius = 22
        cancelButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        confirmButton.setTitle("Use Crop", for: .normal)
        confirmButton.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0)  // BoBA orange
        confirmButton.layer.cornerRadius = 22
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 26, bottom: 10, right: 26)
        confirmButton.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(confirmButton)

        // 5. Constraints — scroll + overlay fill the screen; hint
        //    pinned to top; buttons pinned to bottom safe area.
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hintLabel.heightAnchor.constraint(equalToConstant: hintHeight),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureScrollViewIfNeeded()
        initializeCropRectIfNeeded()
    }

    // MARK: Initial layout

    private var didConfigureScroll = false
    private func configureScrollViewIfNeeded() {
        guard !didConfigureScroll, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        didConfigureScroll = true

        // Size imageView to the image's aspect-fit within the scroll
        // bounds. At zoom=1 the whole image is visible without
        // scrolling.
        let imageAspect  = sourceImage.size.width / sourceImage.size.height
        let scrollAspect = scrollView.bounds.width / scrollView.bounds.height
        let ivSize: CGSize
        if imageAspect > scrollAspect {
            ivSize = CGSize(width: scrollView.bounds.width,
                            height: scrollView.bounds.width / imageAspect)
        } else {
            ivSize = CGSize(width: scrollView.bounds.height * imageAspect,
                            height: scrollView.bounds.height)
        }
        imageView.frame = CGRect(origin: .zero, size: ivSize)
        scrollView.contentSize = ivSize
        scrollView.zoomScale = 1.0
        centerContent()

        // Double-tap zoom toggle (Photos.app feel).
        let dt = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        dt.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(dt)
    }

    private var didInitializeCropRect = false
    private func initializeCropRectIfNeeded() {
        guard !didInitializeCropRect, view.bounds.width > 0, view.bounds.height > 0 else { return }
        didInitializeCropRect = true
        let safeTop = view.safeAreaInsets.top + hintHeight + 24
        let safeBottom = view.safeAreaInsets.bottom + toolbarHeight + 24
        let usable = CGRect(
            x: 32,
            y: safeTop,
            width: view.bounds.width - 64,
            height: view.bounds.height - safeTop - safeBottom
        )
        // Largest 5:7 rect that fits in `usable`.
        let aspect: CGFloat = 5.0 / 7.0
        var w = usable.width
        var h = w / aspect
        if h > usable.height { h = usable.height; w = h * aspect }
        overlay.cropRect = CGRect(
            x: usable.midX - w / 2,
            y: usable.midY - h / 2,
            width: w, height: h
        )
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    /// Keep the image visually centered when smaller than the
    /// scroll bounds — matches Photos.app feel.
    private func centerContent() {
        let dx = max(0, (scrollView.bounds.width  - imageView.frame.width)  / 2)
        let dy = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    // MARK: Actions

    @objc private func handleCancel() { onCancel() }

    @objc private func handleConfirm() {
        let result = performCrop()
        onConfirm(result)
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        let target: CGFloat = scrollView.zoomScale > 1.01 ? 1.0 : min(3.0, scrollView.maximumZoomScale)
        scrollView.setZoomScale(target, animated: true)
    }

    // MARK: Cropping math

    /// Map the overlay's crop rect from screen coords → source pixel
    /// coords using the scroll view's current state, then return the
    /// cropped UIImage at full source resolution.
    private func performCrop() -> UIImage {
        let cropInScreen = overlay.cropRect
        guard cropInScreen.width > 0, cropInScreen.height > 0,
              imageView.bounds.width > 0, imageView.bounds.height > 0
        else { return sourceImage }

        // Screen coords → scroll view's bounds coords.
        let scrollFrameInScreen = scrollView.convert(scrollView.bounds, to: view)
        let cropInScroll = CGRect(
            x: cropInScreen.minX - scrollFrameInScreen.minX,
            y: cropInScreen.minY - scrollFrameInScreen.minY,
            width: cropInScreen.width,
            height: cropInScreen.height
        )

        // Scroll-bounds → content space (already scaled by zoom).
        let zoom = scrollView.zoomScale
        let offset = scrollView.contentOffset
        let contentMin = CGPoint(x: cropInScroll.minX + offset.x, y: cropInScroll.minY + offset.y)
        let contentMax = CGPoint(x: cropInScroll.maxX + offset.x, y: cropInScroll.maxY + offset.y)

        // Content space → image view's natural coords (divide out zoom).
        let ivMin = CGPoint(x: contentMin.x / zoom, y: contentMin.y / zoom)
        let ivMax = CGPoint(x: contentMax.x / zoom, y: contentMax.y / zoom)

        // Image-view's natural bounds → source PIXEL coords.
        let pxScaleX = sourceImage.size.width  / imageView.bounds.width
        let pxScaleY = sourceImage.size.height / imageView.bounds.height
        var srcRect = CGRect(
            x: ivMin.x * pxScaleX,
            y: ivMin.y * pxScaleY,
            width:  (ivMax.x - ivMin.x) * pxScaleX,
            height: (ivMax.y - ivMin.y) * pxScaleY
        )
        // Convert points → pixels (the image's own scale, e.g. @2x).
        srcRect = CGRect(
            x: srcRect.minX * sourceImage.scale,
            y: srcRect.minY * sourceImage.scale,
            width:  srcRect.width  * sourceImage.scale,
            height: srcRect.height * sourceImage.scale
        )
        let pxBounds = CGRect(
            x: 0, y: 0,
            width:  sourceImage.size.width  * sourceImage.scale,
            height: sourceImage.size.height * sourceImage.scale
        )
        srcRect = srcRect.intersection(pxBounds)
        guard !srcRect.isNull, srcRect.width >= 1, srcRect.height >= 1 else { return sourceImage }

        let oriented = sourceImage.normalizedOrientation()
        guard let cg = oriented.cgImage, let cropped = cg.cropping(to: srcRect) else { return sourceImage }
        return UIImage(cgImage: cropped, scale: sourceImage.scale, orientation: .up)
    }
}

// MARK: - CardCropOverlayView
//
// Draws the dim + border + corner dots. Hosts four corner-handle
// UIViews with their own UIPanGestureRecognizers. Critical: the
// `hitTest(_:with:)` override returns nil for touches outside the
// corner handles so the OS passes those touches through to the
// scroll view sitting below this overlay in the controller's view
// hierarchy.

final class CardCropOverlayView: UIView {

    /// In overlay (== screen) coords.
    var cropRect: CGRect = .zero {
        didSet {
            layoutHandles()
            setNeedsDisplay()
        }
    }

    private let visibleCornerDiameter: CGFloat = 22
    private let hitTargetSize: CGFloat = 56
    private let minCropSize: CGFloat = 80

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private lazy var tlHandle = makeHandleView(.topLeft)
    private lazy var trHandle = makeHandleView(.topRight)
    private lazy var blHandle = makeHandleView(.bottomLeft)
    private lazy var brHandle = makeHandleView(.bottomRight)
    private var handles: [UIView] { [tlHandle, trHandle, blHandle, brHandle] }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        addSubview(tlHandle)
        addSubview(trHandle)
        addSubview(blHandle)
        addSubview(brHandle)
        contentMode = .redraw   // re-render on bounds change
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Hit testing — pass through everywhere except handles

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for handle in handles {
            // Convert point into the handle's coord space.
            let local = handle.convert(point, from: self)
            if handle.bounds.contains(local) {
                return handle
            }
        }
        // Outside the corner handles → return nil so the touch
        // continues hit-testing siblings (the scroll view below).
        return nil
    }

    // MARK: Layout

    private func layoutHandles() {
        let s = hitTargetSize
        tlHandle.frame = CGRect(x: cropRect.minX - s / 2, y: cropRect.minY - s / 2, width: s, height: s)
        trHandle.frame = CGRect(x: cropRect.maxX - s / 2, y: cropRect.minY - s / 2, width: s, height: s)
        blHandle.frame = CGRect(x: cropRect.minX - s / 2, y: cropRect.maxY - s / 2, width: s, height: s)
        brHandle.frame = CGRect(x: cropRect.maxX - s / 2, y: cropRect.maxY - s / 2, width: s, height: s)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutHandles()
    }

    // MARK: Drawing — dim mask + border + grid + corner dots

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Dim the area OUTSIDE the crop rect.
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(bounds)
        ctx.setBlendMode(.clear)
        ctx.fill(cropRect)
        ctx.setBlendMode(.normal)

        // Border.
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(cropRect)

        // Rule-of-thirds grid.
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(0.5)
        let r = cropRect
        ctx.move(to: CGPoint(x: r.minX + r.width / 3, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX + r.width / 3, y: r.maxY))
        ctx.move(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.maxY))
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + r.height / 3))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height / 3))
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + 2 * r.height / 3))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * r.height / 3))
        ctx.strokePath()

        // BoBA-orange corner dots at the four corners.
        let bobaOrange = UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0)
        for corner in [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY),
        ] {
            let d = visibleCornerDiameter
            let rect = CGRect(x: corner.x - d / 2, y: corner.y - d / 2, width: d, height: d)
            ctx.setFillColor(bobaOrange.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: rect)
        }
    }

    // MARK: Corner handles + gesture handling

    private func makeHandleView(_ corner: Corner) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear     // visible dot is drawn in the overlay
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        v.addGestureRecognizer(pan)
        v.tag = cornerTag(corner)
        return v
    }

    private func cornerTag(_ c: Corner) -> Int {
        switch c {
        case .topLeft:     return 1
        case .topRight:    return 2
        case .bottomLeft:  return 3
        case .bottomRight: return 4
        }
    }
    private func corner(forTag tag: Int) -> Corner {
        switch tag {
        case 1: return .topLeft
        case 2: return .topRight
        case 3: return .bottomLeft
        default: return .bottomRight
        }
    }

    private var dragStartRect: CGRect = .zero
    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let handleView = gr.view else { return }
        let c = corner(forTag: handleView.tag)
        switch gr.state {
        case .began:
            dragStartRect = cropRect
        case .changed:
            let t = gr.translation(in: self)
            var minX = dragStartRect.minX
            var minY = dragStartRect.minY
            var maxX = dragStartRect.maxX
            var maxY = dragStartRect.maxY
            switch c {
            case .topLeft:     minX += t.x; minY += t.y
            case .topRight:    maxX += t.x; minY += t.y
            case .bottomLeft:  minX += t.x; maxY += t.y
            case .bottomRight: maxX += t.x; maxY += t.y
            }
            minX = max(0, min(minX, bounds.width  - minCropSize))
            minY = max(0, min(minY, bounds.height - minCropSize))
            maxX = min(bounds.width,  max(maxX, minX + minCropSize))
            maxY = min(bounds.height, max(maxY, minY + minCropSize))
            cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        default:
            break
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
