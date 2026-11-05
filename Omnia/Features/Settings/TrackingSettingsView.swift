//
//  TrackingSettingsView.swift
//  Omnia
//

import SwiftUI

/// Settings › Account › Tracking, laid out like Nuvio's (Dafa, 2026-10-27):
/// a card per tracker account, then where the Library, Continue Watching and
/// More Like This come from, then Trakt's own features. Trakt, Simkl and
/// MDBList connect with a code entered on their site, AniList in the
/// browser, PublicMetaDB with its API key.
struct TrackingSettingsView: View {
    @Environment(OmniaAccount.self) private var account
    @State private var library = TrackerLibraryStore.shared

    let showsAdvanced: Bool

    init(showsAdvanced: Bool = false) {
        self.showsAdvanced = showsAdvanced
    }

    var body: some View {
        Group {
            if showsAdvanced {
                OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Library Source",
                    subtitle: "Choose which source Omnia reads for your Library",
                    selection: $library.watchlistSource,
                    options: options(library.availableWatchlistSources, including: library.watchlistSource)
                ) { sourceTitle($0, isLibrary: true) }
                .settingsRow("Library Source")
                SettingsDropdown(
                    "Watch Progress",
                    subtitle: "Choose which progress source powers resume and Continue Watching",
                    selection: $library.continueWatchingSource,
                    options: options(library.availableSources, including: library.continueWatchingSource)
                ) { sourceTitle($0, isLibrary: false) }
                .settingsRow("Watch Progress")
                SettingsDropdown(
                    "More Like This Source",
                    subtitle: "Choose where recommendations come from on title pages",
                    selection: $library.moreLikeThisSource,
                    options: MoreLikeThisSource.allCases
                ) { $0.title }
                .settingsRow("More Like This Source")
                .disabled(TraktExtrasClient.clientID == nil && library.moreLikeThisSource == .tmdb)
                SettingsDropdown(
                    "Continue Watching Window",
                    subtitle: library.effectiveSource(library.continueWatchingSource).tracker == .trakt
                        ? "Only titles paused on Trakt within this time"
                        : "Available when Trakt is the Watch Progress source",
                    selection: $library.traktContinueWatchingDays,
                    options: TrackerLibraryStore.traktContinueWatchingDayOptions
                ) { $0 == 0 ? "All" : "\($0) days" }
                .settingsRow("Continue Watching Window")
                .disabled(library.effectiveSource(library.continueWatchingSource).tracker != .trakt)
                ForEach(TrackerKind.allCases) { kind in
                    TrackerSyncStatusLine(kind: kind)
                }
            } header: {
                Text("Where Omnia Reads From")
            } footer: {
                Text("A tracker's lists are read from your account there, and what you play is scrobbled back to it. Omnia keeps its own progress \(account.user != nil ? "in your Omnia account" : "on this device") either way.")
            }

            Section {
                Toggle(isOn: $library.showsTraktComments) {
                    Text("Comments")
                    Text("Show Trakt reviews on title pages")
                }
                .settingsRow("Comments")
                .disabled(TraktExtrasClient.clientID == nil)
            }
                }
            } else {
                OmniaSettingsForm {
            AccountBackupNotice()
            ForEach(Array(TrackerKind.allCases.enumerated()), id: \.element) { index, kind in
                Section {
                    TrackerAccountCard(kind: kind)
                        .padding(.horizontal, -12)
                        .padding(.vertical, -9)
                } header: {
                    if index == 0 { Text("Accounts") }
                }
            }

            Section {
                SettingsRouteLink(route: .advanced(.tracking), summary: nil)
            }
                }
            }
        }
        .omniaNavigationTitle(showsAdvanced ? "Advanced" : "Tracking")
        .task {
            for kind in TrackerKind.allCases where TrackerAccountStore.shared.isConnected(kind) {
                TrackerAccountStore.shared.refreshUsername(kind)
            }
        }
    }

    private func options(
        _ available: [TrackerLibrarySource],
        including current: TrackerLibrarySource
    ) -> [TrackerLibrarySource] {
        available.contains(current) ? available : available + [current]
    }

    private func sourceTitle(_ source: TrackerLibrarySource, isLibrary: Bool) -> String {
        switch source {
        case .local: isLibrary ? "Omnia Library" : "Omnia Sync"
        case .localAniList: "Omnia + AniList Anime"
        case .traktAniList: "Trakt + AniList Anime"
        default: source.tracker?.title ?? source.title
        }
    }
}

/// One tracker's account card: connected with its name, or the sign-in in
/// progress, as Nuvio's Tracking cards.
private struct TrackerAccountCard: View {
    let kind: TrackerKind

    @Environment(\.openURL) private var openURL
    @Environment(OmniaStore.self) private var store
    @State private var trackers = TrackerAccountStore.shared
    @State private var library = TrackerLibraryStore.shared
    @State private var apiKey = ""
    @State private var confirmsDisconnect = false

