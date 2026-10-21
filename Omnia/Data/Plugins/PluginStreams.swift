//
//  PluginStreams.swift
//  Omnia
//

import Foundation

/// The plugins to ask for a title's streams, captured from PluginStore so
/// the lookup can run without it.
nonisolated struct PluginStreamPlan: Sendable {
    struct Entry: Sendable {
        let scraper: PluginScraper
        let configuration: PluginRuntime.Configuration
    }

    let entries: [Entry]
    let tmdbAPIKey: String?

    static let empty = PluginStreamPlan(entries: [], tmdbAPIKey: nil)
}

extension PluginStore {
    /// The turned-on plugins that handle this kind of title.
    func plan(for item: MediaItem, episode: MediaEpisode?) -> PluginStreamPlan {
        guard pluginsEnabled else { return .empty }
        let type = PluginStreamResolver.mediaType(for: item, episode: episode)
        let entries = scrapers.compactMap { scraper -> PluginStreamPlan.Entry? in
            guard scraper.isEnabled, scraper.supports(type: type),
                  let configuration = configuration(for: scraper)
            else { return nil }
            return .init(scraper: scraper, configuration: configuration)
        }
        return PluginStreamPlan(entries: entries, tmdbAPIKey: tmdbAPIKey)
    }

    func plan(forSourceID sourceID: String) -> PluginStreamPlan {
        guard let scraper = scrapers.first(where: { PluginStreamResolver.sourceID(for: $0) == sourceID }),
              let configuration = configuration(for: scraper)
        else { return .empty }
        return PluginStreamPlan(entries: [.init(scraper: scraper, configuration: configuration)], tmdbAPIKey: tmdbAPIKey)
    }
}

/// Runs plugins for a title and turns what they return into the same
/// sources add-ons produce, so the source list shows both. Plugins come after
/// add-ons, as in Nuvio.
enum PluginStreamResolver {
    static let sourcePrefix = "plugin:"

    static func sourceID(for scraper: PluginScraper) -> String {
        sourcePrefix + scraper.id
    }

    static func isPluginSource(_ id: String) -> Bool {
        id.hasPrefix(sourcePrefix)
    }

    static func mediaType(for item: MediaItem, episode: MediaEpisode?) -> String {
        episode == nil && item.kind == .movie ? "movie" : "tv"
    }

