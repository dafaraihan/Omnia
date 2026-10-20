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

/// Compares the language labels add-ons and files use ("en", "eng",
/// "en-US", "English") by their ISO 639-1 code.
nonisolated enum PlaybackLanguageMatching {
    static func matches(_ label: String?, _ preferred: String) -> Bool {
        guard let label = normalized(label), let preferred = normalized(preferred) else { return false }
        return label == preferred
    }

    static func normalized(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        let primary = String(raw.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(raw))
        if primary.count == 2 { return primary }
        if primary.count == 3 {
            let alpha2: String? = Locale.LanguageCode(primary).identifier(.alpha2)
            if let alpha2, alpha2.count == 2 { return alpha2 }
            // Bibliographic codes Foundation doesn't map.
            let bibliographic = ["ger": "de", "fre": "fr", "dut": "nl", "chi": "zh", "cze": "cs",
                                 "gre": "el", "per": "fa", "rum": "ro", "slo": "sk", "alb": "sq",
                                 "arm": "hy", "baq": "eu", "bur": "my", "geo": "ka", "ice": "is",
                                 "mac": "mk", "may": "ms", "wel": "cy", "pob": "pt"]
            return bibliographic[primary] ?? primary
        }
        return namesToCodes[raw] ?? namesToCodes[primary]
    }

    /// English language names to codes, for add-ons that send "English".
    private static let namesToCodes: [String: String] = {
        let english = Locale(identifier: "en")
        var values: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes {
            let identifier = code.identifier
            guard identifier.count == 2,
                  let name = english.localizedString(forLanguageCode: identifier)?.lowercased()
            else { continue }
            values[name] = identifier
        }
        return values
    }()
}
