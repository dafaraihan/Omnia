import SwiftUI

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

/// The top bar used when Navigation Style is Top Bar. Standard is
/// Omnia's system tab bar; the others are Nuvio's floating bar.
nonisolated enum TopBarStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case native
    case adaptive
    case expanded
    case compact

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
        case .native: "The system tab bar, as on iPad."
        case .adaptive: "Shows labels, and shrinks to icons over the Home hero or once you scroll."
        case .expanded: "Always shows icons and labels."
        case .compact: "Always shows icons only."
        }
    }

    var isNuvio: Bool { self != .native }
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
        switch self {
        case .compact: 104
        case .small: 118
        case .standard: 132
        case .large: 146
        case .extraLarge: 160
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
    case studio
    case collection
    case recommendations

    var id: Self { self }

    var title: String {
        switch self {
        case .genres: "Genres"
        case .facts: "Details"
        case .episodes: "Episodes"
        case .trailers: "Trailers"
        case .bonusContent: "Bonus Content"
        case .people: "People"
        case .studio: "More from the Studio"
        case .collection: "Collection"
        case .recommendations: "More Like This"
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

/// How Omnia looks: accent, cards, Continue Watching and the title page.
/// Every value here is read by the views that draw it.
nonisolated struct DisplayPreferences: Codable, Equatable, Sendable {
    var accentTheme: AccentTheme = .blue
    var customAccentHex = "7C5CFF"
    var customAccentMode: CustomAccentMode = .single
    var customGradientHexes = Self.defaultCustomGradient
    var amoledBlack = false

    var posterWidth: PosterWidthPreset = .standard
    var posterCorner: PosterCornerPreset = .rounded
    var landscapePosters = false
    var cardDepth: CardDepthPreferences = .default
    var cardHover: CardHoverPreferences = .default

    var topBarStyle: TopBarStyle = .native
    var topBarGlow = true

    var hoverPreviewEnabled = false
    var hoverPreviewDelay: HoverPreviewDelay = .two

    var continueWatchingStyle: ContinueWatchingStyle = .wide
    var continueWatchingSort: ContinueWatchingSort = .recent
    var continueWatchingEpisodeThumbnails = true
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
        cardDepth = (try? c.decodeIfPresent(CardDepthPreferences.self, forKey: .cardDepth)) ?? d.cardDepth
        cardHover = (try? c.decodeIfPresent(CardHoverPreferences.self, forKey: .cardHover)) ?? d.cardHover
        hoverPreviewEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hoverPreviewEnabled)) ?? d.hoverPreviewEnabled
        hoverPreviewDelay = (try? c.decodeIfPresent(HoverPreviewDelay.self, forKey: .hoverPreviewDelay)) ?? d.hoverPreviewDelay
        continueWatchingStyle = (try? c.decodeIfPresent(ContinueWatchingStyle.self, forKey: .continueWatchingStyle)) ?? d.continueWatchingStyle
        continueWatchingSort = (try? c.decodeIfPresent(ContinueWatchingSort.self, forKey: .continueWatchingSort)) ?? d.continueWatchingSort
        continueWatchingEpisodeThumbnails = (try? c.decodeIfPresent(Bool.self, forKey: .continueWatchingEpisodeThumbnails)) ?? d.continueWatchingEpisodeThumbnails
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

    var posterCardWidth: CGFloat { posterWidth.width }
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
