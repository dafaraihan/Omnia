//
//  NativePlayerView.swift
//  Omnia
//

import SwiftUI

#if os(macOS)
import AppKit

final class PlaybackVideoHostView: NSView {
    weak var player: OMMpvPlayerController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Hosts the native NSView that libmpv attaches its video output to. SwiftUI
/// intentionally owns the controls above it, leaving the decoder/rendering
/// stack isolated to libmpv.
struct NativePlayerView: NSViewRepresentable {
    let player: OMMpvPlayerController

    func makeNSView(context: Context) -> PlaybackVideoHostView {
        let view = PlaybackVideoHostView()
        view.player = player
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        player.attachVideoView(toHost: view)
        DispatchQueue.main.async {
            player.startIfNeeded()
        }
        return view
    }

    func updateNSView(_ view: PlaybackVideoHostView, context: Context) {
        view.player = player
        if player.videoView.superview !== view {
            player.attachVideoView(toHost: view)
        }
        player.startIfNeeded()
    }

    static func dismantleNSView(_ view: PlaybackVideoHostView, coordinator: ()) {
        view.player?.detachVideoView(fromHost: view)
        view.player = nil
    }
}
#else
import AVKit

/// libmpv is macOS-only in Omnia; this keeps the iPhone/iPad target usable
/// until an iOS libmpv distribution is deliberately bundled.
struct NativePlayerView: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
            .background(.black)
    }
}
#endif
