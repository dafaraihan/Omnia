import SwiftUI

/// Shown on the pages whose credentials the account backs up, when they aren't
/// being backed up: signed out, or the last sync with the account failed.
struct AccountBackupNotice: View {
    @Environment(OmniaAccount.self) private var account
    @Environment(CredentialVaultSync.self) private var credentialVault

    var body: some View {
        if account.isConfigured, account.user == nil {
            Section {
                notice(
                    title: credentialVault.sessionEnded ? "You've been signed out" : "Not signed in",
                    detail: "What you add here stays on this \(OmniaDevice.name). Sign in under Account to back it up; it's added to your account then."
                )
            }
        } else if let problem = credentialVault.problem {
            Section {
                notice(title: "Not synced with your account", detail: problem)
                Button("Retry Sync") { Task { await credentialVault.sync() } }
                    .disabled(credentialVault.isSyncing)
            }
        }
    }

    private func notice(title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.icloud")
        }
    }
}
