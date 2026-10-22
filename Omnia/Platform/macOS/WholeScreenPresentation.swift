//
//  WholeScreenPresentation.swift
//  Omnia
//

#if os(macOS)
import AppKit

/// Omnia's own full screen for the player (Settings › Video Player › Use
/// Whole Screen). macOS's full screen keeps the strip beside the camera notch
/// black, so this makes the window borderless and as large as the screen,
/// with the menu bar and Dock hidden until the pointer reaches them. Leaving
/// puts the window back exactly as it was. It stays in the current Space.
@MainActor
final class WholeScreenPresentation {
    private struct SavedWindow {
        let frame: NSRect
        let styleMask: NSWindow.StyleMask
        let level: NSWindow.Level
        let hasShadow: Bool
        let presentationOptions: NSApplication.PresentationOptions
    }

    private weak var window: NSWindow?
    private var saved: SavedWindow?

    var isActive: Bool { saved != nil }

    func enter(_ window: NSWindow) {
        guard saved == nil, let screen = window.screen ?? NSScreen.main else { return }
        saved = SavedWindow(
            frame: window.frame,
            styleMask: window.styleMask,
            level: window.level,
            hasShadow: window.hasShadow,
            presentationOptions: NSApp.presentationOptions
        )
        self.window = window
        NSApp.presentationOptions.formUnion([.autoHideMenuBar, .autoHideDock])
        // Only the title bar goes: a window keeps becoming key, so the
        // keyboard shortcuts keep working, only while it has a title bar or
        // can be resized.
        window.styleMask.remove(.titled)
        window.styleMask.insert(.fullSizeContentView)
        window.hasShadow = false
        window.level = .normal
        window.setFrame(screen.frame, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
    }

    func leave() {
        guard let saved else { return }
        self.saved = nil
        NSApp.presentationOptions = saved.presentationOptions
        guard let window else { return }
        window.styleMask = saved.styleMask
        window.hasShadow = saved.hasShadow
        window.level = saved.level
        window.setFrame(saved.frame, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        self.window = nil
    }
}
#endif
