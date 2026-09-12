import Foundation

nonisolated enum HLSImagePlaylistError: Error, Equatable {
    case invalidUTF8
    case missingImagePlaylist
    case insecureURL
    case originRejected
    case malformed
    case boundsExceeded
}

nonisolated enum HLSImagePlaylistParser {
    static let maximumManifestBytes = 512 * 1_024
    static let maximumTiles = 10_000
    static let maximumSheetDimension = 8_192
    static let maximumTileDimension = 640

    static func imagePlaylistURL(data: Data, baseURL: URL) throws -> URL {
        let text = try manifestText(from: data)
        guard let baseOrigin = NormalizedOrigin(url: baseURL),
              baseURL.scheme?.lowercased() == "https" else {
            throw HLSImagePlaylistError.insecureURL
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("#EXT-X-IMAGE-STREAM-INF:") else { continue }
            let attributes = try parseAttributes(String(line.dropFirst("#EXT-X-IMAGE-STREAM-INF:".count)))
            guard let uri = attributes["URI"],
                  let resolved = URL(string: uri, relativeTo: baseURL)?.absoluteURL else {
                throw HLSImagePlaylistError.malformed
            }
            try validate(resourceURL: resolved, allowedOrigin: baseOrigin)
            return resolved
        }
        throw HLSImagePlaylistError.missingImagePlaylist
    }

    static func storyboard(
        data: Data,
        playlistURL: URL,
        allowedOriginURL: URL
    ) throws -> PlaybackStoryboardDescriptor {
        let text = try manifestText(from: data)
        guard let allowedOrigin = NormalizedOrigin(url: allowedOriginURL),
              allowedOriginURL.scheme?.lowercased() == "https" else {
            throw HLSImagePlaylistError.insecureURL
        }
        try validate(resourceURL: playlistURL, allowedOrigin: allowedOrigin)

        var pendingDuration: Double?
        var pendingTiles: TileDeclaration?
        var cumulativeStart = 0.0
        var tiles: [PlaybackStoryboardTile] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXT-X-BYTERANGE:") {
                throw HLSImagePlaylistError.malformed
            }
            if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first
                guard let value, let duration = Double(value), duration.isFinite, duration > 0 else {
                    throw HLSImagePlaylistError.malformed
                }
                pendingDuration = duration
                pendingTiles = nil
                continue
            }
            if line.hasPrefix("#EXT-X-TILES:") {
                pendingTiles = try tileDeclaration(
                    from: String(line.dropFirst("#EXT-X-TILES:".count))
                )
                continue
            }
            if line.hasPrefix("#") { continue }

            guard let segmentDuration = pendingDuration,
                  let imageURL = URL(string: line, relativeTo: playlistURL)?.absoluteURL else {
                throw HLSImagePlaylistError.malformed
            }
            try validate(resourceURL: imageURL, allowedOrigin: allowedOrigin)

            if let declaration = pendingTiles {
                let declaredCount = declaration.columns * declaration.rows
                guard declaredCount <= Self.maximumTiles - tiles.count else {
                    throw HLSImagePlaylistError.boundsExceeded
                }
                for index in 0 ..< declaredCount {
                    let start = cumulativeStart + min(Double(index) * declaration.duration, segmentDuration)
                    let end = min(start + declaration.duration, cumulativeStart + segmentDuration)
                    guard end > start else { continue }
                    let row = index / declaration.columns
                    let column = index % declaration.columns
                    tiles.append(
                        PlaybackStoryboardTile(
                            startTime: start,
                            endTime: end,
                            imageURL: imageURL,
                            crop: PlaybackStoryboardCrop(
                                x: column * declaration.width,
                                y: row * declaration.height,
                                width: declaration.width,
                                height: declaration.height
                            )
                        )
                    )
                }
            } else {
                guard tiles.count < Self.maximumTiles else {
                    throw HLSImagePlaylistError.boundsExceeded
                }
                tiles.append(
                    PlaybackStoryboardTile(
                        startTime: cumulativeStart,
                        endTime: cumulativeStart + segmentDuration,
                        imageURL: imageURL,
                        crop: nil
                    )
                )
            }
            cumulativeStart += segmentDuration
            pendingDuration = nil
            pendingTiles = nil
        }

        guard pendingDuration == nil, !tiles.isEmpty else {
            throw HLSImagePlaylistError.malformed
        }
        return PlaybackStoryboardDescriptor(allowedOriginURL: allowedOriginURL, tiles: tiles)
    }

    private struct TileDeclaration {
        let width: Int
        let height: Int
        let columns: Int
        let rows: Int
        let duration: Double
    }

    private static func tileDeclaration(from text: String) throws -> TileDeclaration {
        let attributes = try parseAttributes(text)
        guard let resolution = attributes["RESOLUTION"].flatMap(parsePair),
              let layout = attributes["LAYOUT"].flatMap(parsePair),
              let durationText = attributes["DURATION"],
              let duration = Double(durationText),
              duration.isFinite,
              duration > 0,
              (1 ... maximumTileDimension).contains(resolution.0),
              (1 ... maximumTileDimension).contains(resolution.1),
              (1 ... 100).contains(layout.0),
              (1 ... 100).contains(layout.1),
              resolution.0 * layout.0 <= maximumSheetDimension,
              resolution.1 * layout.1 <= maximumSheetDimension else {
            throw HLSImagePlaylistError.boundsExceeded
        }
        return TileDeclaration(
            width: resolution.0,
            height: resolution.1,
            columns: layout.0,
            rows: layout.1,
            duration: duration
        )
    }

    private static func parsePair(_ value: String) -> (Int, Int)? {
        let components = value.lowercased().split(separator: "x", maxSplits: 1)
        guard components.count == 2,
              let first = Int(components[0]),
              let second = Int(components[1]) else { return nil }
        return (first, second)
    }

    private static func manifestText(from data: Data) throws -> String {
        guard data.count <= maximumManifestBytes else {
            throw HLSImagePlaylistError.boundsExceeded
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw HLSImagePlaylistError.invalidUTF8
        }
        return text
    }

    private static func validate(resourceURL: URL, allowedOrigin: NormalizedOrigin) throws {
        guard resourceURL.scheme?.lowercased() == "https" else {
            throw HLSImagePlaylistError.insecureURL
        }
        guard allowedOrigin.permits(resourceURL) else {
            throw HLSImagePlaylistError.originRejected
        }
    }

    private static func parseAttributes(_ text: String) throws -> [String: String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character == ",", !quoted {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        guard !quoted else { throw HLSImagePlaylistError.malformed }
        fields.append(current)

        var result: [String: String] = [:]
        for field in fields {
            let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { throw HLSImagePlaylistError.malformed }
            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            var value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") || value.hasSuffix("\"") {
                guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
                    throw HLSImagePlaylistError.malformed
                }
                value.removeFirst()
                value.removeLast()
            }
            guard !key.isEmpty, !value.isEmpty else { throw HLSImagePlaylistError.malformed }
            result[key] = value
        }
        return result
    }
}
