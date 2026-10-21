import SwiftUI
import WebKit

/// A YouTube trailer played through YouTube's official IFrame player in a
/// web view, cropped to fill its frame with no controls. Omnia does not
/// extract YouTube streams, so trailers play only through YouTube's player.
struct YouTubeTrailerPlayer {
    enum Event { case playing, ended, failed }

    let videoID: String
    var isMuted: Bool
    var isPlaying: Bool
    let onEvent: (Event) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    fileprivate func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #endif
        context.coordinator.isMuted = isMuted
        context.coordinator.isPlaying = isPlaying
        webView.loadHTMLString(html, baseURL: Coordinator.pageURL)
        return webView
    }

    fileprivate func update(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEvent = onEvent
        if coordinator.isMuted != isMuted {
            coordinator.isMuted = isMuted
            webView.evaluateJavaScript(isMuted ? "player && player.mute()" : "player && player.unMute()")
        }
        if coordinator.isPlaying != isPlaying {
            coordinator.isPlaying = isPlaying
            webView.evaluateJavaScript(isPlaying ? "player && player.playVideo()" : "player && player.pauseVideo()")
        }
    }

    fileprivate static func dismantle(_ webView: WKWebView) {
        webView.evaluateJavaScript("player && player.stopVideo()")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
        webView.navigationDelegate = nil
    }

    /// `videoID` is validated by `MediaVideo.youtubeVideoID` to letters,
    /// digits, `-` and `_`, so it is safe to place in the script.
    private var html: String {
        let mute = isMuted ? 1 : 0
        let origin = Coordinator.pageURL.absoluteString
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}
        #player{position:absolute;top:50%;left:50%;width:100vw;height:56.25vw;min-width:177.78vh;min-height:100vh;
          transform:translate(-50%,-50%) scale(1.18);pointer-events:none}
        </style></head><body>
        <div id="player"></div>
        <script>
        var player;
        function post(e){window.webkit.messageHandlers.\(Coordinator.messageName).postMessage(e)}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('player',{videoId:'\(videoID)',host:'https://www.youtube-nocookie.com',
            playerVars:{autoplay:1,mute:\(mute),controls:0,disablekb:1,fs:0,iv_load_policy:3,
              modestbranding:1,playsinline:1,rel:0,origin:'\(origin)'},
            events:{
              onReady:function(e){\(isMuted ? "e.target.mute()" : "e.target.unMute()");\(isPlaying ? "e.target.playVideo()" : "")},
              onStateChange:function(e){if(e.data===1)post('playing');if(e.data===0)post('ended')},
              onError:function(){post('failed')}}});
        }
        </script>
        <script src="https://www.youtube.com/iframe_api" onerror="post('failed')"></script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageName = "omniaTrailer"
        /// YouTube's embedded player needs a referring page. The app's own
        /// identifier is used, as YouTube asks of apps that embed it.
        static let pageURL = URL(string: "https://\((Bundle.main.bundleIdentifier ?? "omnia").lowercased()).local/")!

        var onEvent: (Event) -> Void
        var isMuted = false
        var isPlaying = true

        init(onEvent: @escaping (Event) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.body as? String {
            case "playing": onEvent(.playing)
            case "ended": onEvent(.ended)
            case "failed": onEvent(.failed)
            default: break
            }
        }

        /// Only the player page and YouTube's own frames load; links never
        /// open inside the hero.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            if navigationAction.targetFrame?.isMainFrame ?? true {
                let isPlayerPage = url?.host() == Self.pageURL.host() || url?.scheme == "about"
                return isPlayerPage && navigationAction.navigationType == .other ? .allow : .cancel
            }
            let host = url?.host() ?? ""
            let isYouTube = ["youtube.com", "youtube-nocookie.com", "google.com", "googlevideo.com", "ytimg.com", "doubleclick.net"]
                .contains { host == $0 || host.hasSuffix("." + $0) }
            return isYouTube || url?.scheme == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onEvent(.failed)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onEvent(.failed)
        }
    }
}

#if os(macOS)
extension YouTubeTrailerPlayer: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) { dismantle(webView) }
}
#else
extension YouTubeTrailerPlayer: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) { dismantle(webView) }
}
#endif
