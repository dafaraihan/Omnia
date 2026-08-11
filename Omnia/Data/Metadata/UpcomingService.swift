import Foundation

enum UpcomingServiceError: Error, Equatable {
    case metadataUnavailable
}

@MainActor
struct UpcomingService {
    typealias Resolver = @MainActor (MediaItem) async throws -> MediaItem

    private let now: () -> Date
    private let calendar: Calendar
    private let resolver: Resolver?

    init(
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current,
        resolver: Resolver? = nil
    ) {
        self.now = now
        self.calendar = calendar
        self.resolver = resolver
    }

    func load(
        savedItems: [MediaItem],
        lookAheadDays: Int,
        itemLimit: Int?
    ) async -> UpcomingResult {
        let loadedAt = now()
        let start = calendar.startOfDay(for: loadedAt)
        let boundedDays = min(max(lookAheadDays, 1), 365)
        let end = calendar.date(byAdding: .day, value: boundedDays, to: start) ?? start
        var values: [UpcomingEpisode] = []
        var failures: [String] = []

        for saved in savedItems where saved.kind == .series {
            let enriched: MediaItem
            if saved.details?.seasons.contains(where: { !$0.episodes.isEmpty }) == true {
                enriched = saved
            } else if let resolver {
                do {
                    enriched = try await resolver(saved)
                } catch {
                    failures.append(saved.id)
                    continue
                }
            } else {
                failures.append(saved.id)
                continue
            }

            guard let seasons = enriched.details?.seasons, !seasons.isEmpty else {
                failures.append(saved.id)
                continue
            }

            for episode in seasons.flatMap(\.episodes) {
                guard let airDateText = episode.airDate,
                      let airDate = parseAirDate(airDateText),
                      airDate >= start,
                      airDate <= end else { continue }
                values.append(UpcomingEpisode(series: enriched, episode: episode, airDate: airDate))
            }
        }

        var seen = Set<String>()
        let ordered = values
            .sorted {
                if $0.airDate != $1.airDate { return $0.airDate < $1.airDate }
                if $0.series.title != $1.series.title { return $0.series.title.localizedStandardCompare($1.series.title) == .orderedAscending }
                if $0.episode.seasonNumber != $1.episode.seasonNumber { return $0.episode.seasonNumber < $1.episode.seasonNumber }
                return $0.episode.episodeNumber < $1.episode.episodeNumber
            }
            .filter { seen.insert($0.id).inserted }
        let boundedLimit = itemLimit.map { min(max($0, 0), 500) }
        let items = boundedLimit.map { Array(ordered.prefix($0)) } ?? ordered

        return UpcomingResult(
            items: items,
            failures: failures.sorted(),
            isStale: !failures.isEmpty && !items.isEmpty,
            lastUpdated: loadedAt
        )
    }

    private func parseAirDate(_ value: String) -> Date? {
        if let instant = ISO8601DateFormatter().date(from: value) {
            return instant
        }
        let components = value.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        return calendar.startOfDay(for: date)
    }
}
