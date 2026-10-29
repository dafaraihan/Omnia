# Continue Watching preview correction — 2026-10-29

User screenshot shows actual miniature cards replacing the previous selector illustrations, and a full-size preview anchored at the leading edge. Restored the exact Card/Wide/Poster schematic selector illustrations from commit 903a235. Kept the actual card renderer in a separate ContinueWatchingLivePreview below the selector.

Live preview uses horizontal scroll alignment centering when content fits, allows scrolling when larger than the viewport, and derives height intrinsically for Dynamic Type. It retains hit testing for shared CardDepthModifier onHover, uses current display preferences and the Continue Watching surface for edge/sheen/hover/halo/lift, adds 24-point effect space, and disables scroll clipping. No effects are forcibly enabled against saved preferences. The independent global Glass Glow setting belongs to navigation chrome; card appearance uses the existing shared card effects, matching other card previews.

Validation: generic iOS Simulator Debug and macOS Debug canonical builds; git diff --check. No tests/fixtures/scripts or dependencies added. Full pointer hover, touch/iPad pointer, accessibility and visual acceptance remain manual; no runtime screenshot verification claimed. Obsolete Mac build product removed after validation, retaining the latest Simulator product only. No hosted or release changes.
