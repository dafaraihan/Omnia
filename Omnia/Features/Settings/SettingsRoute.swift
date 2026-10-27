import Foundation

enum SettingsSection: Int, CaseIterable, Identifiable, Sendable {
    case account
    case general
    case about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .general: "General"
        case .about: "About"
        }
    }
}

enum AboutSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case metadataAndDiscovery
    case playback
    case addonTechnology
    case cloudAndAuthentication
    case appleTechnologies
    case openSourceSoftware
    case attributions
    case licenses
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metadataAndDiscovery: "Metadata & Discovery"
        case .playback: "Playback"
        case .addonTechnology: "Add-on Technology"
        case .cloudAndAuthentication: "Cloud & Authentication"
        case .appleTechnologies: "Apple Technologies"
        case .openSourceSoftware: "Open-Source Software"
        case .attributions: "Attributions"
        case .licenses: "Licenses"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .metadataAndDiscovery: "rectangle.3.group"
        case .playback: "play.rectangle"
        case .addonTechnology: "puzzlepiece.extension"
        case .cloudAndAuthentication: "cloud"
        case .appleTechnologies: "apple.logo"
        case .openSourceSoftware: "chevron.left.forwardslash.chevron.right"
        case .attributions: "text.quote"
        case .licenses: "doc.text"
        case .privacy: "hand.raised"
        }
    }
}

struct SettingsRouteGroup: Identifiable, Equatable, Sendable {
    let section: SettingsSection
    let routes: [SettingsRoute]

    var id: SettingsSection { section }
}

enum SettingsRoute: Hashable, Sendable {
    case account
    case contentDiscovery
    case addons
    case plugins
    case mediaServers
    case liveTV
    case home
    case catalogs
    case collections
    case metadata
    case tmdbEnrichment
    case animeEnrichment
    case metadataSources
    case progress
    case upcoming
    case videoPlayer
    case streamSelection
    case subtitle
    case playbackResolver
    case playbackDiagnostics
    case appearance
    case posterCards
    case streams
    case continueWatching
    case detailPage
    case about
    case metadataProvider(String)
    case tracker(TrackerKind)
    case streamSorting
    case aboutSection(AboutSection)

    /// Nuvio's Settings tree: Layout, Content & Discovery, Playback and
    /// Integrations under General. Omnia's own Progress page opens from
    /// Layout › Continue Watching.
    static let rootGroups: [SettingsRouteGroup] = [
        .init(section: .general, routes: [.account, .appearance, .contentDiscovery, .videoPlayer, .metadata]),
        .init(section: .about, routes: [.about])
    ]

    /// The pages each root page opens, so search finds them from the root.
    var children: [SettingsRoute] {
        switch self {
        case .appearance: [.home, .catalogs, .collections, .continueWatching, .progress, .upcoming, .posterCards, .detailPage, .streams]
        case .contentDiscovery: [.addons, .mediaServers, .liveTV, .plugins]
        case .videoPlayer: [.streamSelection, .subtitle, .playbackResolver, .playbackDiagnostics]
        case .metadata: [.tmdbEnrichment, .animeEnrichment, .metadataProvider("mdblist"), .metadataSources, .streamSorting] + TrackerKind.allCases.map(SettingsRoute.tracker)
        default: []
        }
    }

    static let allVerificationRoutes: [SettingsRoute] =
        rootGroups.flatMap(\.routes)
        + rootGroups.flatMap(\.routes).flatMap(\.children)
        + MetadataProvider.supported.filter { $0.id != "mdblist" }.map { .metadataProvider($0.id) }
        + AboutSection.allCases.map { .aboutSection($0) }

    static func filteredRootGroups(query: String) -> [SettingsRouteGroup] {
        rootGroups.compactMap { group in
            let candidates = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? group.routes
                : group.routes.flatMap { [$0] + $0.children }
            let routes = candidates.filter { $0.matches(query) }
            return routes.isEmpty ? nil : .init(section: group.section, routes: routes)
        }
    }

    var title: String {
        switch self {
        case .account: "Account"
        case .contentDiscovery: "Content & Discovery"
        case .addons: "Add-ons"
        case .plugins: "Plugins"
        case .mediaServers: "Media Servers"
        case .liveTV: "Live TV"
        case .home: "Home Layout"
        case .catalogs: "Catalogs"
        case .collections: "Collections"
        case .metadata: "Integrations"
        case .tmdbEnrichment: "TMDB Enrichment"
        case .animeEnrichment: "Anime Enrichment"
        case .metadataSources: "Metadata Sources"
        case .progress: "Progress"
        case .upcoming: "Upcoming"
        case .videoPlayer: "Playback"
        case .streamSelection: "Stream Selection"
        case .subtitle: "Subtitle"
        case .playbackResolver: "Playback Resolver"
        case .playbackDiagnostics: "Playback Diagnostics"
        case .appearance: "Layout"
        case .posterCards: "Poster Card Style"
        case .streams: "Streams"
        case .continueWatching: "Continue Watching"
        case .detailPage: "Detail Page"
        case .about: "About Omnia"
        case .metadataProvider("mdblist"): "MDBList Ratings"
        case let .metadataProvider(id):
            MetadataProvider.supported.first { $0.id == id }?.name ?? "Metadata Provider"
        case let .tracker(kind):
            kind.title
        case .streamSorting: "Stream Sorting"
        case let .aboutSection(section):
            section.title
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .contentDiscovery: "magnifyingglass"
        case .addons: "puzzlepiece.extension"
        case .plugins: "shippingbox"
        case .mediaServers: "server.rack"
        case .liveTV: "play.tv"
        case .home: "house"
        case .catalogs: "rectangle.stack"
        case .collections: "square.stack.3d.up"
        case .metadata, .metadataProvider, .metadataSources: "rectangle.3.group"
        case .tmdbEnrichment: "sparkles.rectangle.stack"
        case .animeEnrichment: "sparkles.tv"
        case .tracker: "checkmark.circle"
        case .streamSorting: "arrow.up.arrow.down.circle"
        case .progress: "clock.arrow.circlepath"
        case .upcoming: "calendar"
        case .videoPlayer: "play.rectangle"
        case .streamSelection: "list.bullet.rectangle"
        case .subtitle: "captions.bubble"
        case .playbackResolver: "lock.shield"
        case .playbackDiagnostics: "stethoscope"
        case .appearance: "circle.lefthalf.filled"
        case .posterCards: "rectangle.portrait.on.rectangle.portrait"
        case .streams: "play.square.stack"
        case .continueWatching: "play.circle"
        case .detailPage: "doc.richtext"
        case .about: "info.circle"
        case let .aboutSection(section): section.systemImage
        }
    }

