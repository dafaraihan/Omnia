//
//  OmniaAccount.swift
//  Omnia
//

import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class OmniaAccount {
    struct User: Identifiable, Sendable {
        let id: UUID
        let email: String?
        let provider: String?
    }

    enum Provider: String, CaseIterable, Identifiable, Sendable {
        case apple
        case google
        case facebook

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .apple: "apple.logo"
            case .google: "g.circle.fill"
            case .facebook: "f.cursive.circle.fill"
            }
        }
    }

    nonisolated static let redirectURL = URL(string: "omnia://auth-callback")!

    private let client: SupabaseClient?
    private var appleAuthorization: AppleAuthorization?

    @ObservationIgnored var didRecoverIdentity: (() async -> Void)?
    @ObservationIgnored var willChangeIdentity: ((UUID?) throws -> Void)?

    @ObservationIgnored var willSignOut: (() async throws -> Void)?
    @ObservationIgnored var didSignOut: (() async throws -> Void)?
    private(set) var sessionGeneration = UUID()
    private(set) var localResetPending = UserDefaults.standard.bool(forKey: "sign-out-local-reset-pending")
    private(set) var isResettingLocalData = false
    private(set) var isSigningOut = false

    private(set) var user: User?
    var isWorking = false
    var errorMessage: String?
    /// After sign up, or after asking for a sign-in code: the address the
    /// email code was sent to, and what the code is for.
    var pendingCode: PendingCode?

    struct PendingCode: Equatable, Sendable {
        enum Purpose: Sendable { case confirmSignUp, signIn, resetPassword }
        let email: String
        let purpose: Purpose
    }

    var isConfigured: Bool { client != nil }

    init(configuration: SupabaseConfiguration? = .load()) {
        guard let configuration else {
            client = nil
            return
        }

        client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey,
            options: .init(
                auth: .init(
                    redirectToURL: Self.redirectURL,
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        observeSessionEnd()
    }

    /// The SDK drops the session by itself when the server says it's gone, for
    /// example revoked or its account deleted. Without this the app only finds
    /// out at the next launch, and keeps calling a dead session until then.
    private func observeSessionEnd() {
        guard let client else { return }
        Task { [weak self] in
            for await (event, _) in client.auth.authStateChanges where event == .signedOut {
                self?.sessionDidEnd()
            }
        }
    }

    private func sessionDidEnd() {
        guard user != nil, !isSigningOut, !localResetPending else { return }
        try? willChangeIdentity?(nil)
        user = nil
    }

    func restoreSession() async {
        guard let client else { return }
        if let session = client.auth.currentSession {
            do { try apply(session) }
            catch { errorMessage = "Saved credentials could not be opened securely. Retry after unlocking Keychain." }
        }
    }

    func signIn(using provider: Provider) async {
        guard let client else {
            errorMessage = "Omnia’s cloud configuration is unavailable."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            switch provider {
            case .apple:
                let nonce = Self.makeNonce()
                let authorization = AppleAuthorization()
                appleAuthorization = authorization
                let credential = try await authorization.request(nonce: Self.sha256(nonce))
                guard
                    let tokenData = credential.identityToken,
                    let identityToken = String(data: tokenData, encoding: .utf8)
                else {
                    throw AccountError.appleIdentityTokenUnavailable
                }
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: identityToken, nonce: nonce)
                )
                try apply(session)

            case .google:
                let session = try await client.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: Self.redirectURL
                )
                try apply(session)

            case .facebook:
                let session = try await client.auth.signInWithOAuth(
                    provider: .facebook,
                    redirectTo: Self.redirectURL
                )
                try apply(session)
            }
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Email and code sign-in

    /// Creates an account. Supabase emails a email code (and a link) to
    /// confirm the address; until then there is no session.
    func signUp(email: String, password: String, name: String) async -> Bool {
        await perform { client in
            let email = Self.cleanEmail(email)
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: name.isEmpty ? nil : ["display_name": .string(name)],
                redirectTo: Self.redirectURL
            )
            if let session = response.session {
                try self.apply(session)
            } else {
                self.pendingCode = PendingCode(email: email, purpose: .confirmSignUp)
            }
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform { client in
            let email = Self.cleanEmail(email)
            do {
                try self.apply(try await client.auth.signIn(email: email, password: password))
            } catch let error as AuthError where error.errorCode == .emailNotConfirmed {
                // Finish the sign up that was never confirmed.
                try await client.auth.resend(email: email, type: .signup, emailRedirectTo: Self.redirectURL)
                self.pendingCode = PendingCode(email: email, purpose: .confirmSignUp)
            }
        }
    }

    /// Sign in with a code: emails a email code, no password needed.
    /// New addresses get an account, as with Nuvio's link sign-in.
    func sendSignInCode(to email: String) async -> Bool {
        await perform { client in
            let email = Self.cleanEmail(email)
            try await client.auth.signInWithOTP(email: email, redirectTo: Self.redirectURL, shouldCreateUser: true)
            self.pendingCode = PendingCode(email: email, purpose: .signIn)
        }
    }

    func sendPasswordReset(to email: String) async -> Bool {
        await perform { client in
            let email = Self.cleanEmail(email)
            try await client.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
            self.pendingCode = PendingCode(email: email, purpose: .resetPassword)
        }
    }

    /// Checks the code from the email. A reset also sets the new password.
    func verify(code: String, newPassword: String? = nil) async -> Bool {
        guard let pendingCode else { return false }
        return await perform { client in
            let token = code.filter(\.isNumber)
            let type: EmailOTPType = switch pendingCode.purpose {
            case .confirmSignUp: .signup
            case .signIn: .email
            case .resetPassword: .recovery
            }
            let response = try await client.auth.verifyOTP(email: pendingCode.email, token: token, type: type)
            if let newPassword, pendingCode.purpose == .resetPassword {
                try await client.auth.update(user: UserAttributes(password: newPassword))
            }
            if let session = response.session {
                try self.apply(session)
            }
            self.pendingCode = nil
        }
    }

    func resendCode() async -> Bool {
        guard let pendingCode else { return false }
        return await perform { client in
            switch pendingCode.purpose {
            case .confirmSignUp:
                try await client.auth.resend(email: pendingCode.email, type: .signup, emailRedirectTo: Self.redirectURL)
            case .signIn:
                try await client.auth.signInWithOTP(email: pendingCode.email, redirectTo: Self.redirectURL, shouldCreateUser: true)
            case .resetPassword:
                try await client.auth.resetPasswordForEmail(pendingCode.email, redirectTo: Self.redirectURL)
            }
        }
    }

    func cancelCode() {
        pendingCode = nil
        errorMessage = nil
    }

    /// Runs one account request with the shared working and error state.
    private func perform(_ work: (SupabaseClient) async throws -> Void) async -> Bool {
        guard let client else {
            errorMessage = AccountError.notConfigured.errorDescription
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work(client)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private static func cleanEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Supabase's messages, in Omnia's words where they would confuse.
    private static func message(for error: Error) -> String {
        guard let error = error as? AuthError else { return error.localizedDescription }
        switch error.errorCode {
        case .invalidCredentials: return "That email and password don't match."
        case .userAlreadyExists, .emailExists: return "There is already an account with this email. Sign in instead."
        case .weakPassword: return "Choose a longer password, at least 8 characters."
        case .otpExpired: return "That code is wrong or has expired. Ask for a new one."
        case .overEmailSendRateLimit, .overRequestRateLimit:
            return "Too many emails for now. Wait a minute, then try again."
        case .validationFailed: return "Check the email address and password."
        case .signupDisabled: return "New accounts are turned off right now."
        default: return error.localizedDescription
        }
    }

    // MARK: Viewer profiles in the cloud

    struct ViewerProfileRow: Codable, Sendable {
        var userID: UUID
        var id: UUID
        var name: String
        var avatarID: String?
        var colorHex: String
        var position: Int
        var isLocked: Bool
        var usesMainSettings: Bool?
        var usesMainAddons: Bool?
        var usesMainPlugins: Bool?
        var deletedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", id, name, avatarID = "avatar_id", colorHex = "color_hex"
            case position, isLocked = "is_locked", deletedAt = "deleted_at"
            case usesMainSettings = "uses_main_settings", usesMainAddons = "uses_main_addons"
            case usesMainPlugins = "uses_main_plugins"
            case createdAt = "created_at", updatedAt = "updated_at"
        }
    }

    func fetchViewerProfiles() async throws -> [ViewerProfileRow] {
        guard let client, user != nil else { return [] }
        return try await client.from("viewer_profiles").select().execute().value
    }

    func saveViewerProfiles(_ rows: [ViewerProfileRow]) async throws {
        guard let client, !rows.isEmpty else { return }
        try await client.from("viewer_profiles").upsert(rows, onConflict: "user_id,id").execute()
    }

    // MARK: Each profile's data in the cloud

    /// One kind of a profile's data (settings, add-ons, library…) as JSON.
    /// Listing leaves the payload out; it is fetched only when needed.
    struct ProfileDataRow: Codable, Sendable {
        var userID: UUID?
        var profileID: UUID
        var kind: String
        var payload: String?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", profileID = "profile_id", kind, payload, updatedAt = "updated_at"
        }
    }

    /// Where progress and the watchlist live: the account when signed in
    /// (ProfileDataSync uploads them per profile), otherwise this device.
    var storageSummary: String {
        user != nil ? "Stored in Omnia account" : "Stored only on this device"
    }

    func fetchProfileDataIndex() async throws -> [ProfileDataRow] {
        guard let client, user != nil else { return [] }
        return try await client.from("profile_data")
            .select("profile_id,kind,updated_at")
            .execute()
            .value
    }

    func fetchProfileDataPayload(profileID: UUID, kind: String) async throws -> String? {
        guard let client, user != nil else { return nil }
        let rows: [ProfileDataRow] = try await client.from("profile_data")
            .select("profile_id,kind,payload,updated_at")
            .eq("profile_id", value: profileID.uuidString)
            .eq("kind", value: kind)
            .limit(1)
            .execute()
            .value
        return rows.first?.payload
    }

    func saveProfileData(profileID: UUID, kind: String, payload: String, updatedAt: Date) async throws {
        guard let client, let userID = user?.id else { throw AccountError.notConfigured }
        let row = ProfileDataRow(userID: userID, profileID: profileID, kind: kind, payload: payload, updatedAt: updatedAt)
        try await client.from("profile_data")
            .upsert(row, onConflict: "user_id,profile_id,kind", returning: .minimal)
            .execute()
    }

    func deleteProfileData(profileID: UUID) async throws {
        guard let client, user != nil else { return }
        try await client.from("profile_data")
            .delete()
            .eq("profile_id", value: profileID.uuidString)
            .execute()
    }

    // MARK: Avatars uploaded to Omnia's Supabase

    /// A row of the public `avatar_catalog` table. Anyone can read it, so
    /// the picker shows uploaded avatars before signing in too.
    struct AvatarCatalogRow: Codable, Sendable {
        var displayName: String
        var storagePath: String
        var category: String
        var sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name", storagePath = "storage_path"
            case category, sortOrder = "sort_order"
        }
    }

    func fetchAvatarCatalog() async throws -> [AvatarCatalogRow] {
        guard let client else { return [] }
        return try await client.from("avatar_catalog")
            .select("display_name,storage_path,category,sort_order")
            .eq("is_active", value: true)
            .order("category")
            .order("sort_order")
            .execute()
            .value
    }

    func handle(callback url: URL) {
        guard url.scheme == Self.redirectURL.scheme, let client else { return }
        Task {
            do {
                try apply(try await client.auth.session(from: url))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() async {
        guard !isWorking, let client else { return }
        isSigningOut = true
        isWorking = true
        errorMessage = nil
        defer { isWorking = false; isSigningOut = false }
        do {
            try await willSignOut?()
            try willChangeIdentity?(nil)
            // This device only. The SDK's default ends the session everywhere,
            // which silently signed out the account's other devices.
            try await client.auth.signOut(scope: .local)
            user = nil
            localResetPending = true
            UserDefaults.standard.set(true, forKey: "sign-out-local-reset-pending")
        } catch {
            do {
                try willChangeIdentity?(user?.id)
                await didRecoverIdentity?()
            } catch { }
            errorMessage = "Sign-out could not finish. Check your connection and retry so your latest profile changes can sync. Your local session has been kept."
            return
        }
        await finishLocalSignOut()
    }

    /// The marker survives interruption so relaunch cannot expose the previous session.
    func finishLocalSignOut() async {
        guard localResetPending, !isResettingLocalData else { return }
        isResettingLocalData = true
        defer { isResettingLocalData = false }
        do {
            guard let didSignOut else { throw CancellationError() }
            try await didSignOut()
            pendingCode = nil
            errorMessage = nil
            UserDefaults.standard.set(false, forKey: "sign-out-local-reset-pending")
            localResetPending = false
            sessionGeneration = UUID()
        } catch {
            errorMessage = "You are signed out, but local cleanup needs to finish. Retry to return to welcome."
        }
    }

    func metadataAccessToken() async throws -> String {
        guard let client else { throw AccountError.notConfigured }
        let session = try await client.auth.session
        guard session.user.id == user?.id else { throw AccountError.notConfigured }
        return session.accessToken
    }

    private func apply(_ session: Session) throws {
        guard !localResetPending, !isResettingLocalData, !isSigningOut else { throw AccountError.notConfigured }
        try willChangeIdentity?(session.user.id)
        user = .init(
            id: session.user.id,
            email: session.user.email,
            provider: session.user.identities?.first?.provider
        )
    }

    private static func makeNonce() -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0 ..< 32).compactMap { _ in alphabet.randomElement() })
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum AccountError: LocalizedError {
    case notConfigured
    case appleIdentityTokenUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Omnia’s cloud configuration is unavailable."
        case .appleIdentityTokenUnavailable:
            "Apple did not return an identity token."
        }
    }
}

@MainActor
private final class AppleAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    func request(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { reset() }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AccountError.appleIdentityTokenUnavailable)
            return
        }
        continuation?.resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { reset() }
        continuation?.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        if let window = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)) {
            return window
        }
        preconditionFailure("Apple sign-in requires an active window scene.")
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        #endif
    }

    private func reset() {
        continuation = nil
        controller = nil
    }
}
