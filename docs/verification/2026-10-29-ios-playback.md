# iOS playback verification — 2026-10-29

## Changes and evidence

Source inspection identified whole-player 0.72 scaling, centered gesture HUDs without numeric levels, player-only volume attenuation, iOS PiP stubs, fixed 700-point iOS hero heights, and navigation based only on horizontal size class. These are source findings; the reported landscape defect was not reproduced interactively before editing because Device Hub rotation commands were unavailable through the UI automation surface.

Implementation replaces scaling with phone-sized controls and adaptive rows, keeps phone navigation in landscape, shortens landscape heroes, positions gesture HUDs at top center, displays percentages, and reads brightness from the presenting screen. Device volume is observed through AVAudioSession and set through the hosted MPVolumeView; native/AV players remain at unity gain.

PiP uses a retained AVPlayerLayer/AVPictureInPictureController with background audio. AVPlayer playback uses the same layer inline and in PiP. Native Metal playback prepares an AVFoundation companion and hands off position, rate, and unambiguous embedded track selection. Startup/probe work is bounded and canceled on replacement; failed startup restores the original native position. Native Home transitions trigger on entering the background, not merely opening Control Center. No app dependency was added.

Trust boundary: only the already-selected PlaybackSource URL enters AVFoundation. Arbitrary source HTTP headers are not forwarded through undocumented AVFoundation options. Header-bearing sources, unsupported formats, external subtitles, and ambiguous embedded track mappings remain inline. Selected source capabilities are not logged or persisted. The companion may open an additional media connection; device/network and provider-limit checks remain necessary. Subtitle appearance in PiP follows AVKit rather than mpv styling.

## Adaptive icon finding

The pre-change build already contained a shared Icon Composer stack, but its three raster layers had no alpha and included baked-in square backgrounds. Compiled adaptive metadata alone did not establish a useful clear appearance. The new `IOSAppIcon.icon` uses transparent vector orbit foregrounds with light/dark gradients over an Icon Composer background; iPhone/iPad build settings explicitly select it while macOS keeps `AppIcon`. Clean vector layers were chosen after background-removal previews showed edge artifacts. The orbit was traced from the existing mark; the Mac artwork remains untouched. `actool` compiled the iOS-specific icon successfully and its generated small default icon was visually inspected. Installed clear/light/dark appearance still requires device confirmation.

References checked: [Apple Design Resources](https://developer.apple.com/design/resources/), [App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons/), [custom-player PiP](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player), [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview).

## Verification results

- Native iOS Simulator build: passed during implementation; final result recorded below.
- macOS build: passed during implementation; final result recorded below.
- Generic iOS device build: blocked before compilation by missing provisioning profile. Signing was not bypassed.
- AVPlayer-only simulator configuration: passed after guarding native-only subtitle sync controls; final result recorded below. The ignored native build configuration is temporarily moved for this check and restored afterward.
- The AVPlayer-only configuration exposed pre-existing unguarded subtitle-sync references. They are now compiled only with native playback; AVPlayer shows an explicit unavailable explanation.
- An attempted global Swift conditional override failed in swift-crypto because it removed package-required conditions. This was a verification-command configuration failure; no package source was changed.
- iPhone 17 Pro / iOS 26.5 simulator: installed and launched; portrait Home screenshot inspected. Landscape rotation/menu interactions could not be executed through Device Hub's UI surface.
- Independent review identified failed-start rewind and lost playback-rate restoration; both were corrected. Review also identified track-selection mismatch; handoff now maps unambiguous embedded selections and refuses unsupported selections.
- No automated tests, targets, fixtures, or test scripts were created or run, per AGENTS.md.

## Device acceptance still required

1. Rotate a small and large iPhone both ways on Home, detail, and playback; check safe areas, action rows, pause/loading/error overlays, panels, close/retry, long titles, and large text. Repeat iPad multitasking and pointer/keyboard checks; resize Mac playback and exercise its menus/full screen.
2. Double-tap both sides, scrub horizontally, and swipe vertically on each side. Confirm one top-center HUD, correct values, no blocked controls, and cancellation on leaving playback.
3. Change volume with hardware buttons, Control Center, route changes, the in-player slider, and gestures. Verify matching values and no double attenuation. Check Bluetooth/AirPlay routes that cannot change volume locally.
4. Play a compatible source, enter/exit PiP by button and Home gesture, change speed, pause/seek, and restore. Repeat while paused, loading, offline, with failed seeks, at end of media, and during source replacement. Opening Control Center must not itself trigger native PiP. Check header-bearing/unsupported streams and external subtitles remain inline with recoverable feedback.
5. Install the newly signed build and inspect Home Screen default, dark, tinted, clear light, and clear dark appearances. Do not delete user data merely to clear the icon cache.
6. Check VoiceOver/focus order, Dynamic Type, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark, and color-independent status on the changed flows.

These are release acceptance steps, not completed runtime evidence or performance claims.

## Final local results

- `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build`: **BUILD SUCCEEDED**.
- `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build` with the configured native framework: **BUILD SUCCEEDED**.
- The same simulator command with the ignored native configuration temporarily absent: **BUILD SUCCEEDED** for the AVPlayer-only path; configuration restored afterward.
- `plutil -lint AppInfo.plist Omnia.xcodeproj/project.pbxproj`: both OK.
- `git diff --check`: passed.
- Built Info.plist selects `IOSAppIcon`; compiled asset inspection confirms light/dark/tintable IconImageStack entries. Generated default icon visually inspected with its transparent vector foreground over the Composer background.
- Final native simulator product reinstalled and launched successfully on iPhone 17 Pro / iOS 26.5. Obsolete Release and macOS Debug app products removed after verification, leaving the current simulator product in canonical DerivedData.
- Physical-device build remains blocked by the missing provisioning profile. PiP, hardware volume, clear appearances, landscape interaction, and the accessibility/device matrix above remain unverified.
