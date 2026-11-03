import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Nuvio's accent palette. Blue keeps Omnia's original system tint.
nonisolated enum AccentTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case gold
    case jade
    case roseGold
    case arcticBlue
    case graphite
    case crimson
    case ocean
    case violet
    case emerald
    case amber
    case rose
    case white
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .gold: "Gold"
        case .jade: "Jade"
        case .roseGold: "Rose Gold"
        case .arcticBlue: "Arctic Blue"
        case .graphite: "Graphite"
        case .crimson: "Crimson"
        case .ocean: "Ocean"
        case .violet: "Violet"
        case .emerald: "Emerald"
        case .amber: "Amber"
        case .rose: "Rose"
        case .white: "White"
        case .custom: "Custom"
        }
    }

    /// The palette's primary colour, from Nuvio's ThemeColors.
    var hex: String? {
        switch self {
        case .blue: nil
        case .gold: "E8A91C"
        case .jade: "22D37C"
        case .roseGold: "EC70A9"
        case .arcticBlue: "3185F5"
        case .graphite: "AAB2BE"
        case .crimson: "E53935"
        case .ocean: "1E88E5"
        case .violet: "8E24AA"
        case .emerald: "43A047"
        case .amber: "FB8C00"
        case .rose: "D81B60"
        case .white: "F5F5F5"
        case .custom: nil
        }
    }

    /// Nuvio's gradient palettes, in its stop order. Other themes are a
    /// single colour.
    var gradientHexes: [String]? {
        switch self {
        case .gold: ["8A5700", "E8A91C", "FFF1A8", "FFD45C", "9A6200"]
        case .jade: ["7BF08D", "22D37C", "0BBF9A"]
        case .roseGold: ["B75AFF", "EC70A9", "FFB37A"]
        case .arcticBlue: ["4DE3FF", "3185F5", "4D55E8"]
        case .graphite: ["F3F5F7", "AAB2BE", "687381"]
        default: nil
        }
    }
}

/// Nuvio's custom theme: one colour, or a three-colour gradient whose middle
/// colour is the accent.
nonisolated enum CustomAccentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case gradient

    var id: Self { self }

    var title: String {
        switch self {
        case .single: "Single Color"
        case .gradient: "Gradient"
        }
    }
}

/// Native tabs or custom navigation with adaptive label visibility.
nonisolated enum TopBarStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case native, adaptive, expanded, compact
    var id: Self { self }
    var title: String {
        switch self {
        case .native: "Standard"
        case .adaptive: "Adaptive"
        case .expanded: "Always Expanded"
        case .compact: "Always Compact"
        }
    }
    var detail: String {
        switch self {
        case .native: "Uses the system tab bar."
        case .adaptive: "Shrinks as you scroll down and expands as you scroll up."
        case .expanded: "Always shows icons and labels."
        case .compact: "Always shows icons only."
        }
    }
    var isNuvio: Bool { self != .native }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .adaptive
    }
}

nonisolated enum PosterWidthPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case small
    case standard
    case large
    case extraLarge

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var width: CGFloat {
        #if os(iOS)
        // An iPhone fits about three posters across a row, as in Nuvio.
        if Self.isPhone {
            switch self {
            case .compact: return 92
            case .small: return 102
            case .standard: return 112
            case .large: return 124
            case .extraLarge: return 136
            }
        }
        switch self {
        case .compact: return 104
        case .small: return 118
        case .standard: return 132
        case .large: return 146
        case .extraLarge: return 160
        }
        #else
        switch self {
        case .compact: 126
        case .small: 140
        case .standard: 154
        case .large: 172
        case .extraLarge: 190
        }
        #endif
    }

    #if os(iOS)
    /// Read once, on the main thread where views first ask for a width.
    private static let isPhone: Bool = {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
    }()
    #endif
}

nonisolated enum PosterCornerPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case square
    case subtle
    case rounded
    case round

    var id: Self { self }

    var title: String {
        switch self {
        case .square: "Square"
        case .subtle: "Subtle"
        case .rounded: "Rounded"
        case .round: "Round"
        }
    }

    var radius: CGFloat {
        switch self {
        case .square: 0
        case .subtle: 6
        case .rounded: 14
        case .round: 22
        }
    }
}

/// Nuvio's Card Depth Effect: a 1 pt edge highlight fading down the card and
/// a white sheen across its top fifth. Values are percentages, as in Nuvio.
nonisolated struct CardDepthPreferences: Codable, Equatable, Sendable {
    nonisolated enum Surface: String, Codable, CaseIterable, Identifiable, Sendable {
        case posters
        case continueWatching
        case episodes
        case cast
        case trailers
        case collections

        var id: Self { self }

        var title: String {
            switch self {
            case .posters: "Posters"
            case .continueWatching: "Continue Watching"
            case .episodes: "Episodes"
            case .cast: "Cast"
            case .trailers: "Trailers"
            case .collections: "Collections"
            }
        }
    }

    static let edgeLevels = [28, 42, 56]
    static let sheenLevels = [0, 10, 16]
    static let coverageLevels = [0, 50, 100]

    var isEnabled = false
    var edgeStrength = 28
    var sheenStrength = 10
    var edgeCoverage = 0
    var disabledSurfaces: Set<Surface> = []

    static let `default` = Self()

    func isEnabled(for surface: Surface) -> Bool {
        isEnabled && !disabledSurfaces.contains(surface)
    }

    var normalized: Self {
        var value = self
        value.edgeStrength = min(100, max(0, edgeStrength))
        value.sheenStrength = min(100, max(0, sheenStrength))
        value.edgeCoverage = min(100, max(0, edgeCoverage))
        return value
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        edgeStrength = try container.decodeIfPresent(Int.self, forKey: .edgeStrength) ?? 28
        sheenStrength = try container.decodeIfPresent(Int.self, forKey: .sheenStrength) ?? 10
        edgeCoverage = try container.decodeIfPresent(Int.self, forKey: .edgeCoverage) ?? 0
        disabledSurfaces = try container.decodeIfPresent(Set<Surface>.self, forKey: .disabledSurfaces) ?? []
    }
}

