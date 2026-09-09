import XCTest
@testable import Omnia

#if os(macOS)
import AppKit
#endif

final class PlaybackChromePresentationTests: XCTestCase {
    func testTimelineShowsElapsedAndNegativeRemainingTime() {
        let presentation = PlaybackTimelinePresentation(
            positionSeconds: 1_122,
            durationSeconds: 3_120
        )

        XCTAssertEqual(presentation.elapsedText, "18:42")
        XCTAssertEqual(presentation.remainingText, "−33:18")
    }

    func testEpisodeMetadataKeepsSeriesTitlePrimary() {
        let item = MediaItem(
            id: "glass-horizon",
            title: "The Glass Horizon",
            year: "2026",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "play.rectangle",
            artworkColors: [.black],
            progress: nil
        )
        let episode = MediaEpisode(
            id: "glass-horizon:1:6",
            seasonNumber: 1,
            episodeNumber: 6,
            title: "What Was Lost",
            overview: "",
            runtimeMinutes: 52,
            stillURL: nil,
            airDate: nil
        )

        let presentation = PlaybackChromeMetadata(item: item, episode: episode)

        XCTAssertEqual(presentation.title, "The Glass Horizon")
        XCTAssertEqual(presentation.context, "What Was Lost · S1, E6")
    }

    #if os(macOS)
    func testAspectRatioSymbolMatchesTheActiveTwoStateVideoLayout() {
        XCTAssertEqual(
            MacPlaybackAspectRatioSymbolPresentation.symbolName(for: .original),
            "aspectratio"
        )
        XCTAssertEqual(
            MacPlaybackAspectRatioSymbolPresentation.symbolName(for: .fill),
            "aspectratio.fill"
        )
    }

    func testInlineFontCatalogueKeepsSystemFirstAndDeduplicatesFonts() {
        XCTAssertEqual(
            MacSubtitleFontCatalog.displayNames(from: ["Helvetica", "Avenir", "Helvetica", "  "]),
            ["System", "Avenir", "Helvetica"]
        )
    }

    func testSubtitlePreviewContainsTheCompletePlaybackControlGroups() {
        XCTAssertEqual(
            MacSubtitlePreviewPresentation.topLeadingControls,
            [.close, .pictureInPicture, .fullScreen]
        )
        XCTAssertEqual(
            MacSubtitlePreviewPresentation.topTrailingControls,
            [.aspectRatio, .volume]
        )
        XCTAssertEqual(
            MacSubtitlePreviewPresentation.transportControls,
            [.rewind, .playPause, .fastForward]
        )
        XCTAssertEqual(
            MacSubtitlePreviewPresentation.bottomTrailingControls,
            [.audio, .subtitles, .speed]
        )
        XCTAssertTrue(MacSubtitlePreviewPresentation.includesTimeline)
        XCTAssertTrue(MacSubtitlePreviewPresentation.includesMediaMetadata)
    }

    func testSubtitlePreviewAppliesSizeScalePositionBackgroundAndShadow() {
        let style = PlaybackSubtitleStyle(
            fontName: "Avenir Next",
            fontSize: 42,
            scale: 0.75,
            position: 95,
            shadowOpacity: 0.65,
            shadowBlurRadius: 4,
            background: .translucent
        )
        let presentation = MacSubtitlePreviewPresentation(style: style, previewScale: 0.5)

        XCTAssertEqual(presentation.fontName, "Avenir Next")
        XCTAssertEqual(presentation.fontSize, 15.75, accuracy: 0.0001)
        XCTAssertEqual(presentation.backgroundOpacity, 0.55, accuracy: 0.0001)
        XCTAssertEqual(presentation.shadowOpacity, 0.65, accuracy: 0.0001)
        XCTAssertEqual(presentation.shadowBlurRadius, 2, accuracy: 0.0001)
        XCTAssertGreaterThan(
            MacSubtitlePreviewPresentation(style: style, previewScale: 0.5)
                .subtitleBottomInset(in: 360),
            MacSubtitlePreviewPresentation(
                style: PlaybackSubtitleStyle(position: 100),
                previewScale: 0.5
            ).subtitleBottomInset(in: 360)
        )
    }

    func testPlaybackOptionPanelUsesContentHeightUntilItNeedsScrolling() {
        let speedPanelHeight = MacPlaybackPanelLayout.idealHeight(
            rowCount: 6,
            navigationRowCount: 0,
            sliderCount: 0,
            maximumHeight: 900
        )
        let longTrackListHeight = MacPlaybackPanelLayout.idealHeight(
            rowCount: 30,
            navigationRowCount: 0,
            sliderCount: 0,
            maximumHeight: 520
        )

        XCTAssertLessThan(speedPanelHeight, 500)
        XCTAssertEqual(longTrackListHeight, 520)
    }

