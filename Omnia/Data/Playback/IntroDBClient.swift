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
        try Task.checkCancellation()
        guard imdbID.range(of: #"^tt[0-9]{7,10}$"#, options: .regularExpression) != nil,
              (0 ... 1_000).contains(season),
              (0 ... 10_000).contains(episode)
        else { throw IntroDBError.invalidLookup }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.introdb.app"
        components.path = "/segments"
        components.queryItems = [
            URLQueryItem(name: "imdb_id", value: imdbID),
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode))
        ]
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
            let values = try [
                response.intro.map { try $0.segment(kind: .intro) },
                response.recap.map { try $0.segment(kind: .recap) },
                response.outro.map { try $0.segment(kind: .outro) }
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
    }

    struct SegmentResponse: Decodable {
        let startSec: FlexibleSeconds
        let endSec: FlexibleSeconds
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case startSec = "start_sec"
            case endSec = "end_sec"
            case confidence
        }

        func segment(kind: SkipSegment.Kind) throws -> SkipSegment {
            let start = startSec.value
            let end = endSec.value
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