/// The hover effect from Omnia's collection cards: a bright edge and a small
/// lift while the pointer is on a card, available on every card with its
/// own colour.
nonisolated struct CardHoverPreferences: Codable, Equatable, Sendable {
    nonisolated enum ColorSource: String, Codable, CaseIterable, Identifiable, Sendable {
        case white
        case accent
        case custom

        var id: Self { self }

        var title: String {
            switch self {
            case .white: "White"
            case .accent: "Accent Color"
            case .custom: "Custom"
            }
        }
    }

    nonisolated enum Intensity: String, Codable, CaseIterable, Identifiable, Sendable {
        case subtle
        case balanced
        case bold

        var id: Self { self }

        var title: String {
            switch self {
            case .subtle: "Subtle"
            case .balanced: "Balanced"
            case .bold: "Bold"
            }
        }

        /// Balanced is the collection card's edge: 55% at 2 points.
        var edgeOpacity: Double {
            switch self {
            case .subtle: 0.35
            case .balanced: 0.55
            case .bold: 0.8
            }
        }

        var glowRadius: CGFloat {
            switch self {
            case .subtle: 8
            case .balanced: 12
            case .bold: 18
            }
        }
    }

    var isEnabled = true
    var colorSource: ColorSource = .white
    var customHex = "FFFFFF"
    var intensity: Intensity = .balanced
    var outerGlow = false
    var lift = true
    var disabledSurfaces: Set<CardDepthPreferences.Surface> = []

    static let `default` = Self()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
        colorSource = (try? c.decodeIfPresent(ColorSource.self, forKey: .colorSource)) ?? d.colorSource
        customHex = (try? c.decodeIfPresent(String.self, forKey: .customHex)) ?? d.customHex
        intensity = (try? c.decodeIfPresent(Intensity.self, forKey: .intensity)) ?? d.intensity
        outerGlow = (try? c.decodeIfPresent(Bool.self, forKey: .outerGlow)) ?? d.outerGlow
        lift = (try? c.decodeIfPresent(Bool.self, forKey: .lift)) ?? d.lift
        disabledSurfaces = (try? c.decodeIfPresent(Set<CardDepthPreferences.Surface>.self, forKey: .disabledSurfaces)) ?? d.disabledSurfaces
    }

    func isEnabled(for surface: CardDepthPreferences.Surface) -> Bool {
        isEnabled && !disabledSurfaces.contains(surface)
    }

    func color(accent: Color) -> Color {
        switch colorSource {
        case .white: .white
        case .accent: accent
        case .custom: Color(omniaHex: customHex) ?? .white
        }
    }
}

nonisolated enum ContinueWatchingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case card
    case wide
    case poster

    var id: Self { self }

    var title: String {
        switch self {
        case .card: "Card"
        case .wide: "Wide"
        case .poster: "Poster"
        }
    }

    /// Card and Wide use landscape artwork; Poster uses the poster.
    var isLandscape: Bool { self != .poster }
}

/// Independent Continue Watching geometry. Style Default preserves saved layouts.
nonisolated struct ContinueWatchingCardPreferences: Codable, Equatable, Sendable {
    var size: Size = .styleDefault
    var corners: Corners = .styleDefault

    static let `default` = Self()
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? .styleDefault
        corners = (try? c.decodeIfPresent(Corners.self, forKey: .corners)) ?? .styleDefault
    }

    /// Reads saved settings. "matchPosters" was a live link to Poster Card Style
    /// until Nov 2026; it becomes the poster values, so nothing looks different.
    init(from decoder: Decoder, posterWidth: PosterWidthPreset, posterCorner: PosterCornerPreset) throws {
        struct Raw: Decodable { var size: String?; var corners: String? }
        let raw = try Raw(from: decoder)
        size = raw.size == "matchPosters" ? Size(rawValue: posterWidth.rawValue) ?? .styleDefault
            : raw.size.flatMap(Size.init(rawValue:)) ?? .styleDefault
        corners = raw.corners == "matchPosters" ? Corners(rawValue: posterCorner.rawValue) ?? .styleDefault
            : raw.corners.flatMap(Corners.init(rawValue:)) ?? .styleDefault
    }

    enum Size: String, Codable, CaseIterable, Identifiable, Sendable {
        case styleDefault, compact, small, standard, large, extraLarge
        var id: Self { self }
        var title: String {
            switch self {
            case .styleDefault: "Style Default"
            case .compact: "Compact"
            case .small: "Small"
            case .standard: "Standard"
            case .large: "Large"
            case .extraLarge: "Extra Large"
            }
        }
        func posterWidth(for display: DisplayPreferences) -> CGFloat {
            switch self {
            case .styleDefault: display.posterCardWidth
            case .compact: PosterWidthPreset.compact.width
            case .small: PosterWidthPreset.small.width
            case .standard: PosterWidthPreset.standard.width
            case .large: PosterWidthPreset.large.width
            case .extraLarge: PosterWidthPreset.extraLarge.width
            }
        }
    }

    enum Corners: String, Codable, CaseIterable, Identifiable, Sendable {
        case styleDefault, square, subtle, rounded, round
        var id: Self { self }
        var title: String {
            switch self {
            case .styleDefault: "Style Default"
            case .square: "Square"
            case .subtle: "Subtle"
            case .rounded: "Rounded"
            case .round: "Round"
            }
        }
        func radius(for display: DisplayPreferences) -> CGFloat {
            switch self {
            case .styleDefault: display.continueWatchingStyle == .wide ? 16 : display.posterCornerRadius
            case .square: PosterCornerPreset.square.radius
            case .subtle: PosterCornerPreset.subtle.radius
            case .rounded: PosterCornerPreset.rounded.radius
            case .round: PosterCornerPreset.round.radius
            }
        }
    }
}

