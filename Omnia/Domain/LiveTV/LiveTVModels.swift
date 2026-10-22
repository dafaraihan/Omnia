//
//  LiveTVModels.swift
//  Omnia
//

import CryptoKit
import Foundation

/// One channel from a playlist, an Xtream account or a Stalker portal
/// (Nuvio Enhanced's Live TV). Provider channels keep only what identifies
/// the stream; the playable link is built when the channel is played, so
/// account passwords never sit in a saved channel.
nonisolated struct LiveTVChannel: Identifiable, Hashable, Codable, Sendable {
    enum Stream: Hashable, Codable, Sendable {
        case direct(url: URL, headers: [String: String])
        case xtream(streamID: String, containerExtension: String)
        case stalker(command: String)
    }

    /// Stable across reloads and free of stream links, so favorites and the
    /// last watched channel can be saved in plain settings.
    let id: String
    let name: String
    let logoURL: URL?
    let group: String?
    let sourceID: String
    let sourceName: String
    /// tvg-id, epg_channel_id or xmltv_id: the channel's id in a TV guide.
    let guideID: String?
    let stream: Stream

    /// The same stream listed twice is shown once.
    var streamKey: String {
        switch stream {
        case let .direct(url, _): "url:\(url.absoluteString)"
        case let .xtream(streamID, _): "xtream:\(streamID)"
        case let .stalker(command): "stalker:\(command)"
        }
    }
}

nonisolated struct LiveTVProgram: Hashable, Codable, Sendable {
    let title: String
    let start: Date
    let end: Date
    let detail: String?
    let category: String?

    func isAiring(at date: Date) -> Bool {
        start <= date && date < end
    }

    func progress(at date: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / length, 0), 1)
    }
}

/// An M3U playlist added by address or from a file. The address lives in
/// the Keychain and a file's contents in Omnia's encrypted store, as both
/// often carry an account's credentials.
nonisolated struct LiveTVPlaylist: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case url
        case localFile
    }

    let id: String
    var name: String
    var kind: Kind
    var isEnabled: Bool
}

/// An XMLTV guide added by address. The address lives in the Keychain.
nonisolated struct LiveTVGuideSource: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var isEnabled: Bool
}

nonisolated struct LiveTVXtreamAccount: Hashable, Codable, Sendable {
    var server: URL
    var username: String
    var password: String
    var isEnabled: Bool = true
}

nonisolated struct LiveTVStalkerAccount: Hashable, Codable, Sendable {
    var portal: URL
    var macAddress: String
    var username: String
    var password: String
    var isEnabled: Bool = true
}

/// Everything secret about Live TV, saved as one Keychain item.
nonisolated struct LiveTVSecrets: Codable, Sendable {
    var playlistURLs: [String: URL] = [:]
    var guideURLs: [String: URL] = [:]
    var xtream: LiveTVXtreamAccount?
    var stalker: LiveTVStalkerAccount?
}

/// The non-secret Live TV settings, saved in UserDefaults.
nonisolated struct LiveTVConfiguration: Codable, Sendable {
    var playlists: [LiveTVPlaylist] = []
    var guides: [LiveTVGuideSource] = []
    /// Nuvio's "Show Live TV in navigation".
    var showsInNavigation = true
    /// Nuvio's "Auto-detect guides": guides named by playlists and the
    /// Xtream account are used without being added by hand.
    var autoDetectsGuides = true
    var favoriteChannelIDs: [String] = []
    var lastWatchedChannelID: String?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playlists = try container.decodeIfPresent([LiveTVPlaylist].self, forKey: .playlists) ?? []
        guides = try container.decodeIfPresent([LiveTVGuideSource].self, forKey: .guides) ?? []
        showsInNavigation = try container.decodeIfPresent(Bool.self, forKey: .showsInNavigation) ?? true
        autoDetectsGuides = try container.decodeIfPresent(Bool.self, forKey: .autoDetectsGuides) ?? true
        favoriteChannelIDs = try container.decodeIfPresent([String].self, forKey: .favoriteChannelIDs) ?? []
        lastWatchedChannelID = try container.decodeIfPresent(String.self, forKey: .lastWatchedChannelID)
    }
}

