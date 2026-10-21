import Foundation

/// Settings › Layout › Home Layout › Hero Trailer, from Nuvio Enhanced:
/// play the featured title's trailer in the Home hero.
nonisolated struct HeroTrailerPreferences: Codable, Equatable, Sendable {
    static let delayRange = 0...10

    /// Nuvio Enhanced's "Hero Trailer Playback". Off by default.
    var autoplay = false
    /// Seconds to wait after a title appears before its trailer starts.
    var startDelaySeconds = 0
    var startsWithSound = false

    static let `default` = Self()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case autoplay, startDelaySeconds, startsWithSound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoplay = (try? container.decodeIfPresent(Bool.self, forKey: .autoplay)) ?? false
        let delay = (try? container.decodeIfPresent(Int.self, forKey: .startDelaySeconds)) ?? 0
        startDelaySeconds = min(max(delay, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        startsWithSound = (try? container.decodeIfPresent(Bool.self, forKey: .startsWithSound)) ?? false
    }

    static func delayTitle(_ seconds: Int) -> String {
        seconds <= 0 ? "Instant" : "\(seconds) s"
    }
}

extension MediaTitleDetails {
    /// Nuvio's hero trailer pick: a trailer first, then a teaser, then any
    /// other video, keeping TMDB's order within each kind.
    nonisolated var heroTrailer: MediaVideo? {
        func rank(_ video: MediaVideo) -> Int {
            switch video.type.lowercased() {
            case "trailer": 0
            case "teaser": 1
            default: 2
            }
        }
        return trailers.enumerated()
            .filter { $0.element.youtubeVideoID != nil }
            .min { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }?
            .element
    }
}

extension MediaVideo {
    /// Only canonical HTTPS YouTube watch links can seed trailer extraction.
    nonisolated var youtubeVideoID: String? {
        guard let components = URLComponents(url: watchURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(components.host?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.path == "/watch",
              let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
              value.count == 11,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return value
    }
}
