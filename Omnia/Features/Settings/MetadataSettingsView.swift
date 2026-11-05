import SwiftUI
import UniformTypeIdentifiers

/// Settings › Integrations, laid out like Nuvio's: the user's API keys,
/// TMDB Enrichment and MDBList Ratings. Omnia's own metadata routing, which Nuvio doesn't have,
/// sits below them under Metadata Sources.
struct MetadataSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    /// Bumped when a key is saved or removed, so Saved / Not set follows.
    @State private var keyChanges = 0

    let showsAdvanced: Bool

    init(showsAdvanced: Bool = false) {
        self.showsAdvanced = showsAdvanced
    }

    var body: some View {
        Group {
            if showsAdvanced {
                OmniaSettingsForm {
            Section {
                IntegrationLinkRow(
                    route: .tmdbEnrichment,
                    providerID: "tmdb",
                    title: "TMDB Enrichment",
                    detail: tmdbSummary
                )
                IntegrationLinkRow(
                    route: .tvdbEnrichment,
                    providerID: "tvdb",
                    title: "TVDB Enrichment",
                    detail: tvdbSummary
                )
                IntegrationLinkRow(
                    route: .animeEnrichment,
                    providerID: "anilist",
                    title: "Anime Enrichment",
                    detail: animeSummary
                )
                IntegrationLinkRow(
                    route: .metadataProvider("mdblist"),
                    providerID: "mdblist",
                    title: "MDBList Ratings",
                    detail: mdblistSummary
                )
            } header: {
                Text("Fill In Missing Details")
            }

            Section {
                IntegrationLinkRow(
                    route: .metadataSources,
                    providerID: nil,
                    title: "Metadata Sources",
                    detail: "Where built-in catalogs, search and anime come from"
                )
            } header: {
                Text("Omnia")
            } footer: {
                Text("Add-ons describe the titles they list. Metadata Sources choose TMDB, TVDB, AniList, Kitsu or MyAnimeList for Omnia's built-in rows and fill in titles no add-on describes.")
            }
        
                }
            } else {
                OmniaSettingsForm {
            AccountBackupNotice()
            // Every user adds their own keys; nothing TMDB or TVDB is built
            // in. These open the same pages as Metadata Sources › Providers.
            Section {
                ForEach(["tmdb", "tvdb", "fanart"], id: \.self) { id in
                    IntegrationLinkRow(
                        route: .metadataProvider(id),
                        providerID: id,
                        title: "\(MetadataProvider.supported.first { $0.id == id }?.name ?? id) API Key",
                        detail: keyStatus(id)
                    )
                }
            } header: {
                Text("API Keys")
            } footer: {
                Text("Your own free TMDB and TVDB keys unlock artwork, logos, details and search beyond your add-ons; fanart.tv adds textless posters for the iPhone's hero. Keys stay in this device's Keychain and, when you're signed in, in your account's encrypted vault.")
            }

            Section {
                SettingsRouteLink(route: .advanced(.metadata), summary: nil)
            }
                }
            }
        }
        .omniaNavigationTitle(showsAdvanced ? "Advanced" : "Metadata")
        .onReceive(NotificationCenter.default.publisher(for: .providerCredentialDidChange)) { _ in
            keyChanges += 1
        }
    }

    private func keyStatus(_ id: String) -> String {
        _ = keyChanges
        guard let credential = UserManagedProviderCredential(rawValue: id) else { return "" }
        return ProviderCredentialStore.isConfigured(credential) ? "Saved" : "Not set"
    }

    private var tvdbSummary: String {
        guard settings.preferences.integrations.tvdb.enabled else { return "Off" }
        return ProviderCredentialStore.isConfigured(.tvdb) ? "On" : "Needs your TVDB API key"
    }

    private var tmdbSummary: String {
        let tmdb = settings.preferences.integrations.tmdb
        guard tmdb.enabled else { return "Off: add-on data only" }
        // Nothing TMDB is built in: it works only with the user's own key.
        guard ProviderCredentialStore.isConfigured(.tmdb) else { return "Needs your TMDB API key" }
        return "\(tmdb.enabledModuleCount) of \(TMDBEnrichmentPreferences.moduleCount) modules on"
    }

    private var animeSummary: String {
        let anime = settings.preferences.integrations.anime
        guard anime.enabled else { return "Off" }
        let modules = [anime.useBasicInfo, anime.useArtwork].filter { $0 }.count
        return "\(modules) of 2 modules on"
    }

    private var mdblistSummary: String {
        guard settings.preferences.integrations.mdblistEnabled else { return "Off" }
        return ProviderCredentialStore.isConfigured(.mdblist) ? "On" : "Needs an API key"
    }
}

