//
//  SettingsView.swift
//  Omnia
//

import SwiftUI

struct SettingsView: View {
    @Environment(OmniaStore.self) private var store

    private var enabledAddonCount: Int {
        store.installedAddons.filter(\.isEnabled).count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Library") {
                    NavigationLink {
                        AddonsSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Add-ons",
                            detail: enabledAddonCount == 0 ? "No sources enabled" : "\(enabledAddonCount) source\(enabledAddonCount == 1 ? "" : "s") enabled",
                            symbol: "puzzlepiece.extension.fill",
                            tint: .indigo
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        CatalogsSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Catalogs",
                            detail: "TMDB + TVDB defaults · \(store.enabledAddonCatalogCount) optional",
                            symbol: "rectangle.stack.fill",
                            tint: .pink
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        LibraryPreferencesSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Library & Home",
                            detail: "Sort saved titles and choose Home shelves",
                            symbol: "rectangle.grid.2x2.fill",
                            tint: .mint
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        MetadataSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Metadata",
                            detail: "TMDB, TVDB, and your providers",
                            symbol: "rectangle.3.group.fill",
                            tint: .teal,
                            providerMarks: ["tmdb", "tvdb"]
                        )
                    }
                }

                SettingsGroup(title: "Connections") {
                    NavigationLink {
                        AccountSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Account",
                            detail: "Sign in and sync across your devices",
                            symbol: "person.crop.circle.fill",
                            tint: .blue
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        IntegrationsSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Services",
                            detail: "Trakt and future connections",
                            symbol: "person.crop.circle.badge.checkmark",
                            tint: .blue
                        )
                    }
                }

                SettingsGroup(title: "Experience") {
                    NavigationLink {
                        PlaybackSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Playback",
                            detail: "Native controls and resume behavior",
                            symbol: "play.rectangle.fill",
                            tint: .orange
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Appearance",
                            detail: "\(store.appearance.title) · restrained materials",
                            symbol: "circle.lefthalf.filled",
                            tint: .purple
                        )
                    }
                }

                SettingsGroup(title: "About") {
                    SettingsValueRow(title: "Version", value: "1.0")
                    SettingsDivider()
                    SettingsValueRow(title: "Platforms", value: "iPhone, iPad, Mac")
                    SettingsDivider()
                    Link(destination: URL(string: "https://thetvdb.com")!) {
                        SettingsValueRow(title: "TheTVDB", value: "Metadata provided by TheTVDB")
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: "Credits") {
                    SettingsValueRow(title: "TMDB", value: "Metadata and artwork")
                }

                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, -12)
                }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Settings")
    }
}

struct AddonsSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @State private var showingAddAddon = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Catalog Control") {
                    NavigationLink {
                        CatalogsSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Choose Catalogs",
                            detail: "TMDB and TVDB are default; add-on catalogs are optional",
                            symbol: "rectangle.stack.fill",
                            tint: .pink
                        )
                    }
                }

                if store.installedAddons.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No Add-ons Yet", systemImage: "puzzlepiece.extension")
                            .font(.headline)
                        Text("Omnia’s default discovery remains available through TMDB and TVDB. Add an HTTPS manifest only for a source you trust.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Add Add-on", systemImage: "plus") { showingAddAddon = true }
                            .buttonStyle(.glassProminent)
                            .padding(.top, 2)
                    }
                    .padding(18)
                    .background { SettingsSurface() }
                } else {
                    SettingsGroup(title: "Installed Add-ons", footer: "Disabled add-ons are not queried by Omnia.") {
                        ForEach(Array(store.installedAddons.enumerated()), id: \.element.id) { index, addon in
                            if index != 0 { SettingsDivider() }
                            SettingsToggleRow(
                                title: addon.manifest.name,
                                detail: addon.manifest.description,
                                symbol: "puzzlepiece.extension.fill",
                                tint: .indigo,
                                isOn: Binding(
                                    get: { addon.isEnabled },
                                    set: { _ in store.toggleAddon(id: addon.id) }
                                )
                            )
                        }
                    }
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Add-ons")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Add-on", systemImage: "plus") { showingAddAddon = true }
            }
        }
        .sheet(isPresented: $showingAddAddon) {
            AddAddonSheet()
        }
    }
}

struct CatalogsSettingsView: View {
    @Environment(OmniaStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Built-in") {
                    SettingsStaticRow(
                        title: "TMDB + TVDB",
                        detail: "Omnia’s default curated catalogs",
                        symbol: "sparkles",
                        tint: .blue,
                        status: "Default"
                    )
                }

