# iOS playback improvements

Approved in chat: adapt iPhone landscape controls; place gesture feedback at top center with volume and brightness percentages; use device volume; add a PiP button and Home-gesture PiP; enable adaptive icons; build, review, and commit.

Preserve macOS behavior and existing playback engines. Use Apple AVKit for PiP and MediaPlayer for device volume. Native Metal rendering needs an AVPlayer handoff for AVFoundation-compatible sources; unsupported formats must leave inline playback intact. Do not use private APIs or introduce dependencies. Device-only PiP, volume, appearance, and accessibility checks remain explicit release evidence.
