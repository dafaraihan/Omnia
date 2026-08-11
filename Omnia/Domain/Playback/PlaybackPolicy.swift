import Foundation

enum PlaybackAdapter: Equatable, Sendable {
    case avPlayer
    case libmpv
}

enum PlaybackCompatibility: Equatable, Sendable {
    case supported
    case unknown
    case unsupported
}

struct MediaPlaybackKey: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}

struct RememberedSource: Codable, Equatable, Sendable {
    let mediaKey: MediaPlaybackKey
    let addonID: String
    let bingeGroup: String?
    let displayNameFingerprint: String
    let expiresAt: Date
}

enum PlaybackPolicyDecision: Equatable, Sendable {
    case play(AddonStreamCandidate)
    case requiresSelection([AddonStreamCandidate])
    case unavailable
}

enum PlaybackPolicy {
    static func compatibility(
        of candidate: AddonStreamCandidate,
        adapter: PlaybackAdapter
    ) -> PlaybackCompatibility {
        guard case let .nativeHTTPS(url) = candidate.delivery else {
            return .unsupported
        }
        switch url.pathExtension.lowercased() {
        case "m3u8", "mp4", "m4v", "mov":
            return .supported
        case "mkv", "webm":
            return adapter == .libmpv ? .supported : .unsupported
        default:
            return adapter == .libmpv ? .unknown : .unsupported
        }
    }

    static func isEligible(
        _ candidate: AddonStreamCandidate,
        adapter: PlaybackAdapter,
        compatibleOnly: Bool
    ) -> Bool {
        switch compatibility(of: candidate, adapter: adapter) {
        case .supported:
            true
        case .unknown:
            !compatibleOnly && adapter == .libmpv
        case .unsupported:
            false
        }
    }

    static func choose(
        from candidates: [AddonStreamCandidate],
        adapter: PlaybackAdapter,
        compatibleOnly: Bool,
        autoplayFirst: Bool,
        remembered: RememberedSource?,
        now: Date
    ) -> PlaybackPolicyDecision {
        let eligible = candidates.filter {
            isEligible($0, adapter: adapter, compatibleOnly: compatibleOnly)
        }
        guard !eligible.isEmpty else { return .unavailable }

        if let remembered,
           remembered.expiresAt > now,
           let match = eligible.first(where: { candidate in
               guard candidate.addonID == remembered.addonID else { return false }
               if let bingeGroup = remembered.bingeGroup {
                   return candidate.bingeGroup == bingeGroup
               }
               return candidate.displayNameFingerprint == remembered.displayNameFingerprint
           }) {
            return .play(match)
        }
        if autoplayFirst, let first = eligible.first {
            return .play(first)
        }
        return .requiresSelection(eligible)
    }
}

extension AddonStreamCandidate {
    init(
        id: String,
        addonID: String,
        addonName: String,
        streamIdentifier: String,
        displayName: String,
        displayDescription: String?,
        delivery: Delivery,
        filename: String?,
        videoSize: Int64?,
        bingeGroup: String?,
        hasPeerDiscoveryHints: Bool,
        requestHeaders: [String: String]
    ) {
        self.id = id
        self.addonID = addonID
        self.addonName = addonName
        self.streamIdentifier = streamIdentifier
        self.displayName = displayName
        self.displayDescription = displayDescription
        self.delivery = delivery
        self.filename = filename
        self.videoSize = videoSize
        self.bingeGroup = bingeGroup
        self.hasPeerDiscoveryHints = hasPeerDiscoveryHints
        self.requestHeaders = requestHeaders
    }

    var displayNameFingerprint: String {
        DisplayNameFingerprint.make(displayName)
    }

    var isOmniaPlaybackEligible: Bool {
        if case .externalHandoff = delivery { return false }
        if case .unsupported = delivery { return false }
        return true
    }
}

enum DisplayNameFingerprint {
    static func make(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
