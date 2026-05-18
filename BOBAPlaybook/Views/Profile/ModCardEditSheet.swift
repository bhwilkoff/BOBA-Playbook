import SwiftUI
import PhotosUI
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

    // Image upload — PhotosPicker selects, then CardCropView (v2.216
    // built on UIScrollView for native pan/zoom feel) handles the
    // 5:7 crop with corner-resize before the JPEG payload heads to
    // Supabase Storage.
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var croppedPreview: UIImage?
    /// Identifiable carrier so `fullScreenCover(item:)` can trigger
    /// presentation when a photo is picked.
    private struct CroppingPayload: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    @State private var croppingPayload: CroppingPayload?
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
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(
                                selectedImageData != nil ? "Photo Cropped ✓  ·  Pick again" : "Pick a photo",
                                systemImage: "photo.badge.plus"
                            )
                            .font(Design.Fonts.mono(14))
                            .foregroundStyle(selectedImageData != nil ? Design.Colors.bobaCyan : Design.Colors.bobaOrange)
                        }
                        .onChange(of: selectedPhotoItem) { _, item in
                            Task {
                                guard let data = try? await item?.loadTransferable(type: Data.self),
                                      let img = UIImage(data: data) else { return }
                                await MainActor.run {
                                    selectedImageData = nil
                                    croppedPreview = nil
                                    croppingPayload = CroppingPayload(image: img)
                                }
                            }
                        }
                        if let preview = croppedPreview {
                            HStack(spacing: 12) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cropped preview")
                                        .font(Design.Fonts.mono(11, weight: .semibold))
                                        .tracking(1)
                                        .foregroundStyle(Design.Colors.bobaCyan)
                                    Button("Re-crop") {
                                        croppingPayload = CroppingPayload(image: preview)
                                    }
                                    .font(Design.Fonts.mono(12))
                                    .foregroundStyle(Design.Colors.bobaOrange)
                                }
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

                // v2.273 — inline saveError / saveSuccess sections removed;
                // both now surface as .alert above with explicit OK button.
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
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // v2.273 — always-rendered Button + .disabled(isSaving)
                    // alongside an inline ProgressView. The previous
                    // `if isSaving { ProgressView() } else { Button(...) }`
                    // swap pattern was technically valid on iOS 26 but
                    // produced ambiguous UX: the button disappeared
                    // entirely while the spinner appeared in its slot,
                    // and on a fast network the swap could happen so
                    // briefly the user thought nothing had happened.
                    // Beta tester report: "hit submit twice, then cancel."
                    // New pattern keeps the labeled button visible with
                    // an unambiguous "Submitting…" label + adjacent
                    // spinner; .disabled(isSaving) prevents a re-tap.
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(Design.Colors.bobaOrange)
                        }
                        Button(submitButtonLabel) { submit() }
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .disabled(isSaving || (correctionDict.isEmpty && imageAction == .none))
                    }
                }
            }
            // v2.273 — explicit success alert. The inline Section indicator
            // shipped before was easy to miss before the 1.5s auto-dismiss.
            // Now the user gets a modal that requires an explicit tap.
            .alert("Submission received", isPresented: $saveSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text(auth.role == "admin"
                     ? "Changes saved to the catalog."
                     : "Your correction is queued for admin review. You'll see it land in the catalog after approval.")
            }
            .alert("Submission failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .fullScreenCover(item: $croppingPayload) { payload in
                CardCropView(
                    sourceImage: payload.image,
                    onConfirm: { cropped in
                        croppedPreview = cropped
                        // JPEG Q85 ≤ 1200px on the longest side matches
                        // the production "full" tier roughly. The pipeline
                        // merge step re-encodes to WebP later.
                        selectedImageData = jpegForUpload(cropped, maxDim: 1200, quality: 0.85)
                        croppingPayload = nil
                    },
                    onCancel: { croppingPayload = nil }
                )
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

    private var submitButtonLabel: String {
        if isSaving { return "Submitting…" }
        return auth.role == "admin" ? "Save" : "Submit"
    }

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
                    let overrideId = try await SupabaseClient.shared.submitImageOverride(
                        cardNumber: card.cardNumber,
                        action: action.supabaseAction,
                        storagePath: storagePath,
                        status: correctionStatus,
                        bobaId: card.id
                    )

                    // v2.275 — admin replace: trigger immediate merge via
                    // the boba-mod-merge Cloudflare Worker so the new
                    // image appears in the app right away (R2 write +
                    // CF cache purge + applied_image_file on the row,
                    // which CardStore reads into its runtime override map).
                    // Non-admins: status='pending', wait for admin approve.
                    // Removes: no merge needed (CardStore.hideImage handles
                    // the runtime side, daily pipeline writes cards.json).
                    if action == .replace,
                       auth.role == "admin",
                       let id = overrideId {
                        do {
                            let applied = try await SupabaseClient.shared.applyImageOverride(id: id)
                            if let imageFile = applied.imageFile {
                                cardStore.setAppliedOverride(
                                    cardNumber: card.cardNumber,
                                    bobaId: card.id,
                                    imageFile: imageFile
                                )
                            }
                        } catch {
                            // Surface the merge failure to the user, but
                            // keep the DB row — admin can retry via the
                            // panel, or the daily cron will sweep it.
                            saveError = "Saved, but immediate image apply failed: \(error.localizedDescription)"
                        }
                    }
                }

                // Immediately hide the image locally if it was removed
                if action == .remove {
                    cardStore.hideImage(cardNumber: card.cardNumber)
                }
                // v2.273 — alert handles dismiss via its OK button now;
                // no more 1.5s sleep race that beta-tester report exposed.
                isSaving = false
                saveSuccess = true
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
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
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(0, "Image upload failed — no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Surface the actual status + Storage API error body so failures
            // are diagnosable. v2.273 ship reported a generic "Image upload
            // failed" that masked a 400 from a missing storage bucket; the
            // beta tester + admin both lost time guessing at the cause.
            let body = String(data: responseData, encoding: .utf8) ?? ""
            let trimmed = body.prefix(240)
            throw APIError.serverError(
                http.statusCode,
                "Image upload failed (HTTP \(http.statusCode)) — \(trimmed.isEmpty ? "no body" : String(trimmed))"
            )
        }
        return path
    }
}