/// Settings › Layout › Collections › Card Style: the folder tiles in every
/// collection row, like Poster Card Style is for posters. The defaults draw
/// tiles as they looked before the option existed.
nonisolated struct CollectionCardPreferences: Codable, Equatable, Sendable {
    var shape: Shape = .asImported
    var size: Size = .standard
    var corners: Corners = .rounded
    var titles: Titles = .automatic
    var folderCards: FolderCards = .asImported

    static let `default` = Self()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? d.shape
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? d.size
        corners = (try? c.decodeIfPresent(Corners.self, forKey: .corners)) ?? d.corners
        titles = (try? c.decodeIfPresent(Titles.self, forKey: .titles)) ?? d.titles
        folderCards = (try? c.decodeIfPresent(FolderCards.self, forKey: .folderCards)) ?? d.folderCards
    }

    /// Reads saved settings. "matchPosters" was a live link to Poster Card Style
    /// until Nov 2026, and the default size; it becomes the poster values, so
    /// nothing looks different.
    init(from decoder: Decoder, poster: PosterWidthPreset, corner: PosterCornerPreset, landscape: Bool) throws {
        struct Raw: Decodable {
            var shape: String?, size: String?, corners: String?, titles: Titles?, folderCards: String?
        }
        let raw = (try? Raw(from: decoder)) ?? Raw()
        self.init(poster: poster, corner: corner, landscape: landscape, raw: (raw.shape, raw.size, raw.corners, raw.titles, raw.folderCards))
    }

    /// For a saved profile from before these settings existed at all.
    init(poster: PosterWidthPreset, corner: PosterCornerPreset, landscape: Bool) {
        self.init(poster: poster, corner: corner, landscape: landscape, raw: (nil, nil, nil, nil, nil))
    }

    private init(
        poster: PosterWidthPreset, corner: PosterCornerPreset, landscape: Bool,
        raw: (shape: String?, size: String?, corners: String?, titles: Titles?, folderCards: String?)
    ) {
        shape = raw.shape == "matchPosters" ? (landscape ? .landscape : .poster)
            : raw.shape.flatMap(Shape.init(rawValue:)) ?? .asImported
        size = raw.size.flatMap(Size.init(rawValue:)) ?? Size(rawValue: poster.rawValue) ?? .standard
        corners = raw.corners == "matchPosters" ? Corners(rawValue: corner.rawValue) ?? .rounded
            : raw.corners.flatMap(Corners.init(rawValue:)) ?? .rounded
        titles = raw.titles ?? .automatic
        folderCards = raw.folderCards == "matchPosters" ? (landscape ? .landscape : .asImported)
            : raw.folderCards.flatMap(FolderCards.init(rawValue:)) ?? .asImported
    }

    /// The cards inside an opened folder. An Xperience or Nuvio export only
    /// shapes the folder's tile; its titles are portrait posters.
    enum FolderCards: String, Codable, CaseIterable, Identifiable, Sendable {
        case asImported
        case landscape

        var id: Self { self }

        var title: String {
            switch self {
            case .asImported: "As Imported"
            case .landscape: "Landscape"
            }
        }
    }

    enum Shape: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Each collection's own tile shape, from its editor or import.
        case asImported
        case poster
        case square
        case landscape
        case wide

        var id: Self { self }

        var title: String {
            switch self {
            case .asImported: "As Imported"
            case .poster: "Poster"
            case .square: "Square"
            case .landscape: "Landscape"
            case .wide: "Wide"
            }
        }

        func resolved(_ folderShape: HomeCollectionFolder.TileShape) -> HomeCollectionFolder.TileShape {
            switch self {
            case .asImported: folderShape
            case .poster: .poster
            case .square: .square
            case .landscape: .landscape
            case .wide: .wide
            }
        }
    }

    /// The same steps as Poster Card Style, so its size can be applied exactly.
    enum Size: String, Codable, CaseIterable, Identifiable, Sendable {
        case compact, small, standard, large, extraLarge

        var id: Self { self }

        private var preset: PosterWidthPreset { PosterWidthPreset(rawValue: rawValue) ?? .standard }

        var title: String { preset.title }

        @MainActor
        var scale: CGFloat { preset.width / PosterWidthPreset.standard.width }
    }

    /// The same steps as Poster Card Style, so its corners can be applied exactly.
    enum Corners: String, Codable, CaseIterable, Identifiable, Sendable {
        case square, subtle, rounded, round

        var id: Self { self }

        private var preset: PosterCornerPreset { PosterCornerPreset(rawValue: rawValue) ?? .rounded }

        var title: String { preset.title }

        var radius: CGFloat { preset.radius }
    }

    enum Titles: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Drawn when the folder asks for it or has no cover.
        case automatic
        case always
        case never

        var id: Self { self }

        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .always: "Always"
            case .never: "Never"
            }
        }
    }
}