    var searchTerms: [String] {
        switch self {
        case .account: ["profile", "profiles", "avatar", "PIN", "watch time", "sync", "email", "Apple", "Google", "sign in", "sign out"]
        case .contentDiscovery: ["add-ons", "addons", "plugins", "sources", "discovery", "recent searches", "search history", "media servers", "live TV", "IPTV"]
        case .addons: ["sources", "manifest", "timeout", "import", "export"]
        case .liveTV: ["Live TV", "IPTV", "M3U", "playlist", "Xtream", "Stalker", "portal", "MAC", "channels", "TV guide", "EPG", "XMLTV", "navigation"]
        case .mediaServers: ["Jellyfin", "Emby", "media server", "server", "library", "libraries", "sign in", "watch progress"]
        case .plugins: ["Nuvio", "scrapers", "providers", "repository", "JavaScript", "streams", "TMDB"]
        case .home: ["layout", "hero", "hero style", "card", "full-bleed", "dynamic background", "hero trailer", "trailer", "autoplay", "sound", "delay", "rows", "catalogs", "collections", "order", "rename", "unreleased", "catalog type", "upcoming", "discover", "TMDB", "TVDB"]
        case .catalogs: ["catalog", "discover", "TMDB", "TVDB"]
        case .collections: ["collections", "folders", "Nuvio", "Xperience", "import", "export", "pin"]
        case .metadata: ["metadata", "TMDB", "TVDB", "MDBList", "AniList", "providers", "fallback", "ratings", "enrichment"]
        case .tmdbEnrichment: ["TMDB", "enrichment", "trailers", "artwork", "logo", "backdrop", "cast", "credits", "episodes", "more like this", "collections", "productions"]
        case .animeEnrichment: ["anime", "enrichment", "AniList", "Kitsu", "MyAnimeList", "MAL", "synopsis", "artwork", "genres"]
        case .metadataSources: ["metadata", "TMDB", "TVDB", "AniList", "Kitsu", "MyAnimeList", "MAL", "Jikan", "fallback", "anime", "primary source"]
        case .progress: ["local progress", "continue watching", "watchlist", "backup"]
        case .upcoming: ["episodes", "look ahead", "Home"]
        case .videoPlayer: ["video player", "player", "skip intro", "auto skip", "recap", "credits", "up next", "next episode", "threshold", "decoder", "hardware", "overlay", "audio", "subtitles", "SDH", "forced", "source selection", "auto play"]
        case .streamSelection: ["auto play", "autoplay", "first source", "regex", "reuse last link", "binge group", "timeout", "allowed add-ons", "plugins"]
        case .subtitle: ["subtitles", "captions", "SDH", "appearance"]
        case .playbackResolver: ["endpoint", "bearer token", "approved add-ons", "approved HTTPS hosts"]
        case .playbackDiagnostics: ["diagnostics", "log", "errors", "failures", "could not play", "libmpv", "copy"]
        case .appearance: ["appearance", "theme", "system", "light", "dark", "accent", "color", "AMOLED", "black", "hover preview", "poster", "glow", "gradient", "top bar style", "glass glow", "adaptive", "compact", "expanded", "iPadOS", "standard"]
        case .streams: ["streams", "sources", "badges", "Fusion", "size", "add-on logo", "background", "cinematic", "search bar", "pin"]
        case .posterCards: ["poster", "card", "width", "size", "corner", "radius", "landscape", "depth", "glow", "sheen", "edge"]
        case .continueWatching: ["continue watching", "resume", "style", "sort", "thumbnails", "finished"]
        case .detailPage: ["detail", "title page", "background", "episodes", "blur", "spoiler", "sections", "cast", "trailers"]
        case .about: ["resources", "TMDB", "TVDB", "libmpv", "Supabase", "licenses", "privacy"]
        case .metadataProvider: ["metadata provider", title]
        case .streamSorting: ["sort", "sorting", "ranking", "quality", "resolution", "4K", "HDR", "Dolby Vision", "codec", "HEVC", "size", "debrid", "cached", "filters"]
        case .tracker: ["tracker", "scrobble", "scrobbling", "history", "watched", "Trakt", "Simkl", "PublicMetaDB", "PMDB", title]
        case let .aboutSection(section): [section.title]
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        return ([title] + searchTerms).contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }
}
