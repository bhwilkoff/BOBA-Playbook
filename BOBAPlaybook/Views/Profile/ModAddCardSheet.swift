import SwiftUI
import UIKit

// MARK: - ModAddCardSheet
//
// Lets a moderator (or admin) propose a NEW card that isn't yet in the
// catalog. Mirrors ModCardEditSheet's field layout, but every field
// starts blank and the user types in the cardNumber + hero + the rest.
// The cardType picker drives which downstream fields show — a Sealed
// Product doesn't ask for power; a Play card does ask for cost +
// ability text; etc.
//
// On submit:
//   1. Compose the full card spec dictionary from the form fields.
//   2. Compute the canonical bobaId (cardNumber-hero-treatment-variation
//      per scripts/boba_id.py).
//   3. Verify the bobaId isn't already in the local catalog — guards
//      against accidental duplicate submissions.
//   4. If the moderator picked + cropped an image, upload it to
//      Supabase Storage `mod-card-images` first.
//   5. POST to SupabaseClient.submitCardAddition with kind='addition'.
//      Status = "pending" for moderators; "approved" auto for admins.
//
// The actual catalog write happens server-side via the merge worker
// (scripts/merge_approved_additions.py) which picks up approved rows
// and ships them to cards.json + R2.

struct ModAddCardSheet: View {
    @Environment(AuthManager.self)  private var auth
    @Environment(CardStore.self)    private var cardStore
    @Environment(\.dismiss)         private var dismiss

    // MARK: Required across all types
    @State private var cardNumber: String = ""
    @State private var hero:       String = ""
    @State private var name:       String = ""
    @State private var cardType:   CardTypeOption = .hero
    @State private var set:        String = ""
    @State private var subSet:     String = ""
    @State private var variation:  String = ""
    @State private var treatment:  String = ""
    @State private var release:    String = ""
    @State private var element:    String = "NONE"
    @State private var powerText:  String = ""

    // MARK: Hero / Play optional
    @State private var athleteInspiration: String = ""
    @State private var isInspiredInk:      Bool = false
    @State private var rookieInspired:     Bool = false

    // MARK: Play-only
    @State private var playCostText: String = ""
    @State private var playAbility:  String = ""
    @State private var isBonusPlay:  Bool = false
    @State private var isHTD:        Bool = false
    @State private var dbsText:      String = ""
    @State private var dbsTier:      String = ""

    @State private var notes: String = ""

    // MARK: Image flow — iOS native pick + crop, JPEG payload out
    @State private var croppedPreview:    UIImage?
    @State private var selectedImageData: Data?
    @State private var showingCropper:    Bool = false

    // MARK: Submit / validation state
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveSuccess = false
    @State private var bobaIdCollision: Bool = false

    enum CardTypeOption: String, CaseIterable, Identifiable {
        case hero    = "Hero"
        case play    = "Play"
        case hotDog  = "HotDog"
        case sealed  = "Sealed Product"
        var id: String { rawValue }
    }

    /// Standard element vocabulary across the catalog. "ALT" exists
    /// for Alt-Art and other non-element treatments; "NONE" is the
    /// sealed-product default.
    private let elementChoices = [
        "NONE", "FIRE", "ICE", "HEX", "STEEL",
        "BRAWL", "GLOW", "GUM", "SUPER", "ALT",
    ]

