//
//  PluginStore.swift
//  Omnia
//

import CryptoKit
import Foundation
import Observation

/// Installed plugin repositories and their scrapers, as in Nuvio: a
/// repository is a `manifest.json` URL, and each scraper it lists is a
/// JavaScript file Omnia downloads and runs for streams. Kept in Application
/// Support; the optional TMDB key plugins read is kept in the Keychain.
@MainActor
@Observable
final class PluginStore {
    nonisolated static let tmdbKeyAccount = "plugins.tmdb-api-key"

    private(set) var repositories: [PluginRepository] = []
    private(set) var scrapers: [PluginScraper] = []
    private(set) var pluginsEnabled = true
    /// Repositories being refreshed, by id.
    private(set) var refreshing: Set<String> = []
    /// The last refresh error for each repository, by id.
    private(set) var errors: [String: String] = [:]
    private(set) var hasTMDBKey = false

    /// Each scraper's saved settings as JSON, by scraper id.
    private var settings: [String: String] = [:]
    private let directory: URL?

    init(directory: URL? = PluginStore.defaultDirectory) {
        self.directory = directory
        hasTMDBKey = (try? KeychainStore.value(account: Self.tmdbKeyAccount))?.isEmpty == false
        load()
        Task { await refreshDueRepositories() }
    }

