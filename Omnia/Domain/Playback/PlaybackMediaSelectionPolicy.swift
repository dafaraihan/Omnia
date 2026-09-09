import Foundation

struct PlaybackMediaSelectionPolicy: Equatable, Sendable {
    let audioLanguages: [String]?
    let subtitleLanguages: [String]?
    let disablesSubtitles: Bool
    let prefersSDH: Bool

    static func resolve(
        preferences: SettingsPreferences,
        isAnime: Bool,
        systemLanguages: [String] = Locale.preferredLanguages
    ) -> PlaybackMediaSelectionPolicy {
        let normalized = preferences.normalized
        var audio = orderedLanguages(
            preferred: normalized.preferredAudioLanguage,
            fallback: normalized.audioFallbackLanguage,
            systemLanguages: systemLanguages
        )
        var subtitles = orderedLanguages(
            preferred: normalized.preferredSubtitleLanguage,
            fallback: normalized.subtitleFallbackLanguage,
            systemLanguages: systemLanguages
        )
        var disablesSubtitles = !normalized.subtitlesEnabled
            || (normalized.preferredSubtitleLanguage == .none
                && normalized.subtitleFallbackLanguage == .none)

        if isAnime {
            switch normalized.animeAudioPreference {
            case .followPreferred:
                break
            case .sub:
                audio = unique(["ja"] + (audio ?? systemLanguages))
                if disablesSubtitles, normalized.subtitlesEnabled {
                    subtitles = unique(systemLanguages)
                    disablesSubtitles = false
                }
            case .dub:
                audio = audio ?? unique(systemLanguages)
                subtitles = []
                disablesSubtitles = true
            }
        }

        return PlaybackMediaSelectionPolicy(
            audioLanguages: audio,
            subtitleLanguages: disablesSubtitles ? [] : subtitles,
            disablesSubtitles: disablesSubtitles,
            prefersSDH: normalized.sdhPreference == .prefer
        )
    }

    private static func orderedLanguages(
        preferred: PreferredLanguage,
        fallback: PreferredLanguage,
        systemLanguages: [String]
    ) -> [String]? {
        if preferred == .followSystem, fallback == .none {
            return nil
        }

        return unique(
            identifiers(for: preferred, systemLanguages: systemLanguages)
                + identifiers(for: fallback, systemLanguages: systemLanguages)
        )
    }

    private static func identifiers(
        for language: PreferredLanguage,
        systemLanguages: [String]
    ) -> [String] {
        switch language {
        case .followSystem:
            systemLanguages
        case .none:
            []
        case let .language(identifier):
            [identifier]
        }
    }

    private static func unique(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { rawIdentifier in
            let identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { return nil }
            let key = identifier.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return identifier
        }
    }
}
