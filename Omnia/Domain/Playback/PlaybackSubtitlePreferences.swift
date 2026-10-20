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
    /// Six-digit sRGB hex, without "#".
    var textColorHex: String = "FFFFFF"
    var backgroundColorHex: String = "000000"
    var outlineEnabled = true
    var outlineColorHex: String = "000000"
    var outlineSize: Double = 1.65
    var isBold = false
    var isItalic = false
    /// mpv's sub-delay, in seconds. Positive shows subtitles later.
    var delaySeconds: Double = 0

    static let `default` = Self()

    init() {}

    init(
        fontName: String,
        fontSize: Double,
        scale: Double,
        position: Double,
        shadowOpacity: Double,
        shadowBlurRadius: Double,
        background: PlaybackSubtitleBackground
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.scale = scale
        self.position = position
        self.shadowOpacity = shadowOpacity
        self.shadowBlurRadius = shadowBlurRadius
        self.background = background
    }

    /// Older saves have only the first seven fields; the rest fall back to
    /// their defaults instead of failing the whole settings file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        fontName = (try? c.decodeIfPresent(String.self, forKey: .fontName)) ?? d.fontName
        fontSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? d.fontSize
        scale = (try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? d.scale
        position = (try? c.decodeIfPresent(Double.self, forKey: .position)) ?? d.position
        shadowOpacity = (try? c.decodeIfPresent(Double.self, forKey: .shadowOpacity)) ?? d.shadowOpacity
        shadowBlurRadius = (try? c.decodeIfPresent(Double.self, forKey: .shadowBlurRadius)) ?? d.shadowBlurRadius
        background = (try? c.decodeIfPresent(PlaybackSubtitleBackground.self, forKey: .background)) ?? d.background
        textColorHex = (try? c.decodeIfPresent(String.self, forKey: .textColorHex)) ?? d.textColorHex
        backgroundColorHex = (try? c.decodeIfPresent(String.self, forKey: .backgroundColorHex)) ?? d.backgroundColorHex
        outlineEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .outlineEnabled)) ?? d.outlineEnabled
        outlineColorHex = (try? c.decodeIfPresent(String.self, forKey: .outlineColorHex)) ?? d.outlineColorHex
        outlineSize = (try? c.decodeIfPresent(Double.self, forKey: .outlineSize)) ?? d.outlineSize
        isBold = (try? c.decodeIfPresent(Bool.self, forKey: .isBold)) ?? d.isBold
        isItalic = (try? c.decodeIfPresent(Bool.self, forKey: .isItalic)) ?? d.isItalic
        delaySeconds = (try? c.decodeIfPresent(Double.self, forKey: .delaySeconds)) ?? d.delaySeconds
    }

    var normalized: Self {
        let trimmedFontName = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = self
        value.fontName = String((trimmedFontName.isEmpty ? Self.default.fontName : trimmedFontName).prefix(128))
        value.fontSize = Self.clamp(fontSize, 14 ... 72, fallback: Self.default.fontSize)
        value.scale = Self.clamp(scale, 0.5 ... 2, fallback: Self.default.scale)
        value.position = Self.clamp(position, 0 ... 100, fallback: Self.default.position)
        value.shadowOpacity = Self.clamp(shadowOpacity, 0 ... 1, fallback: Self.default.shadowOpacity)
        value.shadowBlurRadius = Self.clamp(shadowBlurRadius, 0 ... 20, fallback: Self.default.shadowBlurRadius)
        value.textColorHex = Self.hex(textColorHex, fallback: Self.default.textColorHex)
        value.backgroundColorHex = Self.hex(backgroundColorHex, fallback: Self.default.backgroundColorHex)
        value.outlineColorHex = Self.hex(outlineColorHex, fallback: Self.default.outlineColorHex)
        value.outlineSize = Self.clamp(outlineSize, 0 ... 5, fallback: Self.default.outlineSize)
        value.delaySeconds = Self.clamp(delaySeconds, -30 ... 30, fallback: 0)
        return value
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
    }

    private static func hex(_ value: String, fallback: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, UInt32(text, radix: 16) != nil else { return fallback }
        return text
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

/// Languages offered by the audio and subtitle pickers. Codes are ISO 639-1,
/// which mpv's alang and slang match against track languages.
enum PlaybackLanguageCatalog {
    static let codes = [
        "en", "id", "ms", "ja", "ko", "zh", "th", "vi", "tl", "hi", "ta", "ar", "he", "tr", "fa",
        "es", "pt", "fr", "de", "it", "nl", "sv", "no", "da", "fi", "pl", "cs", "hu", "ro", "el",
        "ru", "uk", "bg", "hr", "sr"
    ]

    static func name(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}
