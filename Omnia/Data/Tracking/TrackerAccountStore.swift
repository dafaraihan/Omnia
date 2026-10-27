//
//  TrackerAccountStore.swift
//  Omnia
//

import Foundation
import Observation

/// Trakt, Simkl and PublicMetaDB accounts, and scrobbling what plays to
/// them, as Nuvio does (Dafa, 2026-10-26). Each tracker uses the user's own
/// API app or key; its client ID, secret, tokens and keys stay in Keychain
/// on this device.
@Observable
@MainActor
final class TrackerAccountStore {
    static let shared = TrackerAccountStore()

    enum ConnectState: Equatable {
        case idle
        case requestingCode
        case waiting(TrackerDeviceCode)
        case failed(String)
    }

    private(set) var credentials: [TrackerKind: TrackerCredentials] = [:]
    private(set) var connectStates: [TrackerKind: ConnectState] = [:]
    /// When the last scrobble failed, for Settings to show.
    private(set) var lastScrobbleError: [TrackerKind: String] = [:]

    @ObservationIgnored private var connectTasks: [TrackerKind: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scrobbleState: (key: String, action: TrackerScrobbleAction)?

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

    /// Saves the user's API app and shows a code to enter on the tracker's
    /// site, then waits for them to approve it.
    func connect(_ kind: TrackerKind, clientID: String, clientSecret: String?) {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !kind.needsClientSecret || clientSecret?.isEmpty == false else {
            connectStates[kind] = .failed(kind.needsClientSecret
                ? "Enter your app's Client ID and Client Secret."
                : "Enter your app's Client ID.")
            return
        }
        let app = TrackerCredentials(clientID: clientID, clientSecret: kind.needsClientSecret ? clientSecret : nil)
        connectTasks[kind]?.cancel()
        connectStates[kind] = .requestingCode
        connectTasks[kind] = Task { [weak self] in
            do {
                let code = try await TrackerClient.requestDeviceCode(kind, clientID: clientID)
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

    /// PublicMetaDB: checks the user's API key, then keeps it.
    func connect(_ kind: TrackerKind, apiKey: String) {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind.usesAPIKey, !apiKey.isEmpty, apiKey.count <= 512 else {
            connectStates[kind] = .failed("Enter your \(kind.title) API key.")
            return
        }
        connectTasks[kind]?.cancel()
        connectStates[kind] = .requestingCode
        connectTasks[kind] = Task { [weak self] in
            do {
                try await TrackerClient.validateAPIKey(apiKey)
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
        guard let data = try? JSONEncoder.tracker.encode(value), let text = String(data: data, encoding: .utf8) else { return }
        try? KeychainStore.save(text, account: Self.keychainAccount(kind))
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
        self.init(kind: kind, title: item.title, year: Int(item.year.prefix(4)), imdb: imdb, tmdb: tmdb, tvdb: tvdb)
        guard hasIdentifier else { return nil }
    }
}
