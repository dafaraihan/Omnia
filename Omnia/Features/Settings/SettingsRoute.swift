import Foundation

enum SettingsSection: Int, CaseIterable, Identifiable, Sendable {
    case account
    case media
    case playback
    case app
    case about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .media: "Media"
        case .playback: "Playback"
        case .app: "App"
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
    case addons
    case catalogs
    case metadata
    case progress
    case upcoming
    case videoPlayer
    case subtitle
    case playbackResolver
    case appearance
    case about
    case metadataProvider(String)
    case aboutSection(AboutSection)

    static let rootGroups: [SettingsRouteGroup] = [
        .init(section: .account, routes: [.account]),
        .init(section: .media, routes: [.addons, .catalogs, .metadata, .progress, .upcoming]),
        .init(section: .playback, routes: [.videoPlayer, .subtitle]),
        .init(section: .app, routes: [.appearance]),
        .init(section: .about, routes: [.about])
    ]

    static let allVerificationRoutes: [SettingsRoute] =
        rootGroups.flatMap(\.routes)
        + [.playbackResolver]
        + MetadataProvider.supported.map { .metadataProvider($0.id) }
        + AboutSection.allCases.map { .aboutSection($0) }

    static func filteredRootGroups(query: String) -> [SettingsRouteGroup] {
        rootGroups.compactMap { group in
            let routes = group.routes.filter { $0.matches(query) }
            return routes.isEmpty ? nil : .init(section: group.section, routes: routes)
        }
    }

    var title: String {
        switch self {
        case .account: "Account"
        case .addons: "Add-ons"
        case .catalogs: "Catalogs"
        case .metadata: "Metadata"
        case .progress: "Progress"
        case .upcoming: "Upcoming"
        case .videoPlayer: "Video Player"
        case .subtitle: "Subtitle"
        case .playbackResolver: "Playback Resolver"
        case .appearance: "Appearance"
        case .about: "About Omnia"
        case let .metadataProvider(id):
            MetadataProvider.supported.first { $0.id == id }?.name ?? "Metadata Provider"
        case let .aboutSection(section):
            section.title
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .addons: "puzzlepiece.extension"
        case .catalogs: "rectangle.stack"
        case .metadata, .metadataProvider: "rectangle.3.group"
        case .progress: "clock.arrow.circlepath"
        case .upcoming: "calendar"
        case .videoPlayer: "play.rectangle"
        case .subtitle: "captions.bubble"
        case .playbackResolver: "lock.shield"
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle"
        case let .aboutSection(section): section.systemImage
        }
    }

    var searchTerms: [String] {
        switch self {
        case .account: ["Apple", "Google", "Facebook", "sign in", "sign out"]
        case .addons: ["sources", "manifest", "timeout", "import", "export"]
        case .catalogs: ["catalog", "discover", "TMDB", "TVDB"]
        case .metadata: ["TMDB", "TVDB", "MDBList", "AniList", "providers", "fallback"]
        case .progress: ["local progress", "continue watching", "watchlist", "backup"]
        case .upcoming: ["episodes", "look ahead", "Home"]
        case .videoPlayer: ["skip intro", "up next", "audio", "source selection"]
        case .subtitle: ["subtitles", "captions", "SDH", "appearance"]
        case .playbackResolver: ["endpoint", "bearer token", "approved add-ons", "approved HTTPS hosts"]
        case .appearance: ["theme", "system", "light", "dark"]
        case .about: ["resources", "TMDB", "TVDB", "libmpv", "Supabase", "licenses", "privacy"]
        case .metadataProvider: ["metadata provider", title]
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