nonisolated enum LiveTVFailure: Error, Equatable, LocalizedError {
    case invalidAddress
    case insecureAddress
    case unreachable
    case status(Int)
    case tooLarge
    case invalidResponse
    case signInRejected
    case notConfigured
    case fileUnreadable

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter a full address, such as https://example.com/playlist.m3u."
        case .insecureAddress: "Only http:// and https:// addresses without a user name in them can be used."
        case .unreachable: "The server could not be reached."
        case let .status(code): "The server returned status \(code)."
        case .tooLarge: "The file is larger than Omnia's 64 MB limit."
        case .invalidResponse: "The server returned something Omnia could not read."
        case .signInRejected: "The server rejected these sign-in details."
        case .notConfigured: "This source isn't set up anymore."
        case .fileUnreadable: "Omnia couldn't read that file."
        }
    }
}

// MARK: Addresses

/// Live TV's one exception to Omnia's HTTPS rule (Dafa, 2026-10-21): most IPTV
/// providers only serve plain http://, so Live TV sources, their guides,
/// logos and streams may use http:// on any host. Only Live TV uses this; the
/// rest of the app keeps `MediaServerAddressPolicy`. See SECURITY.md.
nonisolated enum LiveTVAddressPolicy {
    static func permits(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host, !host.isEmpty else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// Plain http:// to anywhere but the local network, which App Transport
    /// Security refuses, so Live TV fetches it itself.
    static func needsPlainHTTP(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" && !MediaServerAddressPolicy.isLocalHost(url.host ?? "")
    }
}

nonisolated enum LiveTVAddress {
    /// The address people paste, with https:// added when they leave the
    /// scheme out (http:// for a local server).
    static func url(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            let hostAndPort = text.split(separator: "/").first.map(String.init) ?? text
            let host = hostAndPort.split(separator: ":").first.map(String.init) ?? hostAndPort
            text = (MediaServerAddressPolicy.isLocalHost(host) ? "http://" : "https://") + text
        }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url
        else { return nil }
        return url
    }

    /// Xtream accounts are entered as the server address; a pasted
    /// player_api.php link is trimmed back to it.
    static func xtreamServer(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "/player_api.php", options: .caseInsensitive) {
            text = String(text[..<range.lowerBound])
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = url(from: text) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    static func stalkerPortal(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        return url(from: text)
    }

    /// Accepts 00:1A:79:12:34:56 written with any separator or none.
    static func macAddress(from input: String) -> String? {
        let hex = input.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var pairs: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            pairs.append(String(hex[index..<next]))
            index = next
        }
        return pairs.joined(separator: ":")
    }
}

// MARK: M3U

