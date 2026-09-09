#if os(macOS)
import AppKit
import SwiftUI

/// Keeps macOS navigation chrome transparent while preserving native window
/// and navigation titles. Individual screens still own their content artwork.
struct WindowChrome: NSViewRepresentable {
    let isPlaybackPresented: Bool

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView(frame: .zero)
        view.updatePlaybackPresentation(isPresented: isPlaybackPresented)
        return view
    }

    func updateNSView(_ view: WindowChromeView, context: Context) {
        view.updatePlaybackPresentation(isPresented: isPlaybackPresented)
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowChrome()
    }

    func updatePlaybackPresentation(isPresented: Bool) {
        let shouldRestoreAfterToolbarTransition = restorationState.update(
            isPlaybackPresented: isPresented
        )
        applyWindowChrome()

        guard shouldRestoreAfterToolbarTransition else { return }
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
        window.toolbar?.showsBaselineSeparator = false
    }
}
#endif
