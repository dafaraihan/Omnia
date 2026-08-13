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
            case .localTorrent:
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

struct PlaybackSourceRowState: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case playDirect
        case prepareDisc
        case resolve
        case unavailable(String)
    }

    let action: Action
    let allowsExplicitDiscPreparation: Bool

    var isEligibleForAutoplay: Bool {
        action == .playDirect
    }

    var idleStatus: String? {
        action == .prepareDisc
            ? "Prepare Blu-ray Disc · Downloads to local resolver cache"
            : nil
    }

    func isPrimaryActionDisabled(isLocalPreparationActive: Bool) -> Bool {
        action == .prepareDisc && isLocalPreparationActive
    }

    init(candidate: AddonStreamCandidate) {
        switch candidate.delivery {
        case .nativeHTTPS:
            action = candidate.hasDiscImageHint ? .prepareDisc : .playDirect
            allowsExplicitDiscPreparation = candidate.hasExtensionlessHTTPSURL
        case .localTorrent:
            action = .resolve
            allowsExplicitDiscPreparation = false
        case .externalHandoff:
            action = .unavailable("External page—not locally resolved")
            allowsExplicitDiscPreparation = false
        case .unsupported:
            action = .unavailable("Malformed or unsupported source")
            allowsExplicitDiscPreparation = false
        }
    }
}

nonisolated enum DiscPreparationFailure: Equatable, Sendable {
    case unsupportedDisc
    case encryptedDisc
    case storageFull
    case busy
    case unsafeSource
    case network
}

nonisolated enum DiscPreparationState: Equatable, Sendable {
    case detecting
    case materializing(completedBytes: Int64, totalBytes: Int64)
    case ready
    case failed(DiscPreparationFailure)
}

nonisolated struct DiscPreparationPresentation: Equatable, Sendable {
    let status: String

    init(state: DiscPreparationState) {
        switch state {
        case .detecting:
            status = "Checking disc size…"
        case let .materializing(completedBytes, totalBytes):
            let percent: Int
            if totalBytes > 0 {
                percent = min(max(Int(Double(completedBytes) / Double(totalBytes) * 100), 0), 100)
            } else {
                percent = 0
            }
            status = "Preparing disc locally… \(percent)%"
        case .ready:
            status = "Disc ready to play"
        case let .failed(failure):
            switch failure {
            case .unsupportedDisc:
                status = "This is not a supported unencrypted Blu-ray"
            case .encryptedDisc:
                status = "Encrypted disc media is not supported"
            case .storageFull:
                status = "Not enough resolver cache space"
            case .busy:
                status = "Another local source is already being prepared"
            case .unsafeSource:
                status = "The add-on returned an unsafe disc source"
            case .network:
                status = "The disc source could not be downloaded"
            }
        }
    }
}
