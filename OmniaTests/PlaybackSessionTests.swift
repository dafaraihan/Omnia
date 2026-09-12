import XCTest
@testable import Omnia

final class PlaybackSessionTests: XCTestCase {
    func testTrackSelectionGateRejectsSupersededReply() {
        var gate = PlaybackTrackSelectionGate()
        gate.beginAudio(10)
        gate.beginAudio(11)

        XCTAssertFalse(gate.finishAudio(10))
        XCTAssertTrue(gate.finishAudio(11))
    }

    func testTrackSelectionGateTracksAudioAndSubtitleIndependently() {
        var gate = PlaybackTrackSelectionGate()
        gate.beginAudio(20)
        gate.beginSubtitle(21)

        XCTAssertTrue(gate.finishSubtitle(21))
        XCTAssertTrue(gate.finishAudio(20))
    }

    func testTimelinePreviewResultMatchesOnlyItsSource() {
        XCTAssertTrue(PlaybackTimelinePreviewResultKey(sourceID: "a").matches(sourceID: "a"))
        XCTAssertFalse(PlaybackTimelinePreviewResultKey(sourceID: "a").matches(sourceID: "b"))
    }

    @MainActor
    func testTimelinePreviewSchedulerPublishesOnlyLatestRequestAfterDebounce() async {
        let sleeper = TimelinePreviewSleeperStub()
        let scheduler = PlaybackTimelinePreviewRequestScheduler { duration in
            try await sleeper.sleep(for: duration)
        }
        var published: [Int] = []

        scheduler.schedule(after: .milliseconds(250)) { published.append(1) }
        await sleeper.waitForRequestCount(1)
        scheduler.schedule(after: .milliseconds(250)) { published.append(2) }
        await sleeper.waitForRequestCount(2)
        await sleeper.releaseAll()
        await Task.yield()

        let durations = await sleeper.requestedDurations
        XCTAssertEqual(published, [2])
        XCTAssertEqual(durations, [.milliseconds(250), .milliseconds(250)])
    }

    @MainActor
    func testExplicitEpisodeSelectionSupersedesPendingNextEpisodeLookup() {
        let playback = PlaybackSession()
        let oldNextEpisode = playback.beginSourceSelection()
        let explicitEpisode = playback.beginSourceSelection()

        // A late dismissal/completion from Up Next must not cancel or claim
        // the request created by the explicit episode click.
        playback.cancelSourceSelection(oldNextEpisode)
        XCTAssertFalse(playback.claimSourceSelection(oldNextEpisode))
        XCTAssertTrue(playback.isCurrentSourceSelection(explicitEpisode))
        XCTAssertTrue(playback.claimSourceSelection(explicitEpisode))
        XCTAssertFalse(playback.claimSourceSelection(explicitEpisode))
    }

    @MainActor
    func testClosingPickerOrStoppingPlayerPreventsDelayedPlaybackStart() {
        let playback = PlaybackSession()
        let cancelled = playback.beginSourceSelection()
        playback.cancelSourceSelection(cancelled)
        XCTAssertFalse(playback.claimSourceSelection(cancelled))

        let pending = playback.beginSourceSelection()
        playback.stop(persisting: false)
        XCTAssertFalse(playback.claimSourceSelection(pending))
    }

    func testAspectRatioModeCyclesOriginalFillAndBackToOriginal() {
        XCTAssertEqual(PlaybackAspectRatioMode.allCases, [.original, .fill])
        XCTAssertEqual(PlaybackAspectRatioMode.original.next, .fill)
        XCTAssertEqual(PlaybackAspectRatioMode.fill.next, .original)
    }

    func testAspectRatioModesPreserveGeometryAndOnlyFillUsesPanScan() {
        XCTAssertTrue(PlaybackAspectRatioMode.original.preservesAspectRatio)
        XCTAssertEqual(PlaybackAspectRatioMode.original.panScan, 0)
        XCTAssertTrue(PlaybackAspectRatioMode.fill.preservesAspectRatio)
        XCTAssertEqual(PlaybackAspectRatioMode.fill.panScan, 1)
    }

    @MainActor
    func testStoppingPlaybackResetsAspectRatioForTheNextTitle() {
        let playback = PlaybackSession()
        playback.cycleAspectRatio()
        XCTAssertEqual(playback.aspectRatioMode, .fill)

        playback.stop(persisting: false)

        XCTAssertEqual(playback.aspectRatioMode, .original)
    }

    @MainActor
    func testMacFullScreenNotificationsTrackExclusiveModeWithoutDismissingPlayer() {
        let playback = PlaybackSession()
        playback.isPresentingPlayer = true

        playback.handleFullScreenEnter()
        XCTAssertTrue(playback.isFullScreenActive)

        playback.handleFullScreenExit()

        XCTAssertFalse(playback.isFullScreenActive)
        XCTAssertTrue(playback.isPresentingPlayer)
    }

