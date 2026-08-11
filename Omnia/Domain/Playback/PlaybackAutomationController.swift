import Foundation

struct PlaybackAutomationController: Sendable {
    struct Policy: Equatable, Sendable {
        let showSkipIntro: Bool
        let autoSkipIntro: Bool
        let autoplayNextEpisode: Bool
        let upNextLeadSeconds: Double
    }

    enum Effect: Equatable, Sendable {
        case none
        case presentSkip(SkipSegment)
        case dismissSkip
        case seek(to: Double)
        case presentUpNext
        case resolveNextEpisode
        case stopAtEnd
    }

    let policy: Policy
    private var presentedSkipID: String?
    private var autoSkippedIDs: Set<String> = []
    private var presentedUpNext = false
    private var resolvedNextEpisode = false
    private var stopped = false

    init(policy: Policy) {
        self.policy = policy
    }

    mutating func update(
        position: Double,
        duration: Double?,
        segments: [SkipSegment],
        hasNextEpisode: Bool = false
    ) -> Effect {
        guard !stopped, position.isFinite, position >= 0 else { return .none }
        let intro = segments.first { segment in
            segment.kind == .intro
                && position >= segment.startSeconds
                && position < segment.endSeconds
        }

        if let intro {
            let identifier = segmentID(intro)
            if policy.autoSkipIntro, !autoSkippedIDs.contains(identifier) {
                autoSkippedIDs.insert(identifier)
                presentedSkipID = nil
                return .seek(to: intro.endSeconds)
            }
            if policy.showSkipIntro,
               !policy.autoSkipIntro,
               presentedSkipID != identifier {
                presentedSkipID = identifier
                return .presentSkip(intro)
            }
        } else if presentedSkipID != nil {
            presentedSkipID = nil
            return .dismissSkip
        }

        guard hasNextEpisode,
              !presentedUpNext,
              let duration,
              duration.isFinite,
              duration > 0,
              duration - position <= policy.upNextLeadSeconds,
              duration - position >= 0
        else { return .none }
        presentedUpNext = true
        return .presentUpNext
    }

    mutating func playbackEnded(hasNextEpisode: Bool) -> Effect {
        guard !stopped else { return .none }
        if policy.autoplayNextEpisode, hasNextEpisode, !resolvedNextEpisode {
            resolvedNextEpisode = true
            return .resolveNextEpisode
        }
        stopped = true
        return .stopAtEnd
    }

    mutating func cancel() -> Effect {
        stopped = true
        presentedSkipID = nil
        return .stopAtEnd
    }

    private func segmentID(_ segment: SkipSegment) -> String {
        "\(segment.kind.rawValue):\(segment.startSeconds):\(segment.endSeconds)"
    }
}
