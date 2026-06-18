import SwiftUI
import UIKit

// MARK: - SecureInputField
// UIViewRepresentable wrapper for a secure text field that maintains white dot
// color even when iOS autofill / strong-password injection resets UIKit styling.
// SwiftUI's SecureField cannot guarantee foreground color through autofill because
// UIKit resets textColor on the backing UITextField when the system injects text.

struct SecureInputField: UIViewRepresentable {

    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType = .password
    var submitLabel: UIReturnKeyType = .done
    var onSubmit: (() -> Void)?
    var focused: Bool = false
    /// When false, the field renders text in cleartext (eye-toggle off).
    /// Default true preserves the existing behavior for unparameterized
    /// call sites. Threaded via updateUIView so a parent @State flip
    /// re-asserts isSecureTextEntry without losing focus or caret position.
    var isSecure: Bool = true

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = isSecure
        field.textColor = .white
        field.tintColor = .white
        field.keyboardAppearance = .dark
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = submitLabel
        field.textContentType = textContentType
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
        field.font = UIFont(name: "ChakraPetch-Regular", size: 15)
            ?? UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        // Keep UIKit text in sync with SwiftUI binding (but don't reset cursor)
        if field.text != text {
            field.text = text
        }
        // Always re-assert white — autofill can reset this
        field.textColor = .white
        field.textContentType = textContentType
        field.returnKeyType = submitLabel
        // Re-assert secure-entry state on every SwiftUI update so the
        // eye-toggle in the parent (Android tick 446 parity) flips the
        // field without rebuilding the UITextField.
        if field.isSecureTextEntry != isSecure {
            field.isSecureTextEntry = isSecure
        }

        // First-responder management: ONLY programmatically focus when a
        // caller explicitly asks (focused == true). We must NOT resign when
        // focused == false — that is the DEFAULT, and updateUIView runs on
        // every keystroke (the text binding changes each character), so an
        // auto-resign here yanks the keyboard away the instant the user types
        // the first character of their password. That was the "password field
        // ejects me out of the field" sign-in bug (App Store review, June
        // 2026, Submission 71738157). The user taps to focus and taps away /
        // submits to resign; UIKit handles that natively.
        if focused && !field.isFirstResponder {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func textChanged(_ field: UITextField) {
            text = field.text ?? ""
            // Re-assert color after every keystroke (autofill can reset mid-entry)
            field.textColor = .white
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit?()
            return true
        }
    }
}
