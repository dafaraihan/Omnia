//
//  PlaybackRecovery.swift
//  Omnia
//
//  Nuvio's recovery from a source that stops playing, after its
//  tryRefreshCredentialedSourceAfterError (PlayerScreenRuntimeEffects.kt,
//  NuvioMedia/NuvioMobile, GPL-3.0), extended to try the next source.
//

import Foundation

/// The title and source list a playing stream was picked from.
struct PlaybackRecoveryContext {
    let item: MediaItem
    let progressItem: MediaItem
    let episode: MediaEpisode?
    let resumeAt: Double?
    let linkKey: MediaPlaybackKey
    /// The list the user or auto-play chose from, best first.
    let candidates: [AddonStreamCandidate]
    /// Stream addresses that failed, so none is tried twice.
    var failedURLs: Set<URL> = []
    /// Add-ons already asked again, so each is refreshed once.
    var refreshedAddonIDs: Set<String> = []
    var switches = 0

    static let maximumSwitches = 2
}

/// On a playback error (Dafa, 2026-10-26):
/// 1. note the failure in the Diagnostics log,
/// 2. ask the same add-on for its streams again and play the same release
///    (a debrid or proxy link often expires) from where it stopped,
/// 3. otherwise play the next source in the list, up to two times,
/// and only then leave the error on screen.
@MainActor
enum PlaybackRecovery {
    static func recover(
        from message: String,
        playback: PlaybackSession,
        store: OmniaStore,
        settings: SettingsPreferencesStore
    ) async {
        guard !playback.isRecoveringSource, var context = playback.recoveryContext,
              let linkKey = playback.currentLinkKey, linkKey == context.linkKey,
              let failed = playback.currentCandidate
        else {
            logUnrecoverable(message, playback: playback)
            return
        }
        let failedURL = playback.source?.url
        let logDate = PlaybackFailureLog.shared.record(
            item: context.item,
            episode: context.episode,
            candidate: failed,
            streamURL: failedURL,
            message: message
        )
        if let failedURL { context.failedURLs.insert(failedURL) }
        // Resume where it stopped; a stream that never started keeps the
        // position it was opened at.
        let resumeAt = playback.positionSeconds > 5 ? playback.positionSeconds : context.resumeAt

        playback.isRecoveringSource = true
        defer { playback.isRecoveringSource = false }

        // 1. The same release, fetched again from its add-on.
        if !context.refreshedAddonIDs.contains(failed.addonID),
           let addon = store.installedAddons.first(where: { $0.id == failed.addonID && $0.isEnabled }) {
            context.refreshedAddonIDs.insert(failed.addonID)
            let fresh = await PlaybackSourceResolver.resolve(
                addon: addon,
                mediaTypes: context.item.streamMediaTypes,
                identifiers: context.item.streamIdentifierCandidates(for: context.episode),
                timeout: settings.preferences.addonTimeout,
                transport: HTTPTransport()
            ).candidates
            guard stillFailing(playback, linkKey: linkKey) else { return }
            if let match = bestMatch(for: failed, in: fresh, excluding: context.failedURLs),
               let source = match.nativePlaybackSource {
                playback.recoveryContext = context
                PlaybackFailureLog.shared.setOutcome("Played a fresh link from \(match.addonName)", for: logDate)
                restart(source, candidate: match, context: context, resumeAt: resumeAt, playback: playback, store: store, settings: settings)
                return
            }
        }

        // 2. The next source in the list.
        guard context.switches < PlaybackRecoveryContext.maximumSwitches,
              let next = nextCandidate(after: failed, in: context),
              let source = next.nativePlaybackSource,
              stillFailing(playback, linkKey: linkKey)
        else {
            playback.recoveryContext = context
            PlaybackFailureLog.shared.setOutcome("No other source worked", for: logDate)
            return
        }
        context.switches += 1
        playback.recoveryContext = context
        PlaybackFailureLog.shared.setOutcome("Switched to \(next.addonName): \(next.displayName)", for: logDate)
        restart(source, candidate: next, context: context, resumeAt: resumeAt, playback: playback, store: store, settings: settings)
        showNotice("Switched to another source: \(next.addonName)", playback: playback)
    }

    /// A failure with no source list to recover from (Live TV, a media
    /// server, an Up Next pick) is still logged.
    private static func logUnrecoverable(_ message: String, playback: PlaybackSession) {
        guard !playback.isRecoveringSource, let item = playback.mediaItem else { return }
        let date = PlaybackFailureLog.shared.record(
            item: item,
            episode: playback.episode,
            candidate: playback.currentCandidate,
            streamURL: playback.source?.url,
            message: message
        )
        PlaybackFailureLog.shared.setOutcome("Not retried", for: date)
    }

    /// The user may have closed the player or picked another source while
    /// streams were being fetched.
    private static func stillFailing(_ playback: PlaybackSession, linkKey: MediaPlaybackKey) -> Bool {
        playback.isPresentingPlayer && playback.currentLinkKey == linkKey && playback.playbackError != nil
    }

    /// The same release from a fresh answer: same name, then same binge
    /// group, then same file name; a different address than the ones that
    /// failed.
    static func bestMatch(
        for failed: AddonStreamCandidate,
        in candidates: [AddonStreamCandidate],
        excluding failedURLs: Set<URL>
    ) -> AddonStreamCandidate? {
        let playable = candidates.filter { candidate in
            guard let url = candidate.nativePlaybackSource?.url else { return false }
            return !failedURLs.contains(url)
        }
        return playable.first { $0.displayName == failed.displayName && $0.displayDescription == failed.displayDescription }
            ?? playable.first { $0.displayName == failed.displayName }
            ?? playable.first { failed.bingeGroup != nil && $0.bingeGroup == failed.bingeGroup }
            ?? playable.first { failed.filename != nil && $0.filename == failed.filename }
    }

    /// The next playable source after the failed one, then from the top.
    static func nextCandidate(after failed: AddonStreamCandidate, in context: PlaybackRecoveryContext) -> AddonStreamCandidate? {
        let list = context.candidates
        let start = min((list.firstIndex { $0.id == failed.id } ?? -1) + 1, list.count)
        let ordered = Array(list[start...]) + Array(list[..<start])
        return ordered.first { candidate in
            guard candidate.id != failed.id, let url = candidate.nativePlaybackSource?.url else { return false }
            return !context.failedURLs.contains(url)
        }
    }

    private static func restart(
        _ source: PlaybackSource,
        candidate: AddonStreamCandidate,
        context: PlaybackRecoveryContext,
        resumeAt: Double?,
        playback: PlaybackSession,
        store: OmniaStore,
        settings: SettingsPreferencesStore
    ) {
        PlaybackLauncher.start(
            input: .stream(source),
            candidate: candidate,
            item: context.item,
            progressItem: context.progressItem,
            episode: context.episode,
            resumeAt: resumeAt,
            linkKey: context.linkKey,
            playback: playback,
            settings: settings,
            store: store
        )
    }

    private static func showNotice(_ text: String, playback: PlaybackSession) {
        playback.recoveryNotice = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if playback.recoveryNotice == text { playback.recoveryNotice = nil }
        }
    }
}
