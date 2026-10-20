#if os(macOS)
import AppKit
import SwiftUI

private enum MacPlaybackPanel: Hashable {
    case episodes
    case audio
    case subtitles
    case speed
}

private enum MacSubtitlePanelPage: Hashable {
    case overview
    case language
    case style
    case font
    case background
}

private struct MacPlaybackPanelObservationBoundary<Content: View>: View, Equatable {
    let panel: MacPlaybackPanel
    let subtitlePage: MacSubtitlePanelPage
    let episodeSeasonNumber: Int?
    let content: () -> Content

    init(
        panel: MacPlaybackPanel,
        subtitlePage: MacSubtitlePanelPage,
        episodeSeasonNumber: Int? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.panel = panel
        self.subtitlePage = subtitlePage
        self.episodeSeasonNumber = episodeSeasonNumber
        self.content = content
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.panel == rhs.panel
            && lhs.subtitlePage == rhs.subtitlePage
            && lhs.episodeSeasonNumber == rhs.episodeSeasonNumber
    }

    var body: some View {
        content()
    }
}

enum MacPlaybackKeyboardAction: Equatable {
    case seekBackward10
    case seekForward10
    case togglePause
    case close

    static func resolve(keyCode: UInt16, hasCommandLikeModifier: Bool) -> Self? {
        guard !hasCommandLikeModifier else { return nil }
        switch keyCode {
        case 123: return .seekBackward10
        case 124: return .seekForward10
        // Space lives here rather than on the Play button, which leaves the
        // view tree when the chrome auto-hides.
        case 49: return .togglePause
        case 53: return .close
        default: return nil
        }
    }
}

struct MacPlaybackKeyboardMonitor: NSViewRepresentable {
    let perform: (MacPlaybackKeyboardAction) -> Void

    func makeNSView(context: Context) -> MacPlaybackKeyboardMonitorView {
        MacPlaybackKeyboardMonitorView(perform: perform)
    }

    func updateNSView(_ view: MacPlaybackKeyboardMonitorView, context: Context) {
        view.perform = perform
    }
}

final class MacPlaybackKeyboardMonitorView: NSView {
    var perform: (MacPlaybackKeyboardAction) -> Void
    private var monitor: Any?

    init(perform: @escaping (MacPlaybackKeyboardAction) -> Void) {
        self.perform = perform
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? removeMonitor() : installMonitor()
    }