    private let dbsTierChoices = ["", "Low", "Medium", "High", "Very High"]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                taxonomySection
                imageSection
                if cardType == .play { playSection }
                if cardType == .hero || cardType == .play { heroOptionsSection }
                notesSection
                errorSection
                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.nearBlack)
            .navigationTitle("Add new card")
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
                        Button(auth.role == "admin" ? "Add" : "Submit") { submit() }
                            .font(Design.Fonts.mono(14, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                            .disabled(!canSubmit)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCropper) {
                NativeImageCropper(
                    onPick: { cropped in
                        croppedPreview = cropped
                        selectedImageData = jpegForUpload(cropped, maxDim: 1200, quality: 0.85)
                        showingCropper = false
                    },
                    onCancel: { showingCropper = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: cardNumber) { _, _ in checkCollision() }
            .onChange(of: hero)       { _, _ in checkCollision() }
            .onChange(of: name)       { _, _ in checkCollision() }
            .onChange(of: treatment)  { _, _ in checkCollision() }
            .onChange(of: variation)  { _, _ in checkCollision() }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("IDENTITY") {
            Picker("Type", selection: $cardType) {
                ForEach(CardTypeOption.allCases) { Text($0.rawValue).tag($0) }
            }
            .font(Design.Fonts.mono(14))

            field("Card #", binding: $cardNumber, placeholder: "e.g. Promo, BBF-150, Top 8")
            field(cardType == .sealed ? "Product name" : "Name",
                  binding: $name,
                  placeholder: cardType == .sealed ? "Booster Box / Display Case / …" : "Display name")
            if cardType != .sealed {
                field("Hero", binding: $hero,
                      placeholder: "Bojax, A.I., Skeee, …")
            }
            if bobaIdCollision {
                Label("This bobaId already exists in the catalog.", systemImage: "exclamationmark.triangle.fill")
                    .font(Design.Fonts.mono(12))
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .top) {
                Text("bobaId")
                    .font(Design.Fonts.mono(12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Design.Colors.textMuted)
                Spacer()
                Text(previewBobaId)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(bobaIdCollision ? .orange : Design.Colors.bobaCyan)
                    .multilineTextAlignment(.trailing)
            }
        }
        .listRowBackground(Design.Colors.surface)
    }

    private var taxonomySection: some View {
        Section("TAXONOMY") {
            field("Set",       binding: $set,       placeholder: "Promo Cards, Alpha Edition, …")
            field("Sub-set",   binding: $subSet,    placeholder: "First Reward Promo, 2025 Apex, …")
            field("Variation", binding: $variation, placeholder: "(optional)")
            field("Treatment", binding: $treatment, placeholder: "Exclusive Battlefoil, Alt Art Battlefoil, …")
            field("Release",   binding: $release,   placeholder: "Promo, Alpha, Griffey, …")
            Picker("Weapon", selection: $element) {
                ForEach(elementChoices, id: \.self) { Text($0).tag($0) }
            }
            .font(Design.Fonts.mono(14))
            if cardType != .sealed {
                field("Power", binding: $powerText,
                      placeholder: "195",
                      keyboard: .numberPad)
            }
        }
        .listRowBackground(Design.Colors.surface)
    }

    private var imageSection: some View {
        Section("IMAGE") {
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
            } else {
                Text("Optional. The auto-pipeline can find art later if you skip this.")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
        .listRowBackground(Design.Colors.surface)
    }

    private var heroOptionsSection: some View {
        Section("HERO DETAILS") {
            field("Athlete inspiration", binding: $athleteInspiration,
                  placeholder: "Bo Jackson, Allen Iverson, …")
            Toggle("Inspired Ink (serialized)", isOn: $isInspiredInk)
                .font(Design.Fonts.mono(14))
                .tint(Design.Colors.bobaOrange)
            Toggle("Rookie inspired", isOn: $rookieInspired)
                .font(Design.Fonts.mono(14))
                .tint(Design.Colors.bobaOrange)
        }
        .listRowBackground(Design.Colors.surface)
    }

    private var playSection: some View {
        Section("PLAY DETAILS") {
            field("Cost", binding: $playCostText, placeholder: "0 = FREE", keyboard: .numberPad)
            Toggle("Bonus Play", isOn: $isBonusPlay)
                .font(Design.Fonts.mono(14))
                .tint(Design.Colors.bobaOrange)
            Toggle("Home Team Discount (HTD)", isOn: $isHTD)
                .font(Design.Fonts.mono(14))
                .tint(Design.Colors.bobaOrange)
            field("DBS", binding: $dbsText, placeholder: "(optional)", keyboard: .numberPad)
            Picker("DBS Tier", selection: $dbsTier) {
                ForEach(dbsTierChoices, id: \.self) { t in
                    Text(t.isEmpty ? "—" : t).tag(t)
                }
            }
            .font(Design.Fonts.mono(14))
            VStack(alignment: .leading, spacing: 6) {
                Text("Ability text")
                    .font(Design.Fonts.mono(12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Design.Colors.textMuted)
                TextEditor(text: $playAbility)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .frame(minHeight: 80)
            }
        }
        .listRowBackground(Design.Colors.surface)
    }

    private var notesSection: some View {
        Section("NOTES") {
            TextEditor(text: $notes)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textSecondary)
                .frame(minHeight: 60)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Optional: source for the card, anything reviewers need to know…")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textMuted)
                            .padding(.top, 8).padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
        .listRowBackground(Design.Colors.surface)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = saveError {
            Section {
                Text(error)
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(.red)
            }
            .listRowBackground(Design.Colors.surface)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if saveSuccess {
            Section {
                Label(
                    auth.role == "admin" ? "Card added." : "Submitted for admin review.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.bobaCyan)
            }
            .listRowBackground(Design.Colors.surface)
        }
    }

    // MARK: - Field builder

    @ViewBuilder
    private func field(_ label: String, binding: Binding<String>,
                       placeholder: String = "",
                       keyboard: UIKeyboardType = .default) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Design.Fonts.mono(12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Design.Colors.textMuted)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: binding)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textPrimary)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Derived state

    /// Effective hero/name string per the bobaId formula:
    /// `hero || name`.
    private var bobaIdHeroOrName: String {
        let h = hero.trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? name.trimmingCharacters(in: .whitespaces) : h
    }

    private var previewBobaId: String {
        let cn = cardNumber.trimmingCharacters(in: .whitespaces)
        let h  = bobaIdHeroOrName
        let t  = treatment.trimmingCharacters(in: .whitespaces)
        let v  = variation.trimmingCharacters(in: .whitespaces)
        return "\(cn)-\(h)-\(t)-\(v)"
    }

    private var canSubmit: Bool {
        let cn = cardNumber.trimmingCharacters(in: .whitespaces)
        let h  = bobaIdHeroOrName
        let s  = set.trimmingCharacters(in: .whitespaces)
        // cardNumber and (hero || name) are required for the bobaId to
        // be meaningful. Set is required so the card knows where it
        // lives. Power is required for non-Sealed types.
        guard !cn.isEmpty, !h.isEmpty, !s.isEmpty else { return false }
        if cardType != .sealed, Int(powerText.trimmingCharacters(in: .whitespaces)) == nil {
            return false
        }
        if bobaIdCollision { return false }
        return true
    }

    private func checkCollision() {
        let candidate = previewBobaId
        // Empty-ish bobaIds (no cardNumber typed yet) shouldn't flag.
        if candidate.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty {
            bobaIdCollision = false
            return
        }
        bobaIdCollision = cardStore.displayCards.contains { $0.id == candidate }
    }

    // MARK: - Submit

    private func submit() {
        isSaving = true
        saveError = nil
        saveSuccess = false
        let spec = composeSpec()
        let bid  = previewBobaId
        let notesText = notes.isEmpty ? nil : notes
        let imageData = selectedImageData
        let cardNum = cardNumber.trimmingCharacters(in: .whitespaces)
        let isAdmin = auth.role == "admin"
        let status = isAdmin ? "approved" : "pending"

        Task {
            do {
                var storagePath: String? = nil
                if let data = imageData {
                    storagePath = try await uploadImage(data: data, cardNumber: cardNum)
                }
                try await SupabaseClient.shared.submitCardAddition(
                    cardSpec:         spec,
                    bobaId:           bid,
                    notes:            notesText,
                    imageStoragePath: storagePath,
                    status:           status
                )
                saveSuccess = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// Build the full card spec dictionary (matches the cards.json
    /// record shape — same field set as scripts/import_new_cards.py
    /// build_card_record).
    private func composeSpec() -> [String: Any] {
        let cn = cardNumber.trimmingCharacters(in: .whitespaces)
        let nm = name.trimmingCharacters(in: .whitespaces).isEmpty
                 ? bobaIdHeroOrName
                 : name.trimmingCharacters(in: .whitespaces)
        let h  = hero.trimmingCharacters(in: .whitespaces)
        let s  = set.trimmingCharacters(in: .whitespaces)
        let ss = subSet.trimmingCharacters(in: .whitespaces)
        let v  = variation.trimmingCharacters(in: .whitespaces)
        let tr = treatment.trimmingCharacters(in: .whitespaces)
        let rl = release.trimmingCharacters(in: .whitespaces)
        let p  = Int(powerText.trimmingCharacters(in: .whitespaces))

        var spec: [String: Any] = [
            "cardNumber":         cn,
            "name":               nm,
            "hero":               h,
            "cardType":           cardType.rawValue,
            "set":                s,
            "subSet":             ss,
            "variation":          v,
            "treatment":          tr,
            "release":            rl,
            "element":            element,
            "power":              p as Any,
            "isInspiredInk":      isInspiredInk,
            "rookieInspired":     rookieInspired,
        ]
        if cardType == .play {
            spec["playCost"]    = Int(playCostText.trimmingCharacters(in: .whitespaces)) as Any
            spec["playAbility"] = playAbility.isEmpty ? NSNull() : playAbility
            spec["isBonusPlay"] = isBonusPlay
            spec["isHTD"]       = isHTD
            spec["dbs"]         = Int(dbsText.trimmingCharacters(in: .whitespaces)) as Any
            spec["dbsTier"]     = dbsTier.isEmpty ? NSNull() : dbsTier
        } else {
            spec["playCost"]    = NSNull()
            spec["playAbility"] = NSNull()
            spec["isBonusPlay"] = false
            spec["isHTD"]       = false
        }
        if !athleteInspiration.isEmpty {
            spec["athleteInspiration"] = athleteInspiration
        }
        return spec
    }

    /// Upload the cropped JPEG to the `mod-card-images` Supabase
    /// Storage bucket. Matches ModCardEditSheet.uploadImage but the
    /// filename prefix uses the new card's number + a timestamp.
    private func uploadImage(data: Data, cardNumber: String) async throws -> String {
        guard let userId = SupabaseClient.shared.userId else {
            throw APIError.serverError(401, "Not authenticated")
        }
        // Sanitize the card number for the storage path — slashes /
        // spaces are problematic.
        let safeCN = cardNumber
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let path = "\(userId)/new-\(safeCN)-\(Int(Date().timeIntervalSince1970)).jpg"
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

    /// Same JPEG-resize-encode helper as ModCardEditSheet — duplicated
    /// here to keep the file self-contained per the
    /// [[feedback_xcode_synchronized_groups]] gotcha (new shared
    /// helper files aren't reliably picked up by the Xcode project).
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
}
