//
//  TrackerSettingsView.swift
//  Omnia
//

import SwiftUI

/// A tracker's row in Settings › Integrations.
struct TrackerLinkRow: View {
    let kind: TrackerKind
    @State private var trackers = TrackerAccountStore.shared

    var body: some View {
        NavigationLink {
            SettingsDestinationView(route: .tracker(kind))
        } label: {
            HStack(spacing: 12) {
                TrackerMark(kind: kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsLinkRow()
    }

    private var status: String {
        guard trackers.isConnected(kind) else { return "Not connected" }
        return trackers.scrobbles(kind) ? "Connected · Scrobbling" : "Connected · Scrobbling off"
    }
}

struct TrackerMark: View {
    let kind: TrackerKind

    var body: some View {
        Group {
            if let assetName = kind.assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                // PublicMetaDB's favicon: its wordmark on a light tile.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.92))
                    .overlay {
                        Text("pmdb")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(-0.5)
                            .foregroundStyle(Color(white: 0.04))
                    }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Settings › Integrations › Trakt, Simkl or PublicMetaDB, like Nuvio's:
/// connect with a code shown here (or, for PublicMetaDB, an API key),
/// choose whether to scrobble, disconnect.
struct TrackerSettingsView: View {
    let kind: TrackerKind

    @Environment(\.openURL) private var openURL
    @State private var trackers = TrackerAccountStore.shared
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var apiKey = ""

    private var isConnected: Bool { trackers.isConnected(kind) }

    var body: some View {
        OmniaSettingsForm {
            if isConnected {
                connectedSections
            } else if kind.usesAPIKey {
                apiKeySection
            } else {
                appSection
                connectSection
            }
        }
        .omniaNavigationTitle(kind.title)
        .onAppear {
            if clientID.isEmpty { clientID = trackers.credentials[kind]?.clientID ?? "" }
        }
    }

    // MARK: Not connected

    private var appSection: some View {
        Section {
            TextField("Client ID", text: $clientID)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if kind.needsClientSecret {
                SecureField("Client Secret", text: $clientSecret)
            }
            Button("Create an App on \(kind.title)", systemImage: "arrow.up.right.square") {
                openURL(kind.applicationURL)
            }
        } header: {
            Text("Your \(kind.title) App")
        } footer: {
            Text("\(kind.applicationGuidance) They stay in Keychain on this device; Omnia doesn't ship its own.")
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("API Key", text: $apiKey)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Get a Key on \(kind.title)", systemImage: "arrow.up.right.square") {
                openURL(kind.applicationURL)
            }
            switch trackers.connectState(kind) {
            case .requestingCode:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking the key with \(kind.title)…")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                connectWithKeyButton
            case .idle, .waiting:
                connectWithKeyButton
            }
        } header: {
            Text("Your \(kind.title) Key")
        } footer: {
            Text("\(kind.applicationGuidance) It stays in Keychain on this device. \(kind.summary)")
        }
    }

    private var connectWithKeyButton: some View {
        Button("Connect \(kind.title)", systemImage: "link") {
            trackers.connect(kind, apiKey: apiKey)
        }
        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            switch trackers.connectState(kind) {
            case .idle:
                Button("Connect \(kind.title)", systemImage: "link") {
                    trackers.connect(kind, clientID: clientID, clientSecret: clientSecret)
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty
                          || (kind.needsClientSecret && clientSecret.trimmingCharacters(in: .whitespaces).isEmpty))
            case .requestingCode:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Asking \(kind.title) for a code…")
                }
            case .waiting(let code):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Go to \(code.verificationURL.absoluteString) and enter this code:")
                    Text(code.userCode)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to approve Omnia…")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Open \(kind.title)", systemImage: "safari") { openURL(code.verificationURL) }
                Button("Cancel", role: .cancel) { trackers.cancelConnect(kind) }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Try Again", systemImage: "arrow.clockwise") {
                    trackers.connect(kind, clientID: clientID, clientSecret: clientSecret)
                }
            }
        } header: {
            Text("Connect")
        } footer: {
            Text(kind.summary)
        }
    }

    // MARK: Connected

    @ViewBuilder
    private var connectedSections: some View {
        Section {
            Toggle(isOn: Binding(
                get: { trackers.scrobbles(kind) },
                set: { trackers.setScrobbles($0, for: kind) }
            )) {
                Text("Scrobble Playback")
                Text(kind.usesAPIKey
                     ? "Save where you stop to \(kind.title). Titles stopped past 80% are logged as watched."
                     : "Tell \(kind.title) what you're watching. Titles stopped past 80% are marked watched.")
            }
            if let error = trackers.lastScrobbleError[kind] {
                Label("Last scrobble failed: \(error)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Label {
                Text("Connected")
            } icon: {
                TrackerMark(kind: kind)
            }
        } footer: {
            Text("Movies and episodes need an IMDb, TMDB or TVDB ID to be scrobbled; Live TV isn't.")
        }

        Section {
            Button("Disconnect \(kind.title)", role: .destructive) {
                trackers.disconnect(kind)
            }
        } footer: {
            Text(kind.usesAPIKey
                 ? "Removes your \(kind.title) API key from this device."
                 : "Removes your \(kind.title) app details and sign-in from this device.")
        }
    }
}