private struct IntegrationLinkRow: View {
    let route: SettingsRoute
    let providerID: String?
    let title: String
    let detail: String

    var body: some View {
        NavigationLink {
            SettingsDestinationView(route: route)
        } label: {
            HStack(spacing: 12) {
                MetadataProviderMark(providerID: providerID ?? "")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsLinkRow()
    }
}

/// Omnia's per-type metadata routing and its providers. Nuvio has no
/// equivalent: it reads metadata from add-ons and fills gaps from TMDB.
struct MetadataSourcesSettingsView: View {
    var body: some View {
        OmniaSettingsForm {
            ForEach(MetadataContentClass.allCases) { contentClass in
                MetadataRouteSection(contentClass: contentClass)
            }

            Section("Providers") {
                // MDBList's key is under MDBList Ratings; AniList's account
                // under Account › Tracking (its metadata needs no key).
                ForEach(MetadataProvider.supported.filter { $0.id != "mdblist" && $0.id != "anilist" }) { provider in
                    NavigationLink {
                        SettingsDestinationView(route: .metadataProvider(provider.id))
                    } label: {
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
                    .settingsLinkRow()
                }
            }
        }
        .omniaNavigationTitle("Metadata Sources")
    }
}

/// Nonempty TMDB data replaces the enabled parts of an add-on title.
struct TMDBEnrichmentSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    private var enabled: Bool { settings.preferences.integrations.tmdb.enabled }

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle(isOn: settings.binding(\.integrations.tmdb.enabled)) {
                    Text("Enable TMDB Enrichment")
                    Text("Replace enabled fields with available TMDB information.")
                }
                .settingsRow("Enable TMDB Enrichment")
            } header: {
                Text("TMDB Enrichment")
            } footer: {
                Text("When no add-on describes a title, Omnia still shows TMDB's page for it.")
            }

            Section {
                module("Trailers", "Trailers and extras for the detail page.", \.useTrailers)
                module("Artwork", "Poster, logo and backdrop images.", \.useArtwork)
                module("Basic Info", "Title, year, description and genres.", \.useBasicInfo)
                module("Details", "Runtime, status, age rating, budget and revenue.", \.useDetails)
                module("Credits", "Cast with photos, directors and writers.", \.useCredits)
                module("Productions", "Studios and networks, and more titles from them.", \.useProductions)
                module("Episodes", "Seasons with episode titles, overviews, stills and runtimes.", \.useEpisodes)
                module("More Like This", "Recommendations on the detail page.", \.useMoreLikeThis)
                module("Collections", "Movie collections in release order.", \.useCollections)
            } header: {
                Text("Modules")
            } footer: {
                Text("Enabled modules use nonempty TMDB data. Missing sections preserve your add-on information. Requests use your own API key on this device.")
            }
            .disabled(!enabled)
        }
        .omniaNavigationTitle("TMDB Enrichment")
    }

    private func module(
        _ title: String,
        _ detail: String,
        _ keyPath: WritableKeyPath<TMDBEnrichmentPreferences, Bool>
    ) -> some View {
        Toggle(isOn: settings.binding((\SettingsPreferences.integrations.tmdb).appending(path: keyPath))) {
            Text(title)
            Text(detail)
        }
    }
}

