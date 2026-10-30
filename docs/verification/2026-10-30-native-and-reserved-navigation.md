# Native and reserved navigation — 2026-10-30

User screenshot: Layout settings with custom navigation covers the Streams row. Requested native-like custom placement/size and restored Standard.

Restored TopBarStyle.native (Standard) with system tab chrome on iOS/iPadOS. Standard disables the custom bar and Glass Glow controls; custom choices and saved values remain. Mac chooser stays on supported custom modes; existing Mac sidebar behavior is unchanged.

Replaced the bottom custom bar's outer TabView safe-area inset with a distinct VStack layout region below TabView. The actual page viewport shrinks by bar height plus padding, so Forms, pushed pages and scroll views cannot draw actionable content in that region. The custom portrait bar uses near-full-width native-like margins, 64-point expanded/52-point compact height, with minimum44-point targets. Regular-width iPad top placement is unchanged.

Canonical generic iOS Simulator and macOS Debug builds: BUILD SUCCEEDED. git diff --check: passed. Installed/launched latest simulator app. Device Hub screenshot visibly confirmed Home card content ends above a separate opaque navigation region, without the former overlap. A subsequent attempt to open Profile failed with noWindowsAvailable, so the exact Streams-row tap, selecting Standard, keyboard, VoiceOver, orientation and multitasking flows remain manual acceptance. No runtime pixel-identical-native claim. No tests/scripts/fixtures/dependencies, hosted changes or release publication.
