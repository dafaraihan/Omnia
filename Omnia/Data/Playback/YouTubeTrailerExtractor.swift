import Foundation

/// Resolves a public trailer on-device. Uses the player-response approach
/// documented in Nuvio Enhanced; no remote resolver, scripts or user cookies.
/// Only single-source HLS/muxed MP4 is suitable for Omnia's preview AVPlayer.
nonisolated struct YouTubeTrailerExtractor: Sendable {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private struct Client: Sendable {
        let name: String
        let id: String
        let version: String
        let userAgent: String
    }

    private static let clients = [
        Client(name: "VISIONOS", id: "101", version: "1.02",
               userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"),
        Client(name: "ANDROID_VR", id: "28", version: "1.65.10",
               userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L) gzip"),
        Client(name: "IOS", id: "5", version: "20.10.1",
               userAgent: "com.google.ios.youtube/20.10.1 (iPhone16,2; U; CPU iOS 17_4 like Mac OS X)")
    ]

    @concurrent
    func resolve(videoID: String) async -> HeroTrailerSource? {
        guard videoID.count == 11,
              videoID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return await withTaskGroup(of: HeroTrailerSource?.self) { group in
            group.addTask { try? await Self.extract(videoID: videoID) }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func extract(videoID: String) async throws -> HeroTrailerSource? {
        let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)&hl=en")!
        var watchRequest = URLRequest(url: watchURL)
        watchRequest.setValue(clients[0].userAgent, forHTTPHeaderField: "User-Agent")
        let html = String(decoding: try await read(watchRequest, limit: 4 * 1_024 * 1_024), as: UTF8.self)
        guard let key = configValue("INNERTUBE_API_KEY", in: html), key.count <= 256 else { return nil }
        let visitor = configValue("VISITOR_DATA", in: html).flatMap { $0.count <= 4_096 ? $0 : nil }
        var endpoint = URLComponents(string: "https://www.youtube.com/youtubei/v1/player")!
        endpoint.queryItems = [URLQueryItem(name: "key", value: key)]

        for client in clients {
            try Task.checkCancellation()
            do {
                var context: [String: Any] = [
                    "clientName": client.name, "clientVersion": client.version,
                    "hl": "en", "gl": "US"
                ]
                switch client.name {
                case "VISIONOS":
                    context.merge(["deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                                   "osName": "visionOS", "osVersion": "26.5.23O471"]) { _, new in new }
                case "ANDROID_VR":
                    context.merge(["deviceMake": "Oculus", "deviceModel": "Quest 3", "osName": "Android",
                                   "osVersion": "12L", "androidSdkVersion": 32, "platform": "MOBILE"]) { _, new in new }
                default:
                    context.merge(["deviceModel": "iPhone16,2", "osName": "iPhone",
                                   "osVersion": "17.4.0.21E219", "platform": "MOBILE"]) { _, new in new }
                }
                var request = URLRequest(url: endpoint.url!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                request.setValue(client.id, forHTTPHeaderField: "X-YouTube-Client-Name")
                request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
                request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "videoId": videoID, "context": ["client": context],
                    "contentCheckOk": true, "racyCheckOk": true,
                    "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]]
                ])
                let response = try JSONDecoder().decode(PlayerResponse.self, from: await read(request, limit: 1_024 * 1_024))
                guard response.playabilityStatus?.status == "OK", let streams = response.streamingData else { continue }
                if let raw = streams.hlsManifestUrl, let url = mediaURL(raw),
                   let source = try? await fullHDManifest(url) {
                    return source
                }
                // Adaptive files require a separate audio source. Never pass a
                // silent video-only format to the single-source preview player.
                let formats = (streams.formats ?? []).filter {
                    $0.mimeType?.hasPrefix("video/mp4") == true &&
                    $0.mimeType?.contains("mp4a") == true && $0.height == 1_080 && $0.width == 1_920
                }
                for format in formats.prefix(3) {
                    guard let raw = format.url, let url = mediaURL(raw) else { continue }
                    if (try? await probe(url)) == true { return HeroTrailerSource(url: url) }
                }
            } catch {
                try Task.checkCancellation()
                // Client profiles can stop working independently. Try the next
                // one without logging signed media URLs or response contents.
            }
        }
        return nil
    }

    private static func configValue(_ name: String, in html: String) -> String? {
        let pattern = "\"\(name)\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    /// Normalize before comparing host boundaries; substring checks would
    /// accept googlevideo.com.attacker.example. Credentials/ports are rejected.
    static func mediaURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= 16_384, let url = URL(string: raw), secure(url),
              let host = url.host?.lowercased(), host.hasSuffix(".googlevideo.com") else { return nil }
        return url
    }

    private static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil &&
            url.fragment == nil && (url.port == nil || url.port == 443)
    }

    private static func permitted(_ url: URL) -> Bool {
        secure(url) && (url.host?.lowercased() == "www.youtube.com" || mediaURL(url.absoluteString) != nil)
    }

    private static func read(_ request: URLRequest, limit: Int) async throws -> Data {
        guard let url = request.url, permitted(url) else { throw URLError(.badURL) }
        var request = request
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (bytes, response) = try await session.bytes(for: request, delegate: RedirectGuard())
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              let finalURL = response.url, permitted(finalURL),
              response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    private static func probe(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, response) = try await session.bytes(for: request, delegate: RedirectGuard())
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, let finalURL = response.url,
              mediaURL(finalURL.absoluteString) != nil,
              [200, 206].contains(response.statusCode) else { return false }
        // Validate headers only; even a server ignoring Range cannot make this
        // probe download an entire trailer into memory.
        return true
    }

    private static func fullHDManifest(_ url: URL) async throws -> HeroTrailerSource? {
        let data = try await read(URLRequest(url: url), limit: 256 * 1_024)
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.first == "#EXTM3U" else { return nil }
        var shared = ["#EXTM3U"]
        var variants: [(tag: String, url: URL)] = []
        let uriPattern = try NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.hasPrefix("#") {
                guard let resolved = URL(string: line, relativeTo: url)?.absoluteURL,
                      mediaURL(resolved.absoluteString) != nil else { return nil }
            }
            // Preserve audio/subtitle renditions, rewriting their relative
            // URLs because the filtered master is served from memory.
            var rewritten = line
            for match in uriPattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 1), in: line),
                      let resolved = URL(string: String(line[range]), relativeTo: url)?.absoluteURL,
                      mediaURL(resolved.absoluteString) != nil,
                      let replacementRange = Range(match.range(at: 1), in: rewritten) else { return nil }
                rewritten.replaceSubrange(replacementRange, with: resolved.absoluteString)
            }
            if line.hasPrefix("#EXT-X-VERSION:") || line == "#EXT-X-INDEPENDENT-SEGMENTS" ||
                line.hasPrefix("#EXT-X-MEDIA:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                shared.append(rewritten)
            }
            if line.hasPrefix("#EXT-X-STREAM-INF:"),
               String(line.dropFirst("#EXT-X-STREAM-INF:".count))
                .range(of: "(?:^|,)RESOLUTION=1920x1080(?:,|$)", options: .regularExpression) != nil,
               !line.contains("VIDEO=\""),
               index + 1 < lines.count, !lines[index + 1].hasPrefix("#"),
               let variant = URL(string: lines[index + 1], relativeTo: url)?.absoluteURL,
               mediaURL(variant.absoluteString) != nil {
                variants.append((rewritten, variant))
            }
        }
        for variant in variants.prefix(3) {
            try Task.checkCancellation()
            guard (try? await probe(variant.url)) == true else { continue }
            let master = (shared + [variant.tag, variant.url.absoluteString]).joined(separator: "\n") + "\n"
            return HeroTrailerSource(url: url, playlist: Data(master.utf8))
        }
        return nil
    }

    private struct PlayerResponse: Decodable {
        struct Playability: Decodable { let status: String? }
        struct Streams: Decodable {
            let hlsManifestUrl: String?
            let formats: [Format]?
        }
        struct Format: Decodable {
            let url: String?
            let mimeType: String?
            let height: Int?
            let width: Int?
        }
        let playabilityStatus: Playability?
        let streamingData: Streams?
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let source = response.url, let target = request.url,
                  task.countOfBytesReceived <= 4 * 1_024 * 1_024,
                  permitted(target),
                  source.host?.lowercased() == target.host?.lowercased() ||
                    (mediaURL(source.absoluteString) != nil && mediaURL(target.absoluteString) != nil)
            else { completionHandler(nil); return }
            completionHandler(request)
        }
    }
}
