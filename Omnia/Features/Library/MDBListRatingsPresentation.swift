import Foundation
import Observation

nonisolated struct MDBListRatingPresentationItem: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: MDBListRatingProviderID?
    let displayName: String
    let formattedValue: String
    let assetName: String?
    let accessibilityLabel: String
    let isAggregate: Bool
}

nonisolated struct MDBListRatingsPresentation: Equatable, Sendable {
    let items: [MDBListRatingPresentationItem]
    let discoveredProviderIDs: Set<MDBListRatingProviderID>
    let response: MDBListTitleRatings

    init(
        response: MDBListTitleRatings,
        preferences: MDBListRatingPreferences
    ) {
        self.response = response
        var firstRatingByProvider: [MDBListRatingProviderID: MDBListRating] = [:]
        for rating in response.ratings where firstRatingByProvider[rating.providerID] == nil {
            firstRatingByProvider[rating.providerID] = rating
        }

        discoveredProviderIDs = Set(firstRatingByProvider.keys)
        var resolvedItems = MDBListRatingProviderRegistry
            .sortedDescriptors(for: discoveredProviderIDs)
            .filter { preferences.isEnabled($0.id) }
            .compactMap { descriptor -> MDBListRatingPresentationItem? in
                guard let rating = firstRatingByProvider[descriptor.id],
                      let formattedValue = MDBListRatingProviderRegistry.formattedValue(
                        rating.value,
                        for: descriptor.id
                      ) else {
                    return nil
                }
                return MDBListRatingPresentationItem(
                    id: descriptor.id.rawValue,
                    providerID: descriptor.id,
                    displayName: descriptor.displayName,
                    formattedValue: formattedValue,
                    assetName: MDBListRatingProviderRegistry.assetName(
                        for: descriptor.id,
                        value: rating.value
                    ),
                    accessibilityLabel: "\(descriptor.displayName), \(formattedValue)",
                    isAggregate: false
                )
            }

        if let score = response.score,
           let formattedScore = MDBListRatingProviderRegistry.formattedAggregate(score) {
            resolvedItems.append(MDBListRatingPresentationItem(
                id: "mdblist",
                providerID: nil,
                displayName: "MDBList",
                formattedValue: formattedScore,
                assetName: MDBListRatingProviderRegistry.aggregateAssetName,
                accessibilityLabel: "MDBList, \(formattedScore)",
                isAggregate: true
            ))
        }
        items = resolvedItems
    }
}

nonisolated struct MDBListRatingSettingsRow: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: MDBListRatingProviderID?
    let displayName: String
    let assetName: String?
    let isEnabled: Bool?
    let detail: String?
}

nonisolated enum MDBListRatingSettingsModel {
    static func rows(
        preferences: MDBListRatingPreferences
    ) -> [MDBListRatingSettingsRow] {
        var rows = MDBListRatingProviderRegistry.settingsDescriptors(
            discovered: preferences.discoveredProviderIDs
        ).map { descriptor in
            MDBListRatingSettingsRow(
                id: descriptor.id.rawValue,
                providerID: descriptor.id,
                displayName: descriptor.displayName,
                assetName: descriptor.defaultAssetName,
                isEnabled: preferences.isEnabled(descriptor.id),
                detail: nil
            )
        }
        rows.append(MDBListRatingSettingsRow(
            id: "mdblist",
            providerID: nil,
            displayName: "MDBList Score",
            assetName: MDBListRatingProviderRegistry.aggregateAssetName,
            isEnabled: nil,
            detail: "Always shown"
        ))
        return rows
    }
}

nonisolated enum MDBListRatingsRecoveryAction: Equatable, Sendable {
    case retry
    case openSettings
}

nonisolated enum MDBListRatingsLoadState: Equatable, Sendable {
    case idle
    case loading
    case empty
    case loaded(MDBListRatingsPresentation)
    case failed(MDBListMetadataError, recovery: MDBListRatingsRecoveryAction?)

    /// The ratings to show under the providers switched on now, so turning
    /// one off or on in Settings applies at once, without a new request.
    func applying(_ preferences: MDBListRatingPreferences) -> Self {
        guard case let .loaded(presentation) = self else { return self }
        let current = MDBListRatingsPresentation(response: presentation.response, preferences: preferences)
        return current.items.isEmpty ? .empty : .loaded(current)
    }
}

@MainActor
@Observable
final class MDBListRatingsLoader {
    private(set) var state: MDBListRatingsLoadState = .idle

    private let service: any MDBListRatingServing
    private var requestTask: Task<Void, Never>?
    private var requestToken = UUID()
    private var titleID: String?

    func state(forItemID id: String) -> MDBListRatingsLoadState {
        titleID == id ? state : .loading
    }

    init(service: any MDBListRatingServing) {
        self.service = service
    }

    convenience init() {
        self.init(service: MDBListMetadataClient())
    }

    func load(
        for item: MediaItem,
        preferences: MDBListRatingPreferences
    ) async {
        await startRequest(
            for: item,
            preferences: preferences,
            bypassCache: false
        )
    }

    func retry(
        for item: MediaItem,
        preferences: MDBListRatingPreferences
    ) async {
        guard state != .loading else { return }
        await startRequest(
            for: item,
            preferences: preferences,
            bypassCache: true
        )
    }

    func reset() {
        cancel()
        titleID = nil
        state = .idle
    }

    func cancel() {
        requestToken = UUID()
        requestTask?.cancel()
        requestTask = nil
        if state == .loading {
            state = .idle
        }
    }

    private func startRequest(
        for item: MediaItem,
        preferences: MDBListRatingPreferences,
        bypassCache: Bool
    ) async {
        requestTask?.cancel()
        let token = UUID()
        requestToken = token
        // Identifier enrichment can change the route without changing the title.
        // Retain useful same-title ratings while its new route is requested.
        let keepsRatings: Bool
        if titleID == item.id, case .loaded = state { keepsRatings = true }
        else { keepsRatings = false }
        titleID = item.id
        if !keepsRatings { state = .loading }

        let task = Task { [weak self, service] in
            do {
                let response = try await service.titleRatings(
                    for: item,
                    bypassCache: bypassCache
                )
                guard let self, self.requestToken == token else { return }
                guard let response else {
                    if keepsRatings { return }
                    self.state = .empty
                    return
                }
                // Kept even when every provider is off, so switching one
                // back on shows it without another request.
                self.state = .loaded(MDBListRatingsPresentation(
                    response: response,
                    preferences: preferences
                ))
            } catch is CancellationError {
                // Explicit cancel/new requests change the token. A cancellation
                // still owned here (for example key revocation) must settle loading.
                guard let self, self.requestToken == token else { return }
                self.state = .empty
            } catch let error as MDBListMetadataError {
                guard let self, self.requestToken == token else { return }
                if !keepsRatings { self.apply(error) }
            } catch {
                guard let self, self.requestToken == token else { return }
                if !keepsRatings { self.state = .failed(.temporarilyUnavailable, recovery: .retry) }
            }
        }
        requestTask = task
        await task.value
        if requestToken == token {
            requestTask = nil
        }
    }

    private func apply(_ error: MDBListMetadataError) {
        switch error {
        case .noSupportedIdentifier, .notFound:
            state = .empty
        case .authenticationRequired:
            state = .failed(error, recovery: .openSettings)
        case .rateLimited:
            state = .failed(error, recovery: nil)
        case .temporarilyUnavailable, .malformedResponse, .responseTooLarge:
            state = .failed(error, recovery: .retry)
        }
    }
}
