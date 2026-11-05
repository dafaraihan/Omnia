#if os(macOS)
import AppKit
import SwiftUI

/// Keeps macOS navigation chrome transparent while preserving native window
/// and navigation titles. Individual screens still own their content artwork.
struct WindowChrome: NSViewRepresentable {
    let isPlaybackPresented: Bool
    let isExclusiveFullScreen: Bool

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView(frame: .zero)
        view.updatePlaybackPresentation(
            isPresented: isPlaybackPresented,
            isExclusiveFullScreen: isExclusiveFullScreen
        )
        return view
    }

    func updateNSView(_ view: WindowChromeView, context: Context) {
        view.updatePlaybackPresentation(
            isPresented: isPlaybackPresented,
            isExclusiveFullScreen: isExclusiveFullScreen
        )
    }
}

enum WindowChromePresentation {
    static let hidesToolbarDuringPlayback = true
    static let hidesToolbarBackgroundDuringBrowsing = true
}

struct WindowChromeRestorationState {
    private var wasPlaybackPresented: Bool?

    mutating func update(isPlaybackPresented: Bool) -> Bool {
        defer { wasPlaybackPresented = isPlaybackPresented }
        return wasPlaybackPresented == true && !isPlaybackPresented
    }
}

final class WindowChromeView: NSView {
    private var restorationState = WindowChromeRestorationState()
    private var restorationTask: Task<Void, Never>?
    private var isPlaybackPresented = false
    private var isExclusiveFullScreen = false
    private weak var suppressedTitlebarHitLayer: NSView?
    private var titlebarHitLayerWasHidden = false
    private weak var suppressedTitlebarWindow: NSWindow?
    private var titlebarWindowIgnoredMouseEvents = false
    private var optionsBeforeHidingMenuBar: NSApplication.PresentationOptions?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            restoreTitlebarHitLayer()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowChrome()
    }

    func updatePlaybackPresentation(
        isPresented: Bool,
        isExclusiveFullScreen: Bool
    ) {
        let didChangeFullScreenPresentation = self.isExclusiveFullScreen != isExclusiveFullScreen
        self.isPlaybackPresented = isPresented
        self.isExclusiveFullScreen = isExclusiveFullScreen
        let shouldRestoreAfterToolbarTransition = restorationState.update(
            isPlaybackPresented: isPresented
        )
        applyWindowChrome()

        guard shouldRestoreAfterToolbarTransition || didChangeFullScreenPresentation else { return }
        restorationTask?.cancel()
        restorationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.applyWindowChrome()

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.applyWindowChrome()
        }
    }

    func applyWindowChrome() {
        guard let window else { return }

        // Applying in `viewDidMoveToWindow` matters: SwiftUI may create this
        // representable before it is attached to a window.
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        updateTitlebarHitLayer(in: window)
        updateMenuBarVisibility(in: window)
    }

    /// A full-screen Space follows the system's menu bar setting, which can
    /// leave the bar on screen. Playback hides it and the Dock outright; every
    /// keyboard shortcut still works. Whole Screen keeps its own options.
    private func updateMenuBarVisibility(in window: NSWindow) {
        let isSpace = window.styleMask.contains(.fullScreen)
        if isPlaybackPresented, isExclusiveFullScreen, isSpace {
            guard optionsBeforeHidingMenuBar == nil else { return }
            let current = NSApp.presentationOptions
            optionsBeforeHidingMenuBar = current
            // Auto-hiding the toolbar is only valid with an auto-hiding menu
            // bar, and AppKit raises on an invalid set, so it isn't carried over.
            NSApp.presentationOptions = current.intersection(.fullScreen).union([.hideDock, .hideMenuBar])
        } else if let saved = optionsBeforeHidingMenuBar {
            optionsBeforeHidingMenuBar = nil
            // Out of the Space, the saved full-screen options no longer apply.
            NSApp.presentationOptions = isSpace ? saved : []
        }
    }

    private func updateTitlebarHitLayer(in window: NSWindow) {
        guard isPlaybackPresented && isExclusiveFullScreen else {
            restoreTitlebarHitLayer()
            return
        }
        suppressFullScreenTitlebarWindow(of: window)
        guard let titlebarHitLayer = fullScreenTitlebarHitLayer(in: window) else {
            return
        }

        if suppressedTitlebarHitLayer !== titlebarHitLayer {
            restoreTitlebarHitLayer()
            suppressedTitlebarHitLayer = titlebarHitLayer
            titlebarHitLayerWasHidden = titlebarHitLayer.isHidden
        }
        titlebarHitLayer.isHidden = true
    }

    private func fullScreenTitlebarHitLayer(in window: NSWindow) -> NSView? {
        guard let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview else {
            return nil
        }

        // In an exclusive full-screen Space, AppKit wraps the ordinary
        // titlebar container in a shallow full-screen toolbar view. Hiding only
        // the inner container leaves that transparent parent intercepting the
        // playback controls beneath it. Never select the full window frame.
        guard let parent = titlebarContainer.superview,
              parent.bounds.height <= 160
        else {
            return titlebarContainer
        }
        return parent
    }

    /// In a full-screen Space the titlebar and toolbar move into their own
    /// borderless window (`NSToolbarFullScreenWindow`) layered above the
    /// content window. Hiding views inside it isn't enough: the window itself
    /// still takes every click in its frame, which is where the player's close,
    /// PiP, full-screen, aspect and volume controls sit. Let clicks pass
    /// through it while full-screen playback is on screen.
    private func suppressFullScreenTitlebarWindow(of window: NSWindow) {
        guard let titlebarWindow = window.standardWindowButton(.closeButton)?.window,
              titlebarWindow !== window
        else { return }

        if suppressedTitlebarWindow !== titlebarWindow {
            restoreTitlebarWindow()
            suppressedTitlebarWindow = titlebarWindow
            titlebarWindowIgnoredMouseEvents = titlebarWindow.ignoresMouseEvents
        }
        titlebarWindow.ignoresMouseEvents = true
    }

    private func restoreTitlebarWindow() {
        suppressedTitlebarWindow?.ignoresMouseEvents = titlebarWindowIgnoredMouseEvents
        suppressedTitlebarWindow = nil
        titlebarWindowIgnoredMouseEvents = false
    }

    private func restoreTitlebarHitLayer() {
        restoreTitlebarWindow()
        suppressedTitlebarHitLayer?.isHidden = titlebarHitLayerWasHidden
        suppressedTitlebarHitLayer = nil
        titlebarHitLayerWasHidden = false
    }
}

/// Reports whether the view's window can be seen: false while it is
/// minimized, hidden, on another Space or fully covered. Decorative video
/// and timers pause then, since nobody can see them.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> WindowVisibilityView {
        let view = WindowVisibilityView(frame: .zero)
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ view: WindowVisibilityView, context: Context) {
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
    }
}

final class WindowVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.report() }
        }
        report()
    }

    private func report() {
        guard let window else { return }
        onChange?(window.occlusionState.contains(.visible))
    }
}
#endif
