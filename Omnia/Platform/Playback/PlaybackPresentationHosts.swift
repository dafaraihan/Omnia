import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

/// The presented controller owns the phone orientation mask for its whole
/// lifetime, including loading and source replacement.
struct PhonePlaybackPresentation: UIViewControllerRepresentable {
    let content: AnyView
    func makeUIViewController(context: Context) -> Controller { Controller(rootView: AnyView(content.environment(\.self, context.environment))) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.rootView = AnyView(content.environment(\.self, context.environment))
    }
    final class Controller: UIHostingController<AnyView> {
        private weak var playbackScene: UIWindowScene?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard UIDevice.current.userInterfaceIdiom == .phone,
                  let scene = view.window?.windowScene else { return }
            playbackScene = scene
            setNeedsUpdateOfSupportedInterfaceOrientations()
            // Retry after presentation, when this controller owns the mask.
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if let playbackScene {
                PhonePlaybackOrientationState.shared.restoreIfDismissed(in: playbackScene)
            }
        }

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            UIDevice.current.userInterfaceIdiom == .phone ? .landscape : .all
        }
    }
}

/// Lives in the presenting scene, so replacing a source or entering PiP does
/// not release orientation. Only dismissal releases the scene request.
struct PhonePlaybackOrientationHost: UIViewRepresentable {
    let isPresented: Bool

    func makeUIView(context: Context) -> HostView { HostView() }
    func updateUIView(_ view: HostView, context: Context) {
        view.isPresented = isPresented
        view.updateOrientation()
    }

    final class HostView: UIView {
        var isPresented = false
        private var appliedPresentation = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateOrientation()
        }
        func updateOrientation() {
            guard UIDevice.current.userInterfaceIdiom == .phone,
                  let scene = window?.windowScene,
                  appliedPresentation != isPresented else { return }
            appliedPresentation = isPresented
            if isPresented {
                PhonePlaybackOrientationState.shared.begin(in: scene)
            } else {
                PhonePlaybackOrientationState.shared.end(in: scene)
            }
        }
    }
}

/// Saves only the affected scene's interface orientation. No request is made
/// when the root first appears without a player.
@MainActor
private final class PhonePlaybackOrientationState {
    static let shared = PhonePlaybackOrientationState()
    private struct Entry {
        let orientation: UIInterfaceOrientationMask
        var isDismissing = false
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func begin(in scene: UIWindowScene) {
        let orientation: UIInterfaceOrientationMask
        switch scene.interfaceOrientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        default: orientation = .portrait
        }
        entries[ObjectIdentifier(scene)] = Entry(orientation: orientation)
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
    }

    func end(in scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        guard entries[key] != nil else { return }
        entries[key]?.isDismissing = true
        if scene.keyWindow?.rootViewController?.presentedViewController == nil {
            restoreIfDismissed(in: scene)
        }
    }

    func restoreIfDismissed(in scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        guard let entry = entries[key], entry.isDismissing else { return }
        entries[key] = nil
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: entry.orientation)) { _ in }
    }
}

#elseif os(macOS)
import AppKit

/// The same AVPlayerLayer surface used by hero previews, with normal player
/// chrome supplied by PlaybackExperienceView rather than a second AVKit UI.
struct TrailerPlaybackSurface: NSViewRepresentable {
    let player: AVPlayer
    let fillsFrame: Bool
    func makeNSView(context: Context) -> TrailerVideoView { TrailerVideoView() }
    func updateNSView(_ view: TrailerVideoView, context: Context) {
        view.videoLayer.player = player
        view.videoLayer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
    }
    static func dismantleNSView(_ view: TrailerVideoView, coordinator: ()) {
        view.videoLayer.player = nil
    }
}
#endif
