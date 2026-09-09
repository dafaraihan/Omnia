import Foundation

enum PlaybackSubtitleBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case translucent
    case solid

    var id: String { rawValue }
}

struct PlaybackSubtitleStyle: Codable, Equatable, Sendable {
    var fontName: String = "sans-serif"
    var fontSize: Double = 42
    var scale: Double = 1
    var position: Double = 95
    var shadowOpacity: Double = 0.65
    var shadowBlurRadius: Double = 2
    var background: PlaybackSubtitleBackground = .none

    static let `default` = Self()

    var normalized: Self {
        let trimmedFontName = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            fontName: String((trimmedFontName.isEmpty ? Self.default.fontName : trimmedFontName).prefix(128)),
            fontSize: min(max(fontSize.isFinite ? fontSize : Self.default.fontSize, 14), 72),
            scale: min(max(scale.isFinite ? scale : Self.default.scale, 0.5), 2),
            position: min(max(position.isFinite ? position : Self.default.position, 0), 100),
            shadowOpacity: min(max(shadowOpacity.isFinite ? shadowOpacity : Self.default.shadowOpacity, 0), 1),
            shadowBlurRadius: min(max(shadowBlurRadius.isFinite ? shadowBlurRadius : Self.default.shadowBlurRadius, 0), 20),
            background: background
        )
    }
}

struct PlaybackSubtitlePreferenceUpdate: Equatable, Sendable {
    let style: PlaybackSubtitleStyle
    let isEnabled: Bool?
    let preferredLanguage: PreferredLanguage?

    static func selecting(
        id: Int?,
        from tracks: [PlaybackTrack],
        style: PlaybackSubtitleStyle
    ) -> Self {
        guard let id else {
            return Self(style: style.normalized, isEnabled: false, preferredLanguage: nil)
        }
        let language = tracks.first(where: { $0.id == id })?.language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredLanguage = language.flatMap { value in
            value.isEmpty ? nil : PreferredLanguage.language(value)
        }
        return Self(style: style.normalized, isEnabled: true, preferredLanguage: preferredLanguage)
    }
}
