import Foundation

/// Nuvio's Auto Stream Selection modes.
nonisolated enum AutoStreamSelectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case firstSource
    case regexMatch

    var id: Self { self }

    var title: String {
        switch self {
        case .manual: "Manual"
        case .firstSource: "First Available Source"
        case .regexMatch: "Regex Match"
        }
    }
}

/// Which sources automatic selection may pick from.
nonisolated enum AutoStreamSelectionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case allSources
    case addonsOnly
    case pluginsOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .allSources: "All Sources"
        case .addonsOnly: "Add-ons Only"
        case .pluginsOnly: "Plugins Only"
        }
    }
}

nonisolated enum NextEpisodeThresholdMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage
    case minutesBeforeEnd

    var id: Self { self }

    var title: String {
        switch self {
        case .percentage: "Percentage Watched"
        case .minutesBeforeEnd: "Minutes Before End"
        }
    }
}

/// Nuvio's Decoder Priority, mapped onto mpv's hwdec options.
nonisolated enum DecoderPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case deviceOnly
    case preferDevice
    case preferApp

    var id: Self { self }

    var title: String {
        switch self {
        case .deviceOnly: "Hardware Only"
        case .preferDevice: "Prefer Hardware"
        case .preferApp: "Software"
        }
    }

    var detail: String {
        switch self {
        case .deviceOnly: "Uses the Mac's video decoder and never falls back to software."
        case .preferDevice: "Uses the Mac's video decoder, and software when it can't."
        case .preferApp: "Decodes in software. Uses more power, but plays unusual formats."
        }
    }
}

/// How long automatic selection waits for add-ons before choosing.
/// 0 picks the first match as soon as it arrives; `unlimited` waits for every
/// source to answer.
nonisolated enum StreamSelectionTimeout {
    static let unlimited = -1
    static let options = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 25, 30, unlimited]

    static func title(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Instant"
        case unlimited: "Unlimited"
        case 1: "1 second"
        default: "\(seconds) seconds"
        }
    }

    /// Snaps a stored value to the nearest offered option, lower on a tie.
    static func normalized(_ seconds: Int) -> Int {
        if seconds < 0 || seconds > 30 { return unlimited }
        let finite = options.filter { $0 >= 0 }
        return finite.min { lhs, rhs in
            let left = abs(lhs - seconds)
            let right = abs(rhs - seconds)
            return left == right ? lhs < rhs : left < right
        } ?? 3
    }
}