struct TVDBEnrichmentSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle("Enable TVDB Enrichment", isOn: settings.binding(\.integrations.tvdb.enabled))
                .settingsRow("Enable TVDB Enrichment")
            } footer: {
                Text("Replace enabled fields with available TVDB information using your own API key. Missing sections preserve existing information. Metadata Sources sets the priority; if TVDB isn't listed there, it comes last. Anime titles follow the Anime order only.")
            }
            Section("Modules") {
                module("Trailers", \.useTrailers)
                module("Artwork", \.useArtwork)
                module("Basic Info", \.useBasicInfo)
                module("Details", \.useDetails)
                module("Credits", \.useCredits)
                module("Productions", \.useProductions)
                module("Episodes", \.useEpisodes)
            }
            .disabled(!settings.preferences.integrations.tvdb.enabled)
        }
        .omniaNavigationTitle("TVDB Enrichment")
    }

    private func module(_ title: String, _ keyPath: WritableKeyPath<TMDBEnrichmentPreferences, Bool>) -> some View {
        Toggle(title, isOn: settings.binding((\SettingsPreferences.integrations.tvdb.modules).appending(path: keyPath)))
    }
}

/// Anime Enrichment, after TMDB Enrichment: AniList, Kitsu and MyAnimeList
/// fill in what an anime title's add-on and TMDB left out (Dafa,
/// 2026-10-27). They're asked in the Anime order under Metadata Sources.
struct AnimeEnrichmentSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(OmniaStore.self) private var store

    private var enabled: Bool { settings.preferences.integrations.anime.enabled }

    private var sourcesInUse: String {
        let sources = store.metadataRouting.anime.requestedProviders.filter(\.isAnimeDatabase).map(\.title)
        return sources.isEmpty ? "none: turn one on under Metadata Sources › Anime" : sources.formatted(.list(type: .and))
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle(isOn: settings.binding(\.integrations.anime.enabled)) {
                    Text("Enable Anime Enrichment")
                    Text("Use anime databases to fill in what your add-ons and TMDB leave out.")
                }
                .settingsRow("Enable Anime Enrichment")
            } header: {
                Text("Anime Enrichment")
            } footer: {
                Text("Asks \(sourcesInUse), in that order. Only titles with an AniList, Kitsu or MyAnimeList ID are looked up, and none of them needs a key.")
            }

            Section {
                module("Basic Info", "Synopsis, genres and year.", \.useBasicInfo)
                module("Artwork", "Poster and banner images.", \.useArtwork)
            } header: {
                Text("Modules")
            } footer: {
                Text("A turned-off module leaves that part to your add-on and TMDB.")
            }
            .disabled(!enabled)
        }
        .omniaNavigationTitle("Anime Enrichment")
    }

    private func module(
        _ title: String,
        _ detail: String,
        _ keyPath: WritableKeyPath<AnimeEnrichmentPreferences, Bool>
    ) -> some View {
        Toggle(isOn: settings.binding((\SettingsPreferences.integrations.anime).appending(path: keyPath))) {
            Text(title)
            Text(detail)
        }
    }
}

/// A type's metadata sources as one list (Dafa, 2026-10-26): drag to set
/// the order, switch a source off to stop using it. The first source that's
/// on is asked first; the others fill in what it's missing, in order.
private struct MetadataRouteSection: View {
    @Environment(OmniaStore.self) private var store
    @State private var draggedSource: MetadataProviderIdentifier?

    let contentClass: MetadataContentClass

    private var route: MetadataRoute { store.metadataRouting[contentClass] }
    private var allowedSources: [MetadataProviderIdentifier] { contentClass.availableSources }
    private var sources: [MetadataProviderIdentifier] { route.orderedSources(allowed: allowedSources) }
    private var inUse: [MetadataProviderIdentifier] { sources.filter(route.isInUse) }

