import Foundation

/// Settings › Layout › Streams, Nuvio's stream page options, plus Nuvio
/// Enhanced's search bar and pinned sources.
nonisolated struct StreamPagePreferences: Codable, Equatable, Sendable {
    enum BadgePlacement: String, Codable, CaseIterable, Identifiable, Sendable {
        case top, bottom
        var id: Self { self }
        var title: String {
            switch self {
            case .top: "Top"
            case .bottom: "Bottom"
            }
        }
    }

    enum Background: String, Codable, CaseIterable, Identifiable, Sendable {
        case cinematic, normal
        var id: Self { self }
        var title: String {
            switch self {
            case .cinematic: "Cinematic"
            case .normal: "Normal"
            }
        }
    }

    /// Nuvio's defaults: size badges on, badges below the name, no add-on
    /// logo. Omnia opens on the Cinematic backdrop, like Nuvio on desktop.
    var showSizeBadges = true
    var badgePlacement: BadgePlacement = .bottom
    var showAddonLogo = false
    var background: Background = .cinematic
    var showsSearchBar = false
    /// Add-on and plugin source ids whose streams always sort first.
    var pinnedSourceIDs: [String] = []

    static let `default` = Self()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showSizeBadges, badgePlacement, showAddonLogo, background, showsSearchBar, pinnedSourceIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        showSizeBadges = (try? container.decodeIfPresent(Bool.self, forKey: .showSizeBadges)) ?? fallback.showSizeBadges
        badgePlacement = (try? container.decodeIfPresent(BadgePlacement.self, forKey: .badgePlacement)) ?? fallback.badgePlacement
        showAddonLogo = (try? container.decodeIfPresent(Bool.self, forKey: .showAddonLogo)) ?? fallback.showAddonLogo
        background = (try? container.decodeIfPresent(Background.self, forKey: .background)) ?? fallback.background
        showsSearchBar = (try? container.decodeIfPresent(Bool.self, forKey: .showsSearchBar)) ?? fallback.showsSearchBar
        pinnedSourceIDs = (try? container.decodeIfPresent([String].self, forKey: .pinnedSourceIDs)) ?? []
    }

    func isPinned(_ sourceID: String) -> Bool {
        pinnedSourceIDs.contains(sourceID)
    }

    mutating func togglePin(_ sourceID: String) {
        if let index = pinnedSourceIDs.firstIndex(of: sourceID) {
            pinnedSourceIDs.remove(at: index)
        } else {
            pinnedSourceIDs.append(sourceID)
        }
    }
}