    private var isConnected: Bool { trackers.isConnected(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TrackerMark(kind: kind, size: 30)
                Text(kind.title)
                    .font(.title2.weight(.bold))
                Spacer(minLength: 0)
            }

            if isConnected {
                connected
            } else {
                signIn
            }

            Button("Visit \(kind.title)") { openURL(kind.websiteURL) }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .confirmationDialog("Disconnect \(kind.title)?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { trackers.disconnect(kind) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Omnia stops reading from and scrobbling to \(kind.title), and removes its sign-in from this device. Your \(kind.title) account isn't changed.")
        }
    }

    // MARK: Connected

    @ViewBuilder
    private var connected: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trackers.credentials[kind]?.username.map { "Connected as \($0)" } ?? "Connected")
                .font(.headline)
            Text(kind.summary)
                .font(.callout)
                .opacity(0.85)
        }
        Toggle(isOn: Binding(get: { trackers.scrobbles(kind) }, set: { trackers.setScrobbles($0, for: kind) })) {
            Text("Scrobble Playback")
        }
        .settingsRow("Scrobble Playback")
        .toggleStyle(OmniaSwitchToggleStyle())
        if let error = trackers.lastScrobbleError[kind] {
            Label("Last scrobble failed: \(error)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
        }
        HStack(spacing: 10) {
            Button {
                library.sync(kind, addons: store.installedAddons)
                trackers.refreshUsername(kind)
            } label: {
                Label(library.state(kind) == .syncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(library.state(kind) == .syncing)
            Button("Disconnect", role: .destructive) { confirmsDisconnect = true }
        }
        .buttonStyle(TrackerCardButtonStyle(prominent: false))
    }

    // MARK: Signing in

    @ViewBuilder
    private var signIn: some View {
        switch trackers.connectState(kind) {
        case .idle:
            notConnected
        case .requestingCode:
            OmniaLoadingRow(kind.usesAPIKey ? "Checking the key with \(kind.title)…" : "Asking \(kind.title) for a code…")
        case .waiting(let code):
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter this code on \(kind.title)")
                    .font(.headline)
                Text("Open \(kind.title) and enter this code to approve Omnia. This card updates on its own.")
                    .font(.callout)
                    .opacity(0.85)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(code.userCode)
                    .font(.title.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Text(code.verificationURL.absoluteString)
                    .font(.callout)
                    .opacity(0.85)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            Button("Open \(kind.title)") { openURL(code.verificationURL) }
                .buttonStyle(TrackerCardButtonStyle(prominent: true))
            Button("Cancel") { trackers.cancelConnect(kind) }
                .buttonStyle(TrackerCardButtonStyle(prominent: false))
        case .waitingForBrowser:
            VStack(alignment: .leading, spacing: 4) {
                Text("Finish signing in on \(kind.title)")
                    .font(.headline)
                Text("Approve Omnia in your browser; it brings you back here when done.")
                    .font(.callout)
                    .opacity(0.85)
            }
            Button("Open \(kind.title) Again") { startBrowserSignIn() }
                .buttonStyle(TrackerCardButtonStyle(prominent: true))
            Button("Cancel") { trackers.cancelConnect(kind) }
                .buttonStyle(TrackerCardButtonStyle(prominent: false))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
            notConnected
        }
    }

    @ViewBuilder
    private var notConnected: some View {
        Text(kind.summary)
            .font(.callout)
            .opacity(0.85)
        switch kind.connection {
        case .apiKey:
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.primary)
            HStack(spacing: 10) {
                Button("Connect") { trackers.connect(kind, apiKey: apiKey) }
                    .buttonStyle(TrackerCardButtonStyle(prominent: true))
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if let url = kind.apiKeyURL {
                    Button("Get a Key") { openURL(url) }
                        .buttonStyle(TrackerCardButtonStyle(prominent: false))
                }
            }
        case .code:
            Button("Connect \(kind.title)") { trackers.connect(kind) }
                .buttonStyle(TrackerCardButtonStyle(prominent: true))
                .disabled(!trackers.isAvailable(kind))
            if !trackers.isAvailable(kind) { unavailableNote }
        case .browser:
            Button("Sign In with \(kind.title)") { startBrowserSignIn() }
                .buttonStyle(TrackerCardButtonStyle(prominent: true))
                .disabled(!trackers.isAvailable(kind))
            if !trackers.isAvailable(kind) { unavailableNote }
        }
    }

    private var unavailableNote: some View {
        Text("This build of Omnia doesn't include its \(kind.title) app yet.")
            .font(.caption)
            .opacity(0.85)
    }

    private func startBrowserSignIn() {
        if let url = trackers.beginBrowserSignIn(kind) { openURL(url) }
    }

    // MARK: Look

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .bottomTrailing) {
                TrackerMark(kind: kind, size: 110)
                    .opacity(0.08)
                    .padding(16)
                    .accessibilityHidden(true)
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    /// Each tracker's brand colours, as Nuvio's cards.
    private var gradient: [Color] {
        let hexes: [String] = switch kind {
        case .trakt: ["7B2FBF", "E63A3A"]
        case .simkl: ["2A2A2E", "131315"]
        case .mdblist: ["1D3F78", "3366B0"]
        case .pmdb: ["3A3A40", "1C1C20"]
        case .anilist: ["152232", "02A9FF"]
        }
        return hexes.map { Color(omniaHex: $0) ?? .gray }
    }
}

/// Nuvio's card buttons: a white filled one for the main action, an
/// outlined one for the rest.
private struct TrackerCardButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.vertical, 9)
            .padding(.horizontal, 18)
            .frame(maxWidth: prominent ? .infinity : nil)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background {
                Capsule().fill(prominent ? Color.white : Color.clear)
                Capsule().strokeBorder(Color.white.opacity(prominent ? 0 : 0.6), lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

struct TrackerMark: View {
    let kind: TrackerKind
    var size: CGFloat = 24

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
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
