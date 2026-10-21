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

enum WatchlistMode: String, Codable, CaseIterable, Sendable {
    case local
}

enum PreferredLanguage: Codable, Equatable, Hashable, Sendable {
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

enum MacNavigationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case sidebar
    case topBar

    var id: Self { self }
}

/// How Search opens on the Mac, chosen separately from the navigation
/// style. Automatic keeps each style's original behavior: a page in the
/// sidebar, a floating panel from the top bar.
enum MacSearchStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case page
    case floating

    var id: Self { self }

    func usesFloatingSearch(with navigationStyle: MacNavigationStyle) -> Bool {
        switch self {
        case .automatic: navigationStyle == .topBar
        case .page: false
        case .floating: true
        }
    }
}

nonisolated struct MDBListRatingPreferences: Codable, Equatable, Sendable {
    var discoveredProviderIDs: Set<String>
    var disabledProviderIDs: Set<String>

    init(
        discoveredProviderIDs: Set<String> = [],
        disabledProviderIDs: Set<String> = []
    ) {
        self.discoveredProviderIDs = discoveredProviderIDs
        self.disabledProviderIDs = disabledProviderIDs
    }

    static let `default` = Self()

    func isEnabled(_ id: MDBListRatingProviderID) -> Bool {
        !disabledProviderIDs.contains(id.rawValue)
    }

    var normalized: Self {
        Self(
            discoveredProviderIDs: canonicalIDs(from: discoveredProviderIDs),
            disabledProviderIDs: canonicalIDs(from: disabledProviderIDs)
        )
    }

    private func canonicalIDs(from values: Set<String>) -> Set<String> {
        Set(values.compactMap { MDBListRatingProviderID($0)?.rawValue })
    }
}

struct SettingsPreferences: Codable, Equatable, Sendable {
    var addonTimeout: AddonTimeout
    var continueWatchingLimit: BoundedItemLimit
    var watchlistMode: WatchlistMode
    var showUpcoming: Bool
    var upcomingLookAhead: UpcomingLookAhead
    var upcomingItemLimit: BoundedItemLimit
    var showSkipIntro: Bool
    var autoplayNextEpisode: Bool
    var directContinueWatchingPlayback: Bool
    var compatibleFormatsOnly: Bool
    var preferredAudioLanguage: PreferredLanguage
    var audioFallbackLanguage: PreferredLanguage
    var preferredSubtitleLanguage: PreferredLanguage
    var subtitleFallbackLanguage: PreferredLanguage
    var subtitlesEnabled: Bool
    var playbackSubtitleStyle: PlaybackSubtitleStyle
    var sdhPreference: SDHPreference
    var animeAudioPreference: AnimeAudioPreference
    var subtitleAppearance: SubtitleAppearanceMode
    var customSubtitleAppearance: SubtitleAppearance
    var mdblistRatings: MDBListRatingPreferences
    var showMediaCardLabels: Bool
    var navigationStyle: MacNavigationStyle
    var searchStyle: MacSearchStyle
    var display: DisplayPreferences
    var playbackBehavior: PlaybackBehaviorPreferences
    var integrations: IntegrationPreferences = .default
    var streams: StreamPagePreferences = .default
    var heroTrailer: HeroTrailerPreferences = .default

    private enum CodingKeys: String, CodingKey {
        case addonTimeout, continueWatchingLimit, watchlistMode, showUpcoming
        case upcomingLookAhead, upcomingItemLimit, showSkipIntro
        case autoplayNextEpisode
        case directContinueWatchingPlayback, compatibleFormatsOnly
        case preferredAudioLanguage, audioFallbackLanguage
        case preferredSubtitleLanguage, subtitleFallbackLanguage
        case subtitlesEnabled, playbackSubtitleStyle
        case sdhPreference, animeAudioPreference, subtitleAppearance
        case customSubtitleAppearance, mdblistRatings, showMediaCardLabels, navigationStyle
        case searchStyle, display, playbackBehavior, integrations, streams, heroTrailer
    }

    /// Settings replaced by `playbackBehavior`, read once to carry choices over.
    private enum LegacyCodingKeys: String, CodingKey {
        case autoSkipIntro, autoplayFirstCompatibleSource
    }

