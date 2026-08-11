import Foundation

protocol ClockProviding: Sendable {
    var now: Date { get }
}

struct SystemDateClock: ClockProviding {
    var now: Date { .now }
}

actor IntroSegmentCache {
    private struct Entry: Codable, Sendable {
        let segments: [SkipSegment]
        let expiresAt: Date
    }

    private static let positiveLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let negativeLifetime: TimeInterval = 24 * 60 * 60

    private let clock: any ClockProviding
    private var entries: [IntroSegmentKey: Entry] = [:]

    init(clock: any ClockProviding = SystemDateClock()) {
        self.clock = clock
    }

    func value(for key: IntroSegmentKey) -> [SkipSegment]? {
        guard let entry = entries[key], entry.expiresAt > clock.now else { return nil }
        return entry.segments
    }

    func store(_ segments: [SkipSegment], for key: IntroSegmentKey) {
        let lifetime = segments.isEmpty ? Self.negativeLifetime : Self.positiveLifetime
        entries[key] = Entry(segments: segments, expiresAt: clock.now.addingTimeInterval(lifetime))
    }

    func segments(
        for key: IntroSegmentKey,
        fetch: @Sendable () async throws -> [SkipSegment]
    ) async throws -> [SkipSegment] {
        if let fresh = value(for: key) { return fresh }
        do {
            let fetched = try await fetch()
            store(fetched, for: key)
            return fetched
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let stale = entries[key]?.segments { return stale }
            throw error
        }
    }
}
