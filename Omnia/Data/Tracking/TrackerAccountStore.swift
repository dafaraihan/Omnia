//
//  TrackerAccountStore.swift
//  Omnia
//

import Foundation
import Observation

/// Trakt, Simkl, MDBList, PublicMetaDB and AniList accounts, and scrobbling
/// what plays to them, as Nuvio does (Dafa, 2026-10-26). Users sign in with
/// Omnia's own apps (a code, or AniList in the browser) or, for
/// PublicMetaDB, their API key; tokens and keys stay in Keychain on this
/// device.
@Observable
@MainActor
final class TrackerAccountStore {
    static let shared = TrackerAccountStore()

    enum ConnectState: Equatable {
        case idle
        case requestingCode
        case waiting(TrackerDeviceCode)
        case waitingForBrowser
        case failed(String)
    }

    private(set) var credentials: [TrackerKind: TrackerCredentials] = [:]
    private(set) var connectStates: [TrackerKind: ConnectState] = [:]
    /// When the last scrobble failed, for Settings to show.
    private(set) var lastScrobbleError: [TrackerKind: String] = [:]

    @ObservationIgnored private var connectTasks: [TrackerKind: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scrobbleState: (key: String, action: TrackerScrobbleAction)?
    @ObservationIgnored private var lastUsernameRefresh = Date.distantPast

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for kind in TrackerKind.allCases {
            credentials[kind] = Self.loadCredentials(kind)
        }
    }

    // MARK: Accounts

    func isConnected(_ kind: TrackerKind) -> Bool { credentials[kind]?.isConnected == true }

    func connectState(_ kind: TrackerKind) -> ConnectState { connectStates[kind] ?? .idle }

    func scrobbles(_ kind: TrackerKind) -> Bool {
        defaults.object(forKey: Self.scrobbleKey(kind)) as? Bool ?? true
    }

    func setScrobbles(_ enabled: Bool, for kind: TrackerKind) {
        defaults.set(enabled, forKey: Self.scrobbleKey(kind))
        // Observation doesn't see UserDefaults; nudge the views.
        credentials[kind] = credentials[kind]
    }

    /// Whether this build has Omnia's own app for `kind` (from
    /// Config/Secrets.xcconfig).
    func isAvailable(_ kind: TrackerKind) -> Bool { TrackerAppCredentials.app(for: kind) != nil }

    /// Trakt, Simkl and MDBList: shows a code to enter on the tracker's site,
    /// then waits for the user to approve Omnia there.
    func connect(_ kind: TrackerKind) {
        guard kind.connection == .code else { return }
        guard let app = TrackerAppCredentials.app(for: kind) else {
            connectStates[kind] = .failed("This build of Omnia has no \(kind.title) app set up.")
            return
        }
        connectTasks[kind]?.cancel()
        connectStates[kind] = .requestingCode
        connectTasks[kind] = Task { [weak self] in
            do {
                let code = try await TrackerClient.requestDeviceCode(kind, clientID: app.clientID)
                guard !Task.isCancelled else { return }
                self?.connectStates[kind] = .waiting(code)
                await self?.waitForApproval(kind, code: code, app: app)
            } catch {
                guard !Task.isCancelled else { return }
                self?.connectStates[kind] = .failed(
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't reach \(kind.title)."
                )
            }
        }
    }

    /// PublicMetaDB's API key: checks it with PublicMetaDB, then keeps it.
    func connect(_ kind: TrackerKind, apiKey: String) {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind.usesAPIKey, !apiKey.isEmpty, apiKey.count <= 4096 else {
            connectStates[kind] = .failed("Enter your \(kind.title) API key.")
            return
        }
        connectTasks[kind]?.cancel()
        connectStates[kind] = .requestingCode
        connectTasks[kind] = Task { [weak self] in
            do {
                try await TrackerClient.validateAPIKey(kind, apiKey)
                guard !Task.isCancelled else { return }
                self?.store(TrackerCredentials(clientID: "", accessToken: apiKey), for: kind)
                self?.connectStates[kind] = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self?.connectStates[kind] = .failed(
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't reach \(kind.title)."
                )
            }
        }
    }

    /// AniList: the sign-in page to open in the browser. Its return link is
    /// accepted only while this sign-in is waiting.
    func beginBrowserSignIn(_ kind: TrackerKind) -> URL? {
        guard kind.connection == .browser else { return nil }
        guard let app = TrackerAppCredentials.app(for: kind),
              let url = TrackerClient.anilistAuthorizationURL(clientID: app.clientID)
        else {
            connectStates[kind] = .failed("This build of Omnia has no \(kind.title) app set up.")
            return nil
        }
        connectTasks[kind]?.cancel()
        connectStates[kind] = .waitingForBrowser
        return url
    }