nonisolated enum LiveTVPlaylistParser {
    /// Channels in playlist order. `#EXTVLCOPT` user agent and referrer lines
    /// become the stream's request headers.
    static func channels(in text: String, sourceID: String, sourceName: String) -> [LiveTVChannel] {
        var channels: [LiveTVChannel] = []
        var seen = Set<String>()
        var info: ExtInf?
        var headers: [String: String] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let upper = line.prefix(12).uppercased()
                if upper.hasPrefix("#EXTINF") {
                    info = extInf(line)
                    headers = [:]
                } else if upper.hasPrefix("#EXTVLCOPT") {
                    let option = line.drop { $0 != ":" }.dropFirst()
                    let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        switch parts[0].lowercased() {
                        case "http-user-agent": headers["User-Agent"] = parts[1]
                        case "http-referrer", "http-referer": headers["Referer"] = parts[1]
                        default: break
                        }
                    }
                }
                continue
            }
            defer {
                info = nil
                headers = [:]
            }
            guard let url = URL(string: line), let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil
            else { continue }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            let fallbackName = url.deletingPathExtension().lastPathComponent
            let name = info?.name.nonBlank ?? (fallbackName.isEmpty ? "Channel" : fallbackName)
            channels.append(LiveTVChannel(
                id: "m3u:\(sourceID):\(LiveTVHashing.digest(key))",
                name: name,
                logoURL: info?.logo.flatMap { URL(string: $0) },
                group: info?.group?.nonBlank,
                sourceID: sourceID,
                sourceName: sourceName,
                guideID: info?.guideID?.nonBlank,
                stream: .direct(url: url, headers: headers)
            ))
        }
        return channels
    }

    /// Guide addresses named in the playlist header (url-tvg, x-tvg-url or
    /// tvg-url, each possibly a comma-separated list).
    static func guideURLs(in text: String) -> [URL] {
        guard let header = text.split(whereSeparator: \.isNewline).lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }),
              header.uppercased().hasPrefix("#EXTM3U")
        else { return [] }
        var urls: [URL] = []
        for key in ["url-tvg", "x-tvg-url", "tvg-url"] {
            guard let value = attribute(key, in: header) else { continue }
            for part in value.split(separator: ",") {
                let text = part.trimmingCharacters(in: .whitespaces)
                guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      !urls.contains(url) else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    private struct ExtInf {
        let name: String
        let logo: String?
        let group: String?
        let guideID: String?
    }

    private static func extInf(_ line: String) -> ExtInf {
        // The name follows the first comma outside a quoted attribute, as
        // group titles may hold commas of their own.
        var inQuotes = false
        var nameStart: String.Index?
        for index in line.indices {
            let character = line[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                nameStart = line.index(after: index)
                break
            }
        }
        let name = nameStart.map { String(line[$0...]).trimmingCharacters(in: .whitespaces) } ?? ""
        return ExtInf(
            name: name.nonBlank ?? attribute("tvg-name", in: line) ?? "",
            logo: attribute("tvg-logo", in: line),
            group: attribute("group-title", in: line),
            guideID: attribute("tvg-id", in: line)
        )
    }

    static func attribute(_ key: String, in line: String) -> String? {
        var searchStart = line.startIndex
        while let range = line.range(of: key + "=", options: .caseInsensitive, range: searchStart..<line.endIndex) {
            searchStart = range.upperBound
            // `tvg-url` must not match inside `x-tvg-url`.
            if range.lowerBound > line.startIndex {
                let previous = line[line.index(before: range.lowerBound)]
                guard previous == " " || previous == "\t" || previous == ":" else { continue }
            }
            var valueStart = range.upperBound
            guard valueStart < line.endIndex else { return nil }
            let value: Substring
            if line[valueStart] == "\"" {
                valueStart = line.index(after: valueStart)
                let end = line[valueStart...].firstIndex(of: "\"") ?? line.endIndex
                value = line[valueStart..<end]
            } else {
                let end = line[valueStart...].firstIndex { $0 == " " || $0 == "," } ?? line.endIndex
                value = line[valueStart..<end]
            }
            return String(value).nonBlank
        }
        return nil
    }
}

// MARK: TV guide

nonisolated enum LiveTVGuideMatcher {
    private static let qualityTokens: Set<String> = [
        "hd", "fhd", "uhd", "sd", "hq", "4k", "8k", "hevc", "h264", "h265", "raw",
        "480p", "576p", "720p", "1080p", "1080i", "2160p", "720", "1080", "2160", "60fps", "50fps"
    ]

    /// "UK: BBC One HD [Backup]" and "BBC One" both become "bbcone".
    static func normalizedName(_ name: String) -> String {
        var text = name.lowercased()
        for (open, close) in [("[", "]"), ("(", ")"), ("{", "}")] {
            while let start = text.range(of: open),
                  let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        // Drop a short country or package prefix such as "UK:" or "US |".
        if let separator = text.firstIndex(where: { $0 == ":" || $0 == "|" }) {
            let prefix = text[..<separator].trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty, prefix.count <= 6 {
                text = String(text[text.index(after: separator)...])
            }
        }
        return text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !qualityTokens.contains($0) }
            .joined()
    }

    /// The programme airing at `date` and the one after it.
    static func nowAndNext(in programs: [LiveTVProgram], at date: Date) -> (now: LiveTVProgram?, next: LiveTVProgram?) {
        let current = programs.first { $0.isAiring(at: date) }
        let after = current?.end ?? date
        let next = programs.first { $0.start >= after }
        return (current, next)
    }
}

/// XMLTV times look like `20261021183000 +0700`.
nonisolated enum LiveTVGuideTime {
    static func date(from text: String) -> Date? {
        let bytes = Array(text.utf8)
        func number(_ start: Int, _ length: Int) -> Int? {
            guard start >= 0, start + length <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[start..<(start + length)] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2),
              let hour = number(8, 2), let minute = number(10, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let second = number(12, 2) ?? 0
        var offset = 0
        if let signIndex = bytes.firstIndex(where: { $0 == 43 || $0 == 45 }), signIndex >= 12,
           let hours = number(signIndex + 1, 2), let minutes = number(signIndex + 3, 2) {
            offset = (hours * 3_600 + minutes * 60) * (bytes[signIndex] == 45 ? -1 : 1)
        }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Days since 1970-01-01 for a Gregorian date.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

nonisolated enum LiveTVHashing {
    /// A short, stable id for text that may hold credentials.
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    nonisolated var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
