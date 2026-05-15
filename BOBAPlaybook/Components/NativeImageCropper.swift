import SwiftUI
import UIKit

// MARK: - NativeImageCropper
//
// Thin SwiftUI wrapper around UIImagePickerController + its built-in
// editing UI (allowsEditing = true). Replaces the custom CardCropView
// for the moderator flows after v2.213's hand-rolled cropping turned
// out to be impossible to get right against SwiftUI's gesture stack.
//
// What the user gets:
//   1. Standard iOS photo picker (the one they already know).
//   2. After tapping a photo, iOS presents its NATIVE crop screen —
//      pan + zoom the image behind a fixed square window, then
//      "Choose" to confirm. The gestures all work because Apple
//      wrote them. No edge-handle confusion.
//   3. Cancel either step → onCancel.
//
// Note: the iOS crop window is fixed-square. Real BoBA cards are
// 5:7, so a moderator picks the card from their library, then in
// the iOS editor zooms the card to FILL the square (leaving a bit
// of bleed top + bottom OR cropping the sides slightly). The
// catalog renders every image at `.aspectRatio(5/7, .fit)` so an
// almost-square crop reads correctly with neutral top/bottom
// bleed visible.
//
// Why not PHPickerViewController? PHPicker is the modern picker
// but it does NOT include a crop UI. UIImagePickerController is the
// only Apple-supplied path that gives a built-in editor with the
// pan + zoom interaction the user described as the desired feel.
// It's still fully supported in iOS 18 and our use case here
// (.photoLibrary, single image) isn't affected by the camera-
// contention issue documented in
// feedback_camera_contention_avcapture_uipicker — that memory is
// about the .camera source type.

struct NativeImageCropper: UIViewControllerRepresentable {
    /// Called with the cropped UIImage on confirm.
    let onPick: (UIImage) -> Void
    /// Called when the user cancels at any point (picker or editor).
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true     // enables the built-in pan/zoom crop screen
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // .editedImage is the cropped result; .originalImage is the
            // raw photo. Prefer edited (the moderator cropped it on
            // purpose) and fall back to original only if for some
            // reason the edit step was skipped.
            let edited = info[.editedImage] as? UIImage
            let original = info[.originalImage] as? UIImage
            if let img = edited ?? original {
                onPick(img)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
