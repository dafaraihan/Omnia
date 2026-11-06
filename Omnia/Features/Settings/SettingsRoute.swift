enum SettingsSection: Int, CaseIterable, Identifiable, Sendable {
    case look
    case player
    case sources
    case discovery
    case device
    case about

    var id: Int { rawValue }
}

import Foundation

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
        case .privacy: "lock.shield"
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
    case tvdbEnrichment
    case animeEnrichment
    case metadataSources
    case progress
    case videoPlayer
    case subtitle
    case playbackResolver
    case playbackDiagnostics
    case appearance
    case navigation
    case playerControls
    case notifications
    case privacy
    case battery
    case liquidGlass
    case posterCards
    case landscapeCards
    case streams
    case continueWatching
    case detailPage
    case about
    case metadataProvider(String)
    case tracking
    case aboutSection(AboutSection)
    /// The less common options of a page, one level below it.
    indirect case advanced(SettingsRoute)

    /// The Settings tree. Account & Profiles is the profile card above these.
    /// Navigation only has options where there is a sidebar or top bar.
    static var rootGroups: [SettingsRouteGroup] {
        return [
            .init(section: .look, routes: [.appearance, .home, .detailPage]),
            .init(section: .player, routes: [.videoPlayer]),
            .init(section: .sources, routes: [.addons, .plugins, .mediaServers, .liveTV, .metadata]),
            .init(section: .discovery, routes: [.contentDiscovery, .tracking, .notifications]),
            .init(section: .device, routes: [.privacy, .battery, .progress]),
            .init(section: .about, routes: [.about])
        ]
    }

    /// The pages a root page opens, so search finds them from the root.
    var children: [SettingsRoute] {
        return switch self {
        case .home: [.catalogs, .collections, .continueWatching]
        case .appearance: OmniaDevice.isPhone ? [.liquidGlass, .posterCards, .landscapeCards] : [.liquidGlass, .navigation, .posterCards, .landscapeCards]
        case .videoPlayer: [.playerControls, .subtitle, .streams, .playbackResolver, .playbackDiagnostics]
        case .metadata: [.metadataProvider("tmdb"), .metadataProvider("tvdb"), .metadataProvider("fanart"),
                         .tmdbEnrichment, .tvdbEnrichment, .animeEnrichment, .metadataProvider("mdblist"), .metadataSources]
        default: []
        }
    }

    static func filteredRootGroups(query: String) -> [SettingsRouteGroup] {
        rootGroups.compactMap { group in
            let candidates = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? group.routes
                : group.routes.flatMap { [$0] + $0.children }
            let routes = candidates.filter { $0.matches(query) }
            return routes.isEmpty ? nil : .init(section: group.section, routes: routes)
        }
    }

    /// What a row that opens this page says. Search shows the full title.
    var linkTitle: String {
        if case .advanced = self { return "Advanced" }
        return title
    }

    var title: String {
        switch self {
        case let .advanced(route): "\(route.title) › Advanced"
        case .account: "Account & Profiles"
        case .contentDiscovery: "Search & Discover"
        case .addons: "Add-ons"
        case .plugins: "Plugins"
        case .mediaServers: "Media Servers"
        case .liveTV: "Live TV"
        case .home: "Home"
        case .catalogs: "Catalogs"
        case .collections: "Collections"
        case .metadata: "Metadata"
        case .tmdbEnrichment: "TMDB Enrichment"
        case .tvdbEnrichment: "TVDB Enrichment"
        case .animeEnrichment: "Anime Enrichment"
        case .metadataSources: "Metadata Sources"
        case .progress: "Data & Backup"
        case .videoPlayer: "Player"
        case .subtitle: "Subtitles"
        case .playbackResolver: "Cache and Sharing"
        case .playbackDiagnostics: "Diagnostics"
        case .appearance: "Appearance"
        case .navigation: "Navigation"
        case .playerControls: "Player Look"
        case .notifications: "Notifications"
        case .privacy: "Privacy"
        case .battery: "Battery & Performance"
        case .liquidGlass: "Liquid Glass"
        case .posterCards: "Poster Card Style"
        case .landscapeCards: "Landscape Card Style"
        case .streams: "Streams"
        case .continueWatching: "Continue Watching"
        case .detailPage: "Title Page"
        case .about: "About"
        case .metadataProvider("mdblist"): "MDBList Ratings"
        case let .metadataProvider(id):
            MetadataProvider.supported.first { $0.id == id }?.name ?? "Metadata Provider"
        case .tracking:
            "Tracking"
        case let .aboutSection(section):
            section.title
        }
    }

    var systemImage: String {
        switch self {
        case .advanced: "slider.horizontal.3"
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
        case .tvdbEnrichment: "sparkles.rectangle.stack"
        case .animeEnrichment: "sparkles.tv"
        case .tracking: "checkmark.circle"
        case .progress: "clock.arrow.circlepath"
        case .videoPlayer: "play.rectangle"
        case .subtitle: "captions.bubble"
        case .playbackResolver: "externaldrive.connected.to.line.below"
        case .playbackDiagnostics: "stethoscope"
        case .appearance: "circle.lefthalf.filled"
        case .navigation: "sidebar.left"
        case .playerControls: "slider.horizontal.below.rectangle"
        case .notifications: "bell.badge"
        case .privacy: "lock.shield"
        case .battery: "battery.75percent"
        case .liquidGlass: "drop.halffull"
        case .posterCards: "rectangle.portrait.on.rectangle.portrait"
        case .landscapeCards: "rectangle.on.rectangle"
        case .streams: "play.square.stack"
        case .continueWatching: "play.circle"
        case .detailPage: "doc.richtext"
        case .about: "info.circle"
        case let .aboutSection(section): section.systemImage
        }
    }

    var searchTerms: [String] {
        switch self {
        case .advanced: []
        case .account: ["profile", "profiles", "avatar", "PIN", "watch time", "sync", "email", "Apple", "Google", "sign in", "sign out"]
        case .contentDiscovery: ["add-ons", "addons", "plugins", "sources", "discovery", "recent searches", "search history", "media servers", "live TV", "IPTV"]
        case .addons: ["sources", "manifest", "timeout", "import", "export"]
        case .liveTV: ["Live TV", "IPTV", "M3U", "playlist", "Xtream", "Stalker", "portal", "MAC", "channels", "TV guide", "EPG", "XMLTV", "navigation"]
        case .mediaServers: ["Jellyfin", "Emby", "media server", "server", "library", "libraries", "sign in", "watch progress"]
        case .plugins: ["Nuvio", "scrapers", "providers", "repository", "JavaScript", "streams", "TMDB"]
        case .home: ["layout", "hero", "hero style", "card", "full-bleed", "dynamic background", "hero trailer", "trailer", "autoplay", "sound", "delay", "rows", "catalogs", "collections", "order", "rename", "unreleased", "catalog type", "upcoming", "discover", "TMDB", "TVDB"]
        case .catalogs: ["catalog", "discover", "TMDB", "TVDB"]
        case .collections: ["collections", "folders", "Nuvio", "Xperience", "import", "export", "pin"]
        case .metadata: ["metadata", "TMDB", "TVDB", "MDBList", "AniList", "providers", "fallback", "ratings", "enrichment", "API key", "API keys", "key", "fanart"]
        case .tvdbEnrichment: ["TVDB", "enrichment", "artwork", "credits", "episodes"]
        case .tmdbEnrichment: ["TMDB", "enrichment", "trailers", "artwork", "logo", "backdrop", "cast", "credits", "episodes", "more like this", "collections", "productions"]
        case .animeEnrichment: ["anime", "enrichment", "AniList", "Kitsu", "MyAnimeList", "MAL", "synopsis", "artwork", "genres"]
        case .metadataSources: ["metadata", "TMDB", "TVDB", "AniList", "Kitsu", "MyAnimeList", "MAL", "Jikan", "fallback", "anime", "primary source"]
        case .progress: ["local progress", "continue watching", "watchlist", "backup"]
        case .videoPlayer: ["video player", "player", "skip intro", "auto skip", "recap", "credits", "up next", "next episode", "threshold", "decoder", "engine", "KSPlayer", "mpv", "hardware", "Metal", "rendering", "gpu-next", "OpenGL", "overlay", "audio", "subtitles", "SDH", "forced", "source selection", "auto play"]
        case .subtitle: ["player appearance", "subtitles", "captions", "SDH", "appearance"]
        case .playbackResolver: ["endpoint", "bearer token", "approved add-ons", "approved HTTPS hosts"]
        case .playbackDiagnostics: ["diagnostics", "log", "errors", "failures", "could not play", "libmpv", "copy"]
        case .navigation: ["sidebar", "top bar", "tab bar", "adaptive", "size", "glass glow"]
        case .playerControls: ["player appearance", "controls", "menu size", "timeline", "overlays", "loading", "pause"]
        case .notifications: ["reminders", "new episode", "alerts"]
        case .privacy: ["app lock", "Face ID", "Touch ID", "passcode", "content warnings", "parents guide"]
        case .battery: ["low power", "energy", "decoder", "hardware", "Metal", "hover preview"]
        case .appearance: ["appearance", "theme", "system", "light", "dark", "accent", "color", "AMOLED", "black", "hover preview", "poster", "glow", "gradient", "top bar style", "glass glow", "adaptive", "compact", "expanded", "iPadOS", "standard"]
        case .liquidGlass: ["liquid glass", "glass", "transparency", "frosted", "blur", "intensity"]
        case .streams: ["streams", "sources", "badges", "Fusion", "size", "add-on logo", "background", "cinematic", "search bar", "pin"]
        case .posterCards: ["poster", "card", "width", "size", "corner", "radius", "landscape", "depth", "glow", "sheen", "edge", "custom poster", "poster source", "RPDB", "rating posters"]
        case .landscapeCards: ["landscape", "card", "size", "corners", "continue watching", "collections", "folder names", "wide"]
        case .continueWatching: ["continue watching", "resume", "style", "sort", "thumbnails", "finished"]
        case .detailPage: ["detail", "title page", "background", "episodes", "blur", "spoiler", "sections", "cast", "trailers"]
        case .about: ["resources", "TMDB", "TVDB", "libmpv", "Supabase", "licenses", "privacy"]
        case .metadataProvider: ["metadata provider", title, "API key", "key", "credential", "token"]
        case .tracking: ["tracking", "tracker", "scrobble", "scrobbling", "history", "watched", "Trakt", "Simkl", "MDBList", "PublicMetaDB", "PMDB", "AniList", "library source", "watch progress", "continue watching", "more like this", "comments", "sign in"]
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