    init(
        addonTimeout: AddonTimeout,
        continueWatchingLimit: BoundedItemLimit,
        watchlistMode: WatchlistMode,
        showUpcoming: Bool,
        upcomingLookAhead: UpcomingLookAhead,
        upcomingItemLimit: BoundedItemLimit,
        showSkipIntro: Bool,
        autoplayNextEpisode: Bool,
        directContinueWatchingPlayback: Bool,
        compatibleFormatsOnly: Bool,
        preferredAudioLanguage: PreferredLanguage,
        audioFallbackLanguage: PreferredLanguage,
        preferredSubtitleLanguage: PreferredLanguage,
        subtitleFallbackLanguage: PreferredLanguage,
        subtitlesEnabled: Bool,
        playbackSubtitleStyle: PlaybackSubtitleStyle,
        sdhPreference: SDHPreference,
        animeAudioPreference: AnimeAudioPreference,
        subtitleAppearance: SubtitleAppearanceMode,
        customSubtitleAppearance: SubtitleAppearance,
        mdblistRatings: MDBListRatingPreferences,
        showMediaCardLabels: Bool,
        navigationStyle: MacNavigationStyle,
        searchStyle: MacSearchStyle = .automatic,
        display: DisplayPreferences = .default,
        playbackBehavior: PlaybackBehaviorPreferences = .default
    ) {
        self.addonTimeout = addonTimeout
        self.continueWatchingLimit = continueWatchingLimit
        self.watchlistMode = watchlistMode
        self.showUpcoming = showUpcoming
        self.upcomingLookAhead = upcomingLookAhead
        self.upcomingItemLimit = upcomingItemLimit
        self.showSkipIntro = showSkipIntro
        self.autoplayNextEpisode = autoplayNextEpisode
        self.directContinueWatchingPlayback = directContinueWatchingPlayback
        self.compatibleFormatsOnly = compatibleFormatsOnly
        self.preferredAudioLanguage = preferredAudioLanguage
        self.audioFallbackLanguage = audioFallbackLanguage
        self.preferredSubtitleLanguage = preferredSubtitleLanguage
        self.subtitleFallbackLanguage = subtitleFallbackLanguage
        self.subtitlesEnabled = subtitlesEnabled
        self.playbackSubtitleStyle = playbackSubtitleStyle
        self.sdhPreference = sdhPreference
        self.animeAudioPreference = animeAudioPreference
        self.subtitleAppearance = subtitleAppearance
        self.customSubtitleAppearance = customSubtitleAppearance
        self.mdblistRatings = mdblistRatings
        self.showMediaCardLabels = showMediaCardLabels
        self.navigationStyle = navigationStyle
        self.searchStyle = searchStyle
        self.display = display
        self.playbackBehavior = playbackBehavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addonTimeout = try container.decode(AddonTimeout.self, forKey: .addonTimeout)
        continueWatchingLimit = try container.decode(BoundedItemLimit.self, forKey: .continueWatchingLimit)
        watchlistMode = try container.decode(WatchlistMode.self, forKey: .watchlistMode)
        showUpcoming = try container.decode(Bool.self, forKey: .showUpcoming)
        upcomingLookAhead = try container.decode(UpcomingLookAhead.self, forKey: .upcomingLookAhead)
        upcomingItemLimit = try container.decode(BoundedItemLimit.self, forKey: .upcomingItemLimit)
        showSkipIntro = try container.decode(Bool.self, forKey: .showSkipIntro)
        autoplayNextEpisode = try container.decode(Bool.self, forKey: .autoplayNextEpisode)
        directContinueWatchingPlayback = try container.decode(Bool.self, forKey: .directContinueWatchingPlayback)
        compatibleFormatsOnly = try container.decode(Bool.self, forKey: .compatibleFormatsOnly)
        preferredAudioLanguage = try container.decode(PreferredLanguage.self, forKey: .preferredAudioLanguage)
        audioFallbackLanguage = try container.decode(PreferredLanguage.self, forKey: .audioFallbackLanguage)
        preferredSubtitleLanguage = try container.decode(PreferredLanguage.self, forKey: .preferredSubtitleLanguage)
        subtitleFallbackLanguage = try container.decode(PreferredLanguage.self, forKey: .subtitleFallbackLanguage)
        subtitlesEnabled = try container.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled) ?? true
        playbackSubtitleStyle = try container.decodeIfPresent(
            PlaybackSubtitleStyle.self,
            forKey: .playbackSubtitleStyle
        ) ?? .default
        sdhPreference = try container.decode(SDHPreference.self, forKey: .sdhPreference)
        animeAudioPreference = try container.decode(AnimeAudioPreference.self, forKey: .animeAudioPreference)
        subtitleAppearance = try container.decode(SubtitleAppearanceMode.self, forKey: .subtitleAppearance)
        customSubtitleAppearance = try container.decodeIfPresent(
            SubtitleAppearance.self,
            forKey: .customSubtitleAppearance
        ) ?? .default
        mdblistRatings = try container.decodeIfPresent(
            MDBListRatingPreferences.self,
            forKey: .mdblistRatings
        ) ?? .default
        showMediaCardLabels = try container.decodeIfPresent(
            Bool.self,
            forKey: .showMediaCardLabels
        ) ?? true
        navigationStyle = try container.decodeIfPresent(
            MacNavigationStyle.self,
            forKey: .navigationStyle
        ) ?? .sidebar
        searchStyle = try container.decodeIfPresent(
            MacSearchStyle.self,
            forKey: .searchStyle
        ) ?? .automatic
        display = (try? container.decodeIfPresent(
            DisplayPreferences.self,
            forKey: .display
        )) ?? .default
        integrations = (try? container.decodeIfPresent(
            IntegrationPreferences.self,
            forKey: .integrations
        )) ?? .default
        streams = (try? container.decodeIfPresent(
            StreamPagePreferences.self,
            forKey: .streams
        )) ?? .default
        heroTrailer = (try? container.decodeIfPresent(
            HeroTrailerPreferences.self,
            forKey: .heroTrailer
        )) ?? .default
        if let behavior = try? container.decodeIfPresent(
            PlaybackBehaviorPreferences.self,
            forKey: .playbackBehavior
        ) {
            playbackBehavior = behavior
        } else {
            let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            var behavior = PlaybackBehaviorPreferences.default
            if (try? legacy?.decodeIfPresent(Bool.self, forKey: .autoSkipIntro)) == true {
                behavior.autoSkipSegments = [.intro]
            }
            if (try? legacy?.decodeIfPresent(Bool.self, forKey: .autoplayFirstCompatibleSource)) == true {
                behavior.autoSelectionMode = .firstSource
            }
            playbackBehavior = behavior
        }
    }

    static let `default` = SettingsPreferences(
        addonTimeout: .seconds20,
        continueWatchingLimit: .unlimited,
        watchlistMode: .local,
        showUpcoming: true,
        upcomingLookAhead: .days60,
        upcomingItemLimit: .unlimited,
        showSkipIntro: true,
        autoplayNextEpisode: false,
        directContinueWatchingPlayback: false,
        compatibleFormatsOnly: true,
        preferredAudioLanguage: .followSystem,
        audioFallbackLanguage: .none,
        preferredSubtitleLanguage: .followSystem,
        subtitleFallbackLanguage: .none,
        subtitlesEnabled: true,
        playbackSubtitleStyle: .default,
        sdhPreference: .followSystem,
        animeAudioPreference: .followPreferred,
        subtitleAppearance: .followSystem,
        customSubtitleAppearance: .default,
        mdblistRatings: .default,
        showMediaCardLabels: true,
        navigationStyle: .sidebar
    )

    var normalized: SettingsPreferences {
        var value = self
        if value.audioFallbackLanguage == value.preferredAudioLanguage {
            value.audioFallbackLanguage = .none
        }
        if value.subtitleFallbackLanguage == value.preferredSubtitleLanguage {
            value.subtitleFallbackLanguage = .none
        }
        value.customSubtitleAppearance = value.customSubtitleAppearance.normalized
        value.playbackSubtitleStyle = value.playbackSubtitleStyle.normalized
        value.mdblistRatings = value.mdblistRatings.normalized
        value.display = value.display.normalized
        value.playbackBehavior = value.playbackBehavior.normalized
        return value
    }

    var resolvedSubtitleAppearance: SubtitleAppearance {
        switch subtitleAppearance {
        case .followSystem, .standard: .standard
        case .boxed: .boxed
        case .classic: .classic
        case .minimal: .minimal
        case .bold: .bold
        case .custom: customSubtitleAppearance.normalized
        }
    }
}