    static func resolve(_ plan: PluginStreamPlan, for item: MediaItem, episode: MediaEpisode?) async -> [AddonSourceResolution] {
        guard !plan.entries.isEmpty else { return [] }
        let tmdbID = await tmdbID(for: item, apiKey: plan.tmdbAPIKey)
        return await withTaskGroup(of: (Int, AddonSourceResolution).self) { group in
            for (position, entry) in plan.entries.enumerated() {
                group.addTask {
                    (position, await resolve(entry, tmdbID: tmdbID, plan: plan, item: item, episode: episode))
                }
            }
            var results: [(Int, AddonSourceResolution)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// One plugin's sources. `tmdbID` is looked up once per title by the
    /// caller and shared, so each plugin can be listed as soon as it answers.
    static func resolve(
        _ entry: PluginStreamPlan.Entry,
        tmdbID: String?,
        plan: PluginStreamPlan,
        item: MediaItem,
        episode: MediaEpisode?
    ) async -> AddonSourceResolution {
        let id = sourceID(for: entry.scraper)
        guard let tmdbID else {
            let reason = plan.tmdbAPIKey == nil
                ? "Plugins need this title's TMDB ID. Add a TMDB API key in Settings › Content & Discovery › Plugins so Omnia can look it up."
                : "Omnia couldn't find this title on TMDB, which plugins search by."
            return AddonSourceResolution(
                addonID: id,
                addonName: entry.scraper.name,
                candidates: [],
                state: .failed,
                failure: .plugin(reason)
            )
        }
        do {
            let outcome = try await PluginRuntime.streams(
                entry.configuration,
                tmdbID: tmdbID,
                mediaType: mediaType(for: item, episode: episode),
                season: episode?.seasonNumber,
                episode: episode?.episodeNumber
            )
            var seen = Set<String>()
            let candidates = outcome.results.enumerated().compactMap { position, result -> AddonStreamCandidate? in
                let candidate = AddonStreamCandidate(plugin: result, scraper: entry.scraper, tmdbID: tmdbID, position: position)
                return seen.insert(candidate.deduplicationKey).inserted ? candidate : nil
            }
            // An empty answer says what the plugin ran into, since plugins
            // catch their own errors and just return nothing.
            let emptyReason = "Found nothing for TMDB \(tmdbID)."
                + (outcome.problem.map { " Last problem: \($0)" } ?? "")
            return AddonSourceResolution(
                addonID: id,
                addonName: entry.scraper.name,
                candidates: candidates,
                state: candidates.isEmpty ? .empty : .loaded,
                failure: candidates.isEmpty ? .plugin(emptyReason) : nil
            )
        } catch {
            return AddonSourceResolution(
                addonID: id,
                addonName: entry.scraper.name,
                candidates: [],
                state: .failed,
                failure: (error as? PluginRuntimeError) == .cancelled
                    ? .cancelled
                    : .plugin((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            )
        }
    }

    /// Plugins look titles up by TMDB ID. Most titles carry one; for the rest
    /// an IMDb ID is converted with TMDB's find endpoint when a key is set.
    static func tmdbID(for item: MediaItem, apiKey: String?) async -> String? {
        let direct = item.externalIDs["tmdb"] ?? item.externalIDs["tmdb_id"]
            ?? (item.metadataProvider == .tmdb ? item.metadataProviderID : nil)
        if let direct = direct.map(normalizedTMDBID), !direct.isEmpty { return direct }

        let imdb = item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"] ?? (item.id.hasPrefix("tt") ? item.id : nil)
        guard let apiKey, let imdb = imdb?.split(separator: ":").first.map(String.init), imdb.hasPrefix("tt"),
              var components = URLComponents(string: "https://api.themoviedb.org/3/find/\(imdb)")
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "external_source", value: "imdb_id"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let key = item.kind == .movie ? "movie_results" : "tv_results"
        let match = (object[key] as? [[String: Any]])?.first ?? (object["movie_results"] as? [[String: Any]])?.first
        return (match?["id"] as? NSNumber)?.stringValue
    }

    /// "tmdb:603", "tmdb/603" and "603:1:2" all mean 603.
    private static func normalizedTMDBID(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["tmdb:", "tmdb/"] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        return text.split(whereSeparator: { $0 == ":" || $0 == "/" }).first.map(String.init) ?? text
    }
}

extension AddonStreamCandidate {
    /// A plugin's stream, shown in the source list like an add-on's.
    init(plugin result: PluginStreamResult, scraper: PluginScraper, tmdbID: String, position: Int) {
        let sourceID = PluginStreamResolver.sourceID(for: scraper)
        let name = result.name ?? scraper.name
        let details = [result.quality, result.size, result.language].compactMap { $0 }.joined(separator: " · ")
        let description = [result.title == name ? nil : result.title, details.isEmpty ? nil : details, result.provider]
            .compactMap { $0 }
            .joined(separator: "\n")

        id = "\(sourceID)::\(tmdbID)::\(position)::\(result.url)"
        addonID = sourceID
        addonName = scraper.name
        streamIdentifier = tmdbID
        displayName = name
        displayDescription = description.isEmpty ? nil : description
        filename = nil
        videoSize = nil
        bingeGroup = nil
        requestHeaders = result.headers

        let url = URL(string: result.url)
        let hash = result.infoHash ?? Self.magnetInfoHash(result.url)
        if let url, url.scheme?.lowercased() == "https", url.host != nil {
            delivery = .nativeHTTPS(url)
            hasPeerDiscoveryHints = false
        } else if let hash,
                  let descriptor = try? LocalTorrentPlaybackDescriptor(
                    infoHash: hash,
                    fileIndex: nil,
                    displayName: result.title,
                    expectedByteCount: nil
                  ) {
            delivery = .localTorrent(descriptor)
            hasPeerDiscoveryHints = false
        } else {
            // Omnia only plays HTTPS streams; plain HTTP ones are listed but
            // not played, like an add-on's.
            delivery = .unsupported
            hasPeerDiscoveryHints = false
        }
    }

    private static func magnetInfoHash(_ text: String) -> String? {
        guard text.lowercased().hasPrefix("magnet:"),
              let range = text.range(of: #"(?i)urn:btih:([a-z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return text[range].split(separator: ":").last.map(String.init)
    }
}
