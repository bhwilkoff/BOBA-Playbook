import SwiftUI
import SafariServices

// MARK: - ProfileView
// Auth + account + display + notifications + role + about, all in one
// sheet per DESIGN.md §6.5. Pushed-to-detail screens (Mod Panel,
// Privacy Policy, etc.) use NavigationLink inside the sheet's own
// NavigationStack so the dismissal contract stays intact (§3.4).
//
// Sections inside the sheet, in order:
//   - Header (avatar, @username, email, role badge)
//   - Account (username inline edit, email, change password)
//   - Connections (Discord link/unlink)
//   - Collection Sharing (toggle + public URL)
//   - Display (icon Menu, per-tab columns, default mode, reset walkthroughs)
//   - Notifications (DisclosureGroup, deferred — UI only)
//   - Role & Access (DisclosureGroup, request streamer/mod)
//   - Moderation (mod/admin only — Mod Panel + Admin Panel pushes)
//   - About (DisclosureGroup, Privacy/Terms/Feedback/Version)
//   - Sign Out + Delete Account
//
// Per DESIGN.md §3.10/§5.5, no .scrollContentBackground or
// .listRowBackground overrides — Form gets the iOS 26 inset Liquid
// Glass treatment automatically inside the sheet.

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    // Discord identity for the Connections row + avatar fallback.
    // DiscordService is re-instantiated per view (existing pattern in
    // CollectionView) — it restores its tokens from Keychain on init,
    // so each instance ends up authorized without a singleton.
    @State private var discord = DiscordService()
    @State private var discordWorking = false

    // Modal state — keep it minimal so the sheet doesn't accumulate
    // modal-on-modal layers (§3.4).
    @State private var showingSignIn          = false
    @State private var showingDeleteConfirm   = false
    @State private var showingSignOutConfirm  = false
    @State private var showingPrivacy         = false
    @State private var showingTerms           = false
    @State private var passwordResetSent      = false
    @State private var roleRequestForRole: String?  // "moderator" or "streamer"
    @State private var showingPractice        = false
    @State private var copyConfirmed          = false

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAuthenticated { signedInView }
                else                    { signedOutView }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal)        { BOBAWordmark() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Fonts.mono(13, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingSignIn) { SignInView() }
        .sheet(item: Binding(
            get: { roleRequestForRole.map(RoleRequestTarget.init(role:)) },
            set: { roleRequestForRole = $0?.role }
        )) { target in
            RoleRequestSheet(role: target.role)
        }
        .sheet(isPresented: $showingPrivacy) { SafariSheet(url: URL(string: "https://bobaplaybook.com/privacy/")!) }
        .sheet(isPresented: $showingTerms)   { SafariSheet(url: URL(string: "https://bobaplaybook.com/terms/")!) }
        .fullScreenCover(isPresented: $showingPractice) {
            NavigationStack {
                PlayView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showingPractice = false }
                                .foregroundStyle(Design.Colors.bobaOrange)
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            if auth.confirmationEmailSent { confirmationBanner(text: "Check your email to confirm your account.") }
            else if passwordResetSent      { confirmationBanner(text: "Password reset email sent — check your inbox.") }
        }
        .task { await auth.loadProfile() }
        .onChange(of: auth.isAuthenticated) { _, isOn in
            if isOn { Task { await auth.loadProfile() } }
        }
    }

    // MARK: - Banner

    private func confirmationBanner(text: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "envelope.badge.fill")
                .foregroundStyle(Design.Colors.bobaCyan)
            Text(text)
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.surface.opacity(0.97))
        .overlay(Rectangle().frame(height: 1)
                    .foregroundStyle(Design.Colors.bobaCyan.opacity(0.4)),
                 alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Signed out

    private var signedOutView: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()
            Image(systemName: "person.circle")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Not signed in")
                .font(Design.Fonts.display(20))
                .foregroundStyle(Design.Colors.textPrimary)
            Text("Sign in to sync your collection\nand access it on any device.")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
            Button { showingSignIn = true } label: {
                Text("Sign In / Create Account")
                    .font(Design.Fonts.display(16))
                    .foregroundStyle(Design.Colors.nearBlack)
                    .frame(maxWidth: 280)
                    .frame(height: 50)
                    .background(Design.Colors.bobaOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signed in

    private var signedInView: some View {
        Form {
            headerSection
            accountSection
            connectionsSection
            sharingSection
            displaySection
            notificationsSection
            roleAccessSection
            if auth.isMod { moderationSection }
            aboutSection
            signOutSection
            deleteAccountSection
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: Design.Spacing.md) {
                AvatarView(
                    discordAvatarURL: discord.currentUser?.avatarURL ?? URL(string: auth.discordAvatarURL ?? ""),
                    fallbackInitial: initialFor(username: auth.username, email: auth.email),
                    accentColor: AppIconOption.currentColor(for: selectedIconName)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(usernameDisplay)
                        .font(Design.Fonts.display(18))
                        .foregroundStyle(Design.Colors.textPrimary)
                    if let email = auth.email {
                        Text(email)
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        roleBadge
                        if auth.isStreamer && !auth.isAdmin {
                            roleBadgePill("STREAMER", Design.Colors.bobaCyan)
                        }
                        if let pill = providerPill {
                            pill
                        }
                        // Admin-only Practice shortcut. Tapping the
                        // bolt opens PracticeView in a fullScreenCover
                        // — kept admin-only because the practice
                        // executor is gated pending the BoBA IP review
                        // (DECISIONS.md, #033).
                        if auth.isAdmin {
                            Button {
                                showingPractice = true
                            } label: {
                                Image(systemName: "bolt.square.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Design.Colors.bobaOrange)
                            }
                            .accessibilityLabel("Practice (admin only)")
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Design.Spacing.xs)
        }
    }

    @AppStorage("selectedIconName") private var selectedIconName: String = "default"

    private var usernameDisplay: String {
        if let u = auth.username, !u.isEmpty { return "@\(u)" }
        return "BOBA Player"
    }

    private func initialFor(username: String?, email: String?) -> String {
        let source = username ?? email?.split(separator: "@").first.map(String.init) ?? "B"
        return String(source.uppercased().prefix(1))
    }

    private var roleBadge: some View {
        Group {
            if auth.isAdmin     { roleBadgePill("ADMIN", Design.Colors.bobaOrange) }
            else if auth.isMod  { roleBadgePill("MOD",   Design.Colors.bobaCyan)   }
            else                { roleBadgePill("MEMBER", Design.Colors.textMuted) }
        }
    }

    private func roleBadgePill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Design.Fonts.mono(9, weight: .bold))
            .foregroundStyle(Design.Colors.nearBlack)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// Sign-in method indicator. Renders a small pill next to the
    /// role badge so the user knows which provider their session
    /// was created with — matters for "how do I disconnect Apple?"
    /// or "do I have a password I can change?" questions. Email
    /// users see no pill (it's the unmarked default).
    private var providerPill: AnyView? {
        switch auth.signInProvider {
        case "apple":
            return AnyView(HStack(spacing: 3) {
                Image(systemName: "applelogo").font(.system(size: 9))
                Text("APPLE").font(Design.Fonts.mono(9, weight: .bold))
            }
            .foregroundStyle(Design.Colors.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 3)))
        case "discord":
            return AnyView(HStack(spacing: 3) {
                Image("discord-logo")
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 9, height: 9)
                Text("DISCORD").font(Design.Fonts.mono(9, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: "5865F2"))
            .clipShape(RoundedRectangle(cornerRadius: 3)))
        default:
            // Email / unknown — no pill (the unmarked default
            // matches the historical UI; password reset is the
            // affordance for "this is an email account").
            return nil
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            UsernameRow()
            // Email is informational; we don't let users change it
            // here (Supabase email change is a multi-step flow with
            // confirm-from-old-and-new). Surface a future-feature
            // hint instead.
            HStack {
                Label("Email", systemImage: "envelope")
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                Text(auth.email ?? "—")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // Change password — fires Supabase recover email. Disabled
            // for OAuth-only accounts (no password to reset).
            Button {
                Task {
                    if await auth.requestPasswordReset() {
                        passwordResetSent = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            passwordResetSent = false
                        }
                    }
                }
            } label: {
                Label("Change Password", systemImage: "lock.rotation")
                    .foregroundStyle(Design.Colors.bobaCyan)
            }
        }
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        Section {
            HStack {
                Label {
                    Text("Discord")
                        .foregroundStyle(Design.Colors.textPrimary)
                } icon: {
                    Image("discord-logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color(hex: "5865F2"))  // Discord brand blurple
                }
                Spacer()
                if discord.isAuthorized, let user = discord.currentUser {
                    Text(user.displayName)
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(1)
                }
                Button(discordWorking ? "Working…"
                       : (discord.isAuthorized ? "Disconnect" : "Connect")) {
                    Task { await toggleDiscord() }
                }
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(discord.isAuthorized ? Color.red : Design.Colors.bobaCyan)
                .disabled(discordWorking)
            }
        } header: {
            Text("Connections")
        } footer: {
            Text("Connect Discord to chat in the trade room and to use your Discord avatar across the app.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .task { await refreshDiscordSnapshot() }
    }

    private func refreshDiscordSnapshot() async {
        guard discord.isAuthorized, discord.currentUser == nil else { return }
        await discord.fetchCurrentUser()
    }

    private func toggleDiscord() async {
        discordWorking = true
        defer { discordWorking = false }
        if discord.isAuthorized {
            discord.disconnect()
            await auth.setDiscordIdentity(discordId: nil, avatarUrl: nil)
        } else {
            await discord.authorize()
            if discord.isAuthorized {
                await discord.fetchCurrentUser()
                if let u = discord.currentUser {
                    await auth.setDiscordIdentity(
                        discordId: u.id, avatarUrl: u.avatarURL?.absoluteString)
                }
            }
        }
    }

    // MARK: - Collection sharing

    private var sharingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { auth.publicCollectionEnabled },
                set: { newValue in Task { await auth.setPublicCollectionEnabled(newValue) } }
            )) {
                Label("Public Collection", systemImage: "globe")
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .tint(Design.Colors.bobaOrange)

            if auth.publicCollectionEnabled {
                if let url = publicCollectionURL {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "link")
                            .foregroundStyle(Design.Colors.textMuted)
                        Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        // .buttonStyle(.borderless) is required inside
                        // a Form row that has multiple buttons —
                        // without it iOS routes every tap to the row
                        // itself, so this button looked dead. Setting
                        // BOTH UIPasteboard.string and .url so apps
                        // that only read .string (e.g., browser
                        // address bars) get the URL too.
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            UIPasteboard.general.url = url
                            copyConfirmed = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.5))
                                copyConfirmed = false
                            }
                        } label: {
                            Image(systemName: copyConfirmed ? "checkmark.circle.fill" : "doc.on.doc")
                                .foregroundStyle(copyConfirmed ? Color(hex: "4CAF50") : Design.Colors.bobaCyan)
                                .symbolEffect(.bounce, value: copyConfirmed)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy link")
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Design.Colors.bobaCyan)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Share link")
                    }
                } else {
                    Text("Pick a username above to enable your public link.")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }
        } header: {
            Text("Collection Sharing")
        } footer: {
            Text("Share a public link to your collection at bobaplaybook.com/u/{username}. Anyone with the link can view it; designations marked private are still hidden.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }

    private var publicCollectionURL: URL? {
        guard let u = auth.username, !u.isEmpty else { return nil }
        return URL(string: "https://bobaplaybook.com/u/\(u)")
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            // App icon — native Menu picker, no fake-push (§3.7)
            HStack {
                Label("App Icon", systemImage: "app.badge")
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                Menu {
                    ForEach(AppIconOption.all) { option in
                        Button {
                            applyIcon(option)
                        } label: {
                            HStack {
                                Image(option.previewAssetName)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(option.label)
                                if selectedIconName == option.iconName {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentIcon.label)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                }
            }

            ColumnsPickerRow(label: "Find — columns",       systemImage: "magnifyingglass",
                             storageKey: "bp_findGridColumns_v1",       defaultValue: 2)
            ColumnsPickerRow(label: "Decks — columns",      systemImage: "rectangle.stack",
                             storageKey: "bp_decksGridColumns_v1",      defaultValue: 3)
            ColumnsPickerRow(label: "Collection — columns", systemImage: "person.crop.rectangle.stack",
                             storageKey: "bp_collectionGridColumns_v1", defaultValue: 3)

            CollectionDisplayModeRow()

            Button {
                WalkthroughsManager.shared.resetAll()
            } label: {
                Label("Reset Feature Walkthroughs", systemImage: "arrow.clockwise")
                    .foregroundStyle(Design.Colors.bobaOrange)
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Walkthroughs fire on first visit to each tab and feature. Reset replays them all.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }

    private var currentIcon: AppIconOption {
        AppIconOption.all.first(where: { $0.iconName == selectedIconName }) ?? AppIconOption.all[0]
    }

    private func applyIcon(_ option: AppIconOption) {
        let name: String? = option.iconName == "default" ? nil : option.iconName
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil { selectedIconName = option.iconName }
        }
    }

    // MARK: - Notifications (deferred backend — UI ships now)

    private var notificationsSection: some View {
        Section {
            DisclosureGroup {
                Toggle(isOn: Binding(
                    get: { auth.notificationsEnabled },
                    set: { newValue in
                        Task { await auth.setNotificationPrefs(
                            notifications: newValue, matchAlerts: auth.matchAlertsEnabled) }
                    }
                )) {
                    Label("Push notifications", systemImage: "bell")
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .tint(Design.Colors.bobaCyan)

                Toggle(isOn: Binding(
                    get: { auth.matchAlertsEnabled },
                    set: { newValue in
                        Task { await auth.setNotificationPrefs(
                            notifications: auth.notificationsEnabled, matchAlerts: newValue) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Trade match alerts", systemImage: "arrow.left.arrow.right.circle")
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text("Coming soon")
                            .font(Design.Fonts.mono(10, weight: .bold))
                            .foregroundStyle(Design.Colors.bobaOrange)
                    }
                }
                .tint(Design.Colors.bobaCyan)
            } label: {
                Label("Notifications", systemImage: "bell.badge")
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        } footer: {
            Text("Trade match alerts notify you when someone has your Wanted/Grail in their collection (or vice versa). The matching pipeline is in development — toggle now to opt in early.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }

    // MARK: - Role & Access

    private var roleAccessSection: some View {
        Section {
            DisclosureGroup {
                if auth.canRequestStreamer {
                    Button {
                        roleRequestForRole = "streamer"
                    } label: {
                        Label("Request Streamer Access", systemImage: "video.bubble")
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                }
                if auth.canRequestMod {
                    Button {
                        roleRequestForRole = "moderator"
                    } label: {
                        Label("Request Moderator Access", systemImage: "shield.lefthalf.filled.badge.checkmark")
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                }
                if let pending = auth.pendingRoleRequest {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(Design.Colors.bobaCyan)
                        Text("\(pending.capitalized) request pending")
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                }
                if !auth.canRequestStreamer && !auth.canRequestMod && auth.pendingRoleRequest == nil {
                    Text("You already have the highest role.")
                        .font(Design.Fonts.mono(12))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            } label: {
                Label("Role & Access", systemImage: "person.badge.shield.checkmark")
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        } footer: {
            Text("Streamers get the Whatnot Shows feature for prepping live broadcasts. Moderators help improve the catalog: upload card images, fix wrong card data, and flag issues.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }

    // MARK: - Moderation (mod / admin only)

    private var moderationSection: some View {
        Section("Moderation") {
            NavigationLink {
                ModPanelView()
            } label: {
                Label("Mod Panel", systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(Design.Colors.bobaCyan)
            }
            if auth.isAdmin {
                NavigationLink {
                    AdminPanelView()
                } label: {
                    Label("Admin Panel", systemImage: "person.badge.key.fill")
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            DisclosureGroup {
                Button { showingPrivacy = true } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                Button { showingTerms = true } label: {
                    Label("Terms of Service", systemImage: "doc.text")
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                Button {
                    if let url = feedbackMailto { UIApplication.shared.open(url) }
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                        .foregroundStyle(Design.Colors.bobaCyan)
                }
                HStack {
                    Label("Version", systemImage: "number")
                        .foregroundStyle(Design.Colors.textPrimary)
                    Spacer()
                    Text(versionLine)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            } label: {
                Label("About", systemImage: "info.circle")
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        }
    }

    private var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    private var feedbackMailto: URL? {
        let subject = "BOBA Playbook feedback (v\(versionLine))"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:ben@learningischange.com?subject=\(subject)")
    }

    // MARK: - Sign out + delete

    private var signOutSection: some View {
        Section {
            Button {
                showingSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.red)
            }
            .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirm,
                                titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your collection data is saved in the cloud and will sync back when you sign in again.")
            }
        }
    }

    private var deleteAccountSection: some View {
        Section {
            Button {
                showingDeleteConfirm = true
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .confirmationDialog("Delete your account?",
                                isPresented: $showingDeleteConfirm,
                                titleVisibility: .visible) {
                // Wired to a coming-soon path; the destructive
                // confirmation surface ships now so the App Store
                // 5.1.1(v) requirement is met from the user's POV.
                Button("Delete Account", role: .destructive) {
                    // TODO: call Worker /account/delete (deferred,
                    // see DECISIONS.md). For now, sign-out so the
                    // user has a path forward and message them.
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Account deletion is processed within 30 days. Your collection, decks, and shared links will be permanently removed. This cannot be undone.")
            }
        } footer: {
            Text("Email ben@learningischange.com for immediate deletion.")
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textMuted)
        }
    }
}

// MARK: - Avatar

private struct AvatarView: View {
    let discordAvatarURL: URL?
    let fallbackInitial: String
    let accentColor: Color

    var body: some View {
        Group {
            if let url = discordAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: initialView
                    }
                }
            } else {
                initialView
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(accentColor.opacity(0.6), lineWidth: 2)
        )
    }

    private var initialView: some View {
        Text(fallbackInitial)
            .font(Design.Fonts.display(24))
            .foregroundStyle(Design.Colors.nearBlack)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(accentColor)
    }
}

// MARK: - UsernameRow (inline edit + debounced validation)

private struct UsernameRow: View {
    @Environment(AuthManager.self) private var auth
    @State private var draft: String = ""
    @State private var status: ValidationStatus = .idle
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    enum ValidationStatus: Equatable {
        case idle, checking, available, mine
        case taken, banned, reserved, invalidChars, tooShort, tooLong, networkError

        var color: Color {
            switch self {
            case .available, .mine: return Color(hex: "4CAF50")
            case .checking, .idle:  return Design.Colors.textMuted
            default:                return Color.red
            }
        }
        var icon: String {
            switch self {
            case .available, .mine: return "checkmark.circle.fill"
            case .checking:          return "arrow.triangle.2.circlepath"
            case .idle:              return ""
            default:                 return "xmark.circle.fill"
            }
        }
        var message: String {
            switch self {
            case .idle:         return ""
            case .checking:     return "Checking…"
            case .available:    return "Available"
            case .mine:         return "Your username"
            case .taken:        return "Already taken"
            case .banned:       return "Not allowed"
            case .reserved:     return "Reserved word"
            case .invalidChars: return "Letters, numbers, _ - only"
            case .tooShort:     return "At least 2 characters"
            case .tooLong:      return "30 characters max"
            case .networkError: return "Check failed — try again"
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "at")
                .foregroundStyle(Design.Colors.bobaCyan)
                .frame(width: 28)
            TextField("username", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { Task { await commit() } }
                .onChange(of: draft) { _, newValue in
                    let normalized = newValue.lowercased()
                    if normalized != newValue { draft = normalized; return }
                    scheduleCheck()
                }
            Spacer(minLength: 4)
            statusPill
        }
        .onAppear {
            draft = auth.username ?? ""
            status = (auth.username == nil) ? .idle : .mine
            // Auto-derive a username for first-time profile opens.
            if auth.username == nil {
                Task { await deriveAndSet() }
            }
        }
        .onChange(of: auth.username ?? "") { _, newValue in
            if newValue != draft && !focused {
                draft = newValue
                status = .mine
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            if !status.icon.isEmpty {
                Image(systemName: status.icon)
                    .font(.system(size: 11, weight: .bold))
            }
            if !status.message.isEmpty {
                Text(status.message)
                    .font(Design.Fonts.mono(10, weight: .bold))
            }
        }
        .foregroundStyle(status.color)
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        let candidate = draft
        if candidate == (auth.username ?? "") {
            status = candidate.isEmpty ? .idle : .mine
            return
        }
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            status = .checking
            let result = await auth.checkUsername(candidate)
            if Task.isCancelled { return }
            status = mapStatus(result)
            // If validation passed, commit on the next idle moment.
            if status == .available {
                let writeResult = await auth.setUsername(candidate)
                status = mapStatus(writeResult)
                if writeResult == "available" { status = .mine }
            }
        }
    }

    private func commit() async {
        let candidate = draft
        guard candidate != (auth.username ?? "") else { return }
        status = .checking
        let result = await auth.setUsername(candidate)
        status = (result == "available") ? .mine : mapStatus(result)
        focused = false
    }

    private func mapStatus(_ raw: String) -> ValidationStatus {
        switch raw {
        case "available":     return .available
        case "taken":         return .taken
        case "banned":        return .banned
        case "reserved":      return .reserved
        case "invalid_chars": return .invalidChars
        case "too_short":     return .tooShort
        case "too_long":      return .tooLong
        default:              return .networkError
        }
    }

    /// First-time auto-derivation: try the email local-part (or
    /// Discord username), append numeric suffix on collision until we
    /// find an available handle. Runs once per profile-open while
    /// username is still nil. Falls back to user-{6-char-hash} when
    /// derivation can't escape banned/reserved/invalid territory.
    private func deriveAndSet() async {
        let seed = deriveSeed()
        guard !seed.isEmpty else { return }
        // Try seed, then seed2, seed3, … up to seed99.
        for suffix in [""] + (2...99).map(String.init) {
            let candidate = String((seed + suffix).prefix(30))
            let result = await auth.checkUsername(candidate)
            if result == "available" {
                let writeResult = await auth.setUsername(candidate)
                if writeResult == "available" {
                    draft = candidate
                    status = .mine
                    return
                }
            }
            if result == "invalid_chars" || result == "too_short" {
                break  // seed isn't recoverable by suffix
            }
        }
        // Last-ditch: user-{6-char hash from user_id}
        if let uid = auth.userId {
            let hash = String(uid.uuidString.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            let fallback = "user-\(hash)"
            let writeResult = await auth.setUsername(fallback)
            if writeResult == "available" {
                draft = fallback
                status = .mine
            }
        }
    }

    private func deriveSeed() -> String {
        if let email = auth.email,
           let local = email.split(separator: "@").first {
            let cleaned = local.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            if cleaned.count >= 2 { return cleaned }
        }
        return ""
    }
}

// MARK: - ColumnsPickerRow (Display section)

private struct ColumnsPickerRow: View {
    let label: String
    let systemImage: String
    let storageKey: String
    let defaultValue: Int
    @AppStorage private var value: Int

    init(label: String, systemImage: String, storageKey: String, defaultValue: Int) {
        self.label = label
        self.systemImage = systemImage
        self.storageKey = storageKey
        self.defaultValue = defaultValue
        _value = AppStorage(wrappedValue: defaultValue, storageKey)
    }

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Picker("", selection: $value) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }
}

// MARK: - CollectionDisplayModeRow

private struct CollectionDisplayModeRow: View {
    // Wall is intentionally absent — it's a sharing affordance
    // (renders cards as a single image), NOT a persistent display
    // mode. The Collection tab's Wall is invoked from the toolbar,
    // not selected here.
    @AppStorage("bp_collectionDisplayMode_v2") private var raw: String = "list"

    var body: some View {
        HStack {
            Label("Collection — default", systemImage: "rectangle.3.group")
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Picker("", selection: $raw) {
                Text("List").tag("list")
                Text("Grid").tag("grid")
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }
}

// MARK: - RoleRequestSheet

private struct RoleRequestTarget: Identifiable {
    let role: String
    var id: String { role }
}

private struct RoleRequestSheet: View {
    let role: String  // "moderator" or "streamer"
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(blurb)
                        .font(Design.Fonts.mono(13))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                Section("Why are you requesting this?") {
                    TextField("A short note for the admins…",
                              text: $reason, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if working {
                            HStack {
                                ProgressView().tint(Design.Colors.nearBlack)
                                Text("Submitting…")
                            }
                        } else {
                            Text("Submit request")
                                .font(Design.Fonts.display(15))
                                .foregroundStyle(Design.Colors.nearBlack)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    .listRowBackground(reason.trimmingCharacters(in: .whitespaces).isEmpty
                                       ? Design.Colors.textMuted
                                       : Design.Colors.bobaOrange)
                }
            }
            .navigationTitle("Request \(role.capitalized) Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var blurb: String {
        switch role {
        case "streamer":
            return "Streamers get the Whatnot Shows feature: pre-curate cards for live breaks, run a giveaway tally, and generate a wall image of your shop's hits."
        case "moderator":
            return "Moderators help improve the catalog: upload card images from your collection, fix wrong card data, and flag image issues. Approvals are reviewed by an admin."
        default:
            return ""
        }
    }

    private func submit() async {
        working = true
        await auth.requestRole(role, reason: reason)
        working = false
        dismiss()
    }
}

// MARK: - Safari sheet wrapper

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // iOS 26 deprecated preferredBarTintColor / preferredControlTintColor
        // ("Tinting the bars interferes with background effects that the
        // system provides"). Let SFSafariViewController use its own
        // adaptive Liquid Glass treatment.
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
