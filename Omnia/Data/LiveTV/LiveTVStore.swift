//
//  LiveTVStore.swift
//  Omnia
//

import Foundation
import Observation

/// Nuvio Enhanced's Live TV (Settings › Content & Discovery › Live TV):
/// M3U playlists, an Xtream account and a Stalker portal, their channels and
/// TV guide, favorites and the last watched channel. Settings are saved in
/// UserDefaults; addresses and accounts in the Keychain; channel lists and
/// playlist files in an encrypted store.
@MainActor
@Observable
final class LiveTVStore {
    static let shared = LiveTVStore()

    nonisolated static let storageKey = "live-tv-v1"
    nonisolated static let secretsAccount = "live-tv-secrets-v1"
    private static let channelsFile = "channels.sealed"
    private static let guideFile = "guide.sealed"
    /// Guides are refreshed once a day, as in Nuvio.
    private static let guideLifetime: TimeInterval = 24 * 3_600

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var configuration: LiveTVConfiguration
    private var secrets: LiveTVSecrets
    private(set) var channels: [LiveTVChannel] = []
    private(set) var channelState: LoadState = .idle
    /// The last problem loading each source, by source id.
    private(set) var sourceProblems: [String: String] = [:]
    /// Programmes by channel id, oldest first.
    private(set) var guide: [String: [LiveTVProgram]] = [:]
    private(set) var guideState: LoadState = .idle
    private(set) var guideUpdatedAt: Date?

