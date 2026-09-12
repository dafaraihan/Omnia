# Liquid Glass Sliders and System Preferences in Omnia

Date: 2026-09-16

## Decision

**Yes:** a SwiftUI app can get the current iOS, iPadOS, and macOS 27 Liquid Glass slider treatment by using the standard `Slider`. Apple documents that standard controls, including `Slider`, automatically adopt Liquid Glass; during interaction, a slider’s knob transforms into Liquid Glass. The supported way to get the *system* appearance is to keep the system control and avoid hard-coded control metrics or competing custom backgrounds. [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) [Build a SwiftUI app with the new design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/323/)

**Also yes, automatically:** a view using SwiftUI Liquid Glass adapts to the person’s macOS/iOS/iPadOS 27 Liquid Glass preference (the system slider from ultra-clear to fully tinted). Apple states that the revised material automatically responds to that slider, without app code changes. [What’s new in SwiftUI (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/269/)

**No:** Apple does not document a public API that exposes the preferred-Liquid-Glass slider’s value, lets an app observe its precise clear/tinted level, or lets an app set the global preference. An app can select its own `Glass.regular` or `Glass.clear` variant, but that is an app-local rendering request, not a read or write of the person’s system preference. The appropriate integration is to let system materials adapt; do not read private defaults or attempt to duplicate the setting.

## Public SwiftUI surface and availability

Liquid Glass APIs were introduced in the **26** platform releases, not 27. The current 27 releases refine their rendered result automatically. `View.glassEffect(_:in:)`, `Glass`, `GlassEffectContainer`, and the glass button styles are available from **iOS 26.0, iPadOS 26.0, and macOS 26.0** (and remain available on 27); they are unavailable on visionOS. The Apple-shipped Xcode 27.0 public SwiftUI interface in this workspace declares the core APIs as `@available(iOS 26.0, macOS 26.0, ...)`. Apple’s SwiftUI documentation describes the same API as applying Liquid Glass to a view. [glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29) [Glass](https://developer.apple.com/documentation/swiftui/glass) [Build a SwiftUI app with the new design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/323/)

The relevant public APIs are:

| Need | Public API | Boundary |
| --- | --- | --- |
| Native slider appearance | `Slider` | Use the standard control; it receives the system’s interactive Liquid Glass thumb on the supported OS. |
| Custom non-slider surface | `glassEffect(_:in:)` with `Glass.regular` or `Glass.clear` | Applies system-rendered material to an app view; the default is regular glass in a capsule. |
| Custom interactive surface | `Glass.interactive()` | Requests the system’s interactive glass behavior for a custom control. |
| Custom tint | `Glass.tint(_:)` | Supplies an app tint; it does not select or override the user’s global clear/tinted preference. |
| Coordinated custom glass | `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)` | Combines/morphs nearby custom glass effects; Apple recommends containers to avoid excessive independent rendering. |
| Custom button | `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)` | Prefer these over placing raw glass behind a `Button`; the configurable `.glass(Glass)` overload is available from 26.1. |

Apple’s custom-view guidance covers the surface APIs above, but it does **not** expose an API to restyle the internals of `Slider` to an exact hand-built Liquid Glass thumb. Therefore, a custom-drawn slider can use `glassEffect` around its own surfaces, but cannot claim the exact system slider rendering. Use stock `Slider` when visual and accessibility parity are requirements. [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) [GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)

For a deployment target below 26, guard direct uses of these symbols with `if #available(iOS 26.0, macOS 26.0, *)` and provide a normal non-glass fallback. Omnia currently sets its Mac deployment target to 26.0/26.5 in project configurations, so the existing native Mac app is already within the public API availability range; its project is presently configured to build the macOS target only.

## System and accessibility propagation

Standard SwiftUI controls, toolbars, sheets, popovers, and navigation containers dynamically adapt to the Liquid Glass preference and accessibility configuration. Apple specifically advises removing custom backgrounds that obscure system effects, and says that standard components adapt automatically under the person’s preferred Liquid Glass look, Reduce Transparency, Reduce Motion, and increased contrast. [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) [Materials — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/materials)

For **custom** Omnia content, SwiftUI supplies public, read-only environment values for adjacent accessibility preferences:

- `@Environment(\.accessibilityReduceTransparency)` tells the app whether Reduce Transparency is enabled; Apple says affected UI backgrounds should be opaque. [accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)
- `@Environment(\.accessibilityReduceMotion)` tells the app to avoid large, especially simulated-3D, animations. [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- `@Environment(\.colorSchemeContrast)` reflects the user-controlled system-wide contrast setting. [colorScheme](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme)
- `@Environment(\.accessibilityShowBorders)` tells custom controls to draw clearly visible edges. It is available on iOS/iPadOS from 26.1 and on macOS 27; on earlier macOS versions it is true when Increased Contrast is enabled. [accessibilityShowBorders](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityshowborders)

Those values are useful for custom backup decorations such as Omnia’s hover transforms and manual opacity layers. They do not reveal or control the system Liquid Glass preference. Apple’s documented `EnvironmentValues` catalog contains these accessibility values but no Liquid-Glass-preference accessor; its WWDC26 guidance instead says material responds to the user’s slider automatically. [EnvironmentValues](https://developer.apple.com/documentation/swiftui/environmentvalues/) [What’s new in SwiftUI (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/269/)

## Omnia context and recommendation

Omnia already uses ordinary `Slider` controls in its playback chrome and subtitle settings, including the playback timeline and volume sliders in `Omnia/Features/Playback/MacPlaybackChrome.swift`, the compact playback surface in `Omnia/Features/Playback/PlaybackViews.swift`, and subtitle controls in `Omnia/Features/Settings/SubtitleAppearanceSettingsView.swift`. On macOS it also uses `glassEffect` and `GlassEffectContainer` in `Omnia/UI/Components/OmniaLiquidGlass.swift` and the playback chrome. The app’s custom helper currently checks Reduce Motion; its subtitle overlay already checks Reduce Transparency and contrast.

For an iOS/iPadOS/macOS 27 design pass:

1. Retain standard `Slider` for volume, timeline, and settings values. The system then supplies the correct interactive Liquid Glass slider appearance and tracks future system refinements.
2. Do not add a separate Omnia “match system Liquid Glass amount” slider: it cannot be bound to the global setting with public APIs. An optional Omnia-only visual preference is possible, but it must be described as independent and must not fight the system material.
3. Keep custom `glassEffect` limited to important functional surfaces, place related effects in `GlassEffectContainer`, and test standard and custom surfaces at both ends of the system slider as well as Reduce Transparency, Increased Contrast, Reduce Motion, VoiceOver, Dynamic Type, keyboard, and pointer conditions.
4. For custom interactive controls on macOS 27, additionally honor `accessibilityShowBorders`; the standard `Slider` already owns its corresponding system behavior.

No application source was changed for this research.

## Sources

All external sources above are first-party Apple documentation, Human Interface Guidelines, Apple Developer videos, or the Apple-distributed Xcode 27 public SDK interface inspected locally on 2026-09-16.
