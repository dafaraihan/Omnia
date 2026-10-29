# Verification — 2026-10-29

Implemented the seven requested changes under the approved Nuvio matching design, retaining Apple system typography. User screenshots and source inspection established the missing portrait ratings slot; both iPhone hero call sites now use existing MDBList state/recovery UI. See the design, plan and pinned-source research in the adjacent documentation folders.

macOS Debug and generic iOS Simulator Debug builds both returned BUILD SUCCEEDED using canonical DerivedData. git diff --check passed. Independent diff review identified preview/carousel ownership during fullscreen playback; presentation/player/scene gates were corrected before the final builds. No automated tests, fixtures or scripts were added or run.

Simulator installation/launch completed. A captured framebuffer showed a landscape player at 0:01, which alone does not prove rotation timing or video rendering. Device Hub capture failed with ScreenCaptureKit SCStreamErrorDomain -3811; interactive flow acceptance could not be completed.

TMDB uses stable external IDs and isolated optional failures. TVDB defaults off, offers supported enrichment modules, and bounds traversal to 30 seasons and 500 episodes per season. Provider responses are capped at 8 MiB with cancellation and request/resource timeouts. Enrichment preserves source/history identity and episode source dates. No new dependencies, secrets or hosted mutations were introduced.

Trailer playback uses explicit purpose/history isolation and AVFoundation to preserve generated HLS master/audio information. Mac trailer PiP is unavailable. Continue Watching badges reflect existing progress/air-date data; synthetic New Episode/New Season flags were not introduced.

Pending manual acceptance: authenticated provider success/empty/offline/partial failures; iPhone loading rotation, dismissal/orientation restore and PiP on hardware; iPad multitasking; Mac resizing/fullscreen; trailer audio, handoff/end/error restoration and history isolation; Card sizes/spoilers/next-up; VoiceOver, Dynamic Type, keyboard/focus, Reduce Motion/Transparency, contrast and light/dark appearance. No performance claim is made. Packaging/publication is outside this change.

Commands:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Obsolete canonical Mac app products were removed after validation; the latest Simulator app is retained as the single current build.