    private var detectedGuideURLs: [URL] = []
    private var loadedSignature: String?
    private var loadedGuideSignature: String?
    private var vaultGeneration = 0
    private var needsChannelReload = false
    private var needsGuideReload = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(LiveTVConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = LiveTVConfiguration()
        }
        if let text = try? KeychainStore.value(account: Self.secretsAccount),
           let saved = try? JSONDecoder().decode(LiveTVSecrets.self, from: Data(text.utf8)) {
            secrets = saved
        } else {
            secrets = LiveTVSecrets()
        }
    }

    // MARK: State

    var xtreamAccount: LiveTVXtreamAccount? { secrets.xtream }
    var stalkerAccount: LiveTVStalkerAccount? { secrets.stalker }

    /// Whether any source is set up and turned on: Live TV's "has playlist".
    var hasSources: Bool {
        configuration.playlists.contains(where: \.isEnabled)
            || secrets.xtream?.isEnabled == true
            || secrets.stalker?.isEnabled == true
    }

    /// Live TV sits between Discover and Settings once a source is set up,
    /// unless it is hidden in Settings.
    var showsInNavigation: Bool {
        hasSources && configuration.showsInNavigation
    }

    func isFavorite(_ channel: LiveTVChannel) -> Bool {
        configuration.favoriteChannelIDs.contains(channel.id)
    }

    var lastWatchedChannel: LiveTVChannel? {
        guard let id = configuration.lastWatchedChannelID else { return nil }
        return channels.first { $0.id == id }
    }

    /// Categories by name; Uncategorized is listed first by the page.
    var groups: [String] {
        Set(channels.compactMap(\.group)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var hasUncategorizedChannels: Bool {
        channels.contains { $0.group == nil }
    }

    func programs(for channel: LiveTVChannel) -> [LiveTVProgram] {
        guide[channel.id] ?? []
    }

    var guideCoverage: (matched: Int, total: Int) {
        (channels.count(where: { guide[$0.id]?.isEmpty == false }), channels.count)
    }

    func playlistHost(_ playlist: LiveTVPlaylist) -> String? {
        secrets.playlistURLs[playlist.id]?.host
    }

    func playlistAddress(_ playlist: LiveTVPlaylist) -> String {
        secrets.playlistURLs[playlist.id]?.absoluteString ?? ""
    }

    func guideHost(_ source: LiveTVGuideSource) -> String? {
        secrets.guideURLs[source.id]?.host
    }

    var channelsStatus: String {
        switch channelState {
        case .idle: hasSources ? "Not loaded yet." : "No sources set up."
        case .loading: "Loading channels…"
        case .loaded: channels.count == 1 ? "1 channel loaded." : "\(channels.count.formatted()) channels loaded."
        case let .failed(message): message
        }
    }

    var guideStatus: String {
        switch guideState {
        case .idle: "Not loaded yet."
        case .loading: "Loading the TV guide…"
        case .loaded:
            "Guide available for \(guideCoverage.matched.formatted()) of \(guideCoverage.total.formatted()) channels."
        case let .failed(message): message
        }
    }

    // MARK: Loading

    /// Shows the saved channels and guide when they match the current
    /// sources, otherwise loads them.
    func loadIfNeeded() async {
        guard hasSources else {
            clearLoadedContent()
            return
        }
        let signature = sourcesSignature
        if loadedSignature != signature, channelState != .loading {
            if let cache = await Self.readSealed(ChannelCache.self, named: Self.channelsFile), cache.signature == signature, sourcesSignature == signature {
                apply(cache)
                loadedSignature = signature
                channelState = .loaded
            } else {
                await reloadChannels()
            }
        }
        await loadGuideIfNeeded()
    }

    func reloadChannels() async {
        guard hasSources else {
            clearLoadedContent()
            return
        }
        guard channelState != .loading else {
            needsChannelReload = true
            return
        }
        channelState = .loading
        let signature = sourcesSignature
        let generation = vaultGeneration
        let result = await LiveTVLoader.channels(loadPlan)
        guard generation == vaultGeneration, signature == sourcesSignature else { return }
        let cache = ChannelCache(
            signature: signature,
            channels: result.channels,
            guideURLs: result.guideURLs,
            problems: result.problems
        )
        apply(cache)
        loadedSignature = signature
        if result.channels.isEmpty, let problem = result.problems.values.first {
            channelState = .failed(problem)
        } else {
            channelState = .loaded
            await Self.writeSealed(cache, named: Self.channelsFile)
        }
        if needsChannelReload {
            needsChannelReload = false
            await reloadChannels()
        }
    }

    private func loadGuideIfNeeded() async {
        guard !channels.isEmpty else { return }
        let signature = guideSignature
        if loadedGuideSignature == signature, let guideUpdatedAt,
           Date().timeIntervalSince(guideUpdatedAt) < Self.guideLifetime {
            return
        }
        if let cache = await Self.readSealed(GuideCache.self, named: Self.guideFile), cache.signature == signature,
           Date().timeIntervalSince(cache.savedAt) < Self.guideLifetime {
            guide = cache.programs
            guideUpdatedAt = cache.savedAt
            loadedGuideSignature = signature
            guideState = .loaded
            return
        }
        await reloadGuide()
    }

    func reloadGuide() async {
        guard !channels.isEmpty else {
            guide = [:]
            guideState = .idle
            return
        }
        guard guideState != .loading else {
            needsGuideReload = true
            return
        }
        guideState = .loading
        let signature = guideSignature
        let generation = vaultGeneration
        let result = await LiveTVLoader.guide(
            urls: guideURLs,
            stalker: configuration.autoDetectsGuides && secrets.stalker?.isEnabled == true ? secrets.stalker : nil,
            channels: channels
        )
        guard generation == vaultGeneration, signature == guideSignature else { return }
        guide = result.programs
        guideUpdatedAt = Date()
        loadedGuideSignature = signature
        if result.programs.isEmpty, let problem = result.problem {
            guideState = .failed(problem)
        } else {
            guideState = .loaded
            await Self.writeSealed(GuideCache(signature: signature, programs: result.programs, savedAt: Date()), named: Self.guideFile)
        }
        if needsGuideReload {
            needsGuideReload = false
            await reloadGuide()
        }
    }

    private func apply(_ cache: ChannelCache) {
        channels = cache.channels
        detectedGuideURLs = cache.guideURLs
        sourceProblems = cache.problems
    }

    private func clearLoadedContent() {
        vaultGeneration &+= 1
        channels = []
        guide = [:]
        sourceProblems = [:]
        detectedGuideURLs = []
        channelState = .idle
        guideState = .idle
        loadedSignature = nil
        loadedGuideSignature = nil
        LiveTVVault.remove(named: Self.channelsFile)
        LiveTVVault.remove(named: Self.guideFile)
    }

    /// Reloads after a source changes, then the guide.
    private func sourcesChanged() {
        Task {
            await reloadChannels()
            await reloadGuide()
        }
    }

    private var loadPlan: LiveTVLoadPlan {
        LiveTVLoadPlan(
            playlists: configuration.playlists.filter(\.isEnabled).map { playlist in
                LiveTVLoadPlan.Playlist(
                    id: playlist.id,
                    name: playlist.name,
                    url: playlist.kind == .url ? secrets.playlistURLs[playlist.id] : nil
                )
            },
            xtream: secrets.xtream?.isEnabled == true ? secrets.xtream : nil,
            stalker: secrets.stalker?.isEnabled == true ? secrets.stalker : nil
        )
    }

    private var guideURLs: [URL] {
        var urls = configuration.guides.filter(\.isEnabled).compactMap { secrets.guideURLs[$0.id] }
        if configuration.autoDetectsGuides {
            urls += detectedGuideURLs
            if let xtream = secrets.xtream, xtream.isEnabled, let url = LiveTVXtreamClient.guideURL(xtream) {
                urls.append(url)
            }
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    /// Changes whenever the channels to load change. Hashed, as it is built
    /// from addresses and passwords.
    private var sourcesSignature: String {
        var parts = configuration.playlists.filter(\.isEnabled).map { playlist in
            "\(playlist.id)|\(playlist.name)|\(secrets.playlistURLs[playlist.id]?.absoluteString ?? "file")"
        }
        if let xtream = secrets.xtream, xtream.isEnabled {
            parts.append("xtream|\(xtream.server.absoluteString)|\(xtream.username)|\(xtream.password)")
        }
        if let stalker = secrets.stalker, stalker.isEnabled {
            parts.append("stalker|\(stalker.portal.absoluteString)|\(stalker.macAddress)|\(stalker.username)|\(stalker.password)")
        }
        return LiveTVHashing.digest(parts.joined(separator: "\n"))
    }

    private var guideSignature: String {
        let parts = [sourcesSignature, String(configuration.autoDetectsGuides)] + guideURLs.map(\.absoluteString)
        return LiveTVHashing.digest(parts.joined(separator: "\n"))
    }

    // MARK: Playback

    /// The playable stream. Xtream links are built here and Stalker links
    /// asked of the portal, so passwords never sit in a saved channel.
    func playbackSource(for channel: LiveTVChannel) async throws -> PlaybackSource {
        let url: URL
        var headers: [String: String] = [:]
        switch channel.stream {
        case let .direct(directURL, directHeaders):
            url = directURL
            headers = directHeaders
        case let .xtream(streamID, containerExtension):
            guard let account = secrets.xtream else { throw LiveTVFailure.notConfigured }
            url = LiveTVXtreamClient.streamURL(account, streamID: streamID, containerExtension: containerExtension)
            // Nuvio's Xtream stream headers; some panels turn away the
            // player's full browser User-Agent.
            headers = ["User-Agent": "Mozilla/5.0", "Accept": "*/*"]
        case let .stalker(command):
            guard let account = secrets.stalker else { throw LiveTVFailure.notConfigured }
            let link = try await LiveTVStalkerClient.playback(account, command: command)
            url = link.0
            headers = link.1
        }
        guard LiveTVAddressPolicy.permits(url) else { throw LiveTVFailure.insecureAddress }
        let (playableURL, playableHeaders) = await LiveTVNameResolution.reachable(url, headers: headers)
        return PlaybackSource(
            liveChannelID: channel.id,
            title: channel.name,
            detail: channel.group,
            sourceName: channel.sourceName,
            url: playableURL,
            requestHeaders: playableHeaders
        )
    }

    /// What the player shows as the title: the channel and what's on now.
    func mediaItem(for channel: LiveTVChannel) -> MediaItem {
        let now = LiveTVGuideMatcher.nowAndNext(in: programs(for: channel), at: Date()).now
        return MediaItem(
            id: PlaybackSource.liveTVIDPrefix + channel.id,
            title: channel.name,
            year: "",
            kind: .movie,
            overview: now?.title ?? channel.group ?? "Live TV",
            genres: channel.group.map { [$0] } ?? [],
            symbol: "play.tv",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: channel.logoURL,
            progress: nil
        )
    }

    /// The channel behind a Live TV player item, if it is still listed.
    func channel(forPlaybackItemID id: String) -> LiveTVChannel? {
        guard id.hasPrefix(PlaybackSource.liveTVIDPrefix) else { return nil }
        let channelID = String(id.dropFirst(PlaybackSource.liveTVIDPrefix.count))
        return channels.first { $0.id == channelID }
    }

    /// The channel before or after this one in the list, wrapping around:
    /// the player's channel up and down.
    func channel(after channel: LiveTVChannel, offset: Int) -> LiveTVChannel? {
        guard channels.count > 1, let index = channels.firstIndex(where: { $0.id == channel.id }) else { return nil }
        let next = (index + offset % channels.count + channels.count) % channels.count
        return channels[next]
    }

    /// Plays a channel, from the Live TV page or the player's channel list.
    func play(
        _ channel: LiveTVChannel,
        in playback: PlaybackSession,
        preferences: SettingsPreferences
    ) async throws {
        let source = try await playbackSource(for: channel)
        markWatched(channel)
        playback.start(
            item: mediaItem(for: channel),
            source: source,
            resumeAt: nil,
            preferences: preferences
        ) { _, _ in }
    }

    func markWatched(_ channel: LiveTVChannel) {
        configuration.lastWatchedChannelID = channel.id
        saveConfiguration()
    }

    func toggleFavorite(_ channel: LiveTVChannel) {
        if let index = configuration.favoriteChannelIDs.firstIndex(of: channel.id) {
            configuration.favoriteChannelIDs.remove(at: index)
        } else {
            configuration.favoriteChannelIDs.append(channel.id)
        }
        saveConfiguration()
    }

    // MARK: Settings

    func setShowsInNavigation(_ shows: Bool) {
        configuration.showsInNavigation = shows
        saveConfiguration()
    }

    func setAutoDetectsGuides(_ detects: Bool) {
        configuration.autoDetectsGuides = detects
        saveConfiguration()
        Task { await reloadGuide() }
    }

    func addPlaylist(name: String, address: String) throws {
        let url = try validatedURL(address)
        let id = UUID().uuidString
        var updated = secrets
        updated.playlistURLs[id] = url
        try saveSecrets(updated)
        configuration.playlists.append(LiveTVPlaylist(
            id: id,
            name: name.liveTVTrimmed ?? url.host ?? "Playlist",
            kind: .url,
            isEnabled: true
        ))
        saveConfiguration()
        sourcesChanged()
    }

    /// Keeps a copy of a chosen .m3u file in the encrypted store.
    func addLocalPlaylist(from fileURL: URL) async throws {
        let generation = vaultGeneration
        let id = UUID().uuidString
        try await Self.importPlaylistFile(fileURL, id: id)
        guard generation == vaultGeneration, !Task.isCancelled else {
            LiveTVVault.remove(named: Self.playlistFile(id))
            throw CancellationError()
        }
        configuration.playlists.append(LiveTVPlaylist(
            id: id,
            name: fileURL.deletingPathExtension().lastPathComponent.liveTVTrimmed ?? "Playlist",
            kind: .localFile,
            isEnabled: true
        ))
        saveConfiguration()
        sourcesChanged()
    }

    func updatePlaylist(_ id: String, name: String, address: String?) throws {
        guard let index = configuration.playlists.firstIndex(where: { $0.id == id }) else { return }
        if let address, configuration.playlists[index].kind == .url {
            let url = try validatedURL(address)
            if secrets.playlistURLs[id] != url {
                var updated = secrets
                updated.playlistURLs[id] = url
                try saveSecrets(updated)
            }
        }
        if let trimmed = name.liveTVTrimmed {
            configuration.playlists[index].name = trimmed
        }
        saveConfiguration()
        sourcesChanged()
    }

    func setPlaylistEnabled(_ isEnabled: Bool, id: String) {
        guard let index = configuration.playlists.firstIndex(where: { $0.id == id }) else { return }
        configuration.playlists[index].isEnabled = isEnabled
        saveConfiguration()
        sourcesChanged()
    }

    func removePlaylist(_ id: String) {
        configuration.playlists.removeAll { $0.id == id }
        var updated = secrets
        updated.playlistURLs[id] = nil
        try? saveSecrets(updated)
        LiveTVVault.remove(named: Self.playlistFile(id))
        saveConfiguration()
        sourcesChanged()
    }

    func connectXtream(server: String, username: String, password: String) async throws {
        let generation = vaultGeneration
        guard let serverURL = LiveTVAddress.xtreamServer(from: server) else { throw LiveTVFailure.invalidAddress }
        guard LiveTVAddressPolicy.permits(serverURL) else { throw LiveTVFailure.insecureAddress }
        let account = LiveTVXtreamAccount(
            server: serverURL,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password.trimmingCharacters(in: .whitespaces)
        )
        try await LiveTVXtreamClient.verify(account)
        guard generation == vaultGeneration, !Task.isCancelled else { throw CancellationError() }
        var updated = secrets
        updated.xtream = account
        try saveSecrets(updated)
        sourcesChanged()
    }

    func disconnectXtream() {
        var updated = secrets
        updated.xtream = nil
        try? saveSecrets(updated)
        sourcesChanged()
    }

    func connectStalker(portal: String, macAddress: String, username: String, password: String) async throws {
        let generation = vaultGeneration
        guard let portalURL = LiveTVAddress.stalkerPortal(from: portal),
              let mac = LiveTVAddress.macAddress(from: macAddress) else { throw LiveTVFailure.invalidAddress }
        guard LiveTVAddressPolicy.permits(portalURL) else { throw LiveTVFailure.insecureAddress }
        let account = LiveTVStalkerAccount(
            portal: portalURL,
            macAddress: mac,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password.trimmingCharacters(in: .whitespaces)
        )
        try await LiveTVStalkerClient.verify(account)
        guard generation == vaultGeneration, !Task.isCancelled else { throw CancellationError() }
        var updated = secrets
        updated.stalker = account
        try saveSecrets(updated)
        sourcesChanged()
    }

    func disconnectStalker() {
        var updated = secrets
        updated.stalker = nil
        try? saveSecrets(updated)
        sourcesChanged()
    }

    func addGuide(name: String, address: String) throws {
        let url = try validatedURL(address)
        let id = UUID().uuidString
        var updated = secrets
        updated.guideURLs[id] = url
        try saveSecrets(updated)
        configuration.guides.append(LiveTVGuideSource(
            id: id,
            name: name.liveTVTrimmed ?? url.host ?? "TV Guide",
            isEnabled: true
        ))
        saveConfiguration()
        Task { await reloadGuide() }
    }

    func setGuideEnabled(_ isEnabled: Bool, id: String) {
        guard let index = configuration.guides.firstIndex(where: { $0.id == id }) else { return }
        configuration.guides[index].isEnabled = isEnabled
        saveConfiguration()
        Task { await reloadGuide() }
    }

    func removeGuide(_ id: String) {
        configuration.guides.removeAll { $0.id == id }
        var updated = secrets
        updated.guideURLs[id] = nil
        try? saveSecrets(updated)
        saveConfiguration()
        Task { await reloadGuide() }
    }

    private func validatedURL(_ address: String) throws -> URL {
        guard let url = LiveTVAddress.url(from: address) else { throw LiveTVFailure.invalidAddress }
        guard LiveTVAddressPolicy.permits(url) else { throw LiveTVFailure.insecureAddress }
        return url
    }

    func vaultSecrets() throws -> LiveTVSecrets {
        guard let text = try KeychainStore.value(account: Self.secretsAccount) else { return LiveTVSecrets() }
        return try JSONDecoder().decode(LiveTVSecrets.self, from: Data(text.utf8))
    }

    func applyVaultConfiguration(_ value: LiveTVConfiguration) throws {
        let data = try JSONEncoder().encode(value)
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        configuration = value
        clearLoadedContent()
    }

    func applyVaultSecrets(_ value: LiveTVSecrets?) throws {
        if let value { try saveSecrets(value) }
        else {
            try CredentialVaultLocalStore.replaceCredential(nil, account: Self.secretsAccount)
            secrets = LiveTVSecrets()
        }
        clearLoadedContent()
    }

    func vaultPlaylist(_ id: String) throws -> Data? {
        let name = Self.playlistFile(id)
        let file = LiveTVVault.directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let data = LiveTVVault.read(named: name) else { throw LiveTVFailure.fileUnreadable }
        return data
    }

    func applyVaultPlaylist(_ data: Data?, id: String) throws {
        if let data { try LiveTVVault.write(data, named: Self.playlistFile(id)) }
        else {
            let file = LiveTVVault.directory.appending(path: Self.playlistFile(id))
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        clearLoadedContent()
    }

    private func saveConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
    }

    private func saveSecrets(_ updated: LiveTVSecrets) throws {
        let data = try JSONEncoder().encode(updated)
        try KeychainStore.save(String(decoding: data, as: UTF8.self), account: Self.secretsAccount)
        secrets = updated
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
    }

    // MARK: Files

    nonisolated static func playlistFile(_ id: String) -> String {
        "playlist-\(id).sealed"
    }

    @concurrent
    private nonisolated static func importPlaylistFile(_ fileURL: URL, id: String) async throws {
        let isScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if isScoped { fileURL.stopAccessingSecurityScopedResource() } }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= LiveTVHTTP.maximumBytes else { throw LiveTVFailure.tooLarge }
        guard let data = try? Data(contentsOf: fileURL) else { throw LiveTVFailure.fileUnreadable }
        let text = LiveTVHTTP.text(from: data)
        guard text.range(of: "#EXTINF", options: .caseInsensitive) != nil else { throw LiveTVFailure.fileUnreadable }
        try LiveTVVault.write(data, named: playlistFile(id))
    }

    @concurrent
    private nonisolated static func readSealed<Value: Decodable & Sendable>(_ type: Value.Type, named name: String) async -> Value? {
        guard let data = LiveTVVault.read(named: name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    @concurrent
    private nonisolated static func writeSealed<Value: Encodable & Sendable>(_ value: Value, named name: String) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? LiveTVVault.write(data, named: name)
    }
}

private nonisolated struct ChannelCache: Codable, Sendable {
    let signature: String
    let channels: [LiveTVChannel]
    let guideURLs: [URL]
    let problems: [String: String]
}

private nonisolated struct GuideCache: Codable, Sendable {
    let signature: String
    let programs: [String: [LiveTVProgram]]
    let savedAt: Date
}

// MARK: Loader

nonisolated struct LiveTVLoadPlan: Sendable {
    struct Playlist: Sendable {
        let id: String
        let name: String
        /// Nil for a playlist file kept in the encrypted store.
        let url: URL?
    }

    var playlists: [Playlist]
    var xtream: LiveTVXtreamAccount?
    var stalker: LiveTVStalkerAccount?
}

nonisolated enum LiveTVLoader {
    struct ChannelResult: Sendable {
        var channels: [LiveTVChannel] = []
        var guideURLs: [URL] = []
        var problems: [String: String] = [:]
    }

    struct GuideResult: Sendable {
        var programs: [String: [LiveTVProgram]] = [:]
        var problem: String?
    }

    private struct SourceResult: Sendable {
        let order: Int
        let sourceID: String
        var channels: [LiveTVChannel] = []
        var guideURLs: [URL] = []
        var problem: String?
    }

    /// Every source at once; channels listed once each, sorted by name.
    @concurrent
    static func channels(_ plan: LiveTVLoadPlan) async -> ChannelResult {
        let results = await withTaskGroup(of: SourceResult.self, returning: [SourceResult].self) { group in
            for (order, playlist) in plan.playlists.enumerated() {
                group.addTask { await load(playlist, order: order) }
            }
            if let xtream = plan.xtream {
                let order = plan.playlists.count
                group.addTask {
                    var result = SourceResult(order: order, sourceID: LiveTVXtreamClient.sourceID)
                    do { result.channels = try await LiveTVXtreamClient.channels(xtream) } catch { result.problem = message(error) }
                    return result
                }
            }
            if let stalker = plan.stalker {
                let order = plan.playlists.count + 1
                group.addTask {
                    var result = SourceResult(order: order, sourceID: LiveTVStalkerClient.sourceID)
                    do { result.channels = try await LiveTVStalkerClient.channels(stalker) } catch { result.problem = message(error) }
                    return result
                }
            }
            var results: [SourceResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.order < $1.order }
        }

        var combined = ChannelResult()
        var seen = Set<String>()
        for result in results {
            if let problem = result.problem { combined.problems[result.sourceID] = problem }
            for url in result.guideURLs where !combined.guideURLs.contains(url) {
                combined.guideURLs.append(url)
            }
            for channel in result.channels where seen.insert(channel.streamKey).inserted {
                combined.channels.append(channel)
            }
        }
        combined.channels.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return combined
    }

    private static func load(_ playlist: LiveTVLoadPlan.Playlist, order: Int) async -> SourceResult {
        var result = SourceResult(order: order, sourceID: playlist.id)
        do {
            let data: Data
            if let url = playlist.url {
                data = try await LiveTVHTTP.data(from: url, headers: ["Accept": "*/*", "User-Agent": "Omnia/1.0"])
            } else if let saved = LiveTVVault.read(named: LiveTVStore.playlistFile(playlist.id)) {
                data = saved
            } else {
                throw LiveTVFailure.fileUnreadable
            }
            let text = LiveTVHTTP.text(from: data)
            result.channels = LiveTVPlaylistParser.channels(in: text, sourceID: playlist.id, sourceName: playlist.name)
            result.guideURLs = LiveTVPlaylistParser.guideURLs(in: text)
            if result.channels.isEmpty {
                result.problem = "\(playlist.name) has no channels Omnia can play."
            }
        } catch {
            result.problem = message(error)
        }
        return result
    }

    /// Guides one at a time, so only one is held in memory. Each channel
    /// keeps the first guide that knows it.
    @concurrent
    static func guide(urls: [URL], stalker: LiveTVStalkerAccount?, channels: [LiveTVChannel]) async -> GuideResult {
        let now = Date()
        let windowStart = now.addingTimeInterval(-3 * 3_600)
        let windowEnd = now.addingTimeInterval(48 * 3_600)
        var result = GuideResult()
        if let stalker {
            do {
                result.programs = try await LiveTVStalkerClient.guide(stalker, from: windowStart, to: windowEnd)
            } catch {
                result.problem = message(error)
            }
        }
        var normalizedNames: [String: String] = [:]
        for channel in channels {
            normalizedNames[channel.id] = LiveTVGuideMatcher.normalizedName(channel.name)
        }
        for url in urls {
            guard !Task.isCancelled, result.programs.count < channels.count else { break }
            do {
                let downloaded = try await LiveTVHTTP.data(from: url, headers: ["Accept": "*/*", "User-Agent": "Omnia/1.0"], timeout: 90)
                let document = LiveTVGuideParser.parse(
                    try LiveTVGzip.unpackedIfNeeded(downloaded),
                    from: windowStart,
                    to: windowEnd
                )
                match(document, channels: channels, normalizedNames: normalizedNames, into: &result.programs)
            } catch {
                result.problem = result.problem ?? "A TV guide couldn't be loaded: \(message(error))"
            }
        }
        return result
    }

    /// Nuvio's order: the guide id, then the guide's channel names, then
    /// the channel's own name.
    private static func match(
        _ document: LiveTVGuideDocument,
        channels: [LiveTVChannel],
        normalizedNames: [String: String],
        into programs: inout [String: [LiveTVProgram]]
    ) {
        var idIndex: [String: String] = [:]
        for key in document.programs.keys {
            idIndex[key.lowercased()] = key
        }
        var nameIndex: [String: String] = [:]
        for (id, names) in document.displayNames where document.programs[id] != nil {
            for name in names + [id] {
                let normalized = LiveTVGuideMatcher.normalizedName(name)
                if !normalized.isEmpty, nameIndex[normalized] == nil {
                    nameIndex[normalized] = id
                }
            }
        }
        for channel in channels where programs[channel.id] == nil {
            var key: String?
            if let guideID = channel.guideID {
                key = idIndex[guideID.lowercased()] ?? nameIndex[LiveTVGuideMatcher.normalizedName(guideID)]
            }
            if key == nil, let name = normalizedNames[channel.id], !name.isEmpty {
                key = nameIndex[name]
            }
            if let key, let list = document.programs[key], !list.isEmpty {
                programs[channel.id] = list
            }
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }
}

private extension String {
    nonisolated var liveTVTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The channel list loads through Omnia's own connections, which use
/// encrypted DNS, but libmpv looks names up with the Mac's ordinary DNS. A
/// provider that DNS blocks the server (common on Indonesian ISPs) then
/// failed with "Failed to open the stream address" although its channels
/// listed fine. For plain http only, when the Mac can't find the server,
/// its address is looked up over encrypted DNS and mpv is pointed at it,
/// with the real name in the Host header so the server still answers.
nonisolated enum LiveTVNameResolution {
    static func reachable(_ url: URL, headers: [String: String]) async -> (URL, [String: String]) {
        guard url.scheme?.lowercased() == "http",
              let host = url.host(percentEncoded: false), !host.isEmpty,
              !isAddress(host),
              await !systemResolves(host),
              let address = await encryptedAddress(for: host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return (url, headers) }
        components.host = address
        guard let resolved = components.url else { return (url, headers) }
        var updated = headers.filter { $0.key.lowercased() != "host" }
        updated["Host"] = url.port.map { "\(host):\($0)" } ?? host
        return (resolved, updated)
    }

    private static func isAddress(_ host: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }

    @concurrent
    private static func systemResolves(_ host: String) async -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        if let result { freeaddrinfo(result) }
        return status == 0
    }

    /// Cloudflare's DNS over HTTPS, the resolver Omnia already uses.
    @concurrent
    private static func encryptedAddress(for host: String) async -> String? {
        var components = URLComponents(string: "https://cloudflare-dns.com/dns-query")
        components?.queryItems = [URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: "A")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await OmniaNetwork.noStore.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { return nil }
        // Type 1 is an IPv4 address; CNAMEs come first in the answer.
        return reply.Answer?.first(where: { $0.type == 1 && isAddress($0.data) })?.data
    }

    private struct Reply: Decodable {
        struct Record: Decodable {
            let type: Int
            let data: String
        }
        let Answer: [Record]?
    }
}