    var body: some View {
        Section {
            ForEach(sources) { provider in
                let isOn = route.isInUse(provider)
                MetadataSourceRow(
                    provider: provider,
                    role: role(of: provider),
                    isOn: Binding(
                        get: { isOn },
                        set: { setInUse(provider, $0) }
                    ),
                    // At least one source stays on.
                    canTurnOff: inUse.count > 1
                )
                .opacity(draggedSource == provider ? 0.72 : 1)
                .modifier(MetadataSourceDragModifier(
                    provider: provider,
                    isDraggable: isOn,
                    inUse: { inUse },
                    draggedSource: $draggedSource,
                    move: reorder
                ))
                .accessibilityAction(named: "Move Earlier") { step(provider, by: -1) }
                .accessibilityAction(named: "Move Later") { step(provider, by: 1) }
            }
        } header: {
            Text(contentClass.title)
        } footer: {
            Text("Drag to change the order. Omnia asks the first source that's on, then the next ones for anything it's missing.")
        }
    }

    private func role(of provider: MetadataProviderIdentifier) -> MetadataSourceRow.Role {
        guard let index = inUse.firstIndex(of: provider) else { return .off }
        return index == 0 ? .primary : .fallback(index)
    }

    private func setInUse(_ provider: MetadataProviderIdentifier, _ on: Bool) {
        var order = inUse
        if on {
            if !order.contains(provider) { order.append(provider) }
        } else {
            guard order.count > 1 else { return }
            order.removeAll { $0 == provider }
        }
        update(order)
    }

    private func reorder(_ order: [MetadataProviderIdentifier]) {
        update(order)
    }

    private func step(_ provider: MetadataProviderIdentifier, by offset: Int) {
        var order = inUse
        guard let index = order.firstIndex(of: provider), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        update(order)
    }

    private func update(_ order: [MetadataProviderIdentifier]) {
        var preferences = store.metadataRouting
        preferences[contentClass].setSources(inUseOrder: order, allowed: allowedSources)
        guard preferences != store.metadataRouting else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            store.metadataRouting = preferences
        }
    }
}

private struct MetadataSourceRow: View {
    enum Role: Equatable {
        case primary
        case fallback(Int)
        case off
    }

    let provider: MetadataProviderIdentifier
    let role: Role
    @Binding var isOn: Bool
    let canTurnOff: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(role == .off ? 0 : 1)
                .accessibilityHidden(true)
            MetadataProviderMark(providerID: provider.rawValue)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.title)
                Text(roleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(provider.title, isOn: $isOn)
                .labelsHidden()
                .disabled(isOn && !canTurnOff)
                .help(isOn && !canTurnOff ? "One source has to stay on." : "")
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var roleText: String {
        let text = switch role {
        case .primary: "Asked first"
        case .fallback(let position): position == 1 ? "Fills in what's missing" : "Then fills in the rest"
        case .off: "Off"
        }
        // TMDB and TVDB answer only with the user's own key.
        guard role != .off, let credential = keyCredential, !ProviderCredentialStore.isConfigured(credential) else {
            return text
        }
        return "\(text) · needs your API key"
    }

    private var keyCredential: UserManagedProviderCredential? {
        switch provider {
        case .tmdb: .tmdb
        case .tvdb: .tvdb
        default: nil
        }
    }
}

/// Drag and drop between the sources that are on, the way Add-ons reorder.
private struct MetadataSourceDragModifier: ViewModifier {
    let provider: MetadataProviderIdentifier
    let isDraggable: Bool
    let inUse: () -> [MetadataProviderIdentifier]
    @Binding var draggedSource: MetadataProviderIdentifier?
    let move: ([MetadataProviderIdentifier]) -> Void

    func body(content: Content) -> some View {
        if isDraggable {
            content
                .onDrag {
                    draggedSource = provider
                    return NSItemProvider(object: provider.rawValue as NSString)
                }
                .onDrop(of: [.text], delegate: MetadataSourceDropDelegate(
                    target: provider,
                    inUse: inUse,
                    draggedSource: $draggedSource,
                    move: move
                ))
        } else {
            content
        }
    }
}

private struct MetadataSourceDropDelegate: DropDelegate {
    let target: MetadataProviderIdentifier
    let inUse: () -> [MetadataProviderIdentifier]
    @Binding var draggedSource: MetadataProviderIdentifier?
    let move: ([MetadataProviderIdentifier]) -> Void

