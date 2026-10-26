import Foundation
import SwiftUI

struct AboutResourceLink: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case official
        case attribution
        case terms
        case privacy
        case license
    }

    let kind: Kind
    let title: String
    let url: URL

    var id: String { "\(kind.rawValue):\(url.absoluteString)" }
}

struct AboutResource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let purpose: String
    let sections: Set<AboutSection>
    let attribution: String?
    let links: [AboutResourceLink]
}

enum AboutCatalog {
    static let resources: [AboutResource] = [
        resource(
            id: "tmdb",
            name: "TMDB",
            purpose: "Movie and series discovery, details, people, and artwork.",
            sections: [.metadataAndDiscovery, .attributions, .privacy],
            attribution: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
            links: [
                link(.attribution, "TMDB API Attribution", "https://developer.themoviedb.org/docs/faq"),
                link(.privacy, "TMDB Privacy Policy", "https://www.themoviedb.org/privacy-policy")
            ]
        ),
        resource(
            id: "tvdb",
            name: "TheTVDB",
            purpose: "Series, season, episode, and artwork metadata.",
            sections: [.metadataAndDiscovery, .attributions, .privacy],
            attribution: "Omnia uses metadata provided by TheTVDB.",
            links: [
                link(.official, "TheTVDB", "https://thetvdb.com"),
                link(.privacy, "TheTVDB Privacy Policy", "https://thetvdb.com/privacy-policy")
            ]
        ),
        resource(
            id: "mdblist",
            name: "MDBList",
            purpose: "Supplies the aggregate and external-source ratings shown on title details using the user's own API key.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [
                link(.official, "MDBList", "https://mdblist.com"),
                link(.terms, "MDBList API Documentation", "https://docs.mdblist.com/docs/api")
            ]
        ),
        resource(
            id: "rating-imdb",
            name: "IMDb Ratings",
            purpose: "IMDb rating values displayed from MDBList title responses; Omnia does not call IMDb for these ratings.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [link(.official, "IMDb", "https://www.imdb.com")]
        ),
        resource(
            id: "rating-rotten-tomatoes",
            name: "Rotten Tomatoes Ratings",
            purpose: "Tomatometer and audience values displayed from MDBList title responses; Omnia does not call Rotten Tomatoes directly.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [
                link(.official, "Rotten Tomatoes", "https://www.rottentomatoes.com"),
                link(.terms, "Rotten Tomatoes Licensing", "https://www.rottentomatoes.com/help_desk/licensing")
            ]
        ),
        resource(
            id: "rating-metacritic",
            name: "Metacritic Ratings",
            purpose: "Metacritic values displayed from MDBList title responses; Omnia does not call Metacritic directly.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [link(.official, "Metacritic", "https://www.metacritic.com")]
        ),
        resource(
            id: "rating-trakt",
            name: "Trakt Ratings",
            purpose: "Trakt values displayed from MDBList title responses; Omnia does not call Trakt directly.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [link(.official, "Trakt", "https://trakt.tv")]
        ),
        resource(
            id: "rating-letterboxd",
            name: "Letterboxd Ratings",
            purpose: "Letterboxd values displayed from MDBList title responses; Omnia does not call Letterboxd directly.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [link(.official, "Letterboxd", "https://letterboxd.com")]
        ),
        resource(
            id: "rating-myanimelist",
            name: "MyAnimeList Ratings",
            purpose: "MyAnimeList values displayed from MDBList title responses; Omnia does not call MyAnimeList directly.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [link(.official, "MyAnimeList", "https://myanimelist.net")]
        ),
        resource(
            id: "rating-roger-ebert",
            name: "Roger Ebert Ratings",
            purpose: "Roger Ebert values displayed from MDBList title responses; Omnia does not call RogerEbert.com directly.",
            sections: [.metadataAndDiscovery, .attributions],
            links: [link(.official, "RogerEbert.com", "https://www.rogerebert.com")]
        ),
        resource(
            id: "anilist",
            name: "AniList",
            purpose: "Anime discovery and optional account metadata.",
            sections: [.metadataAndDiscovery, .privacy],
            links: [
                link(.official, "AniList", "https://anilist.co"),
                link(.terms, "AniList Terms", "https://anilist.co/terms")
            ]
        ),
        resource(
            id: "youtube",
            name: "YouTube",
            purpose: "External trailer playback handoff.",
            sections: [.metadataAndDiscovery, .privacy],
            links: [
                link(.official, "YouTube", "https://www.youtube.com"),
                link(.privacy, "Google Privacy Policy", "https://policies.google.com/privacy")
            ]
        ),
        resource(
            id: "introdb",
            name: "IntroDB",
            purpose: "Read-only intro timestamp lookup.",
            sections: [.playback, .attributions],
            attribution: "Intro timestamps are retrieved from IntroDB.",
            links: [link(.terms, "IntroDB Terms", "https://introdb.app/docs/terms")]
        ),
        resource(
            id: "aiostreams-brand",
            name: "AIOStreams",
            purpose: "AIOStreams' gradient icon, from its repository's branding folder, shown for AIOStreams add-ons that use the default logo.",
            sections: [.addonTechnology, .attributions],
            attribution: "AIOStreams and its logo belong to the AIOStreams project.",
            links: [
                link(.official, "AIOStreams", "https://github.com/Viren070/AIOStreams"),
                link(.license, "AGPL-3.0 License", "https://github.com/Viren070/AIOStreams/blob/main/LICENSE")
            ]
        ),
        resource(
            id: "jellyfin-brand",
            name: "Jellyfin",
            purpose: "The Jellyfin icon in Media Servers, from the jellyfin-ux repository.",
            sections: [.addonTechnology, .attributions],
            attribution: "Jellyfin icon © Jellyfin contributors, licensed CC BY-SA 4.0.",
            links: [
                link(.official, "Jellyfin", "https://jellyfin.org"),
                link(.license, "CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/")
            ]
        ),
        resource(
            id: "emby-brand",
            name: "Emby",
            purpose: "The Emby mark in Media Servers, identifying Emby servers.",
            sections: [.addonTechnology, .attributions],
            attribution: "Emby and its logo are trademarks of Emby LLC.",
            links: [link(.official, "Emby", "https://emby.media")]
        ),
        resource(
            id: "stremio-addons",
            name: "Stremio-Compatible Add-ons",
            purpose: "HTTPS manifest, catalog, metadata, and stream protocol subset.",
            sections: [.addonTechnology],
            links: [
                link(.official, "Stremio Add-on Guide", "https://stremio.github.io/stremio-addon-guide/")
            ]
        ),
        resource(
            id: "avplayer",
            name: "AVPlayer",
            purpose: "In-app iPhone and iPad playback.",
            sections: [.playback, .appleTechnologies],
            links: [
                link(.official, "AVPlayer Documentation", "https://developer.apple.com/documentation/avfoundation/avplayer")
            ]
        ),
        resource(
            id: "libmpv",
            name: "libmpv",
            purpose: "In-app Mac playback.",
            sections: [.playback, .openSourceSoftware, .licenses],
            links: [
                link(.official, "mpv", "https://mpv.io"),
                link(.license, "mpv Copyright and Licenses", "https://github.com/mpv-player/mpv/blob/master/Copyright")
            ]
        ),
        resource(
            id: "supabase",
            name: "Supabase",
            purpose: "Authentication, metadata function, and cloud data boundary.",
            sections: [.cloudAndAuthentication, .privacy],
            links: [
                link(.official, "Supabase", "https://supabase.com"),
                link(.privacy, "Supabase Privacy Policy", "https://supabase.com/privacy")
            ]
        ),
        resource(
            id: "sign-in-with-apple",
            name: "Sign in with Apple",
            purpose: "Native Apple account authentication.",
            sections: [.cloudAndAuthentication, .appleTechnologies, .privacy],
            links: [
                link(.official, "Sign in with Apple", "https://developer.apple.com/sign-in-with-apple/"),
                link(.privacy, "Apple Privacy Policy", "https://www.apple.com/legal/privacy/")
            ]
        ),
        resource(
            id: "google-auth",
            name: "Google OAuth",
            purpose: "Google account authentication through Supabase.",
            sections: [.cloudAndAuthentication, .privacy],
            links: [
                link(.official, "Google Identity", "https://developers.google.com/identity"),
                link(.privacy, "Google Privacy Policy", "https://policies.google.com/privacy")
            ]
        ),
        resource(
            id: "facebook-auth",
            name: "Facebook Login",
            purpose: "Facebook account authentication through Supabase.",
            sections: [.cloudAndAuthentication, .privacy],
            links: [
                link(.official, "Facebook Login", "https://developers.facebook.com/docs/facebook-login/"),
                link(.privacy, "Meta Privacy Policy", "https://www.facebook.com/privacy/policy/")
            ]
        ),
        appleTechnology(
            id: "swiftui",
            name: "SwiftUI",
            purpose: "Application and Settings interface.",
            url: "https://developer.apple.com/documentation/swiftui"
        ),
        appleTechnology(
            id: "foundation",
            name: "Foundation",
            purpose: "Networking, data, URLs, files, and core value types.",
            url: "https://developer.apple.com/documentation/foundation"
        ),
        appleTechnology(
            id: "observation",
            name: "Observation",
            purpose: "Observable application state.",
            url: "https://developer.apple.com/documentation/observation"
        ),
        appleTechnology(
            id: "swiftdata",
            name: "SwiftData",
            purpose: "Durable local media storage.",
            url: "https://developer.apple.com/documentation/swiftdata"
        ),
        appleTechnology(
            id: "avfoundation",
            name: "AVFoundation",
            purpose: "Audiovisual playback and media selection.",
            url: "https://developer.apple.com/documentation/avfoundation"
        ),
        appleTechnology(
            id: "avkit",
            name: "AVKit",
            purpose: "System audiovisual presentation support.",
            url: "https://developer.apple.com/documentation/avkit"
        ),
        appleTechnology(
            id: "authenticationservices",
            name: "AuthenticationServices",
            purpose: "Sign in with Apple authorization.",
            url: "https://developer.apple.com/documentation/authenticationservices"
        ),
        appleTechnology(
            id: "cryptokit",
            name: "CryptoKit",
            purpose: "OAuth nonce hashing.",
            url: "https://developer.apple.com/documentation/cryptokit"
        ),
        appleTechnology(
            id: "security",
            name: "Security",
            purpose: "Keychain storage for user secrets.",
            url: "https://developer.apple.com/documentation/security"
        ),
        appleTechnology(
            id: "uniformtypeidentifiers",
            name: "Uniform Type Identifiers",
            purpose: "JSON import and export types.",
            url: "https://developer.apple.com/documentation/uniformtypeidentifiers"
        ),
        appleTechnology(
            id: "uikit",
            name: "UIKit",
            purpose: "iPhone and iPad platform integration.",
            url: "https://developer.apple.com/documentation/uikit"
        ),
        appleTechnology(
            id: "appkit",
            name: "AppKit",
            purpose: "Mac window and platform integration.",
            url: "https://developer.apple.com/documentation/appkit"
        ),
        resource(
            id: "supabase-swift",
            name: "Supabase Swift",
            purpose: "Swift client package for Supabase services.",
            sections: [.openSourceSoftware, .licenses],
            links: [
                link(.official, "Supabase Swift Repository", "https://github.com/supabase/supabase-swift"),
                link(.license, "Supabase Swift License", "https://github.com/supabase/supabase-swift/blob/main/LICENSE")
            ]
        ),
        resource(
            id: "native-playback-libraries",
            name: "Native Playback Libraries",
            purpose: "The pinned macOS playback closure: mpv, FFmpeg, libtorrent, Boost, libbluray/libudfread, libplacebo, libass, FreeType, FriBidi, HarfBuzz, OpenSSL, and audited build-only inputs.",
            sections: [.openSourceSoftware, .licenses],
            links: [
                link(.license, "mpv Dependency Licenses", "https://github.com/mpv-player/mpv/blob/master/Copyright")
            ]
        )
    ]

    static func items(for section: AboutSection) -> [AboutResource] {
        resources.filter { $0.sections.contains(section) }
    }

    private static func appleTechnology(
        id: String,
        name: String,
        purpose: String,
        url: String
    ) -> AboutResource {
        resource(
            id: id,
            name: name,
            purpose: purpose,
            sections: [.appleTechnologies],
            links: [link(.official, "\(name) Documentation", url)]
        )
    }

    private static func resource(
        id: String,
        name: String,
        purpose: String,
        sections: Set<AboutSection>,
        attribution: String? = nil,
        links: [AboutResourceLink]
    ) -> AboutResource {
        AboutResource(
            id: id,
            name: name,
            purpose: purpose,
            sections: sections,
            attribution: attribution,
            links: links
        )
    }

    private static func link(
        _ kind: AboutResourceLink.Kind,
        _ title: String,
        _ urlString: String
    ) -> AboutResourceLink {
        guard let url = URL(string: urlString), url.scheme == "https" else {
            preconditionFailure("Invalid About resource URL: \(urlString)")
        }
        return AboutResourceLink(kind: kind, title: title, url: url)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        OmniaSettingsForm {
            Section("Omnia") {
                LabeledContent("Version", value: bundleValue(for: "CFBundleShortVersionString"))
                LabeledContent("Build", value: bundleValue(for: "CFBundleVersion"))
                LabeledContent("Platforms", value: "iPhone, iPad, Mac")
            }

            Section("Resources and Technologies") {
                ForEach(AboutSection.allCases) { section in
                    NavigationLink {
                        SettingsDestinationView(route: .aboutSection(section))
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                    .settingsLinkRow()
                }
            }
        }
        .omniaNavigationTitle("About Omnia")
    }

    private func bundleValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return "—"
        }
        return value
    }
}

struct AboutSectionSettingsView: View {
    let section: AboutSection

    var body: some View {
        OmniaSettingsForm {
            if section == .licenses {
                Section("Bundled with Omnia") {
                    NavigationLink {
                        NativePlaybackNoticesView()
                    } label: {
                        Label("Native Playback Notices", systemImage: "doc.text")
                    }
                    .settingsLinkRow()

                    Text("Read the local SPDX inventory and exact license notices shipped with this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(AboutCatalog.items(for: section)) { resource in
                Section(resource.name) {
                    Text(resource.purpose)

                    if let attribution = resource.attribution {
                        LabeledContent("Attribution") {
                            Text(attribution)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    ForEach(resource.links) { link in
                        Link(destination: link.url) {
                            Label(link.title, systemImage: "arrow.up.right")
                        }
                    }
                }
            }
        }
        .omniaNavigationTitle(section.title)
    }
}
