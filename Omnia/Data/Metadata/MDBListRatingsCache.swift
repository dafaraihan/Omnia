import Foundation

actor MDBListRatingsCache {
    typealias Loader = @Sendable () async throws -> MDBListTitleRatings?

    private struct Entry: Sendable {
        let value: MDBListTitleRatings?
        let expiresAt: Date
    }

    private struct InFlight: Sendable {
        let token: UUID
        let task: Task<MDBListTitleRatings?, Error>
    }

    private static let defaultLifetime: TimeInterval = 30 * 60

    private let clock: any ClockProviding
    private let lifetime: TimeInterval
    private var entries: [MDBListLookupRoute: Entry] = [:]
    private var inFlight: [MDBListLookupRoute: InFlight] = [:]

    init(
        clock: any ClockProviding = SystemDateClock(),
        lifetime: TimeInterval = MDBListRatingsCache.defaultLifetime
    ) {
        self.clock = clock
        self.lifetime = lifetime
    }

    func value(
        for route: MDBListLookupRoute,
        bypassCache: Bool = false,
        load: @escaping Loader
    ) async throws -> MDBListTitleRatings? {
        try Task.checkCancellation()

        if !bypassCache {
            if let entry = entries[route] {
                if entry.expiresAt > clock.now {
                    return entry.value
                }
                entries[route] = nil
            }
            if let existing = inFlight[route] {
                let value = try await existing.task.value
                try Task.checkCancellation()
                return value
            }
        }

        let token = UUID()
        let task = Task { try await load() }
        inFlight[route] = InFlight(token: token, task: task)

        do {
            let value = try await task.value
            try Task.checkCancellation()
            if inFlight[route]?.token == token {
                entries[route] = Entry(
                    value: value,
                    expiresAt: clock.now.addingTimeInterval(lifetime)
                )
                inFlight[route] = nil
            }
            return value
        } catch is CancellationError {
            removeInFlight(for: route, token: token)
            throw CancellationError()
        } catch {
            removeInFlight(for: route, token: token)
            throw error
        }
    }

    private func removeInFlight(for route: MDBListLookupRoute, token: UUID) {
        guard inFlight[route]?.token == token else { return }
        inFlight[route] = nil
    }
}
