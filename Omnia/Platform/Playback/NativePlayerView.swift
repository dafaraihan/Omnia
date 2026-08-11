//
//  NativePlayerView.swift
//  Omnia
//

import SwiftUI

#if os(macOS)
import AppKit

/// Hosts the native NSView that libmpv attaches its video output to. SwiftUI
/// intentionally owns the controls above it, leaving the decoder/rendering
/// stack isolated to libmpv.
struct NativePlayerView: NSViewRepresentable {
    let player: OMMpvPlayerController

    func makeNSView(context: Context) -> NSView {
        let view = player.videoView
        DispatchQueue.main.async {
            player.startIfNeeded()
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        player.startIfNeeded()
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