/// Settings › Layout › Continue Watching › Artwork.
nonisolated enum ContinueWatchingArtwork: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The movie's artwork, or the episode's still for a show.
    case artwork
    /// The frame where playback stopped, saved when the player closes.
    case pausedScene

    var id: Self { self }

    var title: String {
        switch self {
        case .artwork: "Title Artwork"
        case .pausedScene: "Paused Scene"
        }
    }
}

nonisolated enum ContinueWatchingSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case recent
    case title
    case nearlyFinished

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recently Watched"
        case .title: "Title"
        case .nearlyFinished: "Nearly Finished"
        }
    }
}

nonisolated enum DetailBackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case artworkColor
    case plain

    var id: Self { self }

    var title: String {
        switch self {
        case .artworkColor: "Artwork Color"
        case .plain: "Plain"
        }
    }
}

nonisolated enum EpisodeCardLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case horizontal
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .list: "List"
        }
    }
}

nonisolated enum DetailSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case genres
    case facts
    case episodes
    case trailers
    case bonusContent
    case people
    case production
    case studio
    case collection
    case recommendations
    case similar

    var id: Self { self }

    var title: String {
        switch self {
        case .genres: "Genres"
        case .facts: "Details"
        case .episodes: "Episodes"
        case .trailers: "Trailers"
        case .bonusContent: "Bonus Content"
        case .people: "People"
        case .production: "Production"
        case .studio: "More from the Studio"
        case .collection: "Collection"
        case .recommendations: "More Like This"
        case .similar: "Similar Titles"
        }
    }
}

nonisolated enum HoverPreviewDelay: Double, Codable, CaseIterable, Identifiable, Sendable {
    case half = 0.5
    case one = 1
    case two = 2
    case three = 3
    case five = 5

    var id: Self { self }

    var title: String {
        rawValue < 1 ? "0.5 seconds" : rawValue == 1 ? "1 second" : "\(Int(rawValue)) seconds"
    }
}

/// iPhone, iPad or Mac. Worked out from the model name rather than UIDevice so
/// settings can be decoded off the main actor.
nonisolated enum OmniaDeviceClass: String, Sendable {
    case phone, pad, mac

    static let current: Self = {
        #if os(macOS)
        return .mac
        #else
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated.hasPrefix("iPad") ? .pad : .phone
        }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine).hasPrefix("iPad") ? .pad : .phone
        #endif
    }()
}

/// How cards look on one kind of device: a size that suits a Mac is too big
/// for an iPhone, so each keeps its own unless the viewer shares one set.
nonisolated struct CardAppearance: Codable, Equatable, Sendable {
    var posterWidth: PosterWidthPreset
    var posterCorner: PosterCornerPreset
    var landscapePosters: Bool
    var cardDepth: CardDepthPreferences
    var cardHover: CardHoverPreferences
    var continueWatchingCard: ContinueWatchingCardPreferences
    var continueWatchingStyle: ContinueWatchingStyle
    var collectionCard: CollectionCardPreferences
}

/// How Omnia looks: accent, cards, Continue Watching and the title page.
/// Every value here is read by the views that draw it.
/// Multipliers on the floating top bar's designed size.
struct TopBarSizePreferences: Codable, Equatable, Sendable {
    static let range = 0.7 ... 1.3

    var size = 1.0
    var height = 1.0
    var width = 1.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) -> Double {
            min(max((try? c.decodeIfPresent(Double.self, forKey: key)) ?? 1, Self.range.lowerBound), Self.range.upperBound)
        }
        size = value(.size)
        height = value(.height)
        width = value(.width)
    }
}

/// Multipliers on the player's designed control and menu sizes.
struct PlayerSizePreferences: Codable, Equatable, Sendable {
    static let range = 0.6 ... 1.4

    var controls = 1.0
    /// How much of the window's width the timeline row takes, at most all of it.
    var timelineLength = 1.0
    var menuSize = 1.0
    var menuWidth = 1.0
    var menuHeight = 1.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) -> Double {
            min(max((try? c.decodeIfPresent(Double.self, forKey: key)) ?? 1, Self.range.lowerBound), Self.range.upperBound)
        }
        controls = value(.controls)
        timelineLength = min(value(.timelineLength), 1)
        menuSize = value(.menuSize)
        menuWidth = value(.menuWidth)
        menuHeight = value(.menuHeight)
    }
}

