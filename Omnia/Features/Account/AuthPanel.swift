import SwiftUI

/// The sign-in panel in a sheet, from Settings › Account or the signed-out alert.
struct AccountSignInSheet: View {
    @Environment(OmniaAccount.self) private var account
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                AuthPanel(onSignedIn: onClose)
                    .padding(OmniaDevice.isPhone ? 20 : 36)
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        account.cancelCode()
                        onClose()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
    }
}

/// Nuvio's sign in and sign up, in Omnia's style: email and password,
/// a code by email instead of a password, Google or Apple, and
/// the code that confirms a new account. Used by onboarding and by
/// Settings › Account.
struct AuthPanel: View {
    enum Mode: Equatable {
        case signIn
        case signUp
        case code
        case forgotPassword
    }

    @Environment(OmniaAccount.self) private var account
    @State private var mode: Mode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var newPassword = ""
    @FocusState private var focusedField: Field?
    /// Shown under the buttons, e.g. "Continue without an account".
    var skipTitle: String?
    var onSkip: (() -> Void)?
    var onSignedIn: () -> Void = {}

    private enum Field: Hashable { case name, email, password, code, newPassword }

    init(
        mode: Mode = .signIn,
        skipTitle: String? = nil,
        onSkip: (() -> Void)? = nil,
        onSignedIn: @escaping () -> Void = {}
    ) {
        _mode = State(initialValue: mode)
        self.skipTitle = skipTitle
        self.onSkip = onSkip
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        VStack(spacing: 22) {
            if let pending = account.pendingCode {
                codeEntry(pending)
            } else {
                form
            }
            if let errorMessage = account.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            if !account.isConfigured {
                Text("Accounts are unavailable in this build of Omnia.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 380)
        .animation(.smooth(duration: 0.25), value: mode)
        .animation(.smooth(duration: 0.25), value: account.pendingCode)
        .onChange(of: account.user?.id) { _, id in
            if id != nil { onSignedIn() }
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.title.weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 6)

            if mode == .signUp {
                field("Name", text: $name, symbol: "person", field: .name)
            }
            field("Email", text: $email, symbol: "envelope", field: .email)
                .textContentType(.username)
            if mode == .signIn || mode == .signUp {
                secureField(
                    mode == .signUp ? "Password (8 or more characters)" : "Password",
                    text: $password,
                    field: .password
                )
                .textContentType(mode == .signUp ? .newPassword : .password)
            }
            if mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") { switchMode(.forgotPassword) }
                        .omniaLinkButtonStyle()
                        .font(.callout)
                }
            }

            primaryButton(primaryTitle, isEnabled: canSubmit, action: submit)

            if mode == .signIn || mode == .signUp {
                divider
                VStack(spacing: 10) {
                    providerButton("Continue with Google", image: Image("GoogleMark")) {
                        Task { await account.signIn(using: .google) }
                    }
                    providerButton("Continue with Apple", image: Image(systemName: "apple.logo")) {
                        Task { await account.signIn(using: .apple) }
                    }
                    providerButton("Sign In with a Code", image: Image(systemName: "number")) {
                        switchMode(.code)
                    }
                }
            }

            footerLinks
        }
        .onSubmit(submit)
        .disabled(account.isWorking || !account.isConfigured)
    }

    private var title: String {
        switch mode {
        case .signIn: "Welcome Back"
        case .signUp: "Create Your Account"
        case .code: "Sign In with a Code"
        case .forgotPassword: "Reset Your Password"
        }
    }

    private var subtitle: String {
        switch mode {
        case .signIn: "Sign in to bring your profiles, library and progress with you."
        case .signUp: "Sign up to keep your profiles and library in sync across devices."
        case .code: "We'll email you a code. No password needed."
        case .forgotPassword: "We'll email you a code to choose a new password."
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .signIn: "Sign In"
        case .signUp: "Create Account"
        case .code, .forgotPassword: "Email Me a Code"
        }
    }

    private var isEmailValid: Bool {
        let value = email.trimmingCharacters(in: .whitespaces)
        return value.count <= 254 && value.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        switch mode {
        case .signIn: isEmailValid && !password.isEmpty
        case .signUp: isEmailValid && password.count >= 8
        case .code, .forgotPassword: isEmailValid
        }
    }

