//
//  PlaybackFailureLog.swift
//  Omnia
//

import Foundation

/// One playback failure, kept so the next "could not play" can be sent
/// along (Dafa, 2026-10-26). Never the stream's address: only its host,
/// and URLs inside mpv's message are cut down to their host too, so no
/// path, query or token is stored.
nonisolated struct PlaybackFailureEntry: Codable, Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let titleID: String
    let title: String
    let episode: String?
    let addon: String
    let host: String
    let message: String
    var outcome: String?

    var reportLine: String {
        var parts = [
            date.formatted(.iso8601),
            "\(title) [\(titleID)]" + (episode.map { " \($0)" } ?? ""),
            "\(addon) @ \(host)",
            message
        ]
        if let outcome { parts.append("→ \(outcome)") }
        return parts.joined(separator: " | ")
    }
}

/// The last 50 playback failures, in Application Support.
@MainActor
final class PlaybackFailureLog {
    static let shared = PlaybackFailureLog()
    static let limit = 50

    private(set) var entries: [PlaybackFailureEntry] = []
    private let fileURL: URL?

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) {
        fileURL = directory?.appending(path: "Omnia", directoryHint: .isDirectory)
            .appending(path: "playback-failures.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            entries = (try? Self.decoder.decode([PlaybackFailureEntry].self, from: data)) ?? []
        }
    }

    @discardableResult
    func record(
        item: MediaItem,
        episode: MediaEpisode?,
        candidate: AddonStreamCandidate?,
        streamURL: URL?,
        message: String
    ) -> Date {
        let entry = PlaybackFailureEntry(
            date: .now,
            titleID: item.id,
            title: item.title,
            episode: episode.map { "S\($0.seasonNumber)E\($0.episodeNumber)" },
            addon: candidate?.addonName ?? "Unknown source",
            host: streamURL?.host() ?? "unknown host",
            message: Self.redacted(message)
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
        return entry.date
    }

    /// Notes what recovery did after the failure recorded at `date`.
    func setOutcome(_ outcome: String, for date: Date) {
        guard let index = entries.firstIndex(where: { $0.date == date }) else { return }
        entries[index].outcome = outcome
        save()
    }

    func removeAll() {
        entries = []
        save()
    }

    var report: String {
        entries.map(\.reportLine).joined(separator: "\n")
    }

    /// Replaces every URL in mpv's message with its host.
    nonisolated static func redacted(_ message: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return message
        }
        var result = message
        let matches = detector.matches(in: message, range: NSRange(message.startIndex..., in: message))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let host = match.url?.host() ?? "link"
            result.replaceSubrange(range, with: "<\(host)>")
        }
        return String(result.prefix(500))
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
