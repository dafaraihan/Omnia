import Foundation

/// Nuvio's Reuse Last Link: the exact stream last played for a movie or
/// episode, replayed without asking the add-ons again while it is fresh.
nonisolated struct CachedStreamLink: Codable, Equatable, Sendable {
    let url: URL
    let requestHeaders: [String: String]
    let addonID: String
    let addonName: String
    let displayName: String
    let displayDescription: String?
    let filename: String?
    let videoSize: Int64?
    let bingeGroup: String?
    let cachedAt: Date
}

final class StreamLinkCacheStore {
    static let storageKey = "stream-link-cache-v1"
    /// Older entries are dropped first once the cache is this large.
    private static let maximumEntries = 300

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Saves a direct stream. Links that carry an expiring signature are not
    /// saved, and replace any older entry, because they would fail later.
    func save(_ candidate: AddonStreamCandidate, for key: MediaPlaybackKey) {
        guard case let .nativeHTTPS(url) = candidate.delivery else { return }
        var values = load()
        // Media server links carry the server's token in their headers,
        // which must stay in the Keychain.
        guard !PlaybackURLCredentials.looksSigned(url), !MediaServerIdentifier.isServerSource(candidate.addonID) else {
            if values.removeValue(forKey: key.rawValue) != nil { save(values) }
            return
        }
        values[key.rawValue] = CachedStreamLink(
            url: url,
            requestHeaders: candidate.requestHeaders,
            addonID: candidate.addonID,
            addonName: candidate.addonName,
            displayName: candidate.displayName,
            displayDescription: candidate.displayDescription,
            filename: candidate.filename,
            videoSize: candidate.videoSize,
            bingeGroup: candidate.bingeGroup,
            cachedAt: now()
        )
        if values.count > Self.maximumEntries {
            let oldest = values.sorted { $0.value.cachedAt < $1.value.cachedAt }
                .prefix(values.count - Self.maximumEntries)
            for entry in oldest { values.removeValue(forKey: entry.key) }
        }
        save(values)
    }

    /// The saved stream as a playable candidate, or nil when there is none,
    /// it is older than `maximumAgeHours`, or its add-on is no longer on.
    func candidate(
        for key: MediaPlaybackKey,
        maximumAgeHours: Int,
        enabledSourceIDs: Set<String>
    ) -> AddonStreamCandidate? {
        var values = load()
        guard let link = values[key.rawValue] else { return nil }
        let age = now().timeIntervalSince(link.cachedAt)
        guard age >= 0,
              age < TimeInterval(maximumAgeHours) * 3_600,
              enabledSourceIDs.contains(link.addonID),
              !PlaybackURLCredentials.looksSigned(link.url)
        else {
            values.removeValue(forKey: key.rawValue)
            save(values)
            return nil
        }
        return AddonStreamCandidate(
            id: "\(link.addonID)::cached::\(link.url.absoluteString)",
            addonID: link.addonID,
            addonName: link.addonName,
            streamIdentifier: key.rawValue,
            displayName: link.displayName,
            displayDescription: link.displayDescription,
            delivery: .nativeHTTPS(link.url),
            filename: link.filename,
            videoSize: link.videoSize,
            bingeGroup: link.bingeGroup,
            hasPeerDiscoveryHints: false,
            requestHeaders: link.requestHeaders
        )
    }

    /// Forgets a link, for example after it failed to play.
    func remove(_ key: MediaPlaybackKey) {
        var values = load()
        guard values.removeValue(forKey: key.rawValue) != nil else { return }
        save(values)
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
        if let fileURL = Self.fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// A stream link can hold a provider's token in its path, so links stay in
    /// a protected file left out of device backups, not in preferences.
    private static let fileURL: URL? = {
        guard var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        directory.append(path: "StreamLinks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory.appending(path: "links.json")
    }()

    private func load() -> [String: CachedStreamLink] {
        // Links saved before the file existed move over on first read.
        if let old = defaults.data(forKey: Self.storageKey),
           let values = try? JSONDecoder().decode([String: CachedStreamLink].self, from: old) {
            save(values)
            defaults.removeObject(forKey: Self.storageKey)
            return values
        }
        guard let fileURL = Self.fileURL, let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: CachedStreamLink].self, from: data)) ?? [:]
    }

    private func save(_ values: [String: CachedStreamLink]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let fileURL = Self.fileURL, let data = try? encoder.encode(values) else { return }
        #if os(macOS)
        try? data.write(to: fileURL, options: .atomic)
        #else
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #endif
    }
}

/// Nuvio's Reuse Binge Group: the last binge group played for each series,
/// so the next session can pick a stream from the same release.
final class BingeGroupCacheStore {
    static let storageKey = "binge-group-cache-v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bingeGroup(forSeries seriesID: String) -> String? {
        load()[seriesID]
    }

    func save(_ bingeGroup: String, forSeries seriesID: String) {
        let trimmed = bingeGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512, !seriesID.isEmpty else { return }
        var values = load()
        guard values[seriesID] != trimmed else { return }
        values[seriesID] = trimmed
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() -> [String: String] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}

/// Nuvio's PlaybackUrlCredentials: a query that looks like a signature or an
/// expiry means the link stops working, so it is never reused.
nonisolated enum PlaybackURLCredentials {
    private static let exactKeys: Set<String> = [
        "accesskey", "accesssignature", "accesssig", "access_token", "accesstoken",
        "auth", "authkey", "authsig", "authsignature", "auth_token", "authtoken",
        "e", "exp", "expiration", "expire", "expires", "expiresat", "expiresin",
        "expires_in", "expiry", "hmac", "jwt", "keypairid", "policy", "sig",
        "signature", "signed", "st", "t", "token",
    ]
    private static let fragments = ["token", "signature", "expires", "expiry"]

    static func looksSigned(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        return items.contains { item in
            let key = item.name.lowercased()
            let compact = key.filter { !"-_.".contains($0) }
            return exactKeys.contains(key)
                || exactKeys.contains(compact)
                || fragments.contains { key.contains($0) }
        }
    }
}
