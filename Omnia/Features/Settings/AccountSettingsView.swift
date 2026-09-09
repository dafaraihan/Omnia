import SwiftUI

struct AccountSettingsView: View {
    @Environment(OmniaAccount.self) private var account
    @State private var confirmation = SettingsConfirmation<DestructiveAction>()

    private enum DestructiveAction: Equatable {
        case signOut
    }

    var body: some View {
        OmniaSettingsForm {
            if let user = account.user {
                Section("Signed In") {
                    LabeledContent("Account", value: user.email ?? user.id.uuidString)
                    LabeledContent("Provider", value: user.provider?.capitalized ?? "Omnia")
                    Button("Sign Out", role: .destructive) {
                        confirmation.request(.signOut)
                    }
                    .disabled(account.isWorking)
                }
            } else {
                Section {
                    ForEach(OmniaAccount.Provider.allCases) { provider in
                        Button {
                            Task { await account.signIn(using: provider) }
                        } label: {
                            HStack(spacing: 12) {
                                AccountProviderMark(provider: provider)
                                Text("Continue with \(provider.title)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if account.isWorking {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(account.isWorking || !account.isConfigured)
                    }
                } header: {
                    Text("Sign In With")
                } footer: {
                    if !account.isConfigured {
                        Text("Cloud sign-in is unavailable until Omnia's Supabase configuration is installed.")
                    }
                }
            }

            if let errorMessage = account.errorMessage {
                Section("Account Connection") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .omniaNavigationTitle("Account")
        .confirmationDialog(
            "Sign Out of Omnia?",
            isPresented: confirmationPresentation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                guard confirmation.confirm() == .signOut else { return }
                Task { await account.signOut() }
            }
            Button("Cancel", role: .cancel) { confirmation.cancel() }
        } message: {
            Text("Local watch progress and app settings remain on this device.")
        }
    }

    private var confirmationPresentation: Binding<Bool> {
        Binding(
            get: { confirmation.pending != nil },
            set: { isPresented in
                if !isPresented { confirmation.cancel() }
            }
        )
    }
}

private struct AccountProviderMark: View {
    let provider: OmniaAccount.Provider
    #if os(macOS)
    @Environment(\.macSettingsSymbolTreatment) private var symbolTreatment
    #endif

    var body: some View {
        Group {
            switch provider {
            case .apple:
                Image(systemName: "apple.logo")
                    .resizable()
                    .scaledToFit()
            case .google:
                Image("GoogleMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            case .facebook:
                Image("FacebookMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            }
        }
        #if os(macOS)
        .foregroundStyle(symbolTreatment.color)
        #else
        .foregroundStyle(.primary)
        #endif
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
