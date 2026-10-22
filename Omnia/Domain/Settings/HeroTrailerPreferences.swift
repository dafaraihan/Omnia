import Foundation

/// What the Home hero does once a title's trailer has played to the end.
nonisolated enum HeroTrailerEndAction: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Move straight on to the next title (Dafa, 2026-10-22).
    case nextTitle
    /// Show the artwork again; the carousel moves on at its usual pace.
    case showArtwork
    /// Play the same trailer again and keep the title.
    case replay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextTitle: "Next Title"
        case .showArtwork: "Show Artwork"
        case .replay: "Replay Trailer"
        }
    }
}

/// Settings › Layout › Home Layout › Hero, from Nuvio Enhanced: the
/// carousel's pace and the featured title's trailer in the Home hero.
nonisolated struct HeroTrailerPreferences: Codable, Equatable, Sendable {
    static let delayRange = 0...10
    static let intervalRange = 5...20

    /// Nuvio Enhanced's "Hero Trailer Playback". Off by default.
    var autoplay = false
    /// Seconds to wait after a title appears before its trailer starts.
    var startDelaySeconds = 0
    var startsWithSound = false
    var afterTrailer: HeroTrailerEndAction = .nextTitle
    /// The carousel moves to the next title on its own.
    var autoAdvance = true
    /// Seconds a title without a playing trailer stays in the hero.
    var intervalSeconds = 8

    static let `default` = Self()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case autoplay, startDelaySeconds, startsWithSound, afterTrailer, autoAdvance, intervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoplay = (try? container.decodeIfPresent(Bool.self, forKey: .autoplay)) ?? false
        let delay = (try? container.decodeIfPresent(Int.self, forKey: .startDelaySeconds)) ?? 0
        startDelaySeconds = min(max(delay, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        startsWithSound = (try? container.decodeIfPresent(Bool.self, forKey: .startsWithSound)) ?? false
        afterTrailer = (try? container.decodeIfPresent(HeroTrailerEndAction.self, forKey: .afterTrailer)) ?? .nextTitle
        autoAdvance = (try? container.decodeIfPresent(Bool.self, forKey: .autoAdvance)) ?? true
        let interval = (try? container.decodeIfPresent(Int.self, forKey: .intervalSeconds)) ?? 8
        intervalSeconds = min(max(interval, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
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