    /// Handles omnia://anilist#access_token=…; true when the link was
    /// AniList's.
    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard let returned = TrackerClient.anilistToken(from: url) else { return false }
        let kind = TrackerKind.anilist
        guard connectState(kind) == .waitingForBrowser, let app = TrackerAppCredentials.app(for: kind) else { return true }
        connectStates[kind] = .requestingCode
        connectTasks[kind] = Task { [weak self] in
            do {
                try await TrackerClient.validateAPIKey(kind, returned.token)
                guard !Task.isCancelled else { return }
                var credentials = app
                credentials.accessToken = returned.token
                credentials.expiresAt = returned.expiresIn.map { Date.now.addingTimeInterval($0) }
                self?.store(credentials, for: kind)
                self?.connectStates[kind] = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self?.connectStates[kind] = .failed("AniList didn't accept the sign-in. Try again.")
            }
        }
        return true
    }

    func cancelConnect(_ kind: TrackerKind) {
        connectTasks[kind]?.cancel()
        connectTasks[kind] = nil
        connectStates[kind] = .idle
    }

    func disconnect(_ kind: TrackerKind) {
        cancelConnect(kind)
        try? KeychainStore.delete(account: Self.keychainAccount(kind))
        credentials[kind] = nil
        lastScrobbleError[kind] = nil
        TrackerLibraryStore.shared.forget(kind)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
    }

    private func waitForApproval(_ kind: TrackerKind, code: TrackerDeviceCode, app: TrackerCredentials) async {
        var interval = code.interval
        while !Task.isCancelled, Date.now < code.expiresAt {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            switch await TrackerClient.poll(kind, code: code, app: app) {
            case .pending:
                continue
            case .slowDown:
                interval += 5
            case .connected(let connected):
                store(connected, for: kind)
                connectStates[kind] = .idle
                return
            case .failed(let message):
                connectStates[kind] = .failed(message)
                return
            }
        }
        if !Task.isCancelled { connectStates[kind] = .failed("The code expired. Try again.") }
    }

    private func store(_ value: TrackerCredentials, for kind: TrackerKind) {
        credentials[kind] = value
        lastScrobbleError[kind] = nil
        if value.username == nil { refreshUsername(kind) }
        persist(value, for: kind)
    }

    private func persist(_ value: TrackerCredentials, for kind: TrackerKind) {
        credentials[kind] = value
        guard let data = try? JSONEncoder.tracker.encode(value), let text = String(data: data, encoding: .utf8) else { return }
        try? KeychainStore.save(text, account: Self.keychainAccount(kind))
        // The account's vault keeps sign-ins, so other devices connect too.
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
    }

    // MARK: Account vault

    /// The saved sign-in as the account vault stores it.
    func vaultValue(_ kind: TrackerKind) throws -> String? {
        try KeychainStore.value(account: Self.keychainAccount(kind))
    }

    /// A sign-in restored from the account vault, or removed there.
    func applyVaultValue(_ text: String?, for kind: TrackerKind) throws {
        guard let text else {
            try? KeychainStore.delete(account: Self.keychainAccount(kind))
            credentials[kind] = nil
            lastScrobbleError[kind] = nil
            TrackerLibraryStore.shared.forget(kind)
            return
        }
        guard let data = text.data(using: .utf8),
              let value = try? JSONDecoder.tracker.decode(TrackerCredentials.self, from: data)
        else { throw TrackerVaultError.unreadable }
        try KeychainStore.save(text, account: Self.keychainAccount(kind))
        credentials[kind] = value
        lastScrobbleError[kind] = nil
        if value.username == nil { refreshUsername(kind) }
    }

    enum TrackerVaultError: Error { case unreadable }

    /// The tracker's credentials with an expiring token refreshed (and kept)
    /// first, for reading lists.
    func validCredentials(_ kind: TrackerKind) async -> TrackerCredentials? {
        guard let current = credentials[kind], current.isConnected else { return nil }
        guard let refreshed = try? await TrackerClient.refreshIfNeeded(kind, current) else { return current }
        if refreshed != current, credentials[kind]?.accessToken == current.accessToken { persist(refreshed, for: kind) }
        return refreshed
    }

    /// At launch and when Omnia comes back to the front: every connected
    /// account's name, at most every ten minutes, silently.
    func refreshUsernamesIfStale() {
        guard Date.now.timeIntervalSince(lastUsernameRefresh) > 600 else { return }
        lastUsernameRefresh = .now
        for kind in TrackerKind.allCases where isConnected(kind) { refreshUsername(kind) }
    }

    /// Looks up the account's name for "Connected as". Asked again whenever
    /// Tracking opens, on Sync Now and at launch, so a name changed on the
    /// tracker shows here too (Trakt may serve the old one for a short while).
    func refreshUsername(_ kind: TrackerKind) {
        guard let current = credentials[kind], current.isConnected else { return }
        Task { [weak self] in
            let refreshed = (try? await TrackerClient.refreshIfNeeded(kind, current)) ?? current
            guard let name = await TrackerClient.username(kind, credentials: refreshed), let self,
                  self.credentials[kind]?.accessToken == current.accessToken
            else { return }
            guard name != refreshed.username || refreshed != current else { return }
            var updated = refreshed
            updated.username = name
            self.persist(updated, for: kind)
        }
    }

    // MARK: Scrobbling

    /// Called as playback changes. Sends start when a title plays and pause
    /// when it pauses, once per change, to every connected tracker.
    func playbackChanged(_ media: TrackerMedia?, progress: Double, runtimeSeconds: Double?, isPlaying: Bool) {
        guard let media, media.hasIdentifier else { return }
        let state = scrobbleState
        if isPlaying {
            guard state?.key != media.key || state?.action != .start else { return }
            send(.start, media: media, progress: progress, runtimeSeconds: runtimeSeconds)
        } else if state?.key == media.key, state?.action == .start {
            send(.pause, media: media, progress: progress, runtimeSeconds: runtimeSeconds)
        }
    }

    /// Called when the player closes. Every tracker marks the title
    /// watched when it stops past 80%.
    func playbackStopped(_ media: TrackerMedia?, progress: Double, runtimeSeconds: Double?) {
        defer { scrobbleState = nil }
        guard let media, media.hasIdentifier, scrobbleState?.key == media.key,
              scrobbleState?.action != .stop
        else { return }
        send(.stop, media: media, progress: progress, runtimeSeconds: runtimeSeconds)
    }

    private func send(_ action: TrackerScrobbleAction, media: TrackerMedia, progress: Double, runtimeSeconds: Double?) {
        scrobbleState = (media.key, action)
        for kind in TrackerKind.allCases where isConnected(kind) && scrobbles(kind) {
            guard let current = credentials[kind] else { continue }
            Task { [weak self] in
                do {
                    let refreshed = try await TrackerClient.refreshIfNeeded(kind, current)
                    if refreshed != current { self?.store(refreshed, for: kind) }
                    try await TrackerClient.scrobble(
                        kind,
                        action: action,
                        media: media,
                        progress: progress,
                        runtimeSeconds: runtimeSeconds,
                        credentials: refreshed
                    )
                    self?.lastScrobbleError[kind] = nil
                    // A pause or stop changes what's in progress there.
                    if action != .start { TrackerLibraryStore.shared.refreshAfterScrobble(kind) }
                } catch {
                    self?.lastScrobbleError[kind] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: Storage

    private static func keychainAccount(_ kind: TrackerKind) -> String { "tracker.\(kind.rawValue).credentials" }
    private static func scrobbleKey(_ kind: TrackerKind) -> String { "tracker-\(kind.rawValue)-scrobbles" }

    private static func loadCredentials(_ kind: TrackerKind) -> TrackerCredentials? {
        guard let text = try? KeychainStore.value(account: keychainAccount(kind)),
              let data = text.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder.tracker.decode(TrackerCredentials.self, from: data)
    }
}

private extension JSONEncoder {
    static var tracker: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var tracker: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension TrackerMedia {
    /// The playing title in tracker terms, or nil for Live TV and titles
    /// with no IMDb, TMDB or TVDB ID.
    nonisolated init?(item: MediaItem, episode: MediaEpisode?) {
        func id(_ keys: [String]) -> String? {
            keys.lazy.compactMap { item.externalIDs[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
        var imdb = id(["imdb", "imdb_id"])
        if imdb == nil, item.id.hasPrefix("tt") { imdb = item.id.split(separator: ":").first.map(String.init) }
        let tmdb = id(["tmdb", "tmdb_id"]).flatMap(Int.init)
        let tvdb = id(["tvdb", "tvdb_id"]).flatMap(Int.init)
        let kind: Kind
        if item.kind == .series {
            guard let episode else { return nil }
            kind = .episode(season: episode.seasonNumber, number: episode.episodeNumber)
        } else {
            kind = .movie
        }
        func animeID(_ keys: [String], prefix: String) -> Int? {
            if let value = id(keys).flatMap({ Int($0) }) { return value }
            let parts = item.id.split(separator: ":")
            guard parts.count >= 2, parts[0] == prefix else { return nil }
            return Int(parts[1])
        }
        self.init(kind: kind, title: item.title, year: Int(item.year.prefix(4)), imdb: imdb, tmdb: tmdb, tvdb: tvdb)
        anilist = animeID(["anilist", "anilist_id"], prefix: "anilist")
        mal = animeID(["mal", "mal_id", "myanimelist"], prefix: "mal")
        guard hasIdentifier else { return nil }
    }
}
