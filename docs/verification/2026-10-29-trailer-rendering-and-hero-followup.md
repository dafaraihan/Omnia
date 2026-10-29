# Trailer rendering and hero follow-up — 2026-10-29

User regression steps: play a Home/detail hero trailer, tap the artwork, observe fullscreen controls/time advancing over black video on iPhone Simulator. The supplied screenshot shows the failure at 0:09. Then inspect portrait hero ratings (previously leading-aligned).

Source trace: startTrailer configures IOSPictureInPictureController and PlaybackExperienceView relies on its AVPlayerLayer for iOS inline rendering. attach returned before assigning layer.player whenever isPictureInPictureSupported was false. The renderer now attaches the player regardless of PiP support; only PiP controller creation is guarded. This preserves the existing single-layer ownership and fixes the demonstrated unsupported-PiP rendering path without adding another player.

At user request, removed hero identity opacity, hit-testing and accessibility suppression and restored Home carousel dots on all platforms. Background trailer tap-to-open remains. MDBListRatingsView now accepts a default-leading alignment; only the two portrait hero call sites opt into centered wrapping. Existing landscape ratings/layout callers retain their alignment.

Validation: canonical generic iOS Simulator Debug and macOS Debug builds returned BUILD SUCCEEDED. git diff --check passed. Latest Simulator app installed/launched. No test suites/scripts/fixtures added or run. Obsolete Mac app product removed after validation, retaining exactly one canonical current Simulator app.

Interactive Device Hub capture failed again with ScreenCaptureKit SCStreamErrorDomain -3811. Visual trailer rendering, centered wrapping, accessibility, hero action/tap coexistence, supported/unsupported PiP transitions and physical iPhone/iPad/Mac playback remain manual acceptance checks; build success alone does not establish those outcomes. No hosted changes, release publication or dependencies.

References: Apple AVPictureInPictureController isPictureInPictureSupported documentation and HIG Layout, reviewed for platform availability and adaptive layout. This follow-up supersedes the previous requirement to hide hero identity while playing.
