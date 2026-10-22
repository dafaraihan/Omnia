import Foundation
import SwiftUI

/// One person watching on this account, like Nuvio's profiles: their own
/// name, avatar, library, progress, settings, add-ons and plugins. The
/// first profile is the main one; the others start fresh and can each
/// choose to use the main profile's settings, add-ons or plugins.
nonisolated struct ViewerProfile: Codable, Identifiable, Hashable, Sendable {
    static let maximumCount = 5
    static let maximumNameLength = 24

    var id: UUID
    var name: String
    /// An `AvatarCatalog` id; nil shows the first letter on `colorHex`.
    var avatarID: String?
    /// Six-digit sRGB hex, without "#".
    var colorHex: String
    /// A four-digit PIN guards switching to this profile. The PIN itself
    /// lives in the Keychain, never here.
    var isLocked: Bool
    /// Settings, Home layout and collections come from the main profile.
    var usesMainSettings = false
    var usesMainAddons = false
    var usesMainPlugins = false
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, avatarID, colorHex, isLocked
        case usesMainSettings, usesMainAddons, usesMainPlugins
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        avatarID = try container.decodeIfPresent(String.self, forKey: .avatarID)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        usesMainSettings = try container.decodeIfPresent(Bool.self, forKey: .usesMainSettings) ?? false
        usesMainAddons = try container.decodeIfPresent(Bool.self, forKey: .usesMainAddons) ?? false
        usesMainPlugins = try container.decodeIfPresent(Bool.self, forKey: .usesMainPlugins) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        avatarID: String?,
        colorHex: String,
        isLocked: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = Self.cleanName(name)
        self.avatarID = avatarID
        self.colorHex = colorHex
        self.isLocked = isLocked
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    static func cleanName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
    }

    var initial: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }

    var avatar: AvatarCatalog.Avatar? {
        avatarID.flatMap(AvatarCatalog.avatar(id:))
    }

    var color: Color { Color(profileHex: colorHex) }

    /// Nuvio's profile colours.
    static let colors = [
        "1E88E5", "E53935", "43A047", "FB8C00",
        "8E24AA", "00ACC1", "F4511E", "3949AB",
        "C0CA33", "D81B60", "00897B", "5E35B1",
        "7CB342", "039BE5", "FFB300", "6D4C41",
    ]
}

/// Omnia's avatar library, grouped by category as in Nuvio's picker. Two
/// sources: illustrated characters from DiceBear's public domain (CC0) sets,
/// drawn by DiceBear's free image service from a name, and avatars uploaded
/// to Omnia's own Supabase (the `avatar_catalog` table and the public
/// `avatars` bucket), which appear without an app update.
nonisolated enum AvatarCatalog {
    struct Avatar: Identifiable, Hashable, Sendable {
        /// What a profile stores: "style:seed" for an illustrated avatar,
        /// "omnia:path" for an uploaded one, "url:link" for one pasted in.
        let id: String
        let category: String
        let name: String
        let url: URL
    }

    /// One row of the picker.
    struct Category: Identifiable, Hashable, Sendable {
        let title: String
        let avatars: [Avatar]
        var id: String { title }
    }

    enum Style: String, CaseIterable, Identifiable, Sendable {
        case notionists
        case lorelei
        case openPeeps = "open-peeps"
        case pixelArt = "pixel-art"
        case thumbs
        case shapes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notionists: "Sketch"
            case .lorelei: "Portrait"
            case .openPeeps: "Peeps"
            case .pixelArt: "Pixel"
            case .thumbs: "Buddies"
            case .shapes: "Abstract"
            }
        }

        /// Soft backgrounds that suit each set, in Omnia's violet-to-teal.
        var backgrounds: [String] {
            switch self {
            case .shapes, .thumbs: ["705cff", "33c9cf", "1e88e5", "8e24aa", "00897b"]
            default: ["c9c2ff", "b8eef0", "ffd6e0", "ffe7b8", "d4f5c9", "d9e4ff"]
            }
        }

        func url(seed: String) -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.dicebear.com"
            components.path = "/9.x/\(rawValue)/png"
            components.queryItems = [
                URLQueryItem(name: "seed", value: seed),
                URLQueryItem(name: "size", value: "256"),
                URLQueryItem(name: "backgroundColor", value: backgrounds.joined(separator: ",")),
                URLQueryItem(name: "backgroundType", value: "gradientLinear"),
            ]
            return components.url!
        }
    }

    /// Names that make friendly, varied faces; each set draws them its way.
    static let seeds = [
        "Aria", "Atlas", "Bento", "Cleo", "Dune", "Echo", "Fable", "Gizmo",
        "Halo", "Indie", "Juno", "Kiwi", "Luna", "Milo", "Nova", "Orion",
        "Pixel", "Quill", "Rio", "Sage", "Tango", "Umi", "Vega", "Willow",
        "Xeno", "Yuki", "Zephyr", "Mochi", "Ember", "Comet", "Lumen", "Saffron",
    ]

    static let illustrated: [Category] = Style.allCases.map { style in
        Category(title: style.title, avatars: seeds.map { illustrated(style, seed: $0) })
    }

    static let all: [Avatar] = illustrated.flatMap(\.avatars)

    private static func illustrated(_ style: Style, seed: String) -> Avatar {
        Avatar(id: "\(style.rawValue):\(seed)", category: style.title, name: seed, url: style.url(seed: seed))
    }

    /// Public files in Omnia's `avatars` bucket.
    static let uploadedBaseURL: URL? = SupabaseConfiguration.load()?.projectURL
        .appending(path: "storage/v1/object/public/avatars", directoryHint: .isDirectory)

    static func uploaded(path: String, category: String, name: String) -> Avatar? {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty, clean.count <= 200, !clean.contains(".."),
              let url = uploadedBaseURL?.appending(path: clean, directoryHint: .notDirectory)
        else { return nil }
        return Avatar(id: "omnia:\(clean)", category: category, name: name, url: url)
    }

    /// Fits the account's `avatar_id` column (220 characters) with "url:".
    static let customLinkLimit = 216

    /// Any image link (PNG, JPEG, WebP, GIF, HEIC), such as Xperience's
    /// avatars. Plain http is fetched over https, like other artwork.
    static func custom(link: String) -> Avatar? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= customLinkLimit,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return Avatar(id: "url:\(url.absoluteString)", category: "Custom", name: name == "/" ? "" : name, url: url)
    }

    static func avatar(id: String) -> Avatar? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        if parts[0] == "omnia" {
            return uploaded(path: parts[1], category: "Omnia", name: "")
        }
        if parts[0] == "url" {
            return custom(link: parts[1])
        }
        guard let style = Style(rawValue: parts[0]), parts[1].count <= 40 else { return nil }
        return illustrated(style, seed: parts[1])
    }

    static func random() -> Avatar {
        all.randomElement() ?? illustrated(.notionists, seed: "Nova")
    }
}

extension Color {
    /// A six-digit hex colour; Omnia's violet when it can't be read.
    nonisolated init(profileHex hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x705CFF
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
