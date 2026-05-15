import SwiftUI
import UIKit

// MARK: - ModCardEditSheet
// Allows moderators to submit card info corrections and image overrides.
// Corrections are written to `card_corrections` table; image actions go to `card_image_overrides`.

struct ModCardEditSheet: View {
    let card: Card
    @Environment(AuthManager.self) private var auth
    @Environment(CardStore.self) private var cardStore
    @Environment(\.dismiss) private var dismiss

    // Correction fields — pre-filled from current card data
    @State private var hero: String
    @State private var element: String
    @State private var set: String
    @State private var variation: String
    @State private var treatment: String
    @State private var playAbility: String
    @State private var notes: String = ""

    // Image upload — picked + cropped via iOS's native UIImagePicker
    // editing UI. v2.215: dropped the custom CardCropView gesture
    // stack in favor of Apple's pan+zoom crop screen, which the
    // user knows from the rest of the OS.
    @State private var selectedImageData: Data?
    @State private var croppedPreview: UIImage?
    @State private var showingCropper: Bool = false
    @State private var imageAction: ImageAction = .none

    // State
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveSuccess = false

    enum ImageAction: CaseIterable {
        case none, replace, remove

        func label(isAdmin: Bool) -> String {
            switch self {
            case .none:    return "No change"
            case .replace: return "Replace image"
            case .remove:  return isAdmin ? "Remove image" : "Flag for removal"
            }
        }

        var supabaseAction: String {
            self == .replace ? "replace" : "remove"
        }
    }

