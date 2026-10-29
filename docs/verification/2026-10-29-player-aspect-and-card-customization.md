# Player aspect and card customization — 2026-10-29

## Requested behavior and diagnosis

User reproduction: play a hero trailer fullscreen on iPhone/iPad, change Original/Fill, try PiP button, swipe Home. Screenshots show visible video but unchanged aspect and no floating video after Home. Source showed cycleAspectRatio drove mpv only; iOS AVPlayerLayer remained resizeAspect. The video host now observes aspectRatioMode and applies resizeAspect/resizeAspectFill on make/update, filling the same safe-area canvas as playback.

Runtime capability evidence on the booted iPhone 17 Pro Max iOS 26.5 Simulator: attached Xcode LLDB to Omnia and evaluated `(BOOL)[(Class)NSClassFromString(@"AVPictureInPictureController") isPictureInPictureSupported]`; returned `(BOOL) NO`, then detached. Consequently this simulator cannot exercise manual or automatic PiP. No fake PiP implementation or speculative workaround was added. Source audit found active playback audio category, background audio mode, retained AVKit controller/layer and automatic inline PiP already configured. Physical supported iPhone/iPad verification is still required, including system automatic PiP enabled, manual enter/restore and swipe Home. The native mpv handoff still requires an AVFoundation-compatible source without arbitrary headers.

Apple references: https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller and https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player .

## Card implementation

Rechecked the pinned official Nuvio clone and research note. Card keeps 1.77 landscape ratio, Nuvio-derived width/insets, lower theme gradient, episode/title/subtitle overlay and top-right badge; Apple native fonts remain. Removed extra bottom text inset and rounded progress track/fill as in the reference. No synthetic release-alert badges were added. The existing Wide/Poster alternatives and saved style selection remain intact.

Continue Watching settings now have independent size and corners below Card Style, including Match Poster Card Style. Style Default decodes absent keys and preserves existing geometry; matching resolves dynamically from current poster preferences. Card/Wide/Poster tile and live previews use actual ContinueWatchingCard rendering with local representative preview data and no remote requests/actions. Full-size preview uses intrinsic height to accommodate Dynamic Type rather than a fixed label allowance.

Collection shape/size/corners offer Match Poster Card Style; existing stored choices decode unchanged. Folder names remain independent because poster style has no equivalent. Collection preview scrolls horizontally and respects Reduce Motion. Library expanded Continue Watching grids now calculate columns using configured card width and cap cards to the available column on narrow windows, preventing large custom cards from overlapping.

## Validation and remaining acceptance

No tests, test scripts, fixtures, dependencies, signing changes, secrets, hosted mutations or release publication. Independent diff review caught fixed-height live preview clipping with accessibility text sizes; corrected before final builds. Source-level Nuvio comparison is not a claim of runtime pixel parity.

Final canonical generic iOS Simulator Debug and macOS Debug builds both returned BUILD SUCCEEDED. git diff --check passed. Obsolete Mac app product removed after verification, leaving one current canonical Simulator app. Manual acceptance remains: iPhone/iPad Original/Fill, supported-device PiP enter/restore/background transitions, live card size/corner switching and dynamic poster inheritance, expanded Library grids at narrow/large widths, Mac/iPad pointer/keyboard, VoiceOver, accessibility text sizes, light/dark, contrast, transparency and motion settings. Device Hub capture has repeatedly failed in this session with SCStreamErrorDomain -3811, so interactive UI acceptance is not claimed.