/// Regex presets from Nuvio's Auto Stream Selection page.
nonisolated struct StreamRegexPreset: Identifiable, Sendable {
    let title: String
    let pattern: String
    var id: String { title }

    static let all: [StreamRegexPreset] = [
        .init(title: "Any 1080p or Better", pattern: #"(2160p|4k|1080p)"#),
        .init(title: "4K or Remux", pattern: #"(2160p|4k|remux)"#),
        .init(title: "1080p", pattern: #"(1080p|full\s*hd)"#),
        .init(title: "720p", pattern: #"(720p|webrip|web-dl)"#),
        .init(title: "WEB", pattern: #"(web[-\s]?dl|webrip)"#),
        .init(title: "BluRay", pattern: #"(bluray|b[dr]rip|remux)"#),
        .init(title: "HEVC", pattern: #"(hevc|x265|h\.265)"#),
        .init(title: "AVC", pattern: #"(x264|h\.264|avc)"#),
        .init(title: "HDR or Dolby Vision", pattern: #"(hdr|hdr10\+?|dv|dolby\s*vision)"#),
        .init(title: "Atmos or DTS", pattern: #"(atmos|truehd|dts[-\s]?hd|dtsx?)"#),
        .init(title: "English", pattern: #"(\beng\b|english)"#),
        .init(title: "No CAM or TS", pattern: #"^(?!.*\b(cam|hdcam|ts|telesync)\b).*$"#),
        .init(title: "No Remux or HDR", pattern: #"^(?!.*\b(hdr|hdr10|dv|dolby|vision|hevc|remux|2160p)\b).+$"#),
    ]
}

/// Playback behavior ported from Nuvio's Playback settings: source
/// selection, next episode, skipping, subtitle filtering, decoding and the
/// player overlays. Every field falls back to its default on decode, so a
/// newer or older settings file never resets the rest.
nonisolated struct PlaybackBehaviorPreferences: Codable, Equatable, Sendable {
    // Reuse Last Link
    var reuseLastLink = false
    var lastLinkCacheHours = 24

    // Auto Stream Selection
    var autoSelectionMode: AutoStreamSelectionMode = .manual
    var autoSelectionRegex = ""
    var selectionTimeoutSeconds = 3
    var selectionScope: AutoStreamSelectionScope = .allSources
    var allowedAddonIDs: Set<String> = []
    var allowedPluginIDs: Set<String> = []
    var preferBingeGroup = true
    var reuseBingeGroup = false

    // Next Episode
    var nextEpisodeThresholdMode: NextEpisodeThresholdMode = .percentage
    var nextEpisodeThresholdPercent = 99.0
    var nextEpisodeThresholdMinutes = 2.0
    var nextEpisodeFallbackToAnySource = true
    var preloadNextEpisodeSources = false

    // Skip Segments: empty shows the Skip button only.
    var autoSkipSegments: Set<SkipSegment.Kind> = []

    // Subtitles
    var stripSDHSubtitles = false
    var useForcedSubtitles = false
    var showOnlyPreferredSubtitleLanguages = false

    // Decoding
    var decoderPriority: DecoderPriority = .preferDevice

    // Overlays
    var showLoadingOverlay = true
    var showLoadingStatus = true
    var showPauseOverlay = true

    static let `default` = PlaybackBehaviorPreferences()

    static let lastLinkCacheHourOptions = [1, 2, 3, 6, 12, 24, 48, 72, 168]
    static let thresholdPercentOptions: [Double] = [97, 97.5, 98, 98.5, 99, 99.5, 100]
    static let thresholdMinuteOptions: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
    static let autoSkipKinds: [SkipSegment.Kind] = [.intro, .recap, .outro, .movieCredits]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case reuseLastLink, lastLinkCacheHours
        case autoSelectionMode, autoSelectionRegex, selectionTimeoutSeconds, selectionScope
        case allowedAddonIDs, allowedPluginIDs, preferBingeGroup, reuseBingeGroup
        case nextEpisodeThresholdMode, nextEpisodeThresholdPercent, nextEpisodeThresholdMinutes
        case nextEpisodeFallbackToAnySource, preloadNextEpisodeSources
        case autoSkipSegments
        case stripSDHSubtitles, useForcedSubtitles, showOnlyPreferredSubtitleLanguages
        case decoderPriority
        case showLoadingOverlay, showLoadingStatus, showPauseOverlay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let defaults = Self.default
        reuseLastLink = value(.reuseLastLink, defaults.reuseLastLink)
        lastLinkCacheHours = value(.lastLinkCacheHours, defaults.lastLinkCacheHours)
        autoSelectionMode = value(.autoSelectionMode, defaults.autoSelectionMode)
        autoSelectionRegex = value(.autoSelectionRegex, defaults.autoSelectionRegex)
        selectionTimeoutSeconds = value(.selectionTimeoutSeconds, defaults.selectionTimeoutSeconds)
        selectionScope = value(.selectionScope, defaults.selectionScope)
        allowedAddonIDs = value(.allowedAddonIDs, defaults.allowedAddonIDs)
        allowedPluginIDs = value(.allowedPluginIDs, defaults.allowedPluginIDs)
        preferBingeGroup = value(.preferBingeGroup, defaults.preferBingeGroup)
        reuseBingeGroup = value(.reuseBingeGroup, defaults.reuseBingeGroup)
        nextEpisodeThresholdMode = value(.nextEpisodeThresholdMode, defaults.nextEpisodeThresholdMode)
        nextEpisodeThresholdPercent = value(.nextEpisodeThresholdPercent, defaults.nextEpisodeThresholdPercent)
        nextEpisodeThresholdMinutes = value(.nextEpisodeThresholdMinutes, defaults.nextEpisodeThresholdMinutes)
        nextEpisodeFallbackToAnySource = value(.nextEpisodeFallbackToAnySource, defaults.nextEpisodeFallbackToAnySource)
        preloadNextEpisodeSources = value(.preloadNextEpisodeSources, defaults.preloadNextEpisodeSources)
        // Unknown segment names from a newer version are dropped, not fatal.
        let skipNames: [String] = value(.autoSkipSegments, [])
        autoSkipSegments = Set(skipNames.compactMap(SkipSegment.Kind.init(rawValue:)))
        stripSDHSubtitles = value(.stripSDHSubtitles, defaults.stripSDHSubtitles)
        useForcedSubtitles = value(.useForcedSubtitles, defaults.useForcedSubtitles)
        showOnlyPreferredSubtitleLanguages = value(.showOnlyPreferredSubtitleLanguages, defaults.showOnlyPreferredSubtitleLanguages)
        decoderPriority = value(.decoderPriority, defaults.decoderPriority)
        showLoadingOverlay = value(.showLoadingOverlay, defaults.showLoadingOverlay)
        showLoadingStatus = value(.showLoadingStatus, defaults.showLoadingStatus)
        showPauseOverlay = value(.showPauseOverlay, defaults.showPauseOverlay)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reuseLastLink, forKey: .reuseLastLink)
        try container.encode(lastLinkCacheHours, forKey: .lastLinkCacheHours)
        try container.encode(autoSelectionMode, forKey: .autoSelectionMode)
        try container.encode(autoSelectionRegex, forKey: .autoSelectionRegex)
        try container.encode(selectionTimeoutSeconds, forKey: .selectionTimeoutSeconds)
        try container.encode(selectionScope, forKey: .selectionScope)
        try container.encode(allowedAddonIDs.sorted(), forKey: .allowedAddonIDs)
        try container.encode(allowedPluginIDs.sorted(), forKey: .allowedPluginIDs)
        try container.encode(preferBingeGroup, forKey: .preferBingeGroup)
        try container.encode(reuseBingeGroup, forKey: .reuseBingeGroup)
        try container.encode(nextEpisodeThresholdMode, forKey: .nextEpisodeThresholdMode)
        try container.encode(nextEpisodeThresholdPercent, forKey: .nextEpisodeThresholdPercent)
        try container.encode(nextEpisodeThresholdMinutes, forKey: .nextEpisodeThresholdMinutes)
        try container.encode(nextEpisodeFallbackToAnySource, forKey: .nextEpisodeFallbackToAnySource)
        try container.encode(preloadNextEpisodeSources, forKey: .preloadNextEpisodeSources)
        try container.encode(autoSkipSegments.map(\.rawValue).sorted(), forKey: .autoSkipSegments)
        try container.encode(stripSDHSubtitles, forKey: .stripSDHSubtitles)
        try container.encode(useForcedSubtitles, forKey: .useForcedSubtitles)
        try container.encode(showOnlyPreferredSubtitleLanguages, forKey: .showOnlyPreferredSubtitleLanguages)
        try container.encode(decoderPriority, forKey: .decoderPriority)
        try container.encode(showLoadingOverlay, forKey: .showLoadingOverlay)
        try container.encode(showLoadingStatus, forKey: .showLoadingStatus)
        try container.encode(showPauseOverlay, forKey: .showPauseOverlay)
    }

    var normalized: Self {
        var value = self
        if !Self.lastLinkCacheHourOptions.contains(value.lastLinkCacheHours) {
            value.lastLinkCacheHours = Self.lastLinkCacheHourOptions.min {
                abs($0 - value.lastLinkCacheHours) < abs($1 - value.lastLinkCacheHours)
            } ?? 24
        }
        value.selectionTimeoutSeconds = StreamSelectionTimeout.normalized(value.selectionTimeoutSeconds)
        value.nextEpisodeThresholdPercent = min(max(value.nextEpisodeThresholdPercent, 97), 100)
        value.nextEpisodeThresholdMinutes = min(max(value.nextEpisodeThresholdMinutes, 0), 3.5)
        value.autoSkipSegments = value.autoSkipSegments.filter { Self.autoSkipKinds.contains($0) }
        return value
    }

    /// The compiled user pattern, or nil when it is empty or invalid.
    var compiledRegex: NSRegularExpression? {
        Self.compile(autoSelectionRegex)
    }

    static func compile(_ pattern: String) -> NSRegularExpression? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
    }

    /// Whether anything can start a stream without the user picking one.
    var isAutoPlayEffectivelyEnabled: Bool {
        if reuseLastLink { return true }
        if preferBingeGroup && reuseBingeGroup { return true }
        switch autoSelectionMode {
        case .manual: return false
        case .firstSource: return true
        case .regexMatch: return compiledRegex != nil
        }
    }

    /// Selection rules for opening a title from the library. Returns nil
    /// when the list should simply show.
    func selectionRequest(rememberedBingeGroup: String?) -> StreamAutoPlayRequest? {
        let bingeGroup = preferBingeGroup && reuseBingeGroup ? rememberedBingeGroup : nil
        let mode: AutoStreamSelectionMode = autoSelectionMode == .regexMatch && compiledRegex == nil
            ? .manual
            : autoSelectionMode
        // With a remembered binge group in Manual mode, Nuvio plays only a
        // stream from that group, and otherwise shows the list.
        if mode == .manual && bingeGroup == nil { return nil }
        return StreamAutoPlayRequest(
            mode: mode == .manual ? .firstSource : mode,
            regexPattern: mode == .regexMatch ? autoSelectionRegex : nil,
            scope: selectionScope,
            allowedAddonIDs: allowedAddonIDs,
            allowedPluginIDs: allowedPluginIDs,
            preferredBingeGroup: bingeGroup,
            bingeGroupOnly: mode == .manual,
            timeoutSeconds: selectionTimeoutSeconds
        )
    }

    /// Selection rules for the next episode, from Nuvio's
    /// PlayerNextEpisodeAutoPlay. Returns nil when the list should show.
    func nextEpisodeRequest(
        currentBingeGroup: String?,
        autoplayNextEpisode: Bool
    ) -> StreamAutoPlayRequest? {
        var mode: AutoStreamSelectionMode = autoSelectionMode == .regexMatch && compiledRegex == nil ? .manual : autoSelectionMode
        var scope = selectionScope
        var addons = allowedAddonIDs
        var plugins = allowedPluginIDs
        var regexPattern: String? = mode == .regexMatch ? autoSelectionRegex : nil
        if mode == .manual && (autoplayNextEpisode || preferBingeGroup) {
            mode = .firstSource
            scope = .allSources
            addons = []
            plugins = []
            regexPattern = nil
        }
        guard mode != .manual else { return nil }
        let bingeGroup = preferBingeGroup ? currentBingeGroup : nil
        let bingeGroupOnly = preferBingeGroup && (!autoplayNextEpisode || !nextEpisodeFallbackToAnySource)
        if bingeGroupOnly && bingeGroup == nil { return nil }
        return StreamAutoPlayRequest(
            mode: mode,
            regexPattern: regexPattern,
            scope: scope,
            allowedAddonIDs: addons,
            allowedPluginIDs: plugins,
            preferredBingeGroup: bingeGroup,
            bingeGroupOnly: bingeGroupOnly,
            timeoutSeconds: selectionTimeoutSeconds
        )
    }
}
