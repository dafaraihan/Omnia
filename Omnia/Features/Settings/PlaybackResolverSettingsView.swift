import SwiftUI

struct PlaybackResolverSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @AppStorage(PlaybackResolverSettings.endpointKey) private var endpoint = ""
    @AppStorage(PlaybackResolverSettings.approvedAddonIDsKey) private var approvedAddonIDs = ""
    @AppStorage(PlaybackResolverSettings.approvedStreamHostsKey) private var approvedStreamHosts = ""

    @State private var authorizationToken = ""
    @State private var hasStoredToken = PlaybackResolverCredentialStore.hasAuthorizationToken
    @State private var statusMessage: String?
    @State private var confirmation = SettingsConfirmation<DestructiveAction>()

    private enum DestructiveAction: Equatable {
        case removeToken
    }

    var body: some View {
        Form {
            Section {
                TextField("HTTPS endpoint", text: $endpoint, prompt: Text("https://resolver.example/v1/resolve"))
                    .textContentType(.URL)
            } header: {
                Text("Resolver Endpoint")
            } footer: {
                Text("Omnia sends a versioned source request only to this HTTPS endpoint and only for an approved add-on.")
            }

            Section {
                SecureField(
                    hasStoredToken ? "Replace stored bearer token" : "Bearer token",
                    text: $authorizationToken
                )
                .textContentType(.password)

                Button(hasStoredToken ? "Replace Token" : "Save Token") { saveToken() }
                    .disabled(authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasStoredToken {
                    Button("Remove Token", role: .destructive) {
                        confirmation.request(.removeToken)
                    }
                }
            } header: {
                Text("Authorization")
            } footer: {
                Text("The token stays in the local Keychain. It is never synced, logged, sent to add-ons, or included in playback URLs.")
            }

            Section {
                TextEditor(text: $approvedAddonIDs)
                    .font(.body.monospaced())
                    .frame(minHeight: 92)

                ForEach(streamAddons) { addon in
                    Button {
                        addAddonID(addon.id)
                    } label: {
                        LabeledContent(addon.manifest.name, value: addon.id)
                    }
                }
            } header: {
                Text("Approved Add-ons")
            } footer: {
                Text("Enter add-on IDs one per line or comma-separated. Only these add-ons may send an info hash to the resolver.")
            }

            Section {
                TextEditor(text: $approvedStreamHosts)
                    .font(.body.monospaced())
                    .frame(minHeight: 92)
            } header: {
                Text("Approved HTTPS Stream Hosts")
            } footer: {
                Text("Enter exact host names only, one per line or comma-separated. Results are rejected unless they use HTTPS and exactly match this allow-list.")
            }

            if let statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Playback Resolver")
        .confirmationDialog(
            "Remove Resolver Token?",
            isPresented: confirmationPresentation,
            titleVisibility: .visible
        ) {
            Button("Remove Token", role: .destructive) {
                guard confirmation.confirm() == .removeToken else { return }
                removeToken()
            }
            Button("Cancel", role: .cancel) { confirmation.cancel() }
        }
    }

    private var streamAddons: [InstalledAddon] {
        store.installedAddons.filter { $0.manifest.supportsStreams }
    }

    private var confirmationPresentation: Binding<Bool> {
        Binding(
            get: { confirmation.pending != nil },
            set: { isPresented in
                if !isPresented { confirmation.cancel() }
            }
        )
    }

    private func addAddonID(_ id: String) {
        let existing = approvedAddonIDs
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !existing.contains(id) else { return }
        approvedAddonIDs = (existing + [id]).joined(separator: "\n")
    }

    private func saveToken() {
        let value = authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        do {
            try PlaybackResolverCredentialStore.saveAuthorizationToken(value)
            authorizationToken = ""
            hasStoredToken = true
            statusMessage = "Authorization token saved in the local Keychain."
        } catch {
            statusMessage = "Omnia could not save the authorization token."
        }
    }

    private func removeToken() {
        do {
            try PlaybackResolverCredentialStore.deleteAuthorizationToken()
            authorizationToken = ""
            hasStoredToken = false
            statusMessage = "Authorization token removed from the local Keychain."
        } catch {
            statusMessage = "Omnia could not remove the authorization token."
        }
    }
}