enum LowPowerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Follows the system's Low Power Mode.
    case automatic
    case on
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Follow System"
        case .on: "On"
        case .off: "Off"
        }
    }
}

/// The fade from a hero's artwork into the page below it.
struct HeroBlendPreferences: Codable, Equatable, Sendable {
    var isEnabled = true
    /// How solid the fade gets, from 0 to 1.
    var strength = 1.0
    /// How much of the hero the fade covers, from the bottom.
    var height = 0.58

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HeroBlendPreferences()
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
        strength = min(max((try? c.decodeIfPresent(Double.self, forKey: .strength)) ?? d.strength, 0.2), 1)
        height = min(max((try? c.decodeIfPresent(Double.self, forKey: .height)) ?? d.height, 0.2), 1)
    }
}

/// The parts of the app the Liquid Glass settings can switch.
enum OmniaGlassElement: Sendable {
    case navigationBar, actionButtons, playerControls, panels
}

enum LiquidGlassStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Each part keeps the glass designed for it.
    case standard
    case clear
    case frosted

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .clear: "Clear"
        case .frosted: "Frosted"
        }
    }
}

struct LiquidGlassPreferences: Codable, Equatable, Sendable {
    var isEnabled = true
    var style = LiquidGlassStyle.standard
    /// 0.5 is the designed look. Lower is more see-through, higher more frosted.
    var intensity = 0.5
    var navigationBar = true
    var actionButtons = true
    var playerControls = true
    var panels = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LiquidGlassPreferences()
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
        style = (try? c.decodeIfPresent(LiquidGlassStyle.self, forKey: .style)) ?? d.style
        intensity = min(max((try? c.decodeIfPresent(Double.self, forKey: .intensity)) ?? d.intensity, 0), 1)
        navigationBar = (try? c.decodeIfPresent(Bool.self, forKey: .navigationBar)) ?? d.navigationBar
        actionButtons = (try? c.decodeIfPresent(Bool.self, forKey: .actionButtons)) ?? d.actionButtons
        playerControls = (try? c.decodeIfPresent(Bool.self, forKey: .playerControls)) ?? d.playerControls
        panels = (try? c.decodeIfPresent(Bool.self, forKey: .panels)) ?? d.panels
    }

    func applies(to element: OmniaGlassElement) -> Bool {
        guard isEnabled else { return false }
        switch element {
        case .navigationBar: return navigationBar
        case .actionButtons: return actionButtons
        case .playerControls: return playerControls
        case .panels: return panels
        }
    }
}