    func dropEntered(info: DropInfo) {
        var order = inUse()
        guard let draggedSource, draggedSource != target,
              let source = order.firstIndex(of: draggedSource),
              let destination = order.firstIndex(of: target)
        else { return }
        order.remove(at: source)
        order.insert(draggedSource, at: destination)
        move(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSource = nil
        return true
    }
}

private struct MetadataProviderMark: View {
    let providerID: String
    #if os(macOS)
    @Environment(\.macSettingsSymbolTreatment) private var symbolTreatment
    #endif

    private var assetName: String? {
        switch providerID {
        case "tmdb": "TMDBMark"
        case "tvdb": "TheTVDBMark"
        case "mdblist": "MDBListMark"
        case "anilist": "AniListMark"
        case "myanimelist": "RatingMyAnimeListMark"
        default: nil
        }
    }

    var body: some View {
        Group {
            if let assetName {
                // Each provider's own logo, in its own colours.
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Image(systemName: "cylinder.split.1x2")
                    .resizable()
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

struct MetadataProviderDetailView: View {
    let provider: MetadataProvider

    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var credentialInput = ""
    @State private var hasStoredCredential = false
    @State private var connectionStatus: String?
    @State private var isTestingConnection = false
    @State private var confirmation = SettingsConfirmation<UserManagedProviderCredential>()

    private var credential: UserManagedProviderCredential? {
        switch provider.id {
        case "mdblist": .mdblist
        case "anilist": .anilist
        case "tmdb": .tmdb
        case "tvdb": .tvdb
        case "fanart": .fanart
        default: nil
        }
    }

    var body: some View {
        OmniaSettingsForm {
            if isMDBList {
                // Nuvio's MDBList Ratings page: switch, API key, providers.
                Section {
                    Toggle(isOn: settings.binding(\.integrations.mdblistEnabled)) {
                        Text("Enable MDBList Ratings")
                        Text("Show ratings from external providers on title pages.")
                    }
                    if !hasStoredCredential {
                        Text("Add your MDBList API key below to see ratings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("MDBList Ratings")
                }
            } else {
                Section("About") {
                    Text(provider.summary)
                }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(credential.entryTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField(
                            credential.entryTitle,
                            text: $credentialInput,
                            prompt: Text("Enter credential")
                        )
                        .labelsHidden()
                        .textContentType(.password)
                    }

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
                        OmniaLoadingRow("Checking connection…")
                    } else if let connectionStatus {
                        Text(connectionStatus)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Credential source", value: "Not configured")
                }
            } header: {
                Text(isMDBList ? "API Key" : "Connection")
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
                    Text("External Ratings Providers")
                } footer: {
                    Text("New rating sources discovered from MDBList are enabled by default. The MDBList score is always shown when available.")
                }
                .disabled(!settings.preferences.integrations.mdblistEnabled)
            }
        }
        .omniaNavigationTitle(isMDBList ? "MDBList Ratings" : provider.name)
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

    private var isMDBList: Bool { provider.id == "mdblist" }

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
            reloadCatalogsIfNeeded(credential)
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
            reloadCatalogsIfNeeded(credential)
        } catch {
            connectionStatus = "Unable to remove the credential."
        }
    }

    /// Omnia's own rows and Discover come from TMDB and TVDB with the
    /// user's key, so they reload when it changes.
    private func reloadCatalogsIfNeeded(_ credential: UserManagedProviderCredential) {
        guard credential == .tmdb || credential == .tvdb else { return }
        Task { await metadata.loadDefaultCatalogs() }
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
                case .tmdb, .tvdb:
                    let provider: MetadataProviderIdentifier = credential == .tmdb ? .tmdb : .tvdb
                    try await OnDeviceMetadataService.shared.verify(provider)
                    connectionStatus = "\(credential.providerName) is connected."
                case .fanart:
                    try await PortraitArtworkResolver.shared.verifyFanartKey()
                    connectionStatus = "fanart.tv is connected."
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
