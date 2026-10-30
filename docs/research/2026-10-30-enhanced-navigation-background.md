# Enhanced navigation and artwork background reference

Research date: 2026-10-30. Read-only source inspection; no upstream code, assets, dependencies or scripts executed or incorporated. Enhanced branch HEAD was resolved with `git ls-remote` and inspected at **5f54c2bd42f2f2fb5edf28945d04b53c8474c676**. Measurements below describe source values in Compose dp, not measured screenshots or device verification. Omnia was inspected in the working checkout; README and DESIGN distinguish current behavior from intended requirements.

## Primary references

All Enhanced links are pinned to that commit:

- [Navigation composition](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/MainTabsDestination.kt#L86-L212)
- [Floating bar dimensions](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/core/ui/FloatingNavigationBar.kt#L95-L260)
- [Scroll state](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/core/ui/NavigationBar.kt#L47-L99)
- [Style and position values](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/features/settings/NavBarStyle.kt)
- [iOS native routing](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/iosApp/iosApp/ContentView.swift#L1785-L1802), [native behavior modes](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/features/settings/NuvioTabBarBehavior.kt), [iOS insets](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/iosMain/kotlin/com/nuvio/app/core/ui/PlatformInsets.ios.kt#L16-L22)
- [Appearance settings visibility](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/features/settings/AppearanceSettingsPage.kt#L135-L237)
- [Dynamic wash](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/core/ui/DynamicArtworkBackground.kt), [artwork extraction](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/core/ui/ArtworkDominantColor.kt), [swatch treatment](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/core/ui/BrightDominantColor.kt)
- [Defaults and persistence](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/features/settings/ThemeSettingsRepository.kt#L30-L64), [theme base/AMOLED](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/core/ui/Theme.kt#L44-L60), [Home application](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/composeApp/src/commonMain/kotlin/com/nuvio/app/features/home/HomeScreen.kt#L1002-L1020)
- [GPL license](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/blob/5f54c2bd42f2f2fb5edf28945d04b53c8474c676/LICENSE)

## Navigation findings

Current Enhanced has Adaptive, Expanded, Compact and Classic; unknown/missing style resolves Adaptive. Position independently defaults Bottom, with Top optional; Classic ignores position. This fork expressly applies the selected style on tablets too. These facts come from Style/position and Appearance sources above.

The custom pill is centered at the bottom for both phone and tablet by default; the optional top placement uses status-bar inset + 10 dp. Bottom padding is safe-drawing bottom inset + 8 dp on iOS. It overlays content; bottom custom navigation reserves 72 dp in the content environment, versus 49 dp for native navigation. Native navigation or an inactive root route suppresses the custom bar. See Navigation composition and iOS insets.

| Custom layout | Expanded | Compact |
| --- | --- | --- |
| Phone height | 64 dp | 48 dp |
| Horizontal outer margin | 28 dp | 58 dp |
| Phone width | min(available width − 56 dp, 400 dp) | min(available width − 116 dp, 400 dp) |
| Tablet inline-label height | 52 dp | 48 dp |
| Tablet width cap | 640 dp | 64 dp × item count + 8 dp |

Dimensions interpolate with label visibility. Phone labels are stacked while tablet labels are inline (`inlineLabels = isTabletLayout`), where tablet layout means explicit tablet mode or width ≥ 768 dp. For a source-width example of 390 dp: phone expanded width 334 dp, compact width 274 dp. These are formulas from Floating bar dimensions, not screenshot measurements.

Adaptive starts expanded, collapses after accumulated downward scroll delta exceeds 60, and expands after upward delta exceeds 60; the counter resets when direction changes. The threshold is raw Compose scroll-coordinate delta (`60f`), not an explicitly dp-converted threshold. Nested scrolling attaches at the tab host, rather than the old per-page absolute scroll thresholds. Expanded/Compact force their state and do not use Adaptive scroll attachment. See Scroll state and Navigation composition.

**iOS 26 qualification:** phones and iPads use native tabs when native behavior is enabled. Its default is Morphed, with Static, Auto Hide and Off alternatives; only Off disables it. Appearance hides custom navigation-style settings while native behavior is enabled. Therefore the custom 64/48 dp rules are not a claim about the default iOS 26 native bar. Native routing and Appearance sources establish this override.

## Dynamic background findings

The feature is **off by default**, independently from AMOLED (also off). Enabling it wraps Home with a whole-screen **solid color wash**, driven by active hero artwork. It is not a blurred backdrop image, theme accent replacement or animated multicolor gradient. Target color mixes **58% MaterialTheme background + 42% extracted artwork tint** component by component; transition is **600 ms LinearOutSlowIn**. Pending extraction retains the previous tint; missing/failed/no tint returns to theme background. Sources: Defaults, Home application and Dynamic wash.

Artwork extraction requests a 96 × 96 sample, caches up to 256 URL colors with LRU-like promotion, rejects swatches outside HSL lightness 0.22–0.92 or saturation below 0.08, then brightens accepted colors to lightness at least 0.45 and at most 0.8. Sources: Artwork extraction and Swatch treatment. These are implementation facts, not requirements to add their dependencies to Omnia.

AMOLED changes the base to pure black, but does **not** suppress the dynamic wash: enabling both still blends in 42% tint, so the resulting Home wash is not pure black. Theme color remains the fallback. No explicit Reduce Motion branch was found in this wash or the searched common/iOS sources (`reduceMotion`, `ReduceMotion`, `reduce_motion`); do not infer that the source proves OS-level animation handling. Verify on device. Source: Dynamic wash and Theme base/AMOLED.

## Comparison and independent Omnia recommendation

Current local `Omnia/UI/Components/NuvioTopBar.swift` uses 52 pt height on iOS for both styles, fixed 56 pt compact item slots (66 pt stacked expanded slots), labels-fit fallback, and Adaptive hides labels over the Home hero/after Home absolute scroll rather than direction-based 60-delta behavior. Current `Omnia/App/OmniaRootView.swift` already places compact-width custom navigation at the bottom, regular-width at the top, using `safeAreaInset` on iPhone rather than Enhanced's overlay. Its compact-width maximum-width budget is window width minus 32 pt. Preserve native safe-area semantics and accessibility rather than transplanting Compose positioning mechanically.

Current `Omnia/Domain/Settings/DisplayPreferences.swift` exposes Standard (`native`) as a separate style; Enhanced retains Classic and separately supports native iOS 26 modes. Thus removing Standard is an Omnia product request, **not** parity with an upstream removal. If removing it, remove it from selectable `allCases` and migrate/decode legacy `native` safely to Adaptive; avoid breaking old stored settings or a `.native` call-site fallback. Keep platform navigation ownership explicit.

Current Omnia `HomeLayoutPreferences` defaults dynamic background **on**, and `HeroBackdropEnvironment.swift` gates a macOS `HeroAccentBackground` layer using it. This differs from Enhanced's off-by-default solid wash. Review existing `HomeView`/accent behavior before changing default or layering another background. Implement artwork tint extraction with existing Apple/repository capabilities; do not add KMPalette/Coil or copy GPL source into Swift as a shortcut.

Recommendation: independently express the requested three style choices with an iPhone bottom pill; use source values as a visual reference (64/48 pt desired silhouette and 28/58 pt outer margins if adequate touch targets remain), but prioritize minimum target sizes, Dynamic Type and fitting all destinations over exact dp arithmetic. Use an explicit geometry fit fallback. For background parity, use a cached dominant color, 42% mix against the resolved Omnia theme surface, default off only if intentionally changing preference semantics, prior tint during loading, base fallback on missing/error artwork and immediate/simplified transition under Reduce Motion. Preserve offline/retry behavior and bound image sampling. No dependency is needed solely for these behaviors.

No builds or automated tests were run for this research-only note. Source inspection cannot establish real iPhone/iPad appearance, VoiceOver, Dynamic Type, gestures, safe areas or iOS 26 native mode behavior. Those require the repository's supported manual/device checks before any product claim.