    @MainActor
    func testSubtitleStyleClampsLiveMpvValues() {
        let style = PlaybackSubtitleStyle(
            fontName: "Avenir Next",
            fontSize: 200,
            scale: 0.1,
            position: 180,
            shadowOpacity: 5,
            shadowBlurRadius: -2,
            background: .translucent
        ).normalized

        XCTAssertEqual(style.fontName, "Avenir Next")
        XCTAssertEqual(style.fontSize, 72)
        XCTAssertEqual(style.scale, 0.5)
        XCTAssertEqual(style.position, 100)
        XCTAssertEqual(style.shadowOpacity, 1)
        XCTAssertEqual(style.shadowBlurRadius, 0)
        XCTAssertEqual(style.background, .translucent)
    }

    @MainActor
    func testSubtitleStyleProducesLiveMpvShadowAndBackgroundOverrides() {
        let values = PlaybackSession.mpvSubtitleOverrides(
            for: PlaybackSubtitleStyle(
                shadowOpacity: 0.6,
                shadowBlurRadius: 4,
                background: .solid
            )
        )

        XCTAssertEqual(values["shadowOpacity"] as? Double, 0.6)
        XCTAssertEqual(values["shadowBlur"] as? Double, 4)
        XCTAssertEqual(values["background"] as? String, "solid")
    }

    @MainActor
    func testSubtitleControlChangesPublishDurablePreferenceUpdates() {
        let playback = PlaybackSession()
        var updates: [PlaybackSubtitlePreferenceUpdate] = []
        playback.setSubtitlePreferencesHandler { updates.append($0) }

        playback.setSubtitleFont("Avenir Next")
        playback.setSubtitleShadowBlurRadius(6)

        XCTAssertEqual(updates.last?.style.fontName, "Avenir Next")
        XCTAssertEqual(updates.last?.style.shadowBlurRadius, 6)
        XCTAssertNil(updates.last?.isEnabled)
        XCTAssertNil(updates.last?.preferredLanguage)
    }

    @MainActor
    func testSelectingSubtitlePublishesEnabledStateAndLanguageWithoutTrackID() {
        let update = PlaybackSubtitlePreferenceUpdate.selecting(
            id: 12,
            from: [PlaybackTrack(id: 12, title: "English", language: "en", codec: "srt", isSelected: false)],
            style: .default
        )

        XCTAssertEqual(update.isEnabled, true)
        XCTAssertEqual(update.preferredLanguage, .language("en"))
    }

    #if os(macOS)
    @MainActor
    func testMacPlaybackVolumeUsesAndTracksTheSystemOutputVolume() {
        let output = TestMacOutputVolumeController(volume: 0.35)
        let playback = PlaybackSession(outputVolumeController: output)

        XCTAssertEqual(playback.volume, 0.35)

        playback.setVolume(0.72)
        XCTAssertEqual(output.volume, 0.72)
        XCTAssertEqual(playback.volume, 0.72)

        output.volume = 0.18
        playback.synchronizeOutputVolume()
        XCTAssertEqual(playback.volume, 0.18)
    }

    @MainActor
    func testMacPlaybackVolumeFallsBackToPlayerVolumeWhenOutputIsUnsupported() {
        let output = TestMacOutputVolumeController(volume: nil)
        let playback = PlaybackSession(outputVolumeController: output)

        playback.setVolume(0.41)

        XCTAssertEqual(playback.volume, 0.41)
        XCTAssertEqual(output.setAttempts, [0.41])
        XCTAssertEqual(
            MacPlaybackVolumeRouting.playerVolumePercent(
                requestedVolume: 0.41,
                systemVolumeAvailable: false
            ),
            41,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacPlaybackVolumeRouting.playerVolumePercent(
                requestedVolume: 0.41,
                systemVolumeAvailable: true
            ),
            100,
            accuracy: 0.0001
        )
    }
    #endif
}

private actor TimelinePreviewSleeperStub {
    private(set) var requestedDurations: [Duration] = []
    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var countContinuations: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        resumeSatisfiedCountWaiters()
        await withCheckedContinuation { sleepContinuations.append($0) }
        try Task.checkCancellation()
    }

    func waitForRequestCount(_ count: Int) async {
        if requestedDurations.count >= count { return }
        await withCheckedContinuation { countContinuations.append((count, $0)) }
    }

    func releaseAll() {
        sleepContinuations.forEach { $0.resume() }
        sleepContinuations.removeAll()
    }

    private func resumeSatisfiedCountWaiters() {
        let ready = countContinuations.filter { requestedDurations.count >= $0.0 }
        countContinuations.removeAll { requestedDurations.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

#if os(macOS)
private final class TestMacOutputVolumeController: MacOutputVolumeControlling {
    var volume: Double?
    private(set) var setAttempts: [Double] = []

    init(volume: Double?) {
        self.volume = volume
    }

    var currentVolume: Double? { volume }

    func setVolume(_ value: Double) -> Bool {
        setAttempts.append(value)
        guard volume != nil else { return false }
        volume = value
        return true
    }
}
#endif
