import Foundation

/// What automatic selection may pick for one source lookup.
nonisolated struct StreamAutoPlayRequest: Equatable, Sendable {
    var mode: AutoStreamSelectionMode
    var regexPattern: String?
    var scope: AutoStreamSelectionScope
    var allowedAddonIDs: Set<String>
    var allowedPluginIDs: Set<String>
    /// Played first when a stream carries this `behaviorHints.bingeGroup`.
    var preferredBingeGroup: String?
    /// Only a stream from `preferredBingeGroup` may play.
    var bingeGroupOnly: Bool
    /// Seconds to wait for add-ons. 0 is instant, `StreamSelectionTimeout.unlimited` waits for all.
    var timeoutSeconds: Int

    var waitsForTimeout: Bool {
        timeoutSeconds > 0
    }
}

/// Nuvio's StreamAutoPlaySelector: walks sources in add-on order and returns
/// the first one automatic selection may play.
enum StreamAutoPlaySelector {
    /// The best stream for the request, with a binge-group match first.
    static func select(
        from candidates: [AddonStreamCandidate],
        request: StreamAutoPlayRequest
    ) -> AddonStreamCandidate? {
        let playable = candidates.filter { isPlayable($0) && isInScope($0, request: request) }
        if let bingeMatch = bingeGroupMatch(in: playable, request: request) {
            return bingeMatch
        }
        guard !request.bingeGroupOnly else { return nil }
        switch request.mode {
        case .manual:
            return nil
        case .firstSource:
            return playable.first
        case .regexMatch:
            guard let pattern = request.regexPattern,
                  let regex = PlaybackBehaviorPreferences.compile(pattern)
            else { return nil }
            let exclusion = exclusionRegex(from: pattern)
            return playable.first { candidate in
                let text = searchableText(candidate)
                let range = NSRange(text.startIndex..., in: text)
                guard regex.firstMatch(in: text, range: range) != nil else { return false }
                if let exclusion, exclusion.firstMatch(in: text, range: range) != nil {
                    return false
                }
                return true
            }
        }
    }

    /// The first stream from the preferred binge group, if any.
    static func bingeGroupMatch(
        in candidates: [AddonStreamCandidate],
        request: StreamAutoPlayRequest
    ) -> AddonStreamCandidate? {
        guard let group = request.preferredBingeGroup?.trimmingCharacters(in: .whitespacesAndNewlines),
              !group.isEmpty
        else { return nil }
        return candidates.first { candidate in
            isPlayable(candidate)
                && isInScope(candidate, request: request)
                && candidate.bingeGroup == group
        }
    }

    /// Only direct streams play without the user; peer-to-peer and disc
    /// sources always need an explicit choice.
    static func isPlayable(_ candidate: AddonStreamCandidate) -> Bool {
        candidate.nativePlaybackSource != nil
            && PlaybackSourceRowState(candidate: candidate).isEligibleForAutoplay
    }

    static func isInScope(_ candidate: AddonStreamCandidate, request: StreamAutoPlayRequest) -> Bool {
        let isPlugin = PluginStreamResolver.isPluginSource(candidate.addonID)
        switch request.scope {
        case .allSources: break
        case .addonsOnly: if isPlugin { return false }
        case .pluginsOnly: if !isPlugin { return false }
        }
        if isPlugin {
            return request.allowedPluginIDs.isEmpty || request.allowedPluginIDs.contains(candidate.addonID)
        }
        return request.allowedAddonIDs.isEmpty || request.allowedAddonIDs.contains(candidate.addonID)
    }

    static func searchableText(_ candidate: AddonStreamCandidate) -> String {
        var parts = [candidate.addonName, candidate.displayName]
        if let description = candidate.displayDescription { parts.append(description) }
        if let filename = candidate.filename { parts.append(filename) }
        if case let .nativeHTTPS(url) = candidate.delivery { parts.append(url.absoluteString) }
        return parts.joined(separator: " ")
    }

