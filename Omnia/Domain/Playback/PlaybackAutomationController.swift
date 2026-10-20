import Foundation

/// Skip prompts, automatic skipping and the Up Next trigger during playback,
/// following Nuvio's player rules.
struct PlaybackAutomationController: Sendable {
    struct Policy: Equatable, Sendable {
        /// Nuvio's Skip Intro master switch: off hides every skip prompt.
        let skipEnabled: Bool
        let autoSkipKinds: Set<SkipSegment.Kind>
        let thresholdMode: NextEpisodeThresholdMode
        let thresholdPercent: Double
        let thresholdMinutes: Double
        /// Seconds ahead of the Up Next trigger to fetch the next episode's
        /// sources, or nil when preloading is off.
        let preloadLeadSeconds: Double?
    }

    enum Effect: Equatable, Sendable {
        case presentSkip(SkipSegment)
        case dismissSkip
        case autoSkip(SkipSegment, to: Double)
        case presentUpNext
        case preloadNextEpisode
    }

    /// Nuvio treats shorter durations as placeholders while a stream opens.
    static let minimumRealDuration = 121.0

    let policy: Policy
    private var presentedSkipID: String?
    /// Holds back the Skip button until the seek of an auto-skip lands.
    private var autoSkippedID: String?
    private var handledSkipIDs: Set<String> = []
    private var lastPosition: Double?
    private var presentedUpNext = false
    private var requestedPreload = false

    init(policy: Policy) {
        self.policy = policy
    }

    mutating func update(
        position: Double,
        duration: Double?,
        segments: [SkipSegment],
        hasNextEpisode: Bool,
        isPlaying: Bool
    ) -> [Effect] {
        guard position.isFinite, position >= 0 else { return [] }
        var effects: [Effect] = []
        let skippable = segments.filter { $0.kind != .postCredits }

        // Segments already behind a resume point, or jumped into with a seek,
        // are never skipped automatically.
        if lastPosition == nil || abs(position - (lastPosition ?? position)) > 3 {
            let isFirstUpdate = lastPosition == nil
            for segment in skippable {
                let id = Self.id(segment)
                if position >= segment.endSeconds && isFirstUpdate {
                    handledSkipIDs.insert(id)
                } else if position > segment.startSeconds + 1 && position < segment.endSeconds {
                    handledSkipIDs.insert(id)
                }
            }
        }
        lastPosition = position

        if policy.skipEnabled,
           let active = skippable.first(where: { position >= $0.startSeconds && position < $0.endSeconds }) {
            let id = Self.id(active)
            if policy.autoSkipKinds.contains(active.kind), isPlaying, !handledSkipIDs.contains(id) {
                handledSkipIDs.insert(id)
                presentedSkipID = nil
                autoSkippedID = id
                var target = Self.skipTarget(for: active, in: segments)
                if let duration, duration.isFinite, duration > 1 { target = min(target, duration - 1) }
                effects.append(.autoSkip(active, to: target))
            } else if presentedSkipID != id, autoSkippedID != id {
                presentedSkipID = id
                effects.append(.presentSkip(active))
            }
        } else {
            // The seek after an auto-skip has landed.
            autoSkippedID = nil
            if presentedSkipID != nil {
                presentedSkipID = nil
                effects.append(.dismissSkip)
            }
        }

        guard hasNextEpisode,
              let duration,
              duration.isFinite,
              duration > Self.minimumRealDuration
        else { return effects }

        let trigger = Self.nextEpisodeTriggerTime(
            duration: duration,
            segments: segments,
            mode: policy.thresholdMode,
            percent: policy.thresholdPercent,
            minutes: policy.thresholdMinutes
        )
        if !presentedUpNext, let trigger, position >= trigger {
            presentedUpNext = true
            effects.append(.presentUpNext)
        }
        if let lead = policy.preloadLeadSeconds, !requestedPreload, !presentedUpNext {
            let remaining = duration - position
            if remaining <= lead || (trigger.map { position + lead >= $0 } ?? false) {
                requestedPreload = true
                effects.append(.preloadNextEpisode)
            }
        }
        return effects
    }

    /// The end of playback always offers the next episode.
    mutating func playbackEnded(hasNextEpisode: Bool) -> Effect? {
        guard hasNextEpisode, !presentedUpNext else { return nil }
        presentedUpNext = true
        return .presentUpNext
    }

    /// Where a skip lands: the start of a following post-credits scene, so it
    /// isn't missed, otherwise the end of the segment.
    static func skipTarget(for segment: SkipSegment, in segments: [SkipSegment]) -> Double {
        if segment.kind.isEnding,
           let scene = segments
            .filter({ $0.kind == .postCredits && $0.startSeconds >= segment.endSeconds - 1 })
            .min(by: { $0.startSeconds < $1.startSeconds }) {
            return scene.startSeconds
        }
        return segment.endSeconds
    }

    /// When Up Next appears, from Nuvio's shouldShowNextEpisodeCard. The
    /// threshold is a fallback: an outro timestamp moves the card to the
    /// credits, and a post-credits scene holds it until the scene ends.
    /// Returns nil when only the end of playback should show it.
    static func nextEpisodeTriggerTime(
        duration: Double,
        segments: [SkipSegment],
        mode: NextEpisodeThresholdMode,
        percent: Double,
        minutes: Double
    ) -> Double? {
        let userTrigger: Double = switch mode {
        case .percentage: (duration * min(max(percent, 97), 100) / 100).rounded(.up)
        case .minutesBeforeEnd: duration - min(max(minutes, 0), 3.5) * 60
        }
        let endings = segments.filter { $0.kind.isEnding }
        guard let latestEnding = endings.max(by: { $0.startSeconds < $1.startSeconds }) else {
            return userTrigger
        }
        if let scene = segments
            .filter({ $0.kind == .postCredits && $0.startSeconds >= latestEnding.endSeconds - 1 })
            .min(by: { $0.startSeconds < $1.startSeconds }) {
            return max(scene.endSeconds, userTrigger)
        }
        let afterOutro = duration - latestEnding.endSeconds
        if afterOutro > 5 {
            // Something plays after the credits without a timestamp; only the
            // user's threshold can tell whether it is worth staying for.
            return afterOutro < duration - userTrigger ? nil : userTrigger
        }
        return endings.map(\.startSeconds).min()
    }

    private static func id(_ segment: SkipSegment) -> String {
        "\(segment.kind.rawValue):\(segment.startSeconds):\(segment.endSeconds)"
    }
}