    init(card: Card) {
        self.card = card
        _hero      = State(initialValue: card.hero)
        _element   = State(initialValue: card.element)
        _set       = State(initialValue: card.set)
        _variation = State(initialValue: card.variation ?? "")
        _treatment = State(initialValue: card.treatment ?? "")
        _playAbility = State(initialValue: card.playAbility ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("CARD DETAILS") {
                    correctionField(label: "Card #", value: card.cardNumber, editable: false, binding: .constant(card.cardNumber))
                    correctionField(label: "Hero", value: card.hero.isEmpty ? "—" : card.hero, editable: true, binding: $hero)
                    correctionField(label: "Weapon", value: card.element.isEmpty ? "—" : card.element, editable: true, binding: $element)
                    correctionField(label: "Set", value: card.set.isEmpty ? "—" : card.set, editable: true, binding: $set)
                    correctionField(label: "Variation", value: card.variation ?? "—", editable: true, binding: $variation)
                    correctionField(label: "Treatment", value: card.treatment ?? "—", editable: true, binding: $treatment)
                }
                .listRowBackground(Design.Colors.surface)

                if card.playAbility != nil || card.cardType == "Play" {
                    Section("PLAY ABILITY") {
                        TextEditor(text: $playAbility)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .frame(minHeight: 80)
                    }
                    .listRowBackground(Design.Colors.surface)
                }

                Section("IMAGE") {
                    Picker("Image Action", selection: $imageAction) {
                        ForEach(ImageAction.allCases, id: \.self) { action in
                            Text(action.label(isAdmin: auth.role == "admin")).tag(action)
                        }
                    }
                    .font(Design.Fonts.mono(14))
                    .foregroundStyle(Design.Colors.textPrimary)

                    if imageAction == .replace {
                        Button {
                            showingCropper = true
                        } label: {
                            Label(
                                selectedImageData != nil ? "Photo Cropped ✓  ·  Pick again" : "Pick & crop a photo",
                                systemImage: "photo.badge.plus"
                            )
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(selectedImageData != nil ? Design.Colors.bobaCyan : Design.Colors.bobaOrange)
                        }
                        if let preview = croppedPreview {
                            HStack(spacing: 12) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text("Cropped preview")
                                    .font(Design.Fonts.mono(11, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(Design.Colors.bobaCyan)
                                Spacer()
                            }
                        }
                    }

                    if imageAction == .remove {
                        Text(auth.role == "admin"
                             ? "This will immediately remove the current image."
                             : "This will flag the current image for admin review and removal.")
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
                .listRowBackground(Design.Colors.surface)

                Section("NOTES") {
                    TextEditor(text: $notes)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .frame(minHeight: 60)
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Optional: explain the correction…")
                                    .font(Design.Fonts.mono(13))
                                    .foregroundStyle(Design.Colors.textMuted)
                                    .padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .listRowBackground(Design.Colors.surface)

                if let error = saveError {
                    Section {
                        Text(error)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Design.Colors.surface)
                }

                if saveSuccess {
                    Section {
                        Label(
                            auth.role == "admin" ? "Changes saved." : "Correction submitted for review.",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.bobaCyan)
                    }
                    .listRowBackground(Design.Colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Edit: \(card.cardNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Design.Colors.bobaOrange)
                    } else {
                        Button(auth.role == "admin" ? "Save" : "Submit") { submit() }
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .disabled(correctionDict.isEmpty && imageAction == .none)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCropper) {
                NativeImageCropper(
                    onPick: { cropped in
                        croppedPreview = cropped
                        // JPEG Q85 ≤ 1200px on the longest side matches
                        // the production "full" tier roughly (R2 stores
                        // WebP Q75 ≤1200px; here we hand Supabase Storage
                        // a JPEG because the existing replace pipeline
                        // accepts that). The pipeline merge step will
                        // re-encode to WebP later.
                        selectedImageData = jpegForUpload(cropped, maxDim: 1200, quality: 0.85)
                        showingCropper = false
                    },
                    onCancel: {
                        showingCropper = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    /// Re-encode a cropped UIImage as JPEG for upload: cap the longer
    /// side at `maxDim` pixels (avoids 12MP straight-from-camera
    /// payloads bloating storage), then jpegData at `quality`.
    private func jpegForUpload(_ image: UIImage, maxDim: CGFloat, quality: CGFloat) -> Data? {
        let resized: UIImage
        let longest = max(image.size.width, image.size.height)
        if longest > maxDim {
            let scale = maxDim / longest
            let target = CGSize(width: image.size.width * scale,
                                height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = false
            resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        } else {
            resized = image
        }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Helpers

    /// Fields that differ from the original card data
    private var correctionDict: [String: String] {
        var dict: [String: String] = [:]
        if hero != card.hero                           { dict["hero"] = hero }
        if element != card.element                     { dict["element"] = element }
        if set != card.set                             { dict["set"] = set }
        if variation != (card.variation ?? "")         { dict["variation"] = variation }
        if treatment != (card.treatment ?? "")         { dict["treatment"] = treatment }
        if playAbility != (card.playAbility ?? "")     { dict["play_ability"] = playAbility }
        return dict
    }

    @ViewBuilder
    private func correctionField(label: String, value: String, editable: Bool, binding: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
                .frame(width: 80, alignment: .leading)
            if editable {
                TextField(value, text: binding)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .multilineTextAlignment(.trailing)
            } else {
                Spacer()
                Text(value)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
    }

    // MARK: - Submit

    private func submit() {
        isSaving = true
        saveError = nil
        saveSuccess = false
        let corrections = correctionDict
        let notesText = notes.isEmpty ? nil : notes
        let action = imageAction
        let imageData = selectedImageData
        let correctionStatus = auth.role == "admin" ? "approved" : "pending"

        Task {
            do {
                // Submit info corrections if any fields changed
                if !corrections.isEmpty {
                    try await SupabaseClient.shared.submitCardCorrection(
                        cardNumber:    card.cardNumber,
                        corrections:   corrections,
                        notes:         notesText,
                        status:        correctionStatus,
                        cardHero:      card.hero,
                        cardElement:   card.element,
                        cardPower:     card.power,
                        cardTreatment: card.treatment,
                        bobaId:        card.id
                    )
                }

                // Submit image override if needed
                if action != .none {
                    var storagePath: String? = nil
                    if action == .replace, let data = imageData {
                        storagePath = try await uploadImage(data: data)
                    }
                    try await SupabaseClient.shared.submitImageOverride(
                        cardNumber: card.cardNumber,
                        action: action.supabaseAction,
                        storagePath: storagePath,
                        status: correctionStatus,
                        bobaId: card.id
                    )
                }

                // Immediately hide the image locally if it was removed
                if action == .remove {
                    cardStore.hideImage(cardNumber: card.cardNumber)
                }
                saveSuccess = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// Uploads image data to Supabase Storage `mod-card-images` bucket.
    private func uploadImage(data: Data) async throws -> String {
        guard let userId = SupabaseClient.shared.userId else {
            throw APIError.serverError(401, "Not authenticated")
        }
        let path = "\(userId)/\(card.cardNumber)-\(Int(Date().timeIntervalSince1970)).jpg"
        let urlString = SupabaseConfig.projectURL + "/storage/v1/object/mod-card-images/\(path)"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = SupabaseClient.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(0, "Image upload failed")
        }
        return path
    }
}