    /// Words inside a negative lookahead such as `(?!.*(cam|ts))` are also
    /// rejected as whole words anywhere in the text, as Nuvio does, so a
    /// lookahead anchored to the start can't be slipped past.
    static func exclusionRegex(from pattern: String) -> NSRegularExpression? {
        guard let finder = try? NSRegularExpression(pattern: #"\(\?![^)]*?\(([^)]+)\)"#) else { return nil }
        let range = NSRange(pattern.startIndex..., in: pattern)
        let words = finder.matches(in: pattern, range: range).compactMap { match -> String? in
            guard let wordsRange = Range(match.range(at: 1), in: pattern) else { return nil }
            return String(pattern[wordsRange])
        }
        guard !words.isEmpty else { return nil }
        return try? NSRegularExpression(
            pattern: #"\b("# + words.joined(separator: "|") + #")\b"#,
            options: [.caseInsensitive]
        )
    }
}

/// Decides when automatic selection plays, following Nuvio's timeout rules:
/// - Instant or Unlimited: every update is checked and the first match plays.
/// - 1 to 30 seconds: before the timeout only a binge-group match plays; at
///   the timeout the best match so far plays; after it every update counts.
/// When every source has answered and nothing matched, the list shows.
struct StreamAutoPlayTracker {
    enum Outcome: Equatable {
        case wait
        case play(AddonStreamCandidate)
        case showList
    }

    let request: StreamAutoPlayRequest
    private(set) var timeoutElapsed: Bool
    private(set) var isSettled = false

    init(request: StreamAutoPlayRequest) {
        self.request = request
        timeoutElapsed = !request.waitsForTimeout
    }

    /// Called with everything found so far. `isComplete` once every source
    /// has answered.
    mutating func update(candidates: [AddonStreamCandidate], isComplete: Bool) -> Outcome {
        guard !isSettled else { return .wait }
        if !timeoutElapsed && !isComplete {
            if let match = StreamAutoPlaySelector.bingeGroupMatch(in: candidates, request: request) {
                return settle(.play(match))
            }
            return .wait
        }
        if let match = StreamAutoPlaySelector.select(from: candidates, request: request) {
            return settle(.play(match))
        }
        return isComplete ? settle(.showList) : .wait
    }

    /// Called once the timeout passes.
    mutating func timeoutFired(candidates: [AddonStreamCandidate], isComplete: Bool) -> Outcome {
        guard !isSettled else { return .wait }
        timeoutElapsed = true
        let outcome = update(candidates: candidates, isComplete: isComplete)
        // Unlimited only reaches here at its fallback, which always settles.
        if outcome == .wait, request.timeoutSeconds == StreamSelectionTimeout.unlimited {
            return settle(.showList)
        }
        return outcome
    }

    /// The user chose to pick a source themselves.
    mutating func cancel() {
        isSettled = true
    }

    private mutating func settle(_ outcome: Outcome) -> Outcome {
        isSettled = true
        return outcome
    }
}

/// One automatic selection while sources arrive: feeds the tracker, fires
/// the timeout, and reports once whether to play or show the list.
@MainActor
final class StreamAutoSelectionRun {
    /// Unlimited still settles after this long, as in Nuvio.
    static let unlimitedFallbackSeconds = 60

    private var tracker: StreamAutoPlayTracker
    private var candidates: [AddonStreamCandidate] = []
    private var isComplete = false
    private var timeoutTask: Task<Void, Never>?
    private let onOutcome: (StreamAutoPlayTracker.Outcome) -> Void

    var isSettled: Bool { tracker.isSettled }
    var request: StreamAutoPlayRequest { tracker.request }

    init(request: StreamAutoPlayRequest, onOutcome: @escaping (StreamAutoPlayTracker.Outcome) -> Void) {
        tracker = StreamAutoPlayTracker(request: request)
        self.onOutcome = onOutcome
        let seconds = request.timeoutSeconds == StreamSelectionTimeout.unlimited
            ? Self.unlimitedFallbackSeconds
            : request.timeoutSeconds
        guard seconds > 0 else { return }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.report(self.tracker.timeoutFired(candidates: self.candidates, isComplete: self.isComplete))
        }
    }

    /// Everything found so far; `isComplete` once every source has answered.
    func receive(_ candidates: [AddonStreamCandidate], isComplete: Bool) {
        self.candidates = candidates
        self.isComplete = isComplete
        report(tracker.update(candidates: candidates, isComplete: isComplete))
    }

    func cancel() {
        tracker.cancel()
        timeoutTask?.cancel()
    }

    private func report(_ outcome: StreamAutoPlayTracker.Outcome) {
        guard outcome != .wait else { return }
        timeoutTask?.cancel()
        onOutcome(outcome)
    }
}
