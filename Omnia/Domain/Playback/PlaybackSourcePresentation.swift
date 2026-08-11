//
//  PlaybackSourcePresentation.swift
//  Omnia
//

struct PlaybackSourceSections: Equatable, Sendable {
    private let ordered: [AddonStreamCandidate]
    let direct: [AddonStreamCandidate]
    let resolverRequired: [AddonStreamCandidate]
    let external: [AddonStreamCandidate]
    let unavailable: [AddonStreamCandidate]

    init(candidates: [AddonStreamCandidate]) {
        ordered = candidates

        var direct: [AddonStreamCandidate] = []
        var resolverRequired: [AddonStreamCandidate] = []
        var external: [AddonStreamCandidate] = []
        var unavailable: [AddonStreamCandidate] = []

        for candidate in candidates {
            switch candidate.delivery {
            case .nativeHTTPS:
                direct.append(candidate)
            case .resolverRequired:
                resolverRequired.append(candidate)
            case .externalHandoff:
                external.append(candidate)
            case .unsupported:
                unavailable.append(candidate)
            }
        }

        self.direct = direct
        self.resolverRequired = resolverRequired
        self.external = external
        self.unavailable = unavailable
    }

    var all: [AddonStreamCandidate] {
        ordered
    }
}
