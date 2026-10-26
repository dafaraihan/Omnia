//
//  MediaServersSettingsView.swift
//  Omnia
//

import SwiftUI

/// The server's own logo, Jellyfin's or Emby's, in its own colours.
private struct MediaServerMark: View {
    let kind: MediaServerKind

    var body: some View {
        Image(kind == .jellyfin ? "JellyfinMark" : "EmbyMark")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// Settings › Content & Discovery › Media Servers, as in Nuvio: connected
/// servers, then Add Server for Jellyfin and Emby.
struct MediaServersSettingsView: View {
    @State private var servers = MediaServerStore.shared
    @State private var signInKind: MediaServerKind?

    var body: some View {
        OmniaSettingsForm {
            Section {
                if servers.connections.isEmpty {
                    Text("No servers connected yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(servers.connections) { connection in
                    NavigationLink {
                        MediaServerDetailView(connectionID: connection.id)
                    } label: {
                        LabeledContent {
                            Text(status(of: connection))
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connection.name)
                                    Text(connection.identity)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                MediaServerMark(kind: connection.kind)
                            }
                        }
                    }
                }
            } header: {
                Text("Servers")
            }

            Section {
                ForEach(MediaServerKind.allCases) { kind in
                    Button {
                        signInKind = kind
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayName)
                                    .foregroundStyle(.primary)
                                Text("Sign in with your server address and \(kind.displayName) user.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            MediaServerMark(kind: kind)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Add Server")
            } footer: {
                Text("Jellyfin \(MediaServerKind.jellyfin.minimumVersion) and Emby \(MediaServerKind.emby.minimumVersion) or later. Plain http:// addresses work only for servers on your local network.")
            }
        }
        .omniaNavigationTitle("Media Servers")
        .sheet(item: $signInKind) { kind in
            MediaServerSignInSheet(kind: kind, address: "", username: "")
        }
    }

    private func status(of connection: MediaServerConnection) -> String {
        if !connection.isEnabled { return "Disabled" }
        if !servers.hasToken(connection) { return "Sign in again" }
        return servers.failures[connection.id]?.status ?? ""
    }
}

/// One server: Enabled, Use Add-on Metadata, Import Watch Progress, its
/// libraries, Sign In Again and Remove (Nuvio's server page).
private struct MediaServerDetailView: View {
    let connectionID: String

    @State private var servers = MediaServerStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false
    @State private var showsSignIn = false
    @State private var showsRemoveConfirmation = false

    var body: some View {
        if let connection = servers.connection(id: connectionID) {
            content(connection)
        } else {
            ContentUnavailableView("Server Removed", systemImage: "server.rack")
        }
    }

    private func content(_ connection: MediaServerConnection) -> some View {
        OmniaSettingsForm {
            Section {
                LabeledContent("Server", value: connection.address.host ?? connection.name)
                LabeledContent("Signed In As", value: connection.identity)
                if let failure = servers.failures[connection.id] {
                    Label(failure.errorDescription ?? failure.status, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                toggle(
                    "Enabled",
                    detail: "Show this server in Home, search, and stream results.",
                    isOn: connection.isEnabled
                ) { servers.setEnabled($0, for: connectionID) }

                toggle(
                    "Use Add-on Metadata",
                    detail: "Titles open with your add-ons' details like any other catalog title, with playback still from \(connection.name). Some titles may not match if your add-ons identify them differently.",
                    isOn: connection.usesAddonMetadata
                ) { servers.setUsesAddonMetadata($0, for: connectionID) }

                toggle(
                    "Import Watch Progress",
                    detail: "Add titles you're watching in \(connection.kind.displayName) to Continue Watching.",
                    isOn: connection.importsWatchProgress
                ) { servers.setImportsWatchProgress($0, for: connectionID) }
            }

            Section {
                if connection.libraries.isEmpty {
                    Text("No movie or series libraries are available to this user.")
                        .foregroundStyle(.secondary)
                }
                ForEach(connection.libraries) { library in
                    Toggle(isOn: Binding(
                        get: { library.isSelected },
                        set: { servers.setLibrary(library.id, selected: $0, in: connectionID) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.name)
                            Text(library.kind.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                Button {
                    isRefreshing = true
                    Task {
                        await servers.refreshLibraries(connectionID)
                        isRefreshing = false
                    }
                } label: {
                    HStack {
                        Text("Refresh Libraries")
                        if isRefreshing {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text("Libraries")
            } footer: {
                Text("Selected libraries appear in Home rows, search, and stream results.")
            }

            Section {
                Button("Sign In Again") { showsSignIn = true }
                Button("Remove Server", role: .destructive) { showsRemoveConfirmation = true }
            }
        }
        .omniaNavigationTitle(connection.name)
        .sheet(isPresented: $showsSignIn) {
            MediaServerSignInSheet(
                kind: connection.kind,
                address: connection.address.absoluteString,
                username: connection.userName
            )
        }
        .confirmationDialog("Remove This Server?", isPresented: $showsRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Server", role: .destructive) {
                Task {
                    await servers.remove(connectionID)
                    dismiss()
                }
            }
        } message: {
            Text("This signs you out of \(connection.name) on this device. You can add it back anytime.")
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

/// Nuvio's sign-in sheet: address, username and password. The password is
/// only used to sign in and is never saved.
private struct MediaServerSignInSheet: View {
    let kind: MediaServerKind

    @Environment(\.dismiss) private var dismiss
    @State private var servers = MediaServerStore.shared
    @State private var address: String
    @State private var username: String
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    init(kind: MediaServerKind, address: String, username: String) {
        self.kind = kind
        _address = State(initialValue: address)
        _username = State(initialValue: username)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server Address", text: $address, prompt: Text(verbatim: "http://192.168.1.10:8096"))
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
                } footer: {
                    Text("Enter your server address and the \(kind.displayName) user to sign in with. Your password is only used to sign in.")
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sign In to \(kind.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Connect", action: connect)
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 320)
        #endif
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await servers.signIn(kind: kind, address: address, username: username, password: password)
                password = ""
                isConnecting = false
                dismiss()
            } catch {
                isConnecting = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not connect to the server."
            }
        }
    }
}
