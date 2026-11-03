import Foundation
import Observation

/// Nuvio's Fusion-style stream badges: up to three imported JSON rule lists,
/// one active at a time. Each enabled filter whose regex matches a stream's
/// name, description or filename adds its badge image to that stream's card.
nonisolated struct StreamBadgeImport: Codable, Equatable, Identifiable, Sendable {
    var sourceURL: String
    var filters: [StreamBadgeFilter]
    var groupCount: Int
    var isActive: Bool
    var importedAt: Date

    var id: String { sourceURL.lowercased() }
    var enabledFilterCount: Int { filters.filter(\.isEnabled).count }

    /// Only the host is shown: badge URLs can carry private tokens.
    var displayHost: String {
        URL(string: sourceURL)?.host() ?? "Badge list"
    }
}

nonisolated struct StreamBadgeFilter: Codable, Equatable, Sendable {
    var name: String
    var pattern: String
    var imageURL: String
    var isEnabled: Bool
    var tagColor: String
    var tagStyle: String
    var borderColor: String
}

nonisolated struct StreamBadge: Hashable, Sendable {
    let name: String
    let imageURL: URL?
    /// Filled tags draw their colour behind the image, as in Nuvio.
    let fillHex: String?
    let borderHex: String?
}

enum StreamBadgeImportError: LocalizedError {
    case invalidURL, limitReached, noFilters, unreadable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Badge URL must start with http:// or https://."
        case .limitReached: "You can import up to \(StreamBadgeStore.importLimit) badge URLs."
        case .noFilters: "Badge import did not contain any usable filters."
        case .unreadable: "Badge import failed."
        }
    }
}

@Observable
@MainActor
final class StreamBadgeStore {
    static let shared = StreamBadgeStore()
    nonisolated static let importLimit = 3

    private(set) var imports: [StreamBadgeImport] = []
    @ObservationIgnored private var compiled: [CompiledFilter] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let directory = URL.applicationSupportDirectory.appending(path: "Omnia", directoryHint: .isDirectory)
        self.fileURL = fileURL ?? directory.appending(path: "stream-badges.json")
        load()
    }

    var activeImport: StreamBadgeImport? {
        imports.first(where: \.isActive) ?? imports.first
    }

    // MARK: Matching

    func badges(for candidate: AddonStreamCandidate) -> [StreamBadge] {
        guard !compiled.isEmpty else { return [] }
        var fields = [
            candidate.filename,
            candidate.displayName,
            candidate.displayDescription,
            candidate.addonName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        if fields.count > 1 { fields.append(fields.joined(separator: " ")) }

        var seen = Set<String>()
        var result: [StreamBadge] = []
        for filter in compiled where fields.contains(where: { filter.matches($0) }) {
            let key = (filter.badge.imageURL?.absoluteString ?? filter.badge.name).lowercased()
            if seen.insert(key).inserted { result.append(filter.badge) }
        }
        return result
    }

    // MARK: Managing imports

    func importRules(from text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw StreamBadgeImportError.invalidURL
        }
        let isUpdate = imports.contains { $0.id == trimmed.lowercased() }
        guard isUpdate || imports.count < Self.importLimit else { throw StreamBadgeImportError.limitReached }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await OmniaNetwork.noStore.data(for: request),
              (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? false
        else { throw StreamBadgeImportError.unreadable }

        let parsed = try Self.parse(data)
        let entry = StreamBadgeImport(
            sourceURL: trimmed,
            filters: parsed.filters,
            groupCount: parsed.groupCount,
            isActive: true,
            importedAt: .now
        )
        var next = imports.filter { $0.id != entry.id }.map { existing in
            var existing = existing
            existing.isActive = false
            return existing
        }
        if let index = imports.firstIndex(where: { $0.id == entry.id }) {
            next.insert(entry, at: min(index, next.count))
        } else {
            next.append(entry)
        }
        replaceImports(with: next)
    }

    func activate(_ entry: StreamBadgeImport) {
        replaceImports(with: imports.map { existing in
            var existing = existing
            existing.isActive = existing.id == entry.id
            return existing
        })
    }

    func remove(_ entry: StreamBadgeImport) {
        var next = imports.filter { $0.id != entry.id }
        if !next.isEmpty, !next.contains(where: \.isActive) {
            next[0].isActive = true
        }
        replaceImports(with: next)
    }

    /// Stores the lists and recompiles the active list's rules.
    private func replaceImports(with next: [StreamBadgeImport]) {
        imports = next
        compiled = Self.compile(next)
        save()
    }

    // MARK: Parsing and storage

    private nonisolated struct Payload: Decodable {
        struct Filter: Decodable {
            let name: String?
            let pattern: String?
            let imageURL: String?
            let isEnabled: Bool?
            let tagColor: String?
            let tagStyle: String?
            let borderColor: String?
        }
        struct Group: Decodable {}

        let filters: [Filter]?
        let groups: [Group]?
    }

    nonisolated static func parse(_ data: Data) throws -> (filters: [StreamBadgeFilter], groupCount: Int) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw StreamBadgeImportError.unreadable
        }
        let filters: [StreamBadgeFilter] = (payload.filters ?? []).compactMap { filter in
            let name = filter.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pattern = filter.pattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, !pattern.isEmpty else { return nil }
            return StreamBadgeFilter(
                name: name,
                pattern: pattern,
                imageURL: filter.imageURL ?? "",
                isEnabled: filter.isEnabled ?? true,
                tagColor: filter.tagColor ?? "",
                tagStyle: filter.tagStyle ?? "",
                borderColor: filter.borderColor ?? ""
            )
        }
        guard !filters.isEmpty else { throw StreamBadgeImportError.noFilters }
        return (filters, payload.groups?.count ?? 0)
    }

    private struct CompiledFilter {
        let badge: StreamBadge
        let regex: NSRegularExpression

        func matches(_ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    private static func compile(_ imports: [StreamBadgeImport]) -> [CompiledFilter] {
        guard let active = imports.first(where: \.isActive) ?? imports.first else { return [] }
        return active.filters.compactMap { filter in
            guard filter.isEnabled,
                  let regex = try? NSRegularExpression(pattern: filter.pattern)
            else { return nil }
            let imageURL = URL(string: filter.imageURL).flatMap { url in
                ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? url : nil
            }
            return CompiledFilter(
                badge: StreamBadge(
                    name: filter.name,
                    imageURL: imageURL,
                    fillHex: filter.tagStyle.caseInsensitiveCompare("filled") == .orderedSame
                        ? filter.tagColor.nonEmptyHex : nil,
                    borderHex: filter.borderColor.nonEmptyHex
                ),
                regex: regex
            )
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([StreamBadgeImport].self, from: data)
        else { return }
        imports = stored
        compiled = Self.compile(stored)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(imports).write(to: fileURL, options: .atomic)
        } catch {
            // Badges are cosmetic; a failed write only loses the import.
        }
    }
}

private extension String {
    var nonEmptyHex: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
