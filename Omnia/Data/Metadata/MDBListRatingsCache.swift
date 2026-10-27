import Foundation

actor MDBListRatingsCache {
    typealias Loader = @Sendable () async throws -> MDBListTitleRatings?

    private struct Key: Hashable, Sendable {
        let route: MDBListLookupRoute
        let credentialScope: String
    }

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
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: InFlight] = [:]

    init(
        clock: any ClockProviding = SystemDateClock(),
        lifetime: TimeInterval = MDBListRatingsCache.defaultLifetime
    ) {
        self.clock = clock
        self.lifetime = lifetime
    }

    func value(
        for route: MDBListLookupRoute,
        credentialScope: String,
        bypassCache: Bool = false,
        load: @escaping Loader
    ) async throws -> MDBListTitleRatings? {
        try Task.checkCancellation()
        let key = Key(route: route, credentialScope: credentialScope)

        if !bypassCache {
            if let entry = entries[key] {
                if entry.expiresAt > clock.now {
                    return entry.value
                }
                entries[key] = nil
            }
            if let existing = inFlight[key] {
                let value = try await existing.task.value
                try Task.checkCancellation()
                return value
            }
        }

        let token = UUID()
        let task = Task { try await load() }
        inFlight[key] = InFlight(token: token, task: task)

        do {
            let value = try await task.value
            try Task.checkCancellation()
            if inFlight[key]?.token == token {
                entries[key] = Entry(
                    value: value,
                    expiresAt: clock.now.addingTimeInterval(lifetime)
                )
                inFlight[key] = nil
                // Speculative hero preparation must not grow retained ratings indefinitely.
                while entries.count > 120, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt }) {
                    entries[oldest.key] = nil
                }
            }
            return value
        } catch is CancellationError {
            removeInFlight(for: key, token: token)
            throw CancellationError()
        } catch {
            removeInFlight(for: key, token: token)
            throw error
        }
    }

    private func removeInFlight(for key: Key, token: UUID) {
        guard inFlight[key]?.token == token else { return }
        inFlight[key] = nil
    }
}
