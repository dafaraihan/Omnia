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

    var user: User?
    var isWorking = false
    var errorMessage: String?

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
    }

    func restoreSession() async {
        guard let client else { return }
        if let session = client.auth.currentSession {
            apply(session)
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
                apply(session)

            case .google:
                let session = try await client.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: Self.redirectURL
                )
                apply(session)

            case .facebook:
                let session = try await client.auth.signInWithOAuth(
                    provider: .facebook,
                    redirectTo: Self.redirectURL
                )
                apply(session)
            }
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handle(callback url: URL) {
        guard url.scheme == Self.redirectURL.scheme, let client else { return }
        Task {
            do {
                apply(try await client.auth.session(from: url))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() async {
        guard let client else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.auth.signOut()
            user = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func metadataAccessToken() async throws -> String {
        guard let client else { throw AccountError.notConfigured }
        return try await client.auth.session.accessToken
    }

    private func apply(_ session: Session) {
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
