# iOS subtitle settings and loading-close follow-up

User evidence: iPhone/iPad subtitle settings differ from macOS; supplied iPad screenshot shows the player stuck at Opening stream with a close button that does not dismiss it.

Source baseline: `SubtitleAppearanceSettingsView` selects a legacy preset/custom form on iOS and the newer complete playback-style form on macOS. The loading close button is 34 points and precedes later overlays; `PlaybackSession.stop` refreshes synchronous native-player properties before teardown, including while no frame has rendered. Interactive reproduction is unavailable because Device Hub screen capture fails and the simulators are shut down.

Implementation: share the Mac's language/font/style/text controls, bindings, live preview, and reset behavior across iOS and macOS; keep native platform forms and size the phone preview to its viewport. Put the loading-close affordance last in the overlay order with a 44-point touch target. Avoid refreshing the native player to persist progress before a first frame exists. On iOS, enqueue loadfile asynchronously, consume its command error reply, and defer native polling/track-property reads until FILE_LOADED. Initial iOS Metal layout/crop callbacks also wait for FILE_LOADED before querying the core. These address the source-level main-thread wait path; interactive confirmation remains pending.

Regression checks: open Settings > Subtitle on iPhone, iPad, and Mac; compare section/control availability, language selections, color/font/style persistence, preview, and reset/cancel. Open a slow source and tap the visible close button during Opening stream; dismissal must not wait for the first frame. Reopen another source and confirm the old session does not return. Repeat after rendered playback to verify progress still saves.

Build and runtime results will be recorded after implementation. IPA packaging remains on hold at the user's request.

Independent review found no confirmed important defects and identified loading-time Metal layout callbacks as an additional risk; those callbacks are now guarded before FILE_LOADED as well.

## Final local evidence

- iOS Simulator build: **BUILD SUCCEEDED**, including the final asynchronous load and loading-query guards.
- macOS build: **BUILD SUCCEEDED** after the final native-controller edits. Mac loading behavior remains behind its existing platform branch.
- `git diff --check`: passed.
- Updated app installed and launched on iPad Pro 11-inch (M5), iPadOS 26.5 Simulator. Device Hub accessibility confirms the app's Home screen.
- Device Hub later exposed accessibility, but its custom tab controls were not individually exposed and its screenshot surface returned only a small perspective thumbnail. The subtitle-page and loading-close tap flows were not reliably automated. The manual regression checks above therefore remain pending.
- No automated tests, suites, fixtures, or test scripts were created or run.
- IPA packaging is still paused; the earlier device build finished but no IPA was packaged. Obsolete device/Mac products are removed at handoff, retaining the current canonical simulator product.
