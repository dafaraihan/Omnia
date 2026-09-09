import SwiftUI

struct PlaybackResolverSettingsView: View {
    @State private var localSettings = LocalResolverSettingsStore()
    @State private var confirmation = SettingsConfirmation<DestructiveAction>()
    @State private var statusMessage: String?

    private enum DestructiveAction: Equatable {
        case revokeConsent
        case removeLegacyToken
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                LabeledContent("Resolver", value: "On this Mac")
                LabeledContent(
                    "Peer access",
                    value: localSettings.preferences.hasCurrentConsent ? "Allowed" : "Consent required"
                )

                if localSettings.preferences.hasCurrentConsent {
                    Button("Revoke Peer Access", role: .destructive) {
                        confirmation.request(.revokeConsent)
                    }
                } else {
                    Button("Allow Local Peer Playback") {
                        localSettings.acceptConsent()
                        statusMessage = "Local peer playback was enabled on this Mac."
                    }
                }
            } header: {
                Text("Local Resolver")
            } footer: {
                Text(LocalTorrentConsent.disclosure)
            }

            Section {
                Picker("Maximum cache", selection: cacheQuotaBinding) {
                    ForEach(ResolverCacheQuota.allCases, id: \.self) { quota in
                        Text(quota.title).tag(quota)
                    }
                }
                Toggle("Keep incomplete downloads", isOn: retainsIncompleteJobsBinding)
            } header: {
                Text("Storage")
            } footer: {
                Text("Locally resolved torrent files and prepared Blu-ray images share Omnia’s sandboxed cache, are excluded from backup, and preserve at least 5 GB of available disk space. Inactive items are evicted oldest first. Keep incomplete downloads applies to both source types.")
            }

            Section {
                TextField(
                    "Download limit (KiB/s, 0 is unlimited)",
                    value: downloadLimitBinding,
                    format: .number
                )
                TextField(
                    "Upload limit (KiB/s)",
                    value: uploadLimitBinding,
                    format: .number
                )
            } header: {
                Text("Bandwidth")
            } footer: {
                Text("Limits are bounded from 0 through 1,000,000 KiB/s. Peer activity is allowed only during an explicitly selected playback job and stops when that job ends.")
            }

            if PlaybackResolverCredentialStore.hasAuthorizationToken {
                Section {
                    Button("Remove Legacy Resolver Token", role: .destructive) {
                        confirmation.request(.removeLegacyToken)
                    }
                } header: {
                    Text("Legacy Remote Resolver")
                } footer: {
                    Text("Remote resolving is no longer used. This only deletes the old token from this Mac’s Keychain.")
                }
            }

            if let statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .omniaNavigationTitle("Local Playback Resolver")
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresentation,
            titleVisibility: .visible
        ) {
            if confirmation.pending == .revokeConsent {
                Button("Revoke Peer Access", role: .destructive) {
                    guard confirmation.confirm() == .revokeConsent else { return }
                    localSettings.revokeConsent()
                    statusMessage = "Local peer playback was disabled."
                }
            }
            if confirmation.pending == .removeLegacyToken {
                Button("Remove Legacy Token", role: .destructive) {
                    guard confirmation.confirm() == .removeLegacyToken else { return }
                    removeLegacyToken()
                }
            }
            Button("Cancel", role: .cancel) { confirmation.cancel() }
        }
    }

    private var cacheQuotaBinding: Binding<ResolverCacheQuota> {
        Binding(
            get: { localSettings.preferences.cacheQuota },
            set: { value in localSettings.update { $0.cacheQuota = value } }
        )
    }

    private var retainsIncompleteJobsBinding: Binding<Bool> {
        Binding(
            get: { localSettings.preferences.retainsIncompleteJobs },
            set: { value in localSettings.update { $0.retainsIncompleteJobs = value } }
        )
    }

    private var downloadLimitBinding: Binding<Int> {
        Binding(
            get: { localSettings.preferences.downloadLimitKilobytesPerSecond },
            set: { value in localSettings.update { $0.downloadLimitKilobytesPerSecond = value } }
        )
    }

    private var uploadLimitBinding: Binding<Int> {
        Binding(
            get: { localSettings.preferences.uploadLimitKilobytesPerSecond },
            set: { value in localSettings.update { $0.uploadLimitKilobytesPerSecond = value } }
        )
    }

    private var confirmationPresentation: Binding<Bool> {
        Binding(
            get: { confirmation.pending != nil },
            set: { if !$0 { confirmation.cancel() } }
        )
    }

    private var confirmationTitle: String {
        switch confirmation.pending {
        case .revokeConsent: "Disable Local Peer Playback?"
        case .removeLegacyToken: "Remove Legacy Resolver Token?"
        case nil: "Confirm Change"
        }
    }

    private func removeLegacyToken() {
        do {
            try PlaybackResolverCredentialStore.deleteAuthorizationToken()
            statusMessage = "The legacy resolver token was removed from the local Keychain."
        } catch {
            statusMessage = "Omnia could not remove the legacy resolver token."
        }
    }
}
