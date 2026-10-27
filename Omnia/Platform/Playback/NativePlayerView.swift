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
import UIKit

#if OMNIA_MPV
final class PlaybackVideoHostView: UIView {
    weak var player: OMMpvPlayerController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }
}

/// Hosts the view libmpv draws into with Metal, as on the Mac. SwiftUI owns
/// the controls above it.
struct NativePlayerView: UIViewRepresentable {
    let player: OMMpvPlayerController

    func makeUIView(context: Context) -> PlaybackVideoHostView {
        let view = PlaybackVideoHostView()
        view.player = player
        player.attachVideoView(toHost: view)
        DispatchQueue.main.async {
            player.startIfNeeded()
        }
        return view
    }

    func updateUIView(_ view: PlaybackVideoHostView, context: Context) {
        view.player = player
        if player.videoView.superview !== view {
            player.attachVideoView(toHost: view)
        }
        player.startIfNeeded()
    }

    static func dismantleUIView(_ view: PlaybackVideoHostView, coordinator: ()) {
        view.player?.detachVideoView(fromHost: view)
        view.player = nil
    }
}
#endif

/// AVPlayer playback: builds without libmpv, and sources mpv couldn't draw.
struct AVPlaybackView: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
            .background(.black)
    }
}

#if !OMNIA_MPV
typealias NativePlayerView = AVPlaybackView
#endif
#endif