    deinit {
        removeMonitor()
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Leave typing alone, for example in the source picker's fields.
            if event.window?.firstResponder is NSText { return event }
            let commandLikeModifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard let action = MacPlaybackKeyboardAction.resolve(
                keyCode: event.keyCode,
                hasCommandLikeModifier: !commandLikeModifiers.isEmpty
            ) else { return event }
            self?.perform(action)
            return nil
        }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

struct MacSubtitleFontCatalog {
    static func displayNames(from availableFamilies: [String]) -> [String] {
        let names = Set(
            availableFamilies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return ["System"] + names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static var availableDisplayNames: [String] {
        displayNames(from: NSFontManager.shared.availableFontFamilies)
    }
}

struct MacPlaybackAspectRatioSymbolPresentation {
    static func symbolName(for mode: PlaybackAspectRatioMode) -> String {
        switch mode {
        case .original: "aspectratio"
        case .fill: "aspectratio.fill"
        }
    }
}

struct MacPlaybackPanelLayout {
    static let scrollIndicatorVerticalInset: CGFloat = 54

    static func idealHeight(
        rowCount: Int,
        navigationRowCount: Int,
        sliderCount: Int,
        maximumHeight: CGFloat
    ) -> CGFloat {
        let chromeHeight: CGFloat = 92
        let contentHeight = chromeHeight
            + CGFloat(max(0, rowCount)) * 44
            + CGFloat(max(0, navigationRowCount)) * 52
            + CGFloat(max(0, sliderCount)) * 62
        return min(maximumHeight, max(180, contentHeight))
    }
}

enum MacPlaybackPromptKind: Equatable {
    case skipIntro
    case upNext
}

enum MacPlaybackPromptAnchor: Equatable {
    case optionControlBand
}

struct MacPlaybackPromptLayout {
    static func anchor(for prompt: MacPlaybackPromptKind) -> MacPlaybackPromptAnchor {
        switch prompt {
        case .skipIntro, .upNext: .optionControlBand
        }
    }
}

enum MacPlaybackAction: Hashable {
    case skipIntro
    case episodes
    case audio
    case subtitles
    case speed
    case nextEpisode
    case upNext
    case cancelUpNext
}

struct MacPlaybackActionPresentation {
    static func actions(
        isChromeVisible: Bool,
        showsSkipIntro: Bool,
        hasEpisodes: Bool = false,
        hasNextEpisode: Bool,
        upNextTitle: String?,
        canCancelUpNext: Bool = false
    ) -> [MacPlaybackAction] {
        var actions: [MacPlaybackAction] = []
        if showsSkipIntro { actions.append(.skipIntro) }
        guard isChromeVisible else {
            if upNextTitle != nil {
                if canCancelUpNext { actions.append(.cancelUpNext) }
                actions.append(.upNext)
            }
            return actions
        }

        if hasEpisodes { actions.append(.episodes) }
        actions += [.audio, .subtitles, .speed]
        if upNextTitle != nil {
            if canCancelUpNext { actions.append(.cancelUpNext) }
            actions.append(.upNext)
        } else if hasNextEpisode {
            actions.append(.nextEpisode)
        }
        return actions
    }
}

struct MacPlaybackEpisodePresentation {
    static func seasonTitle(_ season: MediaSeason) -> String {
        let title = season.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if season.seasonNumber == 0 { return title.isEmpty ? "Specials" : title }
        return title.isEmpty ? "Season \(season.seasonNumber)" : title
    }

    static func title(_ episode: MediaEpisode) -> String {
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = "E\(episode.episodeNumber)"
        return title.isEmpty ? number : "\(number) · \(title)"
    }

    /// Release year and runtime, for example "2024 · 47 min".
    static func details(_ episode: MediaEpisode) -> String {
        var parts: [String] = []
        if let airDate = episode.airDate, airDate.count >= 4 {
            parts.append(String(airDate.prefix(4)))
        }
        if let runtime = episode.runtimeMinutes, runtime > 0 {
            parts.append("\(runtime) min")
        }
        return parts.joined(separator: " · ")
    }

    static func isSame(_ episode: MediaEpisode, _ current: MediaEpisode?) -> Bool {
        guard let current else { return false }
        return episode.id == current.id
            || (episode.seasonNumber == current.seasonNumber && episode.episodeNumber == current.episodeNumber)
    }
}

struct MacPlaybackInteractionPresentation {
    static func keepsChromeVisible(
        isEditingControl: Bool,
        hasPresentedPanel: Bool
    ) -> Bool {
        isEditingControl || hasPresentedPanel
    }
}

struct MacPlaybackVolumePresentation {
    static func displayedValue(dragValue: Double?, playerValue: Double) -> Double {
        dragValue ?? playerValue
    }
}

struct MacPlaybackChromeInsets {
    static func top(isExclusiveFullScreen: Bool, compact: Bool) -> CGFloat {
        if isExclusiveFullScreen { return 12 }
        return compact ? 20 : 30
    }
}

enum MacPlaybackChromeCoordinateSpaceIdentity: Hashable {
    case windowed
    case exclusiveFullScreen

    init(isExclusiveFullScreen: Bool) {
        self = isExclusiveFullScreen ? .exclusiveFullScreen : .windowed
    }
}

enum MacSubtitlePreviewControl: Equatable {
    case close
    case pictureInPicture
    case fullScreen
    case aspectRatio
    case volume
    case rewind
    case playPause
    case fastForward
    case audio
    case subtitles
    case speed
    case nextEpisode
}

struct MacSubtitlePreviewPresentation {
    static let topLeadingControls: [MacSubtitlePreviewControl] = [
        .close, .pictureInPicture, .fullScreen
    ]
    static let topTrailingControls: [MacSubtitlePreviewControl] = [
        .aspectRatio, .volume
    ]
    static let transportControls: [MacSubtitlePreviewControl] = [
        .rewind, .playPause, .fastForward
    ]
    static let bottomTrailingControls: [MacSubtitlePreviewControl] = [
        .audio, .subtitles, .speed, .nextEpisode
    ]
    static let includesTimeline = true
    static let includesMediaMetadata = true

    private let style: PlaybackSubtitleStyle
    private let previewScale: CGFloat

    init(style: PlaybackSubtitleStyle, previewScale: CGFloat) {
        self.style = style.normalized
        self.previewScale = min(max(previewScale, 0.2), 1)
    }

    var fontName: String { style.fontName }
    var fontSize: CGFloat { style.fontSize * style.scale * previewScale }
    var shadowOpacity: Double { style.shadowOpacity }
    var shadowBlurRadius: CGFloat { style.shadowBlurRadius * previewScale }

    var backgroundOpacity: Double {
        switch style.background {
        case .none: 0
        case .translucent: 0.55
        case .solid: 1
        }
    }

    func subtitleBottomInset(in height: CGFloat) -> CGFloat {
        let timelineClearance = 116 * previewScale
        let movableRange = max(0, height - timelineClearance - (110 * previewScale))
        return timelineClearance + movableRange * ((100 - style.position) / 100)
    }
}

/// A non-interactive mirror of the production playback chrome used by
/// Settings so subtitle changes can be judged in their real viewing context.
struct MacSubtitlePlaybackPreview: View {
    let style: PlaybackSubtitleStyle

    private let sampleSubtitle = "The quick brown fox jumps over the lazy dog"

    private var outlineColor: Color {
        style.outlineEnabled ? (Color(omniaHex: style.outlineColorHex) ?? .black) : .clear
    }

    private var outlineWidth: CGFloat {
        style.outlineEnabled ? max(0.5, style.outlineSize * 0.6) : 0
    }

    var body: some View {
        GeometryReader { geometry in
            let previewScale = min(max(min(geometry.size.width / 1_250, geometry.size.height / 650), 0.42), 0.72)
            let presentation = MacSubtitlePreviewPresentation(
                style: style,
                previewScale: previewScale
            )

            ZStack {
                Color.black

                VStack(spacing: 0) {
                    previewTopControls(scale: previewScale)
                    Spacer()
                    previewTransportControls(scale: previewScale)
                    Spacer()
                    previewBottomControls(scale: previewScale)
                }
                .padding(24 * previewScale)

                Text(sampleSubtitle)
                    .font(.custom(previewFontName(presentation.fontName), size: presentation.fontSize))
                    .bold(style.isBold)
                    .italic(style.isItalic)
                    .foregroundStyle(Color(omniaHex: style.textColorHex) ?? .white)
                    .multilineTextAlignment(.center)
                    // Four hard offset shadows stand in for mpv's outline.
                    .shadow(color: outlineColor, radius: 0, x: outlineWidth, y: 0)
                    .shadow(color: outlineColor, radius: 0, x: -outlineWidth, y: 0)
                    .shadow(color: outlineColor, radius: 0, x: 0, y: outlineWidth)
                    .shadow(color: outlineColor, radius: 0, x: 0, y: -outlineWidth)
                    .padding(.horizontal, 12 * previewScale)
                    .padding(.vertical, 5 * previewScale)
                    .background(
                        (Color(omniaHex: style.backgroundColorHex) ?? .black).opacity(presentation.backgroundOpacity),
                        in: RoundedRectangle(cornerRadius: 4 * previewScale, style: .continuous)
                    )
                    .shadow(
                        color: .black.opacity(presentation.shadowOpacity),
                        radius: presentation.shadowBlurRadius
                    )
                    .frame(maxWidth: geometry.size.width * 0.72)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height
                            - presentation.subtitleBottomInset(in: geometry.size.height)
                            - presentation.fontSize / 2
                    )
            }
            .foregroundStyle(.white)
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtitle appearance preview")
        .accessibilityValue(sampleSubtitle)
    }

    private func previewTopControls(scale: CGFloat) -> some View {
        HStack(alignment: .top) {
            HStack(spacing: 8 * scale) {
                previewCircle("xmark", scale: scale)
                previewCircle("pip.enter", scale: scale)
                previewCircle("arrow.up.left.and.arrow.down.right", scale: scale)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8 * scale) {
                previewCircle("aspectratio", scale: scale)
                HStack(spacing: 10 * scale) {
                    Image(systemName: "speaker.wave.2.fill")
                    previewTrack(progress: 0.76, width: 150 * scale, scale: scale)
                }
                .padding(.horizontal, 14 * scale)
                .frame(height: 44 * scale)
                .omniaLiquidGlass(in: Capsule())
            }
        }
    }

    private func previewTransportControls(scale: CGFloat) -> some View {
        HStack(spacing: 24 * scale) {
            previewCircle("gobackward.10", diameter: 58, scale: scale)
            previewCircle("pause.fill", diameter: 82, scale: scale)
            previewCircle("goforward.10", diameter: 58, scale: scale)
        }
    }

    private func previewBottomControls(scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text("2026")
                        .font(.system(size: 13 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("Omnia Preview")
                        .font(.system(size: 22 * scale, weight: .semibold))
                }
                Spacer()
                HStack(spacing: 8 * scale) {
                    previewCircle("waveform", scale: scale)
                    previewCircle("captions.bubble", scale: scale)
                    previewCircle("speedometer", scale: scale)
                    previewCircle("forward.end.fill", scale: scale)
                }
            }

            HStack(spacing: 10 * scale) {
                Text("0:11")
                previewTrack(progress: 0.18, width: nil, scale: scale)
                Text("−1:41:33")
            }
            .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 12 * scale)
            .frame(height: 38 * scale)
            .omniaLiquidGlass(in: Capsule(), role: .playbackTimeline)
        }
    }

