import Observation
import SwiftUI

/// Every avatar the picker offers: the ones uploaded to Omnia's Supabase
/// first, then the illustrated sets. The uploaded list is kept between
/// launches, so the picker is full offline too.
@Observable
@MainActor
final class AvatarLibrary {
    static let shared = AvatarLibrary()

    private(set) var uploaded: [AvatarCatalog.Category] = []
    @ObservationIgnored private var lastRefresh: Date?
    private static let cacheKey = "avatar-catalog-cache-v1"

    var categories: [AvatarCatalog.Category] { uploaded + AvatarCatalog.illustrated }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let rows = try? JSONDecoder().decode([OmniaAccount.AvatarCatalogRow].self, from: data) {
            uploaded = Self.categories(from: rows)
        }
    }

    /// At most every ten minutes, like Nuvio's catalog refresh.
    func refresh(using account: OmniaAccount) async {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 600 { return }
        lastRefresh = .now
        guard let rows = try? await account.fetchAvatarCatalog() else { return }
        uploaded = Self.categories(from: rows)
        if let data = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private static func categories(from rows: [OmniaAccount.AvatarCatalogRow]) -> [AvatarCatalog.Category] {
        var order: [String] = []
        var grouped: [String: [AvatarCatalog.Avatar]] = [:]
        for row in rows.sorted(by: { ($0.category, $0.sortOrder) < ($1.category, $1.sortOrder) }) {
            let category = row.category.trimmingCharacters(in: .whitespaces).capitalized
            guard let avatar = AvatarCatalog.uploaded(path: row.storagePath, category: category, name: row.displayName)
            else { continue }
            if grouped[category] == nil { order.append(category) }
            grouped[category, default: []].append(avatar)
        }
        return order.map { AvatarCatalog.Category(title: $0, avatars: grouped[$0] ?? []) }
    }
}

/// Nuvio's avatar picker: round avatars in a grid, grouped by category.
struct AvatarPicker: View {
    @Environment(OmniaAccount.self) private var account
    @Binding var selection: String?
    var columns = 8
    var size: CGFloat = 60
    private let library = AvatarLibrary.shared

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            CustomAvatarLink(selection: $selection, size: size)
            ForEach(library.categories) { category in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(category.title)
                            .font(.headline)
                        Text("\(category.avatars.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(size), spacing: 12), count: columns),
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(category.avatars) { avatar in
                            AvatarChoice(avatar: avatar, size: size, isSelected: avatar.id == selection) {
                                withAnimation(.snappy(duration: 0.2)) { selection = avatar.id }
                            }
                        }
                    }
                }
            }
        }
        .task { await library.refresh(using: account) }
    }
}

/// Paste a link to any image, such as an Xperience avatar, to use it.
private struct CustomAvatarLink: View {
    @Binding var selection: String?
    let size: CGFloat
    @State private var link = ""
    @State private var problem: String?

    private var current: AvatarCatalog.Avatar? {
        guard let selection, selection.hasPrefix("url:") else { return nil }
        return AvatarCatalog.avatar(id: selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom")
                .font(.headline)
            HStack(spacing: 12) {
                if let current {
                    AvatarChoice(avatar: current, size: size, isSelected: true) {}
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Paste an Image Link", text: $link, prompt: Text("https://…/avatar.webp"))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            // Handled here, so Return doesn't also press the
                            // sheet's default button.
                            .onKeyPress(.return) {
                                use()
                                return .handled
                            }
                        Button("Use", action: use)
                            .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text(problem ?? "Any PNG, JPEG, WebP or GIF link works, including Xperience avatars.")
                        .font(.caption)
                        .foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                }
            }
        }
        .onChange(of: link) { problem = nil }
    }

    private func use() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.count > AvatarCatalog.customLinkLimit {
            problem = "That link is too long. Links up to \(AvatarCatalog.customLinkLimit) characters work."
        } else if let avatar = AvatarCatalog.custom(link: text) {
            withAnimation(.snappy(duration: 0.2)) { selection = avatar.id }
            link = ""
        } else {
            problem = "That doesn't look like a web link. It should start with https://."
        }
    }
}

private struct AvatarChoice: View {
    let avatar: AvatarCatalog.Avatar
    let size: CGFloat
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.displayPreferences) private var display
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            CachedArtworkImage(url: avatar.url, size: CGSize(width: size, height: size)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(.quaternary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(
                    isSelected ? AnyShapeStyle(display.accentColor) : AnyShapeStyle(.white.opacity(0.1)),
                    lineWidth: isSelected ? 3 : 1
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: size * 0.28, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, display.accentColor)
                        .background(Circle().fill(.background).padding(2))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isHovered && !isSelected ? 1.08 : 1)
            .animation(.snappy(duration: 0.18), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(avatar.name.isEmpty ? avatar.category : avatar.name)
        .accessibilityLabel(avatar.name.isEmpty ? "\(avatar.category) avatar" : "\(avatar.category) avatar \(avatar.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
