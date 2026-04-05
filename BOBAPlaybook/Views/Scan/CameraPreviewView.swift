import SwiftUI
import UIKit
import AVFoundation

/// UIViewRepresentable that renders an AVCaptureVideoPreviewLayer full-screen.
/// Reports the preview layer via `onLayerReady` after the first layout pass,
/// so callers can compute the Vision region of interest.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    func makeUIView(context: Context) -> CameraUIView {
        let view = CameraUIView()
        view.previewLayer.session      = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onLayerReady = onLayerReady
        return view
    }

    func updateUIView(_ uiView: CameraUIView, context: Context) {
        uiView.onLayerReady = onLayerReady
    }

    // MARK: - UIView subclass with AVCaptureVideoPreviewLayer as the backing layer
    final class CameraUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?
        private var didReport = false

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            // Report once after the first real layout (bounds > zero)
            if !didReport, bounds.width > 0, bounds.height > 0 {
                didReport = true
                onLayerReady?(previewLayer)
            }
        }
    }
}