    private func previewCircle(
        _ symbol: String,
        diameter: CGFloat = 42,
        scale: CGFloat
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: max(10, diameter * scale * 0.38), weight: .semibold))
            .frame(width: diameter * scale, height: diameter * scale)
            .omniaLiquidGlass(in: Circle())
    }

    private func previewTrack(
        progress: CGFloat,
        width: CGFloat?,
        scale: CGFloat
    ) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule()
                    .fill(.white)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: max(2, 4 * scale))
    }

    private func previewFontName(_ name: String) -> String {
        name == PlaybackSubtitleStyle.default.fontName ? ".AppleSystemUIFont" : name
    }
}

private extension View {
    func playbackCircleGlassButton() -> some View {
        omniaCircularGlassButton()
    }

    func playbackRoundedGlassButton(cornerRadius: CGFloat = 14) -> some View {
        omniaRoundedGlassButton(cornerRadius: cornerRadius)
    }

    func playbackCapsuleGlassButton() -> some View {
        omniaCapsuleGlassButton()
    }
}

private struct MacPlaybackExpandedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let width: CGFloat
    let onEditingChanged: (Bool) -> Void

    @State private var isPointerEditing = false

    var body: some View {
        GeometryReader { geometry in
            Slider(value: $value, in: range)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.interaction, Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { gesture in
                            beginPointerEditingIfNeeded()
                            updateValue(at: gesture.location.x, width: geometry.size.width)
                        }
                        .onEnded { gesture in
                            updateValue(at: gesture.location.x, width: geometry.size.width)
                            endPointerEditingIfNeeded()
                        }
                )
        }
        .frame(width: width, height: 54)
        .onDisappear {
            endPointerEditingIfNeeded()
        }
    }

    private func beginPointerEditingIfNeeded() {
        guard !isPointerEditing else { return }
        isPointerEditing = true
        onEditingChanged(true)
    }

    private func endPointerEditingIfNeeded() {
        guard isPointerEditing else { return }
        isPointerEditing = false
        onEditingChanged(false)
    }

    private func updateValue(at horizontalLocation: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = Double(min(max(horizontalLocation / width, 0), 1))
        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

struct MacPlaybackChrome: View {
    @Environment(PlaybackSession.self) private var playback
    @Binding var isInteracting: Bool
    let close: () -> Void
    let showsSkipIntro: Bool
    var skipTitle = "Skip Intro"
    let skipIntro: () -> Void
    let hasNextEpisode: Bool
    let upNextTitle: String?
    let showUpNext: () -> Void
    /// Stops the next-episode countdown, when one is running.
    var cancelUpNext: (() -> Void)? = nil
    var playEpisode: (MediaEpisode) -> Void = { _ in }

    @State private var activePanel: MacPlaybackPanel?
    @State private var episodeSeasonNumber: Int?
    @State private var subtitlePage: MacSubtitlePanelPage = .overview
    @State private var volumeDragValue: Double?
    @State private var scrubValue: Double?
    @State private var isScrubbingTimeline = false
    @State private var lastScrubSeek = Date.distantPast

    private var duration: Double { playback.durationSeconds ?? 0 }
    private var position: Double { min(max(playback.positionSeconds, 0), duration) }
    private var metadata: PlaybackChromeMetadata {
        PlaybackChromeMetadata(item: playback.mediaItem, episode: playback.episode)
    }
    private var timeline: PlaybackTimelinePresentation {
        PlaybackTimelinePresentation(
            positionSeconds: playback.positionSeconds,
            durationSeconds: playback.durationSeconds
        )
    }
    private var playbackActions: [MacPlaybackAction] {
        MacPlaybackActionPresentation.actions(
            isChromeVisible: true,
            showsSkipIntro: showsSkipIntro,
            hasEpisodes: !episodeSeasons.isEmpty,
            hasNextEpisode: hasNextEpisode,
            upNextTitle: upNextTitle,
            canCancelUpNext: cancelUpNext != nil
        )
    }
    private var episodeSeasons: [MediaSeason] {
        guard playback.episode != nil else { return [] }
        return (playback.mediaItem?.details?.seasons ?? [])
            .filter { !$0.episodes.isEmpty }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    topControls(compact: geometry.size.width < 860)
                    Spacer()
                    bottomControls
                }

                transportControls

                if let activePanel {
                    MacPlaybackPanelObservationBoundary(
                        panel: activePanel,
                        subtitlePage: subtitlePage,
                        episodeSeasonNumber: episodeSeasonNumber
                    ) {
                        playbackPanel(activePanel)
                    }
                    .equatable()
                        .frame(
                            width: activePanel == .episodes
                                ? min(480, max(340, geometry.size.width - 48))
                                : min(390, max(320, geometry.size.width - 48))
                        )
                        .frame(
                            height: panelHeight(
                                activePanel,
                                maximumHeight: min(520, max(180, geometry.size.height - 190))
                            )
                        )
                        .padding(.trailing, 30)
                        .padding(.bottom, 142)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, geometry.size.width < 860 ? 20 : 30)
            .padding(.bottom, geometry.size.width < 860 ? 20 : 30)
            .padding(
                .top,
                MacPlaybackChromeInsets.top(
                    isExclusiveFullScreen: playback.isFullScreenActive,
                    compact: geometry.size.width < 860
                )
            )
        }
        .foregroundStyle(.white)
        .onChange(of: activePanel) { _, panel in
            isInteracting = panel != nil
            if panel != .subtitles {
                subtitlePage = .overview
            }
            if panel == .episodes {
                episodeSeasonNumber = playback.episode?.seasonNumber
            }
        }
        .onDisappear {
            isInteracting = false
        }
    }

    private func topControls(compact: Bool) -> some View {
        HStack(alignment: .top) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    circleButton(
                        symbol: "xmark",
                        label: "Close player",
                        hint: "Stops playback and returns to Omnia",
                        action: close
                    )

                    HStack(spacing: 6) {
                        circleButton(
                            symbol: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                            label: playback.isPictureInPictureActive
                                ? "Exit Picture in Picture"
                                : "Enter Picture in Picture",
                            hint: "Moves playback between Omnia and its floating player",
                            isEnabled: playback.isPictureInPictureAvailable
                        ) {
                            playback.togglePictureInPicture()
                        }

                        circleButton(
                            symbol: playback.isFullScreenActive
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right",
                            label: playback.isFullScreenActive
                                ? "Exit full screen"
                                : "Enter full screen",
                            hint: "Moves Omnia out of or into its exclusive full-screen Space"
                        ) {
                            playback.setFullScreen(!playback.isFullScreenActive)
                        }
                    }
                }
            }

            Spacer(minLength: 20)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        playback.cycleAspectRatio()
                    } label: {
                        AspectRatioSymbol(mode: playback.aspectRatioMode)
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                    }
                    .playbackCircleGlassButton()
                    .accessibilityLabel("Aspect ratio")
                    .accessibilityValue(playback.aspectRatioMode.title)
                    .accessibilityHint("Toggles between Original and Fill")
                    .help("Aspect Ratio: \(playback.aspectRatioMode.title)")

                    HStack(spacing: 12) {
                        Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        MacPlaybackExpandedSlider(
                            value: Binding(
                                get: {
                                    MacPlaybackVolumePresentation.displayedValue(
                                        dragValue: volumeDragValue,
                                        playerValue: playback.volume
                                    )
                                },
                                set: { queueVolumeUpdate($0) }
                            ),
                            range: 0 ... 1,
                            width: compact ? 118 : 188,
                            onEditingChanged: { isEditing in
                                if isEditing {
                                    volumeDragValue = playback.volume
                                } else {
                                    flushVolumeUpdate()
                                }
                                isInteracting = MacPlaybackInteractionPresentation.keepsChromeVisible(
                                    isEditingControl: isEditing,
                                    hasPresentedPanel: activePanel != nil
                                )
                            }
                        )
                        .tint(.white)
                        .accessibilityLabel("Volume")
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .omniaInteractiveLiquidGlass(in: Capsule())
                }
            }
        }
    }

    private var transportControls: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 28) {
                transportButton(symbol: "gobackward.10", label: "Back 10 seconds") {
                    playback.seek(by: -10)
                }

                Button {
                    playback.togglePause()
                } label: {
                    Image(systemName: playback.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .frame(width: 86, height: 86)
                        .contentShape(Circle())
                }
                .playbackCircleGlassButton()
                .accessibilityLabel(playback.isPaused ? "Play" : "Pause")

                transportButton(symbol: "goforward.10", label: "Forward 10 seconds") {
                    playback.seek(by: 10)
                }
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 24) {
                playbackMetadata
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 3)

                Spacer(minLength: 20)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(playbackActions, id: \.self) { action in
                            playbackAction(action)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Text(timeline.elapsedText)
                    .frame(minWidth: 46, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { duration > 0 ? (scrubValue ?? position) : 0 },
                        set: { scrub(to: $0) }
                    ),
                    in: 0 ... max(duration, 0.001),
                    onEditingChanged: { isEditing in
                        isScrubbingTimeline = isEditing
                        if !isEditing, let scrubValue {
                            playback.seek(to: scrubValue)
                            self.scrubValue = nil
                        }
                        isInteracting = MacPlaybackInteractionPresentation.keepsChromeVisible(
                            isEditingControl: isEditing,
                            hasPresentedPanel: activePanel != nil
                        )
                    }
                )
                .tint(.white)
                .accessibilityLabel("Playback position")
                .disabled(duration <= 0)

                Text(timeline.remainingText)
                    .frame(minWidth: 54, alignment: .trailing)
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.74))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .omniaLiquidGlass(in: Capsule(), role: .playbackTimeline)
        }
    }

    /// Dragging the timeline used to send mpv an exact seek for every pointer
    /// move, which queued up seeks faster than mpv could finish them. The knob
    /// now follows the pointer, mpv gets at most one seek per interval while
    /// dragging, and the final position is sent when the drag ends.
    private func scrub(to value: Double) {
        // Keyboard and accessibility adjustments arrive without a drag.
        guard isScrubbingTimeline else {
            playback.seek(to: value)
            return
        }
        scrubValue = value
        let now = Date()
        guard now.timeIntervalSince(lastScrubSeek) >= 0.2 else { return }
        lastScrubSeek = now
        playback.seek(to: value)
    }

    @ViewBuilder
    private var playbackMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            if playback.episode != nil {
                Text(metadata.title)
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
                if !metadata.context.isEmpty {
                    Text(metadata.context)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
            } else {
                if !metadata.context.isEmpty {
                    Text(metadata.context)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                Text(metadata.title)
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func playbackPanel(_ panel: MacPlaybackPanel) -> some View {
        ScrollView {
            switch panel {
            case .episodes:
                episodesPanel
            case .audio:
                audioPanel
            case .subtitles:
                subtitlesPanel
            case .speed:
                speedPanel
            }
        }
        .scrollIndicators(.visible)
        .contentMargins(.horizontal, 22, for: .scrollContent)
        .contentMargins(.vertical, 22, for: .scrollContent)
        .contentMargins(
            .vertical,
            MacPlaybackPanelLayout.scrollIndicatorVerticalInset,
            for: .scrollIndicators
        )
        .contentMargins(.trailing, 6, for: .scrollIndicators)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var selectedEpisodeSeason: MediaSeason? {
        let seasons = episodeSeasons
        let number = episodeSeasonNumber ?? playback.episode?.seasonNumber
        return seasons.first { $0.seasonNumber == number } ?? seasons.first
    }

    private var episodesPanel: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Episodes")
                    .font(.title3.weight(.semibold))
                Spacer()
                if episodeSeasons.count > 1, let season = selectedEpisodeSeason {
                    Menu {
                        Picker("Season", selection: Binding(
                            get: { season.seasonNumber },
                            set: { episodeSeasonNumber = $0 }
                        )) {
                            ForEach(episodeSeasons) { season in
                                Text(MacPlaybackEpisodePresentation.seasonTitle(season))
                                    .tag(season.seasonNumber)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(
                            MacPlaybackEpisodePresentation.seasonTitle(season),
                            systemImage: "chevron.up.chevron.down"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .fixedSize()
                    .accessibilityLabel("Season")
                } else if let season = selectedEpisodeSeason {
                    Text(MacPlaybackEpisodePresentation.seasonTitle(season))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            panelDivider

            ForEach(selectedEpisodeSeason?.episodes ?? []) { episode in
                episodeRow(episode)
            }
        }
    }

    private func episodeRow(_ episode: MediaEpisode) -> some View {
        let isCurrent = MacPlaybackEpisodePresentation.isSame(episode, playback.episode)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                activePanel = nil
            }
            guard !isCurrent else { return }
            playEpisode(episode)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: episode.stillURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.08)
                            Image(systemName: "film")
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .frame(width: 128, height: 72)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .center) {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.headline)
                            .padding(8)
                            .background(.black.opacity(0.55), in: Circle())
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(MacPlaybackEpisodePresentation.title(episode))
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    let details = MacPlaybackEpisodePresentation.details(episode)
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !episode.overview.isEmpty {
                        Text(episode.overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.1))
                }
            }
            .contentShape(Rectangle())
        }
        .omniaMenuRowButton()
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Now playing" : "")
        .accessibilityHint(isCurrent ? "" : "Choose a source for this episode")
    }

    private var audioPanel: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            panelTitle("Audio Track", detail: selectedAudioTrackName)
            panelDivider

            switch PlaybackTrackAvailability(
                isLoading: playback.areTracksLoading,
                tracks: playback.audioTracks
            ) {
            case .loading:
                ProgressView("Tracks still loading")
            case .empty:
                Text("No audio tracks")
                    .foregroundStyle(.secondary)
            case .available:
                ForEach(playback.audioTracks) { track in
                    panelRow(track.displayName, isSelected: track.isSelected) {
                        playback.selectAudioTrack(track.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subtitlesPanel: some View {
        switch subtitlePage {
        case .overview:
            LazyVStack(alignment: .leading, spacing: 12) {
                panelTitle("Subtitles", detail: selectedSubtitleTrackName)

                panelRow("On", isSelected: playback.subtitleTracks.contains(where: \.isSelected), isEnabled: !playback.subtitleTracks.isEmpty) {
                    if let selected = playback.subtitleTracks.first(where: \.isSelected) {
                        playback.selectSubtitleTrack(selected.id)
                    } else if let first = playback.subtitleTracks.first {
                        playback.selectSubtitleTrack(first.id)
                    }
                }
                panelRow("Off", isSelected: !playback.subtitleTracks.contains(where: \.isSelected)) {
                    playback.selectSubtitleTrack(nil)
                }

                panelDivider
                navigationRow("Language", detail: selectedSubtitleTrackName) {
                    subtitlePage = .language
                }
                navigationRow("Style", detail: "Custom") {
                    subtitlePage = .style
                }
            }
        case .language:
            LazyVStack(alignment: .leading, spacing: 12) {
                panelTitle("Language", detail: selectedSubtitleTrackName, backTo: .overview)
                panelDivider
                switch PlaybackTrackAvailability(
                    isLoading: playback.areTracksLoading,
                    tracks: playback.subtitleTracks
                ) {
                case .loading:
                    ProgressView("Tracks still loading")
                case .empty:
                    Text("No embedded subtitles")
                        .foregroundStyle(.secondary)
                case .available:
                    ForEach(playback.subtitleTracks) { track in
                        panelRow(track.displayName, isSelected: track.isSelected) {
                            playback.selectSubtitleTrack(track.id)
                        }
                    }
                }
            }
        case .style:
            LazyVStack(alignment: .leading, spacing: 16) {
                panelTitle("Style", detail: "Custom", backTo: .overview)
                panelDivider
                navigationRow("Font", detail: selectedFontTitle) {
                    subtitlePage = .font
                }
                navigationRow("Background", detail: subtitleBackgroundTitle) {
                    subtitlePage = .background
                }
                styleSlider(
                    "Size",
                    value: Binding(
                        get: { playback.subtitleStyle.fontSize },
                        set: { playback.setSubtitleFontSize($0) }
                    ),
                    range: 14 ... 72,
                    valueText: "\(Int(playback.subtitleStyle.fontSize.rounded())) pt"
                )
                styleSlider(
                    "Scale",
                    value: Binding(
                        get: { playback.subtitleStyle.scale },
                        set: { playback.setSubtitleScale($0) }
                    ),
                    range: 0.5 ... 2,
                    valueText: "\(Int((playback.subtitleStyle.scale * 100).rounded()))%"
                )
                styleSlider(
                    "Position",
                    value: Binding(
                        get: { playback.subtitleStyle.position },
                        set: { playback.setSubtitlePosition($0) }
                    ),
                    range: 0 ... 100,
                    valueText: "\(Int(playback.subtitleStyle.position.rounded()))"
                )
                styleSlider(
                    "Shadow Opacity",
                    value: Binding(
                        get: { playback.subtitleStyle.shadowOpacity },
                        set: { playback.setSubtitleShadowOpacity($0) }
                    ),
                    range: 0 ... 1,
                    valueText: "\(Int((playback.subtitleStyle.shadowOpacity * 100).rounded()))%"
                )
                styleSlider(
                    "Shadow Blur",
                    value: Binding(
                        get: { playback.subtitleStyle.shadowBlurRadius },
                        set: { playback.setSubtitleShadowBlurRadius($0) }
                    ),
                    range: 0 ... 20,
                    valueText: "\(Int(playback.subtitleStyle.shadowBlurRadius.rounded()))"
                )
            }
        case .font:
            LazyVStack(alignment: .leading, spacing: 12) {
                panelTitle("Font", detail: selectedFontTitle, backTo: .style)
                panelDivider
                ForEach(MacSubtitleFontCatalog.availableDisplayNames, id: \.self) { fontName in
                    fontRow(fontName)
                }
            }
        case .background:
            LazyVStack(alignment: .leading, spacing: 12) {
                panelTitle("Background", detail: subtitleBackgroundTitle, backTo: .style)
                panelDivider
                ForEach(PlaybackSubtitleBackground.allCases) { background in
                    panelRow(
                        background.title,
                        isSelected: playback.subtitleStyle.background == background
                    ) {
                        playback.setSubtitleBackground(background)
                    }
                }
            }
        }
    }

    private var speedPanel: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            panelTitle("Playback Speed", detail: playbackRateTitle(playback.playbackRate))
            panelDivider
            ForEach([2.0, 1.5, 1.25, 1, 0.75, 0.5], id: \.self) { rate in
                panelRow(
                    playbackRateTitle(rate),
                    isSelected: abs(playback.playbackRate - rate) < 0.001
                ) {
                    playback.setPlaybackRate(rate)
                }
            }
        }
    }

    private func circleButton(
        symbol: String,
        label: String,
        hint: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .playbackCircleGlassButton()
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .help(label)
    }

    private func transportButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .playbackCircleGlassButton()
        .accessibilityLabel(label)
        .help(label)
    }

    private func optionButton(
        _ panel: MacPlaybackPanel,
        symbol: String,
        label: String
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                activePanel = activePanel == panel ? nil : panel
            }
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .playbackCircleGlassButton()
        .accessibilityLabel(label)
        .accessibilityValue(activePanel == panel ? "Expanded" : "Collapsed")
        .help(label)
    }

    private func promptButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .playbackCapsuleGlassButton()
    }

    @ViewBuilder
    private func playbackAction(_ action: MacPlaybackAction) -> some View {
        switch action {
        case .skipIntro:
            promptButton(skipTitle, symbol: "forward.end.fill", action: skipIntro)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityHint("Seeks past the detected segment")
        case .episodes:
            optionButton(.episodes, symbol: "list.and.film", label: "Episodes")
        case .audio:
            optionButton(.audio, symbol: "waveform", label: "Audio")
        case .subtitles:
            optionButton(.subtitles, symbol: "captions.bubble", label: "Subtitles")
        case .speed:
            optionButton(.speed, symbol: "speedometer", label: "Playback speed")
        case .nextEpisode:
            circleButton(
                symbol: "forward.end.fill",
                label: "Next episode",
                hint: "Choose an in-app source for the next episode",
                action: showUpNext
            )
        case .upNext:
            if let upNextTitle {
                promptButton(upNextTitle, symbol: "forward.end.fill", action: showUpNext)
                    .accessibilityHint("Plays the next episode")
            }
        case .cancelUpNext:
            if let cancelUpNext {
                promptButton("Cancel", symbol: "xmark", action: cancelUpNext)
                    .accessibilityHint("Stops the next episode from starting automatically")
            }
        }
    }

    private func panelTitle(
        _ title: String,
        detail: String,
        backTo destination: MacSubtitlePanelPage? = nil
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let destination {
                Button {
                    subtitlePage = destination
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .omniaCircularMenuRowButton()
                .accessibilityLabel("Back")
            }
        }
    }

    private var panelDivider: some View {
        Divider().overlay(.white.opacity(0.12))
    }

    private func navigationRow(
        _ title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .omniaMenuRowButton()
        .accessibilityElement(children: .combine)
    }

    private func panelRow(
        _ title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .omniaMenuRowButton()
        .disabled(!isEnabled)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func fontRow(_ displayName: String) -> some View {
        let fontName = displayName == "System" ? "sans-serif" : displayName
        let isSelected = playback.subtitleStyle.fontName == fontName

        return Button {
            playback.setSubtitleFont(fontName)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 18)
                Text(displayName)
                    .font(displayName == "System" ? .body : .custom(displayName, size: 16))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .omniaMenuRowButton()
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func styleSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            Slider(value: value, in: range)
                .tint(.white)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var selectedAudioTrackName: String {
        playback.audioTracks.first(where: \.isSelected)?.displayName ?? "Unavailable"
    }

    private var selectedSubtitleTrackName: String {
        playback.subtitleTracks.first(where: \.isSelected)?.displayName ?? "Off"
    }

    private var selectedFontTitle: String {
        playback.subtitleStyle.fontName == "sans-serif"
            ? "System"
            : playback.subtitleStyle.fontName
    }

    private var subtitleBackgroundTitle: String {
        playback.subtitleStyle.background.title
    }

    private func playbackRateTitle(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))×" : String(format: "%.2g×", value)
    }

    private func queueVolumeUpdate(_ value: Double) {
        let clampedValue = min(max(value, 0), 1)
        volumeDragValue = clampedValue
        playback.setVolume(clampedValue)
    }

    private func flushVolumeUpdate() {
        if let volumeDragValue {
            playback.setVolume(volumeDragValue)
        }
        volumeDragValue = nil
    }

    private func panelHeight(
        _ panel: MacPlaybackPanel,
        maximumHeight: CGFloat
    ) -> CGFloat {
        switch panel {
        case .episodes:
            // Episode rows are roughly two standard rows tall.
            return MacPlaybackPanelLayout.idealHeight(
                rowCount: max(1, selectedEpisodeSeason?.episodes.count ?? 1) * 2,
                navigationRowCount: 0,
                sliderCount: 0,
                maximumHeight: maximumHeight
            )
        case .audio:
            return MacPlaybackPanelLayout.idealHeight(
                rowCount: max(1, playback.audioTracks.count),
                navigationRowCount: 0,
                sliderCount: 0,
                maximumHeight: maximumHeight
            )
        case .speed:
            return MacPlaybackPanelLayout.idealHeight(
                rowCount: 6,
                navigationRowCount: 0,
                sliderCount: 0,
                maximumHeight: maximumHeight
            )
        case .subtitles:
            switch subtitlePage {
            case .overview:
                return MacPlaybackPanelLayout.idealHeight(
                    rowCount: 2,
                    navigationRowCount: 2,
                    sliderCount: 0,
                    maximumHeight: maximumHeight
                )
            case .language:
                return MacPlaybackPanelLayout.idealHeight(
                    rowCount: max(1, playback.subtitleTracks.count),
                    navigationRowCount: 0,
                    sliderCount: 0,
                    maximumHeight: maximumHeight
                )
            case .style:
                return MacPlaybackPanelLayout.idealHeight(
                    rowCount: 0,
                    navigationRowCount: 2,
                    sliderCount: 5,
                    maximumHeight: maximumHeight
                )
            case .font:
                return MacPlaybackPanelLayout.idealHeight(
                    rowCount: MacSubtitleFontCatalog.availableDisplayNames.count,
                    navigationRowCount: 0,
                    sliderCount: 0,
                    maximumHeight: maximumHeight
                )
            case .background:
                return MacPlaybackPanelLayout.idealHeight(
                    rowCount: PlaybackSubtitleBackground.allCases.count,
                    navigationRowCount: 0,
                    sliderCount: 0,
                    maximumHeight: maximumHeight
                )
            }
        }
    }
}

