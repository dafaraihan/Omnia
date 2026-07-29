#if os(macOS)
import AppKit
import SwiftUI

/// Keeps macOS navigation chrome stable and titleless. Individual screens own
/// their hero artwork; this view never supplies media artwork or layout.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView {
        WindowChromeView(frame: .zero)
    }

    func updateNSView(_ view: WindowChromeView, context: Context) {
        view.applyWindowChrome()
    }
}

final class WindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowChrome()
    }

    func applyWindowChrome() {
        guard let window else { return }

        // Applying in `viewDidMoveToWindow` matters: SwiftUI may create this
        // representable before it is attached to a window. Configuring only
        // in updateNSView can leave the default “Omnia” title visible.
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}
#endif
