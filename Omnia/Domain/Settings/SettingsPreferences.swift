import Foundation

enum AddonTimeout: Int, Codable, CaseIterable, Sendable {
    case seconds5 = 5
    case seconds10 = 10
    case seconds15 = 15
    case seconds20 = 20
    case seconds30 = 30

    var duration: Duration { .seconds(rawValue) }
}

enum BoundedItemLimit: String, Codable, CaseIterable, Sendable {
    case items10
    case items20
    case items50
    case unlimited

    var value: Int? {
        switch self {
        case .items10: 10
        case .items20: 20
        case .items50: 50
        case .unlimited: nil
        }
    }
}

enum UpcomingLookAhead: Int, Codable, CaseIterable, Sendable {
    case days7 = 7
    case days14 = 14
    case days30 = 30
    case days60 = 60
    case days90 = 90
}

enum UpNextLeadTime: Int, Codable, CaseIterable, Sendable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
}

enum SourceSelectionRetention: Int, Codable, CaseIterable, Sendable {
    case hours24 = 1
    case days3 = 3
    case week1 = 7

    var duration: TimeInterval { TimeInterval(rawValue * 24 * 60 * 60) }
}

enum WatchlistMode: String, Codable, CaseIterable, Sendable {
    case local
}

enum PreferredLanguage: Codable, Equatable, Sendable {
    case followSystem
    case none
    case language(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case identifier
    }

    private enum Kind: String, Codable {
        case followSystem
        case none
        case language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .followSystem:
            self = .followSystem
        case .none:
            self = .none
        case .language:
            let identifier = try container.decode(String.self, forKey: .identifier)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, identifier.count <= 128 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .identifier,
                    in: container,
                    debugDescription: "Invalid language identifier"
                )
            }
            self = .language(identifier)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .followSystem:
            try container.encode(Kind.followSystem, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case let .language(identifier):
            try container.encode(Kind.language, forKey: .kind)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}

enum SDHPreference: String, Codable, CaseIterable, Sendable {
    case followSystem
    case prefer
    case avoid
}

enum AnimeAudioPreference: String, Codable, CaseIterable, Sendable {
    case followPreferred
    case sub
    case dub
}

enum SubtitleAppearanceMode: String, Codable, CaseIterable, Sendable {
    case followSystem
    case standard
    case boxed
    case classic
    case minimal
    case bold
    case custom
}

struct SettingsPreferences: Codable, Equatable, Sendable {
    var addonTimeout: AddonTimeout
    var continueWatchingLimit: BoundedItemLimit
    var watchlistMode: WatchlistMode
    var showUpcoming: Bool
    var upcomingLookAhead: UpcomingLookAhead
    var upcomingItemLimit: BoundedItemLimit
    var showSkipIntro: Bool
    var autoSkipIntro: Bool
    var autoplayNextEpisode: Bool
    var upNextLeadTime: UpNextLeadTime
    var rememberLastSelection: Bool
    var sourceSelectionRetention: SourceSelectionRetention
    var autoplayFirstCompatibleSource: Bool
    var directContinueWatchingPlayback: Bool
    var compatibleFormatsOnly: Bool
    var preferredAudioLanguage: PreferredLanguage
    var audioFallbackLanguage: PreferredLanguage
    var preferredSubtitleLanguage: PreferredLanguage
    var subtitleFallbackLanguage: PreferredLanguage
    var sdhPreference: SDHPreference
    var animeAudioPreference: AnimeAudioPreference
    var subtitleAppearance: SubtitleAppearanceMode

    static let `default` = SettingsPreferences(
        addonTimeout: .seconds20,
        continueWatchingLimit: .unlimited,
        watchlistMode: .local,
        showUpcoming: true,
        upcomingLookAhead: .days60,
        upcomingItemLimit: .unlimited,
        showSkipIntro: true,
        autoSkipIntro: false,
        autoplayNextEpisode: false,
        upNextLeadTime: .seconds30,
        rememberLastSelection: true,
        sourceSelectionRetention: .days3,
        autoplayFirstCompatibleSource: false,
        directContinueWatchingPlayback: false,
        compatibleFormatsOnly: true,
        preferredAudioLanguage: .followSystem,
        audioFallbackLanguage: .none,
        preferredSubtitleLanguage: .followSystem,
        subtitleFallbackLanguage: .none,
        sdhPreference: .followSystem,
        animeAudioPreference: .followPreferred,
        subtitleAppearance: .followSystem
    )

    var normalized: SettingsPreferences {
        var value = self
        if !value.showSkipIntro {
            value.autoSkipIntro = false
        }
        if !value.rememberLastSelection {
            value.autoplayFirstCompatibleSource = false
        }
        if value.audioFallbackLanguage == value.preferredAudioLanguage {
            value.audioFallbackLanguage = .none
        }
        if value.subtitleFallbackLanguage == value.preferredSubtitleLanguage {
            value.subtitleFallbackLanguage = .none
        }
        return value
    }
}