    nonisolated static var defaultDirectory: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support
            .appending(path: Bundle.main.bundleIdentifier ?? "Omnia", directoryHint: .isDirectory)
            .appending(path: "plugins", directoryHint: .isDirectory)
    }

    func scrapers(in repository: PluginRepository) -> [PluginScraper] {
        scrapers.filter { $0.repositoryURL == repository.manifestURL }
    }

    var enabledScraperCount: Int {
        pluginsEnabled ? scrapers.filter(\.isEnabled).count : 0
    }

    // MARK: Repositories

    enum AddError: LocalizedError {
        case invalidURL
        case alreadyInstalled
        case noScrapers

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter the address of a plugin repository's manifest."
            case .alreadyInstalled: "This repository is already installed."
            case .noScrapers: "The repository doesn't list any plugins that run on this device."
            }
        }
    }

    /// Installs a repository from the address a person typed or pasted.
    func addRepository(_ input: String) async throws {
        guard let url = Self.manifestURL(from: input) else { throw AddError.invalidURL }
        guard !repositories.contains(where: { $0.manifestURL == url }) else { throw AddError.alreadyInstalled }
        let id = url.absoluteString
        refreshing.insert(id)
        defer { refreshing.remove(id) }

        let download = try await Self.download(url, previous: [])
        guard !download.scrapers.isEmpty else { throw AddError.noScrapers }
        apply(download)
    }

    func removeRepository(_ repository: PluginRepository) {
        let removed = scrapers(in: repository)
        repositories.removeAll { $0.id == repository.id }
        scrapers.removeAll { $0.repositoryURL == repository.manifestURL }
        errors[repository.id] = nil
        for scraper in removed {
            settings[scraper.id] = nil
            if let file = codeFile(for: scraper.id) { try? FileManager.default.removeItem(at: file) }
        }
        save()
    }

    func refresh(_ repository: PluginRepository) async {
        guard !refreshing.contains(repository.id) else { return }
        refreshing.insert(repository.id)
        defer { refreshing.remove(repository.id) }
        do {
            let download = try await Self.download(repository.manifestURL, previous: scrapers(in: repository))
            guard repositories.contains(where: { $0.id == repository.id }) else { return }
            apply(download)
            errors[repository.id] = nil
        } catch {
            // The last good copy keeps working.
            errors[repository.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for repository in repositories {
                group.addTask { await self.refresh(repository) }
            }
        }
    }

    /// Repositories are refreshed at launch when six hours have passed, or
    /// when one of their scrapers' code is missing.
    private func refreshDueRepositories() async {
        let due = repositories.filter { repository in
            repository.isRefreshDue() || scrapers(in: repository).contains { code(for: $0) == nil }
        }
        for repository in due { await refresh(repository) }
    }

    private func apply(_ download: Download) {
        let repository = download.repository
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
        } else {
            repositories.append(repository)
        }
        let kept = Set(download.scrapers.map(\.scraper.id))
        for removed in scrapers where removed.repositoryURL == repository.manifestURL && !kept.contains(removed.id) {
            if let file = codeFile(for: removed.id) { try? FileManager.default.removeItem(at: file) }
        }
        scrapers.removeAll { $0.repositoryURL == repository.manifestURL }
        for entry in download.scrapers {
            scrapers.append(entry.scraper)
            writeCode(entry.code, for: entry.scraper.id)
        }
        save()
    }

    // MARK: Scrapers

    func setPluginsEnabled(_ enabled: Bool) {
        pluginsEnabled = enabled
        save()
    }

    func setEnabled(_ enabled: Bool, for scraper: PluginScraper) {
        guard let index = scrapers.firstIndex(where: { $0.id == scraper.id }) else { return }
        scrapers[index].isEnabled = enabled && scrapers[index].manifestEnabled
        save()
    }

    func code(for scraper: PluginScraper) -> String? {
        codeFile(for: scraper.id).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    func settingsJSON(for scraper: PluginScraper) -> String {
        settings[scraper.id] ?? "{}"
    }

    func settingsValues(for scraper: PluginScraper) -> [String: Any] {
        guard let data = settingsJSON(for: scraper).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return object
    }

    func saveSettings(_ values: [String: Any], for scraper: PluginScraper) {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return }
        settings[scraper.id] = json
        save()
    }

    func configuration(for scraper: PluginScraper) -> PluginRuntime.Configuration? {
        guard let code = code(for: scraper) else { return nil }
        return PluginRuntime.Configuration(
            code: code,
            scraperID: scraper.id,
            settingsJSON: settingsJSON(for: scraper),
            tmdbAPIKey: tmdbAPIKey
        )
    }

    /// Runs a scraper for The Matrix (or its first episode for series-only
    /// plugins), as Nuvio's Test button does.
    func test(_ scraper: PluginScraper) async throws -> PluginRuntime.StreamsOutcome {
        guard let configuration = configuration(for: scraper) else {
            throw PluginRuntimeError.failed("This plugin's code is missing. Refresh its repository.")
        }
        let isMovie = scraper.supports(type: "movie")
        return try await PluginRuntime.streams(
            configuration,
            tmdbID: isMovie ? "603" : "1399",
            mediaType: isMovie ? "movie" : "tv",
            season: isMovie ? nil : 1,
            episode: isMovie ? nil : 1
        )
    }

    // MARK: TMDB key

    var tmdbAPIKey: String? {
        guard let value = try? KeychainStore.value(account: Self.tmdbKeyAccount), !value.isEmpty else { return nil }
        return value
    }

    func setTMDBAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainStore.delete(account: Self.tmdbKeyAccount)
        } else {
            try? KeychainStore.save(trimmed, account: Self.tmdbKeyAccount)
        }
        hasTMDBKey = !trimmed.isEmpty
    }

    // MARK: Downloading

    private struct Download: Sendable {
        let repository: PluginRepository
        let scrapers: [(scraper: PluginScraper, code: String)]
    }

    enum DownloadError: LocalizedError {
        case status(Int)
        case notAManifest

        var errorDescription: String? {
            switch self {
            case let .status(code): "The repository answered with status \(code)."
            case .notAManifest: "That address isn't a plugin repository manifest."
            }
        }
    }

    private nonisolated static func download(_ manifestURL: URL, previous: [PluginScraper]) async throws -> Download {
        let data = try await fetch(manifestURL)
        guard let manifest = try? JSONDecoder().decode(PluginRepositoryManifest.self, from: data) else {
            throw DownloadError.notAManifest
        }
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let base = baseURL(of: manifestURL)

        // Scrapers download together; one that fails is left out.
        let scrapers = await withTaskGroup(of: (Int, PluginScraper, String)?.self) { group in
            for (position, info) in manifest.scrapers.enumerated() where info.runsOnThisPlatform {
                group.addTask {
                    let codeURL = info.filename.lowercased().hasPrefix("http")
                        ? URL(string: info.filename)
                        : URL(string: base + "/" + info.filename.drop { $0 == "/" })
                    guard let codeURL,
                          let codeData = try? await fetch(codeURL),
                          let code = String(data: codeData, encoding: .utf8)
                    else { return nil }
                    let id = "\(manifestURL.absoluteString.lowercased()):\(info.id)"
                    let previous = previousByID[id]
                    let scraper = PluginScraper(
                        id: id,
                        repositoryURL: manifestURL,
                        name: info.name,
                        description: info.description ?? "",
                        version: info.version,
                        filename: info.filename,
                        supportedTypes: info.supportedTypes,
                        isEnabled: info.enabled && (previous?.isEnabled ?? true),
                        manifestEnabled: info.enabled,
                        hasSettings: info.hasSettings,
                        logo: info.logo.flatMap(URL.init(string:)),
                        contentLanguage: info.contentLanguage,
                        formats: info.formats
                    )
                    return (position, scraper, code)
                }
            }
            var results: [(Int, PluginScraper, String)] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results.sorted { $0.0 < $1.0 }.map { (scraper: $0.1, code: $0.2) }
        }

        let repository = PluginRepository(
            manifestURL: manifestURL,
            name: manifest.name,
            description: manifest.description,
            version: manifest.version.isEmpty ? nil : manifest.version,
            author: manifest.author,
            scraperCount: scrapers.count,
            lastUpdated: .now
        )
        return Download(repository: repository, scrapers: scrapers)
    }

    private nonisolated static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json, text/javascript, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.status(http.statusCode)
        }
        return data
    }

    /// Where a repository's relative script names start: the manifest's folder.
    nonisolated static func baseURL(of manifestURL: URL) -> String {
        var text = manifestURL.absoluteString
        if let query = text.firstIndex(of: "?") { text = String(text[..<query]) }
        if text.hasSuffix("/manifest.json") { text.removeLast("/manifest.json".count) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// Adds `https://` and `/manifest.json` when they're missing, as Nuvio does.
    nonisolated static func manifestURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://"), !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        if let fragment = text.firstIndex(of: "#") { text = String(text[..<fragment]) }
        var query = ""
        if let start = text.firstIndex(of: "?") {
            query = String(text[start...])
            text = String(text[..<start])
        }
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/manifest.json") { text += "/manifest.json" }
        guard let url = URL(string: text + query), url.host() != nil else { return nil }
        return url
    }

    // MARK: Persistence

    private struct StoredState: Codable {
        var pluginsEnabled: Bool
        var repositories: [PluginRepository]
        var scrapers: [PluginScraper]
        var settings: [String: String]
    }

    private var stateFile: URL? { directory?.appending(path: "state.json", directoryHint: .notDirectory) }

    private func codeFile(for scraperID: String) -> URL? {
        let name = SHA256.hash(data: Data(scraperID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?
            .appending(path: "code", directoryHint: .isDirectory)
            .appending(path: "\(name).js", directoryHint: .notDirectory)
    }

    private func writeCode(_ code: String, for scraperID: String) {
        guard let file = codeFile(for: scraperID) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(code.utf8).write(to: file, options: .atomic)
    }

    private func load() {
        guard let stateFile, let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(StoredState.self, from: data)
        else { return }
        pluginsEnabled = state.pluginsEnabled
        repositories = state.repositories
        scrapers = state.scrapers
        settings = state.settings
    }

    private func save() {
        guard let stateFile else { return }
        let state = StoredState(pluginsEnabled: pluginsEnabled, repositories: repositories, scrapers: scrapers, settings: settings)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateFile, options: .atomic)
    }
}
