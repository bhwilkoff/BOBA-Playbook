import SwiftUI
import AuthenticationServices

// MARK: - SignInView
// Sign in with Apple (primary) or email/password (fallback).
// Presented as a sheet when unauthenticated user taps a protected action.

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordVisible = false
    @State private var confirmPasswordVisible = false
    @FocusState private var emailFocused: Bool

    enum Mode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.xl) {
                    header
                    appleButton
                    googleButton
                    discordButton
                    divider
                    emailForm
                    if let err = auth.error {
                        Text(err)
                            .font(Design.Fonts.mono(13))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Design.Spacing.xl)
                    }
                }
                .padding(.horizontal, Design.Spacing.xl)
                .padding(.top, Design.Spacing.xxl)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.bobaOrange)
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onChange(of: auth.isAuthenticated) { _, authenticated in
            if authenticated { dismiss() }
        }
        .onChange(of: auth.confirmationEmailSent) { _, sent in
            if sent { dismiss() }
        }
        .onDisappear { auth.clearError() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: Design.Spacing.sm) {
            BOBAWordmark()
                .font(Design.Fonts.arena(32))
            Text(mode == .signIn ? "Sign in to track your collection" : "Create your account")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(
            mode == .signIn ? .signIn : .signUp,
            onRequest: { request in
                request.requestedScopes = [.email, .fullName]
            },
            onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let idToken = String(data: tokenData, encoding: .utf8)
                    else { return }
                    Task {
                        await auth.signInWithApple(idToken: idToken)
                    }
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.code != ASAuthorizationError.canceled.rawValue {
                        // auth.error is set via the manager on non-cancel errors
                    }
                }
            }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .cornerRadius(Design.Radius.md)
    }

    private var discordButton: some View {
        Button {
            Task { await auth.signInWithDiscord() }
        } label: {
            HStack(spacing: 10) {
                DiscordIconView()
                    .frame(width: 20, height: 20)
                Text(mode == .signIn ? "Sign in with Discord" : "Sign up with Discord")
                    .font(Design.Fonts.mono(15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(red: 0.345, green: 0.396, blue: 0.949)) // #5865F2
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
        .disabled(auth.isLoading)
    }

    // Tick 492 — Sign in with Google (web tick 483 + Android Credential
    // Manager parity). Apple stays primary on iOS per DECISIONS.md #050;
    // Google sits as a third option between Apple and Discord for users
    // who'd rather use their Google account.
    private var googleButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                GoogleGlyphView()
                    .frame(width: 18, height: 18)
                Text(mode == .signIn ? "Sign in with Google" : "Sign up with Google")
                    .font(Design.Fonts.mono(15, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            )
        }
        .disabled(auth.isLoading)
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(Design.Colors.glassBorder).frame(height: 1)
            Text("or")
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .padding(.horizontal, Design.Spacing.sm)
            Rectangle().fill(Design.Colors.glassBorder).frame(height: 1)
        }
    }

    private var emailForm: some View {
        VStack(spacing: Design.Spacing.md) {
            // Mode toggle
            HStack(spacing: 0) {
                modeTab("Sign In", selected: mode == .signIn) { mode = .signIn }
                modeTab("Create Account", selected: mode == .signUp) { mode = .signUp }
            }
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))

            // Email field
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text("EMAIL")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                TextField("you@example.com", text: $email)
                    .font(Design.Fonts.mono(15))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($emailFocused)
                    .submitLabel(.next)
                    .padding(Design.Spacing.md)
                    .background(inputBackground)
            }

            // Password field — Android tick 446 parity: eye-toggle for
            // visibility. SecureInputField re-asserts isSecureTextEntry on
            // updateUIView so the toggle survives without losing focus.
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text("PASSWORD")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                HStack(spacing: Design.Spacing.sm) {
                    SecureInputField(
                        placeholder: "••••••••",
                        text: $password,
                        textContentType: mode == .signIn ? .password : .newPassword,
                        submitLabel: mode == .signIn ? .go : .next,
                        onSubmit: {
                            if mode == .signIn { submitSignIn() }
                            // .next: iOS keyboard will advance to confirmPassword automatically
                            // via textContentType chaining; no manual focus needed
                        },
                        isSecure: !passwordVisible
                    )
                    .frame(height: 44)
                    Button { passwordVisible.toggle() } label: {
                        Image(systemName: passwordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(Design.Colors.textMuted)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(passwordVisible ? "Hide password" : "Show password")
                    .help(passwordVisible ? "Hide password" : "Show password")
                }
                .padding(Design.Spacing.md)
                .background(inputBackground)
            }

            // Confirm password (sign up only)
            if mode == .signUp {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("CONFIRM PASSWORD")
                        .font(Design.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Design.Colors.textMuted)
                        .tracking(1.5)
                    HStack(spacing: Design.Spacing.sm) {
                        SecureInputField(
                            placeholder: "••••••••",
                            text: $confirmPassword,
                            textContentType: .newPassword,
                            submitLabel: .go,
                            onSubmit: { submitSignUp() },
                            isSecure: !confirmPasswordVisible
                        )
                        .frame(height: 44)
                        Button { confirmPasswordVisible.toggle() } label: {
                            Image(systemName: confirmPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(Design.Colors.textMuted)
                                .frame(width: 24, height: 24)
                        }
                        .accessibilityLabel(confirmPasswordVisible ? "Hide password" : "Show password")
                        .help(confirmPasswordVisible ? "Hide password" : "Show password")
                    }
                    .padding(Design.Spacing.md)
                    .background(inputBackground)
                }
            }

            // Submit button
            Button(action: mode == .signIn ? submitSignIn : submitSignUp) {
                ZStack {
                    if auth.isLoading {
                        ProgressView().tint(Design.Colors.nearBlack)
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(Design.Fonts.display(16))
                    }
                }
                .foregroundStyle(Design.Colors.nearBlack)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Design.Colors.bobaOrange)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
            }
            .disabled(auth.isLoading || email.isEmpty || password.isEmpty)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.sm)
            .fill(Design.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.sm)
                    .strokeBorder(Design.Colors.glassBorder, lineWidth: 1)
            )
    }

    private func modeTab(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Design.Fonts.mono(13, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Design.Colors.nearBlack : Design.Colors.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(selected ? Design.Colors.bobaOrange : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
                .padding(2)
        }
    }

    // MARK: - Actions

    private func submitSignIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await auth.signIn(email: email, password: password) }
    }

    private func submitSignUp() {
        guard !email.isEmpty, !password.isEmpty else { return }
        guard password == confirmPassword else {
            // Surface mismatch inline — we'd normally use a proper validation state,
            // but keeping it simple for M2.
            return
        }
        Task { await auth.signUp(email: email, password: password) }
    }
}

// MARK: - Discord icon (rendered from Assets.xcassets/discord-logo.imageset)
// SVG asset with template rendering — tinted white by .foregroundStyle on the parent HStack.

private struct DiscordIconView: View {
    var body: some View {
        Image("discord-logo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
    }
}

// MARK: - Google glyph (tick 492)
// Recognizable "G" in Google brand blue — not the full 4-color brand
// glyph (that needs a custom Asset / SVG that doesn't ship today), but
// enough to disambiguate from Apple + Discord at a glance. Future tick:
// add a multi-color glyph via Assets.xcassets/google-logo.imageset.

private struct GoogleGlyphView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.259, green: 0.522, blue: 0.957)) // #4285F4
            Text("G")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
