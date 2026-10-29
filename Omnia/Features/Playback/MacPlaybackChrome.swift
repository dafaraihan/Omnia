#if os(macOS)
import AppKit
#endif
import SwiftUI

private enum MacPlaybackPanel: Hashable {
    case episodes
    case channels
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
    case sync
}

/// Which channels the player's channel list shows.
private enum MacLiveChannelFilter: Hashable {
    case all
    case favorites
    case group(String)
}

private struct MacPlaybackPanelObservationBoundary<Content: View>: View, Equatable {
    let panel: MacPlaybackPanel
    let subtitlePage: MacSubtitlePanelPage
    let episodeSeasonNumber: Int?
    let channelFilter: MacLiveChannelFilter
    let content: () -> Content

    init(
        panel: MacPlaybackPanel,
        subtitlePage: MacSubtitlePanelPage,
        episodeSeasonNumber: Int? = nil,
        channelFilter: MacLiveChannelFilter = .all,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.panel = panel
        self.subtitlePage = subtitlePage
        self.episodeSeasonNumber = episodeSeasonNumber
        self.channelFilter = channelFilter
        self.content = content
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.panel == rhs.panel
            && lhs.subtitlePage == rhs.subtitlePage
            && lhs.episodeSeasonNumber == rhs.episodeSeasonNumber
            && lhs.channelFilter == rhs.channelFilter
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

#if os(macOS)
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
#endif

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
        #if os(macOS)
        displayNames(from: NSFontManager.shared.availableFontFamilies)
        #else
        displayNames(from: UIFont.familyNames)
        #endif
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

enum MacPlaybackAction: Hashable {
    case sources
    case episodes
    case channels
    case audio
    case subtitles
    case speed
    case nextEpisode
}

/// The controls row. Skip and Up Next aren't in it: they're their own
/// overlay (`PlaybackPromptOverlay`).
struct MacPlaybackActionPresentation {
    static func actions(
        hasEpisodes: Bool = false,
        hasNextEpisode: Bool,
        isLive: Bool = false
    ) -> [MacPlaybackAction] {
        // A live channel has no sources, episodes or speed: its list of
        // channels takes their place.
        if isLive { return [.channels, .audio, .subtitles] }
        var actions: [MacPlaybackAction] = [.sources]
        if hasEpisodes { actions.append(.episodes) }
        actions += [.audio, .subtitles, .speed]
        if hasNextEpisode { actions.append(.nextEpisode) }
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
    @Environment(\.displayPreferences) private var display
    @Environment(SettingsPreferencesStore.self) private var settings
    @Binding var isInteracting: Bool
    let close: () -> Void
    let hasNextEpisode: Bool
    let showUpNext: () -> Void
    var playEpisode: (MediaEpisode) -> Void = { _ in }
    /// Opens this title's sources, to switch to another one.
    var showSources: () -> Void = {}

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var isShort: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    @State private var activePanel: MacPlaybackPanel?
    @State private var episodeSeasonNumber: Int?
    @State private var subtitlePage: MacSubtitlePanelPage = .overview
    @State private var volumeDragValue: Double?
    @State private var scrubValue: Double?
    @State private var isScrubbingTimeline = false
    @State private var lastScrubSeek = Date.distantPast
    @State private var live = LiveTVStore.shared
    @State private var channelFilter: MacLiveChannelFilter = .all
    @State private var switchingChannelID: String?
    @State private var channelNotice: String?
    @State private var channelNoticeTask: Task<Void, Never>?

    /// Live TV plays in this same player; its channel list, channel up and
    /// down, and a live bar stand in for episodes, seeking and the timeline.
    private var isLive: Bool {
        playback.mediaItem?.id.hasPrefix(PlaybackSource.liveTVIDPrefix) == true
    }
    private var currentChannel: LiveTVChannel? {
        playback.mediaItem.flatMap { live.channel(forPlaybackItemID: $0.id) }
    }

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
            hasEpisodes: !episodeSeasons.isEmpty,
            hasNextEpisode: hasNextEpisode,
            isLive: isLive
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

                // Hidden after a failure, so they don't sit on the message.
                if playback.playbackError == nil {
                    if !isPhone || activePanel == nil { transportControls }
                }

                if let activePanel {
                    MacPlaybackPanelObservationBoundary(
                        panel: activePanel,
                        subtitlePage: subtitlePage,
                        episodeSeasonNumber: episodeSeasonNumber,
                        channelFilter: channelFilter
                    ) {
                        playbackPanel(activePanel)
                    }
                    .equatable()
                        .frame(
                            width: activePanel == .episodes || activePanel == .channels
                                ? min(480, max(0, geometry.size.width - 48))
                                : min(390, max(0, geometry.size.width - 48))
                        )
                        .frame(
                            height: panelHeight(
                                activePanel,
                                maximumHeight: min(520, max(100, geometry.size.height - (isShort ? 90 : 190)))
                            )
                        )
                        .padding(.trailing, isPhone ? 0 : 30)
                        .padding(.bottom, isShort ? 50 : 142)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let channelNotice {
                    Label(channelNotice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.top, 70)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: channelNotice)
            .padding(.horizontal, geometry.size.width < 860 ? 20 : 30)
            .padding(.bottom, isShort ? 4 : (geometry.size.width < 860 ? 20 : 30))
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
            if panel == .channels {
                channelFilter = currentChannel?.group.map { .group($0) } ?? .all
            }
        }
        .onDisappear {
            isInteracting = false
            channelNoticeTask?.cancel()
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

                    // The phone and tablet player is always full screen.
                    #if os(macOS)
                    HStack(spacing: 6) {
                        circleButton(
                            symbol: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                            label: playback.isPictureInPictureActive
                                ? "Exit Picture in Picture"
                                : "Enter Picture in Picture",
                            hint: "Moves playback between Omnia and its floating player",
                            isEnabled: playback.isPictureInPictureActive || playback.isPictureInPictureAvailable
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
                    #else
                    circleButton(
                        symbol: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                        label: playback.isPictureInPictureActive ? "Exit Picture in Picture" : "Enter Picture in Picture",
                        hint: "Requires a source supported by Picture in Picture",
                        isEnabled: playback.isPictureInPictureActive || playback.isPictureInPictureAvailable
                    ) { playback.togglePictureInPicture() }
                    #endif
                }
            }

            Spacer(minLength: 20)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        playback.cycleAspectRatio()
                    } label: {
                        AspectRatioSymbol(mode: playback.aspectRatioMode)
                            .frame(width: isPhone ? 44 : 42, height: isPhone ? 44 : 42)
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
                            width: isPhone ? 80 : (compact ? 118 : 188),
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
                        .tint(display.accentColor)
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
            HStack(spacing: isPhone ? 20 : 28) {
                if isLive {
                    transportButton(symbol: "backward.end.fill", label: "Previous channel") {
                        stepChannel(by: -1)
                    }
                    .disabled(currentChannel == nil || live.channels.count < 2)
                } else {
                    transportButton(symbol: "gobackward.10", label: "Back 10 seconds") {
                        playback.seek(by: -10)
                    }
                }

                Button {
                    playback.togglePause()
                } label: {
                    Image(systemName: playback.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .frame(width: isPhone ? 60 : 86, height: isPhone ? 60 : 86)
                        .contentShape(Circle())
                }
                .playbackCircleGlassButton()
                .accessibilityLabel(playback.isPaused ? "Play" : "Pause")

                if isLive {
                    transportButton(symbol: "forward.end.fill", label: "Next channel") {
                        stepChannel(by: 1)
                    }
                    .disabled(currentChannel == nil || live.channels.count < 2)
                } else {
                    transportButton(symbol: "goforward.10", label: "Forward 10 seconds") {
                        playback.seek(by: 10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if isPhone { phoneBottomControls } else { regularBottomControls }
    }

    private var regularBottomControls: some View {
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

            if isLive {
                liveBar
            } else {
                timelineBar
            }
        }
    }

    private var phoneBottomControls: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    if !isShort { playbackMetadata }
                    Spacer(minLength: 8)
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    if !isShort { playbackMetadata }
                    ScrollView(.horizontal) { actionButtons }
                        .scrollIndicators(.hidden)
                }
            }

            if isLive { liveBar } else { timelineBar }
        }
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: isPhone ? 6 : 10) {
                ForEach(playbackActions, id: \.self) { action in playbackAction(action) }
            }
        }
    }

    private var timelineBar: some View {
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
            .tint(display.accentColor)
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

    /// The live bar in the timeline's place: what's on now, how far into it
    /// we are, and when it ends. A channel without a guide just says Live.
    private var liveBar: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let program = currentProgram(at: context.date)
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                    Text("LIVE")
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .combine)

                if let program {
                    Text(program.start, format: .dateTime.hour().minute())
                    ProgressView(value: program.progress(at: context.date))
                        .progressViewStyle(.linear)
                        .tint(display.accentColor)
                        .accessibilityLabel("\(program.title) progress")
                    Text(program.end, format: .dateTime.hour().minute())
                } else {
                    Text(currentChannel?.group ?? "Live TV")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.74))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .omniaLiquidGlass(in: Capsule(), role: .playbackTimeline)
        }
    }

    private func currentProgram(at date: Date) -> LiveTVProgram? {
        guard let currentChannel else { return nil }
        return LiveTVGuideMatcher.nowAndNext(in: live.programs(for: currentChannel), at: date).now
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
        // Keyframe seeks are cheap, so the picture can follow more closely.
        guard now.timeIntervalSince(lastScrubSeek) >= 0.12 else { return }
        lastScrubSeek = now
        playback.previewSeek(to: value)
    }

    @ViewBuilder
    private var playbackMetadata: some View {
        if isLive {
            liveMetadata
        } else {
            titleMetadata
        }
    }

    /// The channel, with what's on now and next under it.
    private var liveMetadata: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let programs = currentChannel.map { live.programs(for: $0) } ?? []
            let guide = LiveTVGuideMatcher.nowAndNext(in: programs, at: context.date)
            VStack(alignment: .leading, spacing: 3) {
                Text(currentChannel?.group ?? "Live TV")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Text(playback.mediaItem?.title ?? "Live TV")
                    .font(isPhone ? .headline : .title.weight(.semibold))
                    .lineLimit(1)
                if let now = guide.now {
                    Text(now.title)
                        .font(.headline.weight(.medium))
                        .lineLimit(1)
                }
                if let next = guide.next {
                    Text("Next \(next.start.formatted(date: .omitted, time: .shortened)) · \(next.title)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private var titleMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            if playback.episode != nil {
                Text(metadata.title)
                    .font(isPhone ? .headline : .title.weight(.semibold))
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
                    .font(isPhone ? .headline : .title.weight(.semibold))
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
            case .channels:
                channelsPanel
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
                CachedArtworkImage(url: episode.stillURL, size: CGSize(width: 128, height: 72)) { phase in
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

    // MARK: Channels

    private var filteredChannels: [LiveTVChannel] {
        switch channelFilter {
        case .all:
            live.channels
        case .favorites:
            live.channels.filter { live.isFavorite($0) }
        case let .group(group):
            live.channels.filter { $0.group == group }
        }
    }

    private func channelFilterTitle(_ filter: MacLiveChannelFilter) -> String {
        switch filter {
        case .all: "All Channels"
        case .favorites: "Favorites"
        case let .group(group): group
        }
    }

    /// Laid out like the Episodes list: a header with a category menu in the
    /// season menu's place, then a row per channel.
    private var channelsPanel: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Channels")
                    .font(.title3.weight(.semibold))
                Spacer()
                Menu {
                    Picker("Category", selection: $channelFilter) {
                        Text("All Channels").tag(MacLiveChannelFilter.all)
                        if !live.configuration.favoriteChannelIDs.isEmpty {
                            Text("Favorites").tag(MacLiveChannelFilter.favorites)
                        }
                        ForEach(live.groups, id: \.self) { group in
                            Text(group).tag(MacLiveChannelFilter.group(group))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(channelFilterTitle(channelFilter), systemImage: "chevron.up.chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()
                .accessibilityLabel("Category")
            }
            panelDivider

            let channels = filteredChannels
            if channels.isEmpty {
                Text(live.channels.isEmpty ? "No channels are loaded." : "No channels in this category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                let now = Date()
                ForEach(channels) { channel in
                    channelRow(channel, at: now)
                }
            }
        }
    }

    private func channelRow(_ channel: LiveTVChannel, at date: Date) -> some View {
        let isCurrent = channel.id == currentChannel?.id
        let isSwitching = channel.id == switchingChannelID
        let program = LiveTVGuideMatcher.nowAndNext(in: live.programs(for: channel), at: date).now

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                activePanel = nil
            }
            guard !isCurrent else { return }
            switchChannel(to: channel)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Color.white.opacity(0.08)
                    if let logoURL = channel.logoURL {
                        LiveTVLogoImage(url: logoURL, size: CGSize(width: 80, height: 48)) {
                            Image(systemName: "play.tv")
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(8)
                    } else {
                        Image(systemName: "play.tv")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 96, height: 64)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .center) {
                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(.black.opacity(0.55), in: Circle())
                    } else if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.headline)
                            .padding(8)
                            .background(.black.opacity(0.55), in: Circle())
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.headline)
                            .lineLimit(1)
                        if live.isFavorite(channel) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Favorite")
                        }
                    }
                    if let program {
                        Text(program.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressView(value: program.progress(at: date))
                            .progressViewStyle(.linear)
                            .tint(display.accentColor)
                            .accessibilityHidden(true)
                    } else if let group = channel.group {
                        Text(group)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
        .disabled(switchingChannelID != nil)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Now playing" : "")
        .accessibilityHint(isCurrent ? "" : "Switches to this channel")
    }

    /// Channel up and down, through the whole list.
    private func stepChannel(by offset: Int) {
        guard let currentChannel, let next = live.channel(after: currentChannel, offset: offset) else { return }
        switchChannel(to: next)
    }

    private func switchChannel(to channel: LiveTVChannel) {
        guard switchingChannelID == nil else { return }
        switchingChannelID = channel.id
        let preferences = settings.preferences
        Task {
            defer { switchingChannelID = nil }
            do {
                try await live.play(channel, in: playback, preferences: preferences)
            } catch {
                showChannelNotice(
                    (error as? LocalizedError)?.errorDescription ?? "\(channel.name) couldn't be started."
                )
            }
        }
    }

    private func showChannelNotice(_ text: String) {
        channelNoticeTask?.cancel()
        channelNotice = text
        channelNoticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            channelNotice = nil
        }
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
                navigationRow("Sync", detail: subtitleDelayTitle) {
                    subtitlePage = .sync
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
                        get: { playback.subtitleStyle.height },
                        set: { playback.setSubtitlePosition(100 - $0) }
                    ),
                    range: 0 ... 100,
                    valueText: "\(Int(playback.subtitleStyle.height.rounded()))"
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
        case .sync:
            subtitleSyncPage
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
                .frame(width: isPhone ? 44 : 42, height: isPhone ? 44 : 42)
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
                .frame(width: isPhone ? 44 : 42, height: isPhone ? 44 : 42)
                .contentShape(Circle())
        }
        .playbackCircleGlassButton()
        .accessibilityLabel(label)
        .disabled(playback.isPictureInPictureActive)
        .accessibilityValue(activePanel == panel ? "Expanded" : "Collapsed")
        .help(label)
    }

    @ViewBuilder
    private func playbackAction(_ action: MacPlaybackAction) -> some View {
        switch action {
        case .sources:
            circleButton(
                symbol: "rectangle.stack.badge.play",
                label: "Sources",
                hint: "Choose another source for what's playing",
                action: showSources
            )
        case .episodes:
            optionButton(.episodes, symbol: "list.and.film", label: "Episodes")
        case .channels:
            optionButton(.channels, symbol: "play.tv", label: "Channels")
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
                .tint(display.accentColor)
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

    private var subtitleDelayTitle: String {
        let delay = playback.subtitleStyle.delaySeconds
        return abs(delay) < 0.05 ? "In sync" : String(format: "%+.1f s", delay)
    }

    /// Nuvio Enhanced's subtitle sync tools: a delay slider, automatic sync,
    /// Sync by Ear and picking the line just heard.
    @ViewBuilder
    private var subtitleSyncPage: some View {
        #if OMNIA_MPV
        LazyVStack(alignment: .leading, spacing: 14) {
            panelTitle("Sync", detail: subtitleDelayTitle, backTo: .overview)
            panelDivider
            styleSlider(
                "Subtitle Delay",
                value: Binding(
                    get: { min(max(playback.subtitleStyle.delaySeconds, -10), 10) },
                    set: { playback.setSubtitleDelay(($0 * 10).rounded() / 10) }
                ),
                range: -10 ... 10,
                valueText: String(format: "%+.1f s", playback.subtitleStyle.delaySeconds)
            )
            MacSubtitleSyncTools(playback: playback, accentColor: display.accentColor)
        }
        #else
        Text("Subtitle synchronization requires native playback.")
            .font(.callout)
            .padding()
        #endif
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
        case .channels:
            // Channel rows are about one and a half standard rows tall.
            return MacPlaybackPanelLayout.idealHeight(
                rowCount: max(1, filteredChannels.count) * 3 / 2,
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
                    navigationRowCount: 3,
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
            case .sync:
                return MacPlaybackPanelLayout.idealHeight(
                    rowCount: 13,
                    navigationRowCount: 0,
                    sliderCount: 1,
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

/// The sync controls below the delay slider. Their own view, so what they
/// remember between presses (Heard, Saw, the captured moment) redraws them.
#if OMNIA_MPV
private struct MacSubtitleSyncTools: View {
    let playback: PlaybackSession
    let accentColor: Color

    /// Sync by Ear: when the line was heard and when its subtitle showed.
    @State private var heardAt: Double?
    @State private var sawAt: Double?
    /// Pick the Line: the moment captured and the lines around it.
    @State private var lineCaptureTime: Double?
    @State private var lineChoices: [SubtitleCue] = []
    @State private var lineCaptureProblem: String?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                syncPill("−0.1 s") { playback.setSubtitleDelay(playback.subtitleStyle.delaySeconds - 0.1) }
                syncPill("Reset") { playback.setSubtitleDelay(0) }
                    .disabled(playback.subtitleStyle.delaySeconds == 0)
                syncPill("+0.1 s") { playback.setSubtitleDelay(playback.subtitleStyle.delaySeconds + 0.1) }
            }
            .padding(.horizontal, 10)
            Text("A positive delay shows subtitles later. Use it when they appear before the speech.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            divider
            syncSectionTitle("Auto Sync", symbol: "waveform")
            automaticSyncControls
                .padding(.horizontal, 10)

            divider
            syncSectionTitle("Sync by Ear", symbol: "ear")
            Text(syncByEarHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            HStack(spacing: 8) {
                syncPill("Heard", symbol: "ear", isActive: heardAt != nil) { markSyncByEar(heard: true) }
                syncPill("Saw", symbol: "eye", isActive: sawAt != nil) { markSyncByEar(heard: false) }
            }
            .padding(.horizontal, 10)

            divider
            syncSectionTitle("Pick the Line", symbol: "text.bubble")
            Text("Press when you hear a line, then choose that line below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            syncPill("I Just Heard a Line", symbol: "hand.tap") { captureHeardLine() }
                .padding(.horizontal, 10)
            if let lineCaptureProblem {
                Text(lineCaptureProblem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            ForEach(Array(lineChoices.enumerated()), id: \.offset) { _, cue in
                Button {
                    if let lineCaptureTime {
                        playback.setSubtitleDelay(lineCaptureTime - cue.startSeconds)
                    }
                    lineChoices = []
                    lineCaptureTime = nil
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cue.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(timeTitle(cue.startSeconds + playback.subtitleStyle.delaySeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .omniaMenuRowButton()
            }
        }
    }

    private var divider: some View {
        Divider().overlay(.white.opacity(0.12))
    }

    @ViewBuilder
    private var automaticSyncControls: some View {
        switch playback.subtitleSyncStatus {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                Text("Listens to the speech while you watch, for up to three minutes, then lines the subtitle up with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                syncPill("Sync Automatically", symbol: "wand.and.stars") { playback.startAutomaticSubtitleSync() }
            }
        case let .listening(progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(accentColor)
                HStack {
                    Text(playback.isPaused ? "Paused. Listening resumes when you play." : "Listening to the speech…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    syncPill("Cancel") { playback.cancelAutomaticSubtitleSync() }
                }
            }
        case let .synced(delay):
            HStack {
                Label(
                    abs(delay) < 0.05 ? "Already in sync" : String(format: "Synced, %+.1f s", delay),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline)
                Spacer()
                syncPill("Again") { playback.startAutomaticSubtitleSync() }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                syncPill("Try Again", symbol: "arrow.clockwise") { playback.startAutomaticSubtitleSync() }
            }
        }
    }

    private var syncByEarHint: String {
        if heardAt != nil { return "Heard captured. Press Saw when its subtitle shows." }
        if sawAt != nil { return "Saw captured. Press Heard when you hear the line." }
        return "Press Heard when you hear a line and Saw when its subtitle shows, in either order."
    }

    private func markSyncByEar(heard: Bool) {
        let now = playback.positionSeconds
        if heard { heardAt = now } else { sawAt = now }
        guard let heardAt, let sawAt else { return }
        self.heardAt = nil
        self.sawAt = nil
        // Taps far apart are two different lines, not one late subtitle.
        guard abs(heardAt - sawAt) <= 20 else { return }
        playback.setSubtitleDelay(playback.subtitleStyle.delaySeconds + heardAt - sawAt)
    }

    private func captureHeardLine() {
        let captured = playback.positionSeconds
        lineCaptureTime = captured
        lineCaptureProblem = nil
        lineChoices = []
        Task {
            do {
                let cues = try await playback.selectedSubtitleCues()
                // Lines that, as currently timed, show within 20 seconds of
                // the moment, nearest first.
                let delay = playback.subtitleStyle.delaySeconds
                let nearby = cues
                    .filter { !$0.text.isEmpty && abs($0.startSeconds + delay - captured) <= 20 }
                    .sorted { abs($0.startSeconds + delay - captured) < abs($1.startSeconds + delay - captured) }
                    .prefix(8)
                lineChoices = nearby.sorted { $0.startSeconds < $1.startSeconds }
                if lineChoices.isEmpty {
                    lineCaptureProblem = "No lines near this moment. Try again on another line."
                }
            } catch {
                lineCaptureProblem = error.localizedDescription
            }
        }
    }

    private func timeTitle(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3_600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    private func syncSectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
    }

    private func syncPill(
        _ title: String,
        symbol: String? = nil,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(isActive ? accentColor.opacity(0.45) : .white.opacity(0.12))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#endif

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