    private func submit() {
        guard canSubmit, !account.isWorking else { return }
        Task {
            switch mode {
            case .signIn: _ = await account.signIn(email: email, password: password)
            case .signUp: _ = await account.signUp(email: email, password: password, name: name)
            case .code: _ = await account.sendSignInCode(to: email)
            case .forgotPassword: _ = await account.sendPasswordReset(to: email)
            }
            if account.pendingCode != nil { focusedField = .code }
        }
    }

    private func switchMode(_ newMode: Mode) {
        account.errorMessage = nil
        password = ""
        mode = newMode
    }

    @ViewBuilder
    private var footerLinks: some View {
        VStack(spacing: 8) {
            switch mode {
            case .signIn:
                linkRow("Don't have an account?", action: "Sign Up") { switchMode(.signUp) }
            case .signUp:
                linkRow("Already have an account?", action: "Sign In") { switchMode(.signIn) }
            case .code, .forgotPassword:
                linkRow("Remember your password?", action: "Sign In") { switchMode(.signIn) }
            }
            if let skipTitle, let onSkip {
                Button(skipTitle, action: onSkip)
                    .omniaLinkButtonStyle()
                    .font(.callout)
                    .padding(.top, 4)
                Text("Your profiles and library stay on this \(OmniaDevice.name). You can sign in later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Code

    private func codeEntry(_ pending: OmniaAccount.PendingCode) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(OmniaBrandColors.gradient)
            VStack(spacing: 6) {
                Text(pending.purpose == .confirmSignUp ? "Confirm Your Email" : "Check Your Email")
                    .font(.title.weight(.bold))
                Text("Enter the code we sent to \(pending.email).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("000000", text: $code)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.plain)
                .padding(.vertical, 12)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused($focusedField, equals: .code)
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(Self.codeLengths.upperBound))
                    if digits != value { code = digits }
                }
                .accessibilityLabel("Email code")
            if pending.purpose == .resetPassword {
                secureField("New password (8 or more characters)", text: $newPassword, field: .newPassword)
                    .textContentType(.newPassword)
            }
            primaryButton(
                pending.purpose == .resetPassword ? "Set New Password" : "Continue",
                isEnabled: Self.codeLengths.contains(code.count) && (pending.purpose != .resetPassword || newPassword.count >= 8),
                action: verifyCode
            )
            HStack(spacing: 16) {
                Button("Send a New Code") { Task { _ = await account.resendCode() } }
                Button("Use a Different Email") {
                    code = ""
                    account.cancelCode()
                }
            }
            .omniaLinkButtonStyle()
            .font(.callout)
            Text("The email also has a button that signs you in, if that's easier.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onSubmit(verifyCode)
        .disabled(account.isWorking)
        .onAppear { focusedField = .code }
    }

    /// Supabase's Email OTP Length setting allows 6 to 10 digits.
    private static let codeLengths = 6...10

    private func verifyCode() {
        guard let pending = account.pendingCode, Self.codeLengths.contains(code.count), !account.isWorking else { return }
        let resets = pending.purpose == .resetPassword
        guard !resets || newPassword.count >= 8 else { return }
        Task {
            if await account.verify(code: code, newPassword: resets ? newPassword : nil) {
                code = ""
                newPassword = ""
            }
        }
    }

    // MARK: Pieces

    private func field(_ title: String, text: Binding<String>, symbol: String, field: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .autocorrectionDisabled()
        }
        .modifier(AuthFieldBackground())
    }

    private func secureField(_ title: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            SecureField(title, text: text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
        }
        .modifier(AuthFieldBackground())
    }

    private func primaryButton(_ title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(account.isWorking ? 0 : 1)
                if account.isWorking { ProgressView().controlSize(.small) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.glassProminent)
        .tint(OmniaBrandColors.violet)
        .controlSize(.large)
        .disabled(!isEnabled)
    }

    private func providerButton(_ title: String, image: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text("or").font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(.separator).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func linkRow(_ prompt: String, action title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(prompt).foregroundStyle(.secondary)
            Button(title, action: action).omniaLinkButtonStyle()
        }
        .font(.callout)
    }
}

private struct AuthFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
    }
}
