//
//  LiveTVSettingsView.swift
//  Omnia
//

import SwiftUI
import UniformTypeIdentifiers

/// Settings › Content & Discovery › Live TV, as in Nuvio Enhanced:
/// Navigation, Manual Reload, Providers, Playlists and TV Guide.
struct LiveTVSettingsView: View {
    @State private var live = LiveTVStore.shared

    @State private var playlistName = ""
    @State private var playlistAddress = ""
    @State private var playlistError: String?
    @State private var importsFile = false
    @State private var editingPlaylist: LiveTVPlaylist?
    @State private var guideName = ""
    @State private var guideAddress = ""
    @State private var guideError: String?
    @State private var isReloadingChannels = false
    @State private var isReloadingGuide = false



    var body: some View {
        Group {
            OmniaSettingsForm {
            AccountBackupNotice()
            Section {
                Toggle(isOn: Binding(
                    get: { live.configuration.showsInNavigation },
                    set: { live.setShowsInNavigation($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Live TV in Navigation")
                        Text("Adds Live TV between Discover and Settings once a playlist or provider is set up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsRow("Show Live TV in Navigation")
                .toggleStyle(OmniaSwitchToggleStyle())
            } header: {
                Text("Navigation")
            }

            Section {
                reloadRow(
                    "Reload Channels",
                    status: live.channelsStatus,
                    isRunning: isReloadingChannels || live.channelState == .loading
                ) {
                    isReloadingChannels = true
                    await live.reloadChannels()
                    isReloadingChannels = false
                }
                .disabled(!live.hasSources)
                reloadRow(
                    "Reload TV Guide",
                    status: live.guideStatus,
                    isRunning: isReloadingGuide || live.guideState == .loading
                ) {
                    isReloadingGuide = true
                    await live.reloadGuide()
                    isReloadingGuide = false
                }
                .disabled(live.channels.isEmpty)
            } header: {
                Text("Manual Reload")
            } footer: {
                Text("Channels are saved on this device and the TV guide is refreshed once a day.")
            }

            XtreamProviderSection()
            StalkerProviderSection()

            Section {
                if live.configuration.playlists.isEmpty {
                    Text("No playlists yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(live.configuration.playlists) { playlist in
                    playlistRow(playlist)
                }
                TextField("Name (Optional)", text: $playlistName, prompt: Text(verbatim: "My Playlist"))
                TextField("Playlist URL", text: $playlistAddress, prompt: Text(verbatim: "https://example.com/playlist.m3u"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(addPlaylist)
                if let playlistError {
                    Label(playlistError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Add URL", systemImage: "link.badge.plus", action: addPlaylist)
                        .disabled(playlistAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Add Local M3U", systemImage: "doc.badge.plus") { importsFile = true }
                }
                #if os(iOS)
                // In an iOS Form a tap on the row fires every button in it.
                .buttonStyle(.borderless)
                #endif
            } header: {
                Text("Playlists")
            } footer: {
                Text("M3U playlists by address or from a file. Addresses are kept in your Keychain and files in Omnia's encrypted storage. Plain http:// addresses work too, but they aren't encrypted, so use https:// when your provider offers it.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { live.configuration.autoDetectsGuides },
                    set: { live.setAutoDetectsGuides($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Detect Guides")
                        Text("Use the guides your playlists and providers name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsRow("Auto-Detect Guides")
                .toggleStyle(OmniaSwitchToggleStyle())
                ForEach(live.configuration.guides) { source in
                    guideRow(source)
                }
                TextField("Name (Optional)", text: $guideName, prompt: Text(verbatim: "My Guide"))
                TextField("XMLTV URL", text: $guideAddress, prompt: Text(verbatim: "https://example.com/guide.xml.gz"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(addGuide)
                if let guideError {
                    Label(guideError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("Add Guide", systemImage: "plus", action: addGuide)
                    .disabled(guideAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("TV Guide (EPG)")
            } footer: {
                Text(live.guideStatus)
            }
                }
        }
        .omniaNavigationTitle("Live TV")
        .fileImporter(
            isPresented: $importsFile,
            allowedContentTypes: Self.playlistTypes
        ) { result in
            guard case let .success(url) = result else { return }
            playlistError = nil
            Task {
                do {
                    try await live.addLocalPlaylist(from: url)
                } catch {
                    playlistError = (error as? LocalizedError)?.errorDescription ?? "Omnia couldn't read that file."
                }
            }
        }
        .sheet(item: $editingPlaylist) { playlist in
            LiveTVPlaylistEditSheet(playlist: playlist)
        }
    }

    private static let playlistTypes: [UTType] = [
        UTType(filenameExtension: "m3u"),
        UTType(filenameExtension: "m3u8"),
        .plainText
    ].compactMap { $0 }

    private func reloadRow(
        _ title: String,
        status: String,
        isRunning: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    private func playlistRow(_ playlist: LiveTVPlaylist) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { playlist.isEnabled },
                set: { live.setPlaylistEnabled($0, id: playlist.id) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                    Text(playlist.kind == .localFile ? "Local file" : live.playlistHost(playlist) ?? "Playlist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let problem = live.sourceProblems[playlist.id] {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .toggleStyle(OmniaSwitchToggleStyle())
            Menu {
                Button("Edit", systemImage: "pencil") { editingPlaylist = playlist }
                Button("Remove", systemImage: "trash", role: .destructive) { live.removePlaylist(playlist.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func guideRow(_ source: LiveTVGuideSource) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { source.isEnabled },
                set: { live.setGuideEnabled($0, id: source.id) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                    Text(live.guideHost(source) ?? "XMLTV")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(OmniaSwitchToggleStyle())
            Button(role: .destructive) {
                live.removeGuide(source.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func addPlaylist() {
        playlistError = nil
        do {
            try live.addPlaylist(name: playlistName, address: playlistAddress)
            playlistName = ""
            playlistAddress = ""
        } catch {
            playlistError = (error as? LocalizedError)?.errorDescription ?? "That address can't be used."
        }
    }

    private func addGuide() {
        guideError = nil
        do {
            try live.addGuide(name: guideName, address: guideAddress)
            guideName = ""
            guideAddress = ""
        } catch {
            guideError = (error as? LocalizedError)?.errorDescription ?? "That address can't be used."
        }
    }
}

// MARK: Providers

private struct XtreamProviderSection: View {
    @State private var live = LiveTVStore.shared
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if let account = live.xtreamAccount {
                LabeledContent("Server", value: account.server.host ?? "Xtream")
                LabeledContent("Username", value: account.username)
                if let problem = live.sourceProblems[LiveTVXtreamClient.sourceID] {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("Disconnect", role: .destructive) { live.disconnectXtream() }
            } else {
                TextField("Server URL", text: $server, prompt: Text(verbatim: "https://provider.example:8080"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                TextField("Username", text: $username, prompt: Text(verbatim: "Username"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $password, prompt: Text(verbatim: "Password"))
                    .onSubmit(connect)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Connect", action: connect)
                        .disabled(isConnecting || server.isEmpty || username.isEmpty || password.isEmpty)
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Xtream Codes")
        } footer: {
            Text("Your provider's server address, username and password. They're kept in your Keychain.")
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await live.connectXtream(server: server, username: username, password: password)
                server = ""
                username = ""
                password = ""
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't connect to the server."
            }
            isConnecting = false
        }
    }
}

private struct StalkerProviderSection: View {
    @State private var live = LiveTVStore.shared
    @State private var portal = ""
    @State private var macAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if let account = live.stalkerAccount {
                LabeledContent("Portal", value: account.portal.host ?? "Stalker Portal")
                LabeledContent("MAC Address", value: account.macAddress)
                if let problem = live.sourceProblems[LiveTVStalkerClient.sourceID] {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("Disconnect", role: .destructive) { live.disconnectStalker() }
            } else {
                TextField("Portal URL", text: $portal, prompt: Text(verbatim: "https://portal.example/c/"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                TextField("MAC Address", text: $macAddress, prompt: Text(verbatim: "00:1A:79:00:00:00"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Username (Optional)", text: $username, prompt: Text(verbatim: "Username"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password (Optional)", text: $password, prompt: Text(verbatim: "Password"))
                    .onSubmit(connect)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Connect", action: connect)
                        .disabled(isConnecting || portal.isEmpty || macAddress.isEmpty)
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Stalker Portal")
        } footer: {
            Text("A MAG portal address and the MAC address registered with your provider.")
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await live.connectStalker(portal: portal, macAddress: macAddress, username: username, password: password)
                portal = ""
                macAddress = ""
                username = ""
                password = ""
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't connect to the portal."
            }
            isConnecting = false
        }
    }
}

// MARK: Edit playlist

private struct LiveTVPlaylistEditSheet: View {
    let playlist: LiveTVPlaylist

    @Environment(\.dismiss) private var dismiss
    @State private var live = LiveTVStore.shared
    @State private var name: String
    @State private var address: String
    @State private var errorMessage: String?

    init(playlist: LiveTVPlaylist) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
        _address = State(initialValue: LiveTVStore.shared.playlistAddress(playlist))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if playlist.kind == .url {
                    TextField("Playlist URL", text: $address)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 220)
        #endif
    }

    private func save() {
        do {
            try live.updatePlaylist(playlist.id, name: name, address: playlist.kind == .url ? address : nil)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "That address can't be used."
        }
    }
}