struct MacPlaybackContextualActions: View {
    let showsSkipIntro: Bool
    var skipTitle = "Skip Intro"
    let skipIntro: () -> Void
    let upNextTitle: String?
    let showUpNext: () -> Void
    var cancelUpNext: (() -> Void)? = nil

    private var actions: [MacPlaybackAction] {
        MacPlaybackActionPresentation.actions(
            isChromeVisible: false,
            showsSkipIntro: showsSkipIntro,
            hasNextEpisode: false,
            upNextTitle: upNextTitle,
            canCancelUpNext: cancelUpNext != nil
        )
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(actions, id: \.self) { action in
                    contextualAction(action)
                }
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func contextualAction(_ action: MacPlaybackAction) -> some View {
        switch action {
        case .skipIntro:
            promptButton(
                skipTitle,
                symbol: "forward.end.fill",
                hint: "Seeks past the detected segment",
                action: skipIntro
            )
            .keyboardShortcut(.return, modifiers: [])
        case .upNext:
            if let upNextTitle {
                promptButton(
                    upNextTitle,
                    symbol: "forward.end.fill",
                    hint: "Plays the next episode",
                    action: showUpNext
                )
            }
        case .cancelUpNext:
            if let cancelUpNext {
                promptButton(
                    "Cancel",
                    symbol: "xmark",
                    hint: "Stops the next episode from starting automatically",
                    action: cancelUpNext
                )
            }
        case .episodes, .audio, .subtitles, .speed, .nextEpisode:
            EmptyView()
        }
    }

    private func promptButton(
        _ title: String,
        symbol: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .playbackCapsuleGlassButton()
        .accessibilityHint(hint)
    }
}

private struct AspectRatioSymbol: View {
    let mode: PlaybackAspectRatioMode

    var body: some View {
        Image(systemName: MacPlaybackAspectRatioSymbolPresentation.symbolName(for: mode))
            .foregroundStyle(.white)
        .font(.title3.weight(.semibold))
    }
}

private extension PlaybackSubtitleBackground {
    var title: String {
        switch self {
        case .none: "None"
        case .translucent: "Translucent"
        case .solid: "Solid"
        }
    }
}
#endif