                if store.installedAddons.isEmpty {
                    SettingsEmptyState(
                        title: "No Add-on Catalogs",
                        message: "When you add an add-on, its declared catalogs will appear here for individual control.",
                        symbol: "rectangle.stack.badge.plus"
                    )
                } else {
                    ForEach(store.installedAddons) { addon in
                        if !addon.manifest.catalogs.isEmpty {
                            SettingsGroup(
                                title: addon.manifest.name,
                                footer: addon.isEnabled ? nil : "Enable this add-on before any of its catalogs can appear in Discover."
                            ) {
                                ForEach(Array(addon.manifest.catalogs.enumerated()), id: \.element.id) { index, catalog in
                                    if index != 0 { SettingsDivider() }
                                    SettingsToggleRow(
                                        title: catalog.name ?? catalog.id,
                                        detail: "\(catalog.type.capitalized) catalog",
                                        symbol: "rectangle.stack",
                                        tint: .indigo,
                                        isOn: Binding(
                                            get: { store.isCatalogEnabled(for: addon, catalog: catalog) },
                                            set: { _ in store.toggleCatalog(for: addon, catalog: catalog) }
                                        ),
                                        isDisabled: !addon.isEnabled
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Catalogs")
    }
}

private struct MetadataSettingsView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Providers") {
                    ForEach(Array(MetadataProvider.supported.enumerated()), id: \.element.id) { index, provider in
                        if index != 0 { SettingsDivider() }
                        NavigationLink {
                            MetadataProviderDetailView(provider: provider)
                        } label: {
                            SettingsNavigationRow(
                                title: provider.name,
                                detail: provider.summary,
                                symbol: "rectangle.3.group.fill",
                                tint: provider.credentialStrategy == .backendManaged ? .teal : .orange,
                                providerMarks: [provider.id]
                            )
                        }
                    }
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Metadata")
    }
}

private struct MetadataProviderDetailView: View {
    let provider: MetadataProvider
    @State private var key = ""
    @State private var saved = false

    private var keychainAccount: String { "provider.\(provider.id).apiKey" }

    var body: some View {
        Form {
            Section("About") {
                Text(provider.summary)
            }

            Section("Connection") {
                if provider.credentialStrategy == .backendManaged {
                    LabeledContent("Credential source", value: "Omnia backend")
                    Text("The shared credential is kept outside the app. This connection becomes available when Omnia’s secure backend is configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SecureField("API Key", text: $key)
                        .textContentType(.password)
                    Button(saved ? "Saved" : "Save Key") { saveKey() }
                        .disabled(key.isEmpty)
                }
            }
        }
        .navigationTitle(provider.name)
        .onAppear { loadKey() }
    }

    private func loadKey() {
        key = (try? KeychainStore.value(account: keychainAccount)) ?? ""
    }

    private func saveKey() {
        try? KeychainStore.save(key, account: keychainAccount)
        saved = true
    }
}

private struct IntegrationsSettingsView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Tracking") {
                    SettingsStaticRow(
                        title: "Trakt",
                        detail: "Requires OAuth credentials before connection",
                        symbol: "checkmark.circle.fill",
                        tint: .red,
                        status: "Not configured"
                    )
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Services")
    }
}

private struct AccountSettingsView: View {
    @Environment(OmniaAccount.self) private var account

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let user = account.user {
                    SettingsGroup(title: "Signed In") {
                        SettingsValueRow(title: "Account", value: user.email ?? user.id.uuidString)
                        SettingsDivider()
                        SettingsValueRow(title: "Provider", value: user.provider?.capitalized ?? "Omnia")
                    }

                    Button("Sign Out", role: .destructive) {
                        Task { await account.signOut() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(account.isWorking)
                } else {
                    SettingsGroup(title: "Cloud Account") {
                        ForEach(Array(OmniaAccount.Provider.allCases.enumerated()), id: \.element.id) { index, provider in
                            if index != 0 { SettingsDivider() }
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
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary.opacity(0.45))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .disabled(account.isWorking || !account.isConfigured)
                        }
                    }
                }

                if let errorMessage = account.errorMessage {
                    SettingsEmptyState(title: "Account Connection", message: errorMessage, symbol: "exclamationmark.triangle.fill")
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Account")
    }
}

private struct PlaybackSettingsView: View {
    @AppStorage("resume-playback") private var resumePlayback = true
    @AppStorage("playback-completion-threshold") private var completionThreshold = 95
    #if os(iOS)
    @AppStorage("picture-in-picture") private var allowsPictureInPicture = true
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Playback") {
                    SettingsToggleRow(title: "Resume where you left off", detail: "Continue from your saved progress", symbol: "arrow.clockwise", tint: .orange, isOn: $resumePlayback)
                    #if os(iOS)
                    SettingsDivider()
                    SettingsToggleRow(title: "Picture in Picture", detail: "Allow video to continue in a floating window", symbol: "pip.enter", tint: .orange, isOn: $allowsPictureInPicture)
                    #endif
                }
                SettingsGroup(title: "Completion") {
                    Picker("Mark a title watched", selection: $completionThreshold) {
                        Text("80% watched").tag(80)
                        Text("90% watched").tag(90)
                        Text("95% watched").tag(95)
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                SettingsGroup(title: "Player") {
                    SettingsValueRow(title: "Controls", value: "Platform native")
                    SettingsDivider()
                    SettingsValueRow(title: "Streaming", value: "AVFoundation")
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Playback")
    }
}

private struct LibraryPreferencesSettingsView: View {
    @AppStorage("library-sort") private var savedSortOrder = LibrarySortOrder.recentAdded.rawValue
    @AppStorage("home-show-continue-watching") private var showsContinueWatching = true
    @AppStorage("home-show-movie-shelf") private var showsMovieShelf = true
    @AppStorage("home-show-series-shelf") private var showsSeriesShelf = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Library") {
                    Picker("Default order", selection: $savedSortOrder) {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                SettingsGroup(title: "Home") {
                    SettingsToggleRow(title: "Continue Watching", detail: "Show titles with saved progress", symbol: "play.rectangle.fill", tint: .orange, isOn: $showsContinueWatching)
                    SettingsDivider()
                    SettingsToggleRow(title: "Movies", detail: "Show the built-in movie shelf", symbol: "film.fill", tint: .indigo, isOn: $showsMovieShelf)
                    SettingsDivider()
                    SettingsToggleRow(title: "Series", detail: "Show the built-in series shelf", symbol: "tv.fill", tint: .teal, isOn: $showsSeriesShelf)
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Library & Home")
    }
}

private struct AppearanceSettingsView: View {
    @Environment(OmniaStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Theme") {
                    Picker("Appearance", selection: Binding(
                        get: { store.appearance },
                        set: { store.appearance = $0 }
                    )) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .padding(14)
                }

                SettingsGroup(title: "Interface") {
                    SettingsValueRow(title: "Mode", value: store.appearance.title)
                    SettingsDivider()
                    SettingsValueRow(title: "Materials", value: "Liquid Glass")
                }
            }
            .omniaSettingsPageLayout()
        }
        .navigationTitle("Appearance")
    }
}

private extension View {
    @ViewBuilder
    func omniaSettingsPageLayout() -> some View {
        #if os(macOS)
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        #else
        self
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 24)
        #endif
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .buttonStyle(.plain)
            .background { SettingsSurface() }

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var providerMarks: [String] = []
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if !providerMarks.isEmpty {
                ProviderMarkStack(providerIDs: providerMarks)
            } else {
                SettingsIcon(symbol: symbol, tint: tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct SettingsStaticRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Color.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
    }
}

/// Provider marks are bundled with Omnia so the settings list works offline.
/// They render as templates to avoid turning settings icons into coloured tiles.
private struct ProviderMarkStack: View {
    let providerIDs: [String]

    var body: some View {
        HStack(spacing: providerIDs.count > 1 ? 3 : 0) {
            ForEach(providerIDs, id: \.self) { providerID in
                ProviderMark(providerID: providerID, compact: providerIDs.count > 1)
            }
        }
        .frame(width: 30, height: 30)
    }
}

private struct ProviderMark: View {
    let providerID: String
    var compact = false

    private var assetName: String? {
        switch providerID {
        case "tmdb": "TMDBMark"
        case "tvdb": "TheTVDBMark"
        case "mdblist": "MDBListMark"
        case "anilist": "AniListMark"
        default: nil
        }
    }

    private var label: String {
        switch providerID {
        case "tmdb": "TMDB"
        case "tvdb": "TheTVDB"
        case "mdblist": "MDBList"
        case "anilist": "AniList"
        case "publicmetadb": "PublicMetaDB"
        default: providerID
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
                // PublicMetaDB does not publish a provider mark; keep its
                // entry neutral until it supplies an official asset.
                Image(systemName: "cylinder.split.1x2")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(.primary)
        .frame(width: compact ? 13 : 26, height: compact ? 18 : 26)
        .accessibilityLabel(label)
    }
}

private struct AccountProviderMark: View {
    let provider: OmniaAccount.Provider

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
        .foregroundStyle(.primary)
        .frame(width: 30, height: 30)
        .accessibilityLabel(provider.title)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 56)
    }
}

private struct SettingsSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            #if os(macOS)
            .fill(Color.primary.opacity(0.055))
            #else
            .fill(.thinMaterial)
            #endif
    }
}

private struct SettingsEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background { SettingsSurface() }
    }
}

private struct AddAddonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OmniaStore.self) private var store
    @State private var address = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/manifest.json", text: $address)
                } header: {
                    Text("Manifest URL")
                } footer: {
                    Text("Add only sources you trust. Omnia validates the manifest and only uses HTTPS endpoints.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Add-on")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addAddon() }
                        .disabled(address.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading { ProgressView("Validating manifest…") }
            }
        }
    }

    private func addAddon() {
        guard let url = URL(string: address) else {
            errorMessage = "Enter a valid HTTPS manifest URL."
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let manifest = try await StremioAddonClient.fetchManifest(from: url)
                store.add(.init(manifest: manifest, manifestURL: url, isEnabled: true, addedAt: .now))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(OmniaStore.preview)
}