nonisolated struct DisplayPreferences: Codable, Equatable, Sendable {
    var accentTheme: AccentTheme = .blue
    var customAccentHex = "7C5CFF"
    var customAccentMode: CustomAccentMode = .single
    var customGradientHexes = Self.defaultCustomGradient
    var amoledBlack = false

    var posterWidth: PosterWidthPreset = .standard { didSet { rememberCardStyle() } }
    var posterCorner: PosterCornerPreset = .rounded { didSet { rememberCardStyle() } }
    var landscapePosters = false { didSet { rememberCardStyle() } }
    /// Nuvio's Custom Poster Source: a poster service URL pattern such as
    /// `https://api.ratingposterdb.com/KEY/imdb/poster-default/{imdb_id}.jpg`.
    /// Empty uses each title's own poster (Dafa, 2026-10-27).
    var customPosterURLPattern = ""
    var cardDepth: CardDepthPreferences = .default { didSet { rememberCardStyle() } }
    var cardHover: CardHoverPreferences = .default { didSet { rememberCardStyle() } }

    var topBarStyle: TopBarStyle = .adaptive
    var topBarGlow = true

    var hoverPreviewEnabled = false
    var hoverPreviewDelay: HoverPreviewDelay = .two

    var continueWatchingCard: ContinueWatchingCardPreferences = .default { didSet { rememberCardStyle() } }
    var continueWatchingStyle: ContinueWatchingStyle = .wide { didSet { rememberCardStyle() } }
    var continueWatchingSort: ContinueWatchingSort = .recent
    /// Settings › Layout › Liquid Glass.
    var liquidGlass = LiquidGlassPreferences()
    /// Settings › Layout › Low Power Mode.
    var lowPowerMode = LowPowerMode.automatic
    /// Settings › Layout › Upcoming › New Episode Reminders.
    var episodeNotifications = false
    /// Settings › Layout › Top Bar Size, on iPad and Mac.
    var topBarSize = TopBarSizePreferences()
    /// Settings › Playback › Player Appearance.
    var playerSize = PlayerSizePreferences()
    /// Settings › Layout › Home Layout › Hero.
    var heroBlend = HeroBlendPreferences()
    /// The title and details under Wide and Poster cards.
    var continueWatchingShowsLabels = true
    var continueWatchingEpisodeThumbnails = true
    /// Each card's picture: the title's artwork, or the scene it stopped on.
    var continueWatchingArtwork: ContinueWatchingArtwork = .artwork
    /// Settings › Layout › Collections › Card Style.
    var collectionCard: CollectionCardPreferences = .default { didSet { rememberCardStyle() } }
    /// Nuvio's Next Up behaviour: after an episode ends, the row offers the
    /// one after the furthest episode watched, not the one just finished.
    var nextUpFromFurthestEpisode = true
    var showsUnairedNextUp = true
    /// Blurs next-up episode stills, so they don't spoil the episode.
    var blursNextUp = false
    /// Offers to resume when Omnia opens after it was closed during playback.
    var resumePromptOnLaunch = true

    var detailBackground: DetailBackgroundMode = .artworkColor
    var episodeLayout: EpisodeCardLayout = .horizontal
    var blurUnwatchedEpisodes = false
    var hiddenDetailSections: Set<DetailSection> = []
    /// The order of a title page's sections (Nuvio's reorderable sections).
    var detailSectionOrder: [DetailSection] = DetailSection.allCases
    /// Nuvio's Poster Transition: the poster expands and blurs into the
    /// title page when it opens.
    var posterTransition = false
    /// Nuvio's Shuffle: offers random episodes on a show's page. Turning it
    /// off pauses shuffle for every show.
    var episodeShuffleAvailable = false

    static let `default` = Self()
    /// Nuvio's default custom gradient, the same as Rose Gold.
    static let defaultCustomGradient = ["B75AFF", "EC70A9", "FFB37A"]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        accentTheme = (try? c.decodeIfPresent(AccentTheme.self, forKey: .accentTheme)) ?? d.accentTheme
        customAccentHex = (try? c.decodeIfPresent(String.self, forKey: .customAccentHex)) ?? d.customAccentHex
        customAccentMode = (try? c.decodeIfPresent(CustomAccentMode.self, forKey: .customAccentMode)) ?? d.customAccentMode
        customGradientHexes = (try? c.decodeIfPresent([String].self, forKey: .customGradientHexes)) ?? d.customGradientHexes
        amoledBlack = (try? c.decodeIfPresent(Bool.self, forKey: .amoledBlack)) ?? d.amoledBlack
        topBarStyle = (try? c.decodeIfPresent(TopBarStyle.self, forKey: .topBarStyle)) ?? d.topBarStyle
        topBarGlow = (try? c.decodeIfPresent(Bool.self, forKey: .topBarGlow)) ?? d.topBarGlow
        posterWidth = (try? c.decodeIfPresent(PosterWidthPreset.self, forKey: .posterWidth)) ?? d.posterWidth
        posterCorner = (try? c.decodeIfPresent(PosterCornerPreset.self, forKey: .posterCorner)) ?? d.posterCorner
        landscapePosters = (try? c.decodeIfPresent(Bool.self, forKey: .landscapePosters)) ?? d.landscapePosters
        customPosterURLPattern = (try? c.decodeIfPresent(String.self, forKey: .customPosterURLPattern)) ?? d.customPosterURLPattern
        cardDepth = (try? c.decodeIfPresent(CardDepthPreferences.self, forKey: .cardDepth)) ?? d.cardDepth
        cardHover = (try? c.decodeIfPresent(CardHoverPreferences.self, forKey: .cardHover)) ?? d.cardHover
        hoverPreviewEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hoverPreviewEnabled)) ?? d.hoverPreviewEnabled
        hoverPreviewDelay = (try? c.decodeIfPresent(HoverPreviewDelay.self, forKey: .hoverPreviewDelay)) ?? d.hoverPreviewDelay
        if c.contains(.continueWatchingCard), let nested = try? c.superDecoder(forKey: .continueWatchingCard),
           let card = try? ContinueWatchingCardPreferences(from: nested, posterWidth: posterWidth, posterCorner: posterCorner) {
            continueWatchingCard = card
        } else {
            continueWatchingCard = d.continueWatchingCard
        }
        continueWatchingStyle = (try? c.decodeIfPresent(ContinueWatchingStyle.self, forKey: .continueWatchingStyle)) ?? d.continueWatchingStyle
        lowPowerMode = (try? c.decodeIfPresent(LowPowerMode.self, forKey: .lowPowerMode)) ?? d.lowPowerMode
        episodeNotifications = (try? c.decodeIfPresent(Bool.self, forKey: .episodeNotifications)) ?? d.episodeNotifications
        topBarSize = (try? c.decodeIfPresent(TopBarSizePreferences.self, forKey: .topBarSize)) ?? d.topBarSize
        playerSize = (try? c.decodeIfPresent(PlayerSizePreferences.self, forKey: .playerSize)) ?? d.playerSize
        heroBlend = (try? c.decodeIfPresent(HeroBlendPreferences.self, forKey: .heroBlend)) ?? d.heroBlend
        liquidGlass = (try? c.decodeIfPresent(LiquidGlassPreferences.self, forKey: .liquidGlass)) ?? d.liquidGlass
        continueWatchingShowsLabels = (try? c.decodeIfPresent(Bool.self, forKey: .continueWatchingShowsLabels)) ?? d.continueWatchingShowsLabels
        continueWatchingSort = (try? c.decodeIfPresent(ContinueWatchingSort.self, forKey: .continueWatchingSort)) ?? d.continueWatchingSort
        continueWatchingEpisodeThumbnails = (try? c.decodeIfPresent(Bool.self, forKey: .continueWatchingEpisodeThumbnails)) ?? d.continueWatchingEpisodeThumbnails
        continueWatchingArtwork = (try? c.decodeIfPresent(ContinueWatchingArtwork.self, forKey: .continueWatchingArtwork)) ?? d.continueWatchingArtwork
        if c.contains(.collectionCard), let nested = try? c.superDecoder(forKey: .collectionCard) {
            collectionCard = try CollectionCardPreferences(from: nested, poster: posterWidth, corner: posterCorner, landscape: landscapePosters)
        } else {
            collectionCard = CollectionCardPreferences(poster: posterWidth, corner: posterCorner, landscape: landscapePosters)
        }
        nextUpFromFurthestEpisode = (try? c.decodeIfPresent(Bool.self, forKey: .nextUpFromFurthestEpisode)) ?? d.nextUpFromFurthestEpisode
        showsUnairedNextUp = (try? c.decodeIfPresent(Bool.self, forKey: .showsUnairedNextUp)) ?? d.showsUnairedNextUp
        blursNextUp = (try? c.decodeIfPresent(Bool.self, forKey: .blursNextUp)) ?? d.blursNextUp
        resumePromptOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .resumePromptOnLaunch)) ?? d.resumePromptOnLaunch
        detailBackground = (try? c.decodeIfPresent(DetailBackgroundMode.self, forKey: .detailBackground)) ?? d.detailBackground
        episodeLayout = (try? c.decodeIfPresent(EpisodeCardLayout.self, forKey: .episodeLayout)) ?? d.episodeLayout
        blurUnwatchedEpisodes = (try? c.decodeIfPresent(Bool.self, forKey: .blurUnwatchedEpisodes)) ?? d.blurUnwatchedEpisodes
        hiddenDetailSections = (try? c.decodeIfPresent(Set<DetailSection>.self, forKey: .hiddenDetailSections)) ?? d.hiddenDetailSections
        detailSectionOrder = Self.completeOrder((try? c.decodeIfPresent([LenientDetailSection].self, forKey: .detailSectionOrder))?.compactMap(\.value) ?? d.detailSectionOrder)
        posterTransition = (try? c.decodeIfPresent(Bool.self, forKey: .posterTransition)) ?? d.posterTransition
        episodeShuffleAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .episodeShuffleAvailable)) ?? d.episodeShuffleAvailable
        cardStyles = (try? c.decodeIfPresent([String: CardAppearance].self, forKey: .cardStyles)) ?? [:]
        sharesCardStyles = (try? c.decodeIfPresent(Bool.self, forKey: .sharesCardStyles)) ?? false
        adoptCardStyleForThisDevice()
    }

    /// Drops repeats and appends sections a saved order doesn't know yet.
    nonisolated static func completeOrder(_ order: [DetailSection]) -> [DetailSection] {
        var seen = Set<DetailSection>()
        let known = order.filter { seen.insert($0).inserted }
        return known + DetailSection.allCases.filter { !seen.contains($0) }
    }

    /// One saved section, ignored when a later version removed it.
    private nonisolated struct LenientDetailSection: Decodable {
        let value: DetailSection?

        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(DetailSection.self)
        }
    }

    var normalized: Self {
        var value = self
        value.cardDepth = cardDepth.normalized
        if Color(omniaHex: customAccentHex) == nil {
            value.customAccentHex = Self.default.customAccentHex
        }
        if Color(omniaHex: cardHover.customHex) == nil {
            value.cardHover.customHex = CardHoverPreferences.default.customHex
        }
        if customGradientHexes.count != 3 || customGradientHexes.contains(where: { Color(omniaHex: $0) == nil }) {
            value.customGradientHexes = Self.defaultCustomGradient
        }
        return value
    }

    var accentColor: Color {
        switch accentTheme {
        case .blue: .blue
        case .custom:
            customAccentMode == .gradient
                ? customGradientColors[1]
                : Color(omniaHex: customAccentHex) ?? .blue
        default: accentTheme.hex.flatMap(Color.init(omniaHex:)) ?? .blue
        }
    }

    private var customGradientColors: [Color] {
        let colors = customGradientHexes.compactMap(Color.init(omniaHex:))
        return colors.count == 3
            ? colors
            : Self.defaultCustomGradient.compactMap(Color.init(omniaHex:))
    }

    /// The accent's colours: several for a gradient theme, otherwise one.
    var accentGradientColors: [Color] {
        switch accentTheme {
        case .custom where customAccentMode == .gradient:
            customGradientColors
        default:
            accentTheme.gradientHexes?.compactMap(Color.init(omniaHex:)) ?? [accentColor]
        }
    }

    var usesAccentGradient: Bool { accentGradientColors.count > 1 }

    /// Nuvio's accentBrush: a gradient running from the top-leading to the
    /// bottom-trailing corner, or the plain accent.
    var accentStyle: AnyShapeStyle {
        usesAccentGradient
            ? AnyShapeStyle(LinearGradient(colors: accentGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(accentColor)
    }

    /// Each device class's card style, carried in the synced settings so a device
    /// never changes another's. The plain fields above are this device's.
    var cardStyles: [String: CardAppearance] = [:]
    /// Poster Card Style › Same Style on All Devices.
    var sharesCardStyles = false

    private var cardAppearance: CardAppearance {
        CardAppearance(
            posterWidth: posterWidth, posterCorner: posterCorner, landscapePosters: landscapePosters,
            cardDepth: cardDepth, cardHover: cardHover, continueWatchingCard: continueWatchingCard,
            continueWatchingStyle: continueWatchingStyle, collectionCard: collectionCard
        )
    }

    private mutating func rememberCardStyle() {
        cardStyles[OmniaDeviceClass.current.rawValue] = cardAppearance
    }

    /// After decoding, the plain fields hold the shared values. This device's own
    /// set replaces them, unless the viewer shares one set. The first time an
    /// iPhone sees this, it starts from them with sizes capped to Small.
    private mutating func adoptCardStyleForThisDevice() {
        let device = OmniaDeviceClass.current
        guard !sharesCardStyles else {
            cardStyles[device.rawValue] = cardAppearance
            return
        }
        if let own = cardStyles[device.rawValue] {
            posterWidth = own.posterWidth
            posterCorner = own.posterCorner
            landscapePosters = own.landscapePosters
            cardDepth = own.cardDepth
            cardHover = own.cardHover
            continueWatchingCard = own.continueWatchingCard
            continueWatchingStyle = own.continueWatchingStyle
            collectionCard = own.collectionCard
            return
        }
        if device == .phone {
            let order = PosterWidthPreset.allCases
            let cap = order.firstIndex(of: .small) ?? 0
            if (order.firstIndex(of: posterWidth) ?? 0) > cap { posterWidth = .small }
            if [.standard, .large, .extraLarge].contains(collectionCard.size) { collectionCard.size = .small }
            if [.standard, .large, .extraLarge].contains(continueWatchingCard.size) { continueWatchingCard.size = .small }
        }
        rememberCardStyle()
    }

    /// Poster Card Style › Apply to All Cards: one copy of the poster look into
    /// Collections, folders and Continue Watching, which stay independent after.
    mutating func applyPosterStyleToAllCards() {
        collectionCard.shape = landscapePosters ? .landscape : .poster
        collectionCard.size = CollectionCardPreferences.Size(rawValue: posterWidth.rawValue) ?? .standard
        collectionCard.corners = CollectionCardPreferences.Corners(rawValue: posterCorner.rawValue) ?? .rounded
        collectionCard.folderCards = landscapePosters ? .landscape : .asImported
        continueWatchingCard.size = ContinueWatchingCardPreferences.Size(rawValue: posterWidth.rawValue) ?? .standard
        continueWatchingCard.corners = ContinueWatchingCardPreferences.Corners(rawValue: posterCorner.rawValue) ?? .rounded
    }

    /// Whether Apply to All Cards has nothing left to do.
    var allCardsMatchPosterStyle: Bool {
        var applied = self
        applied.applyPosterStyleToAllCards()
        return applied.collectionCard == collectionCard && applied.continueWatchingCard == continueWatchingCard
    }

    var posterCardWidth: CGFloat { posterWidth.width }

    var landscapePosterCardWidth: CGFloat {
        #if os(iOS)
        let baseline: CGFloat = 248
        #else
        let baseline: CGFloat = 304
        #endif
        return baseline * posterCardWidth / PosterWidthPreset.standard.width
    }
    var posterCardHeight: CGFloat { posterWidth.width * 1.5 }
    var posterCornerRadius: CGFloat { posterCorner.radius }
    /// Landscape cards keep a slightly larger radius than posters, as before.
    var landscapeCornerRadius: CGFloat { posterCorner == .square ? 0 : posterCorner.radius + 2 }

    func shows(_ section: DetailSection) -> Bool {
        !hiddenDetailSections.contains(section)
    }

    /// Visible sections in the chosen order.
    var orderedDetailSections: [DetailSection] {
        Self.completeOrder(detailSectionOrder).filter(shows)
    }

    mutating func moveDetailSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = Self.completeOrder(detailSectionOrder)
        order.move(fromOffsets: source, toOffset: destination)
        detailSectionOrder = order
    }

    mutating func moveDetailSection(_ section: DetailSection, by offset: Int) {
        var order = Self.completeOrder(detailSectionOrder)
        guard let index = order.firstIndex(of: section) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        detailSectionOrder = order
    }
}

extension Color {
    /// A six-digit RGB hex such as "E8A91C" or "#E8A91C".
    nonisolated init?(omniaHex: String) {
        var text = omniaHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    /// The colour as six-digit sRGB hex, for storing a custom accent.
    var omniaHex: String? {
        let resolved = resolve(in: EnvironmentValues())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = resolved.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3
        else { return nil }
        let rgb = components.prefix(3).map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }
}

/// The plain page colour behind Omnia's pages. AMOLED Black (Settings ›
/// Appearance) makes it true black in Dark appearance.
struct OmniaPageBackground: View {
    @Environment(\.displayPreferences) private var display
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if display.amoledBlack && colorScheme == .dark {
            Color.black
        } else {
            #if os(iOS)
            Color(uiColor: .systemBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        }
    }
}

private struct DisplayPreferencesKey: EnvironmentKey {
    static let defaultValue = DisplayPreferences.default
}

extension EnvironmentValues {
    var displayPreferences: DisplayPreferences {
        get { self[DisplayPreferencesKey.self] }
        set { self[DisplayPreferencesKey.self] = newValue }
    }
}