    func testEditingAnyPlaybackControlPinsChromeVisibility() {
        XCTAssertTrue(
            MacPlaybackInteractionPresentation.keepsChromeVisible(
                isEditingControl: true,
                hasPresentedPanel: false
            )
        )
        XCTAssertTrue(
            MacPlaybackInteractionPresentation.keepsChromeVisible(
                isEditingControl: false,
                hasPresentedPanel: true
            )
        )
        XCTAssertFalse(
            MacPlaybackInteractionPresentation.keepsChromeVisible(
                isEditingControl: false,
                hasPresentedPanel: false
            )
        )
    }

    func testVolumeDragValueWinsOverDelayedPlayerRefresh() {
        XCTAssertEqual(
            MacPlaybackVolumePresentation.displayedValue(
                dragValue: 0.72,
                playerValue: 0.21
            ),
            0.72
        )
        XCTAssertEqual(
            MacPlaybackVolumePresentation.displayedValue(
                dragValue: nil,
                playerValue: 0.21
            ),
            0.21
        )
    }

    func testPlaybackControlHoverLifts() {
        XCTAssertEqual(
            OmniaLiquidGlassPresentation.transform(isHovering: false),
            .init(scale: 1, verticalOffset: 0)
        )
        XCTAssertEqual(
            OmniaLiquidGlassPresentation.transform(isHovering: true),
            .init(scale: 1.04, verticalOffset: -2)
        )
    }

    func testTimelineAndSidebarNeverLift() {
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.playbackTimeline.liftsOnHover)
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.sidebar.liftsOnHover)
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.menuRow.liftsOnHover)
        XCTAssertTrue(OmniaLiquidGlassSurfaceRole.control.liftsOnHover)
    }

    func testOnlyInteractiveControlsAndMenuRowsDarken() {
        XCTAssertTrue(OmniaLiquidGlassSurfaceRole.control.darkensWhenActive)
        XCTAssertTrue(OmniaLiquidGlassSurfaceRole.menuRow.darkensWhenActive)
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.playbackTimeline.darkensWhenActive)
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.sidebar.darkensWhenActive)
    }

    func testModalGlassIsDarkContinuousAndStatic() {
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.modal.liftsOnHover)
        XCTAssertFalse(OmniaLiquidGlassSurfaceRole.modal.darkensWhenActive)
        XCTAssertTrue(OmniaLiquidGlassSurfaceRole.modal.isContinuousSurface)
        XCTAssertEqual(OmniaLiquidGlassSurfaceRole.modal.baseDarkeningOpacity, 0.34)
    }

    func testExclusiveFullScreenMovesTopControlsCloserToSafeEdge() {
        XCTAssertEqual(MacPlaybackChromeInsets.top(isExclusiveFullScreen: true, compact: false), 12)
        XCTAssertEqual(MacPlaybackChromeInsets.top(isExclusiveFullScreen: false, compact: false), 30)
    }

    func testEpisodicPromptsUseSeparatePlaybackChromeAnchors() {
        XCTAssertEqual(
            MacPlaybackPromptLayout.anchor(for: .skipIntro),
            .aboveMetadata
        )
        XCTAssertEqual(
            MacPlaybackPromptLayout.anchor(for: .upNext),
            .aboveOptionControls
        )
    }

    func testPanelScrollIndicatorStaysClearOfRoundedPopoverEdges() {
        XCTAssertEqual(MacPlaybackPanelLayout.scrollIndicatorVerticalInset, 54)
    }

    func testPlaybackKeyboardMapsUnmodifiedArrowsAndEscape() {
        XCTAssertEqual(
            MacPlaybackKeyboardAction.resolve(keyCode: 123, hasCommandLikeModifier: false),
            .seekBackward10
        )
        XCTAssertEqual(
            MacPlaybackKeyboardAction.resolve(keyCode: 124, hasCommandLikeModifier: false),
            .seekForward10
        )
        XCTAssertEqual(
            MacPlaybackKeyboardAction.resolve(keyCode: 53, hasCommandLikeModifier: false),
            .close
        )
    }

    func testPlaybackKeyboardLeavesModifiedAndUnrelatedKeysToMacOS() {
        XCTAssertNil(MacPlaybackKeyboardAction.resolve(keyCode: 123, hasCommandLikeModifier: true))
        XCTAssertNil(MacPlaybackKeyboardAction.resolve(keyCode: 49, hasCommandLikeModifier: false))
    }

    #endif
}
