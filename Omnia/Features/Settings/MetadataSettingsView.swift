import SwiftUI

struct MetadataSettingsView: View {
    var body: some View {
        Form {
            ForEach(MetadataContentClass.allCases) { contentClass in
                MetadataRouteSection(contentClass: contentClass)
            }

            Section("Providers") {
                ForEach(MetadataProvider.supported) { provider in
                    NavigationLink(value: SettingsRoute.metadataProvider(provider.id)) {
                        HStack(spacing: 12) {
                            MetadataProviderMark(providerID: provider.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                Text(provider.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Metadata")
    }
}

private struct MetadataRouteSection: View {
    @Environment(OmniaStore.self) private var store

    let contentClass: MetadataContentClass

    private var route: MetadataRoute { store.metadataRouting[contentClass] }
    private var allowedSources: [MetadataProviderIdentifier] { contentClass.availableSources }
    private var eligibleFallbacks: [MetadataProviderIdentifier] {
        allowedSources.filter { $0 != route.primary }
    }

    var body: some View {
        Section {
            Picker("Primary Source", selection: primaryBinding) {
                ForEach(allowedSources) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            Toggle("Enable Fallback", isOn: fallbackEnabledBinding)

            if route.fallbackEnabled {
                ForEach(eligibleFallbacks) { provider in
                    Toggle(provider.title, isOn: fallbackBinding(for: provider))
                }

                if !route.fallbackOrder.isEmpty {
                    LabeledContent("Fallback Priority") {
                        Text("First to last")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(route.fallbackOrder) { provider in
                        MetadataFallbackRow(
                            provider: provider,
                            canMoveEarlier: provider != route.fallbackOrder.first,
                            canMoveLater: provider != route.fallbackOrder.last,
                            move: { direction in move(provider, direction: direction) }
                        )
                    }
                    .onMove(perform: moveFallback)
                }
            }
        } header: {
            Text(contentClass.title)
        } footer: {
            Text("The primary source is queried first. Enabled fallback sources fill missing metadata in priority order.")
        }
    }

    private var primaryBinding: Binding<MetadataProviderIdentifier> {
        Binding(
            get: { route.primary },
            set: { provider in
                updateRoute { $0.setPrimary(provider, allowed: allowedSources) }
            }
        )
    }

    private var fallbackEnabledBinding: Binding<Bool> {
        Binding(
            get: { route.fallbackEnabled },
            set: { enabled in updateRoute { $0.fallbackEnabled = enabled } }
        )
    }

    private func fallbackBinding(for provider: MetadataProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { route.fallbackOrder.contains(provider) },
            set: { enabled in
                updateRoute {
                    $0.setFallback(provider, enabled: enabled, allowed: allowedSources)
                }
            }
        )
    }

    private func updateRoute(_ update: (inout MetadataRoute) -> Void) {
        var preferences = store.metadataRouting
        update(&preferences[contentClass])
        store.metadataRouting = preferences
    }

    private func move(_ provider: MetadataProviderIdentifier, direction: MetadataFallbackMoveDirection) {
        updateRoute { $0.moveFallback(provider, direction: direction) }
    }

    private func moveFallback(from source: IndexSet, to destination: Int) {
        updateRoute { $0.moveFallback(from: source, to: destination) }
    }
}

private struct MetadataFallbackRow: View {
    let provider: MetadataProviderIdentifier
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let move: (MetadataFallbackMoveDirection) -> Void

    var body: some View {
        HStack(spacing: 12) {
            MetadataProviderMark(providerID: provider.rawValue)
            Text(provider.title)
            Spacer()
            Menu("Change Priority", systemImage: "arrow.up.arrow.down") {
                Button("Move Earlier", systemImage: "arrow.up") { move(.earlier) }
                    .disabled(!canMoveEarlier)
                Button("Move Later", systemImage: "arrow.down") { move(.later) }
                    .disabled(!canMoveLater)
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityAction(named: "Move Earlier") { move(.earlier) }
        .accessibilityAction(named: "Move Later") { move(.later) }
    }
}

private struct MetadataProviderMark: View {
    let providerID: String

    private var assetName: String? {
        switch providerID {
        case "tmdb": "TMDBMark"
        case "tvdb": "TheTVDBMark"
        case "mdblist": "MDBListMark"
        case "anilist": "AniListMark"
        default: nil
        }
    }

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "cylinder.split.1x2")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

struct MetadataProviderDetailView: View {
    let provider: MetadataProvider

    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var credentialInput = ""
    @State private var hasStoredCredential = false
    @State private var connectionStatus: String?
    @State private var isTestingConnection = false
    @State private var confirmation = SettingsConfirmation<UserManagedProviderCredential>()

    private var credential: UserManagedProviderCredential? {
        switch provider.id {
        case "mdblist": .mdblist
        case "anilist": .anilist
        default: nil
        }
    }

    var body: some View {
        Form {
            Section("About") {
                Text(provider.summary)
            }

            Section {
                if provider.credentialStrategy == .backendManaged {
                    LabeledContent("Credential source", value: "Omnia backend")
                    Text("The shared credential is kept outside the app and becomes available only when Omnia's secure backend is configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let credential {
                    Text(credential.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField(credential.entryTitle, text: $credentialInput)
                        .textContentType(.password)

                    if hasStoredCredential {
                        Label("Stored securely in this device's Keychain", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(hasStoredCredential ? "Replace Credential" : "Save Credential") {
                        saveCredential(credential)
                    }
                    .disabled(credentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasStoredCredential {
                        Button("Remove Credential", role: .destructive) {
                            confirmation.request(credential)
                        }
                        Button("Test Connection") { testConnection(credential) }
                            .disabled(isTestingConnection)
                    }

                    if isTestingConnection {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking connection…")
                        }
                        .foregroundStyle(.secondary)
                    } else if let connectionStatus {
                        Text(connectionStatus)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Credential source", value: "Not configured")
                }
            } header: {
                Text("Connection")
            } footer: {
                if provider.credentialStrategy == .userManaged {
                    Text("Credentials stay in the local Keychain and are never displayed after saving.")
                }
            }

            if provider.id == "mdblist" {
                Section {
                    ForEach(ratingSettingsRows.filter { $0.providerID != nil }) { row in
                        Toggle(isOn: ratingProviderBinding(for: row)) {
                            MDBListRatingProviderLabel(row: row)
                        }
                    }

                    if let aggregate = ratingSettingsRows.last,
                       aggregate.providerID == nil {
                        LabeledContent {
                            Text(aggregate.detail ?? "")
                        } label: {
                            MDBListRatingProviderLabel(row: aggregate)
                        }
                    }
                } header: {
                    Text("Ratings on Title Details")
                } footer: {
                    Text("New rating sources discovered from MDBList are enabled by default. The MDBList score is always shown when available.")
                }
            }
        }
        .navigationTitle(provider.name)
        .onAppear { loadStoredCredentialState() }
        .confirmationDialog(
            "Remove \(provider.name) Credential?",
            isPresented: confirmationPresentation,
            titleVisibility: .visible
        ) {
            Button("Remove Credential", role: .destructive) {
                guard let credential = confirmation.confirm() else { return }
                removeCredential(credential)
            }
            Button("Cancel", role: .cancel) { confirmation.cancel() }
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

    private var ratingSettingsRows: [MDBListRatingSettingsRow] {
        MDBListRatingSettingsModel.rows(
            preferences: settings.preferences.mdblistRatings
        )
    }

    private func ratingProviderBinding(
        for row: MDBListRatingSettingsRow
    ) -> Binding<Bool> {
        Binding(
            get: { row.providerID.map(settings.preferences.mdblistRatings.isEnabled) ?? true },
            set: { enabled in
                guard let providerID = row.providerID else { return }
                settings.setMDBListRatingProvider(providerID, enabled: enabled)
            }
        )
    }

    private func loadStoredCredentialState() {
        guard let credential else { return }
        hasStoredCredential = ProviderCredentialStore.isConfigured(credential)
    }

    private func saveCredential(_ credential: UserManagedProviderCredential) {
        let value = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        do {
            try ProviderCredentialStore.save(value, for: credential)
            credentialInput = ""
            hasStoredCredential = true
            connectionStatus = "Credential saved in the device Keychain."
        } catch {
            connectionStatus = "Unable to save the credential."
        }
    }

    private func removeCredential(_ credential: UserManagedProviderCredential) {
        do {
            try ProviderCredentialStore.delete(credential)
            credentialInput = ""
            hasStoredCredential = false
            connectionStatus = "Credential removed from this device."
        } catch {
            connectionStatus = "Unable to remove the credential."
        }
    }

    private func testConnection(_ credential: UserManagedProviderCredential) {
        isTestingConnection = true
        connectionStatus = nil
        Task {
            defer { isTestingConnection = false }
            do {
                switch credential {
                case .mdblist:
                    try await MDBListMetadataClient().verifyStoredCredential()
                    connectionStatus = "MDBList is connected."
                case .anilist:
                    let viewerName = try await AniListMetadataClient().viewerName()
                    connectionStatus = "Connected as \(viewerName)."
                }
            } catch {
                connectionStatus = "The provider could not verify this credential."
            }
        }
    }
}

private struct MDBListRatingProviderLabel: View {
    let row: MDBListRatingSettingsRow

    var body: some View {
        HStack(spacing: 10) {
            if let assetName = row.assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(height: 20)
                    .frame(maxWidth: 72)
                    .accessibilityHidden(true)
            }
            Text(row.displayName)
        }
    }
}
