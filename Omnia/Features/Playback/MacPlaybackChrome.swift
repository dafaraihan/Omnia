#if os(macOS)
import AppKit
import SwiftUI

private enum MacPlaybackPanel: Hashable {
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

enum MacPlaybackKeyboardAction: Equatable {
    case seekBackward10
    case seekForward10
    case close

    static func resolve(keyCode: UInt16, hasCommandLikeModifier: Bool) -> Self? {
        guard !hasCommandLikeModifier else { return nil }
        switch keyCode {
        case 123: return .seekBackward10
        case 124: return .seekForward10
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
    case aboveMetadata
    case aboveOptionControls
}

struct MacPlaybackPromptLayout {
    static func anchor(for prompt: MacPlaybackPromptKind) -> MacPlaybackPromptAnchor {
        switch prompt {
        case .skipIntro: .aboveMetadata
        case .upNext: .aboveOptionControls
        }
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
        .audio, .subtitles, .speed
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
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12 * previewScale)
                    .padding(.vertical, 5 * previewScale)
                    .background(
                        Color.black.opacity(presentation.backgroundOpacity),
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
}

struct MacPlaybackChrome: View {
    @Environment(PlaybackSession.self) private var playback
    @Binding var isInteracting: Bool
    let close: () -> Void
    let showsSkipIntro: Bool
    let skipIntro: () -> Void
    let upNextTitle: String?
    let showUpNext: () -> Void

    @State private var activePanel: MacPlaybackPanel?
    @State private var subtitlePage: MacSubtitlePanelPage = .overview
    @State private var volumeDragValue: Double?

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
                    playbackPanel(activePanel)
                        .frame(
                            width: min(390, max(320, geometry.size.width - 48))
                        )
                        .frame(
                            height: panelHeight(
                                activePanel,
                                maximumHeight: min(520, max(180, geometry.size.height - 190))
                            )
                        )
                        .padding(.trailing, 30)
                        .padding(.bottom, upNextTitle == nil ? 142 : 202)
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

                        Slider(
                            value: Binding(
                                get: {
                                    MacPlaybackVolumePresentation.displayedValue(
                                        dragValue: volumeDragValue,
                                        playerValue: playback.volume
                                    )
                                },
                                set: { queueVolumeUpdate($0) }
                            ),
                            in: 0 ... 1,
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
                        .frame(width: compact ? 118 : 188)
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
                .keyboardShortcut(.space, modifiers: [])

                transportButton(symbol: "goforward.10", label: "Forward 10 seconds") {
                    playback.seek(by: 10)
                }
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    if showsSkipIntro {
                        promptButton(
                            "Skip Intro",
                            symbol: "forward.end.fill",
                            action: skipIntro
                        )
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityHint("Seeks to the end of the detected intro")
                        .padding(.bottom, 7)
                    }

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
                .shadow(color: .black.opacity(0.55), radius: 12, y: 3)

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 10) {
                    if let upNextTitle {
                        promptButton(
                            upNextTitle,
                            symbol: "forward.fill",
                            action: showUpNext
                        )
                        .accessibilityHint("Choose an in-app source for the next episode")
                    }

                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            optionButton(.audio, symbol: "waveform", label: "Audio")
                            optionButton(.subtitles, symbol: "captions.bubble", label: "Subtitles")
                            optionButton(.speed, symbol: "speedometer", label: "Playback speed")
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Text(timeline.elapsedText)
                    .frame(minWidth: 46, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { duration > 0 ? position : 0 },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0 ... max(duration, 0.001),
                    onEditingChanged: { isEditing in
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

    @ViewBuilder
    private func playbackPanel(_ panel: MacPlaybackPanel) -> some View {
        ScrollView {
            switch panel {
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
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            VStack(alignment: .leading, spacing: 12) {
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
            VStack(alignment: .leading, spacing: 12) {
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
            VStack(alignment: .leading, spacing: 16) {
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
            VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
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
        .omniaCapsuleGlassButton()
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
