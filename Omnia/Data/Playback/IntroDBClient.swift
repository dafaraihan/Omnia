import Foundation

enum IntroDBError: Error, Equatable {
    case invalidLookup
    case malformedResponse
    case responseTooLarge
}

struct IntroDBClient: Sendable {
    private static let origin = NormalizedOrigin(scheme: "https", host: "api.introdb.app", port: nil)
    private static let maximumResponseBytes = 256 * 1_024

    let transport: any HTTPTransporting

    init(transport: any HTTPTransporting = HTTPTransport()) {
        self.transport = transport
    }

    func segments(imdbID: String, season: Int, episode: Int) async throws -> [SkipSegment] {
        guard (0 ... 1_000).contains(season),
              (0 ... 10_000).contains(episode)
        else { throw IntroDBError.invalidLookup }
        return try await segments(imdbID: imdbID, query: [
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode))
        ], isMovie: false)
    }

    /// A movie's credits and post-credits scene, as Nuvio asks for them.
    func movieSegments(imdbID: String) async throws -> [SkipSegment] {
        try await segments(imdbID: imdbID, query: [
            URLQueryItem(name: "is_movie", value: "true")
        ], isMovie: true)
    }

    private func segments(imdbID: String, query: [URLQueryItem], isMovie: Bool) async throws -> [SkipSegment] {
        try Task.checkCancellation()
        guard imdbID.range(of: #"^tt[0-9]{7,10}$"#, options: .regularExpression) != nil
        else { throw IntroDBError.invalidLookup }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.introdb.app"
        components.path = "/segments"
        components.queryItems = [URLQueryItem(name: "imdb_id", value: imdbID)] + query
        guard let url = components.url else { throw IntroDBError.invalidLookup }
        let data = try await transport.data(for: HTTPRequestPolicy(
            url: url,
            allowedOrigin: Self.origin,
            timeout: 10,
            maximumResponseBytes: Self.maximumResponseBytes,
            acceptedContentTypes: ["application/json"]
        ))
        try Task.checkCancellation()
        guard data.count <= Self.maximumResponseBytes else { throw IntroDBError.responseTooLarge }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            let scene = try response.postCredits.map { try $0.segment(kind: .postCredits) }
            var ending = try response.outro.map { try $0.segment(kind: isMovie ? .movieCredits : .outro) }
            // Credits stop where a post-credits scene starts, so skipping
            // them never jumps past the scene.
            if let current = ending, let scene,
               scene.startSeconds > current.startSeconds, scene.startSeconds < current.endSeconds {
                ending = SkipSegment(
                    kind: current.kind,
                    startSeconds: current.startSeconds,
                    endSeconds: scene.startSeconds,
                    confidence: current.confidence
                )
            }
            let values = try [
                isMovie ? nil : response.intro.map { try $0.segment(kind: .intro) },
                isMovie ? nil : response.recap.map { try $0.segment(kind: .recap) },
                ending,
                scene
            ].compactMap { $0 }
            guard values.count <= 32 else { throw IntroDBError.malformedResponse }
            return values.sorted { lhs, rhs in
                lhs.startSeconds == rhs.startSeconds ? lhs.kind.rawValue < rhs.kind.rawValue : lhs.startSeconds < rhs.startSeconds
            }
        } catch let error as IntroDBError {
            throw error
        } catch {
            throw IntroDBError.malformedResponse
        }
    }
}

private extension IntroDBClient {
    struct Response: Decodable {
        let intro: SegmentResponse?
        let recap: SegmentResponse?
        let outro: SegmentResponse?
        let postCredits: SegmentResponse?

        enum CodingKeys: String, CodingKey {
            case intro, recap, outro
            case postCredits = "post_credits"
        }
    }

    struct SegmentResponse: Decodable {
        let start: Double
        let end: Double
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case startSec = "start_sec"
            case endSec = "end_sec"
            case startMs = "start_ms"
            case endMs = "end_ms"
            case confidence
        }

        /// IntroDB answers in seconds, or in milliseconds for newer entries.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let start = try container.decodeIfPresent(FlexibleSeconds.self, forKey: .startSec),
               let end = try container.decodeIfPresent(FlexibleSeconds.self, forKey: .endSec) {
                self.start = start.value
                self.end = end.value
            } else {
                start = try container.decode(Double.self, forKey: .startMs) / 1_000
                end = try container.decode(Double.self, forKey: .endMs) / 1_000
            }
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        }

        func segment(kind: SkipSegment.Kind) throws -> SkipSegment {
            let start = self.start
            let end = self.end
            guard start.isFinite, end.isFinite,
                  start >= 0, start < end, end <= 12 * 60 * 60,
                  confidence == nil || (confidence!.isFinite && (0 ... 1).contains(confidence!))
            else { throw IntroDBError.malformedResponse }
            return SkipSegment(kind: kind, startSeconds: start, endSeconds: end, confidence: confidence)
        }
    }

    struct FlexibleSeconds: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
                return
            }
            let text = try container.decode(String.self)
            let parts = text.split(separator: ":").compactMap { Double($0) }
            guard (2 ... 3).contains(parts.count) else {
                throw IntroDBError.malformedResponse
            }
            value = parts.reduce(0) { $0 * 60 + $1 }
        }
    }
}
