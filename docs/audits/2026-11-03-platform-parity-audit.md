# Platform parity, breakage and layout audit — 2026-11-03

Dafa's round of Nov 3, items 8, 9 and 10. Compared iPhone, iPad and Mac at `d8c3005`.

Evidence labels:
- `ran` means seen on a simulator in this audit (iPhone 17 Pro, iPad Air 11-inch).
- `code` means source reading only.
- The Mac app builds and launches here, but screen capture isn't permitted, so nothing on the Mac is visually verified.

## Item 8: same architecture and features?

One project and one target build all three. Data, Domain, Core, sync and the metadata service have no idiom branches (`grep` of `Omnia/Data` and `Omnia/Core`: only Keychain accessibility and Apple sign-in anchors differ by platform). Playback uses libmpv on all three, with AVPlayer only as a fallback on iOS.

| Feature | Mac | iPhone | iPad | Status |
|---|---|---|---|---|
| Player chrome, gestures, panels | Yes | Yes | Yes | Same. Gestures are touch only |
| Animated collection covers | Hover | Was missing | Was missing | **Fixed**: plays while on screen, at most 3 at once, `CollectionViews.swift` |
| Decoder setting, Auto Sync Subtitles, Subtitle Delay | Yes | Was missing | Was missing | **Fixed**: `VideoPlayerSettingsView.swift`, gated on libmpv |
| Playback engine row | libmpv | **Said AVPlayer** | **Said AVPlayer** | **Fixed**: wrong label while libmpv was playing |
| Keyboard control of the player | Yes | Was missing | Was missing | **Fixed**: arrows, space, Esc, `PlaybackViews.swift` |
| Hover Glow, Hover Preview | Yes | No | Hover Glow only | Intended: both need a pointer. Hover Glow settings no longer show on iPhone |
| Metal Rendering toggle, Use Whole Screen | Yes | No | No | Intended: Mac only. iOS mpv has one renderer and no windows |
| Floating Search style | Yes | No | No | Intended: Mac window feature |
| Picture in Picture | Native mpv | MP4/HLS without headers | MP4/HLS without headers | **Limit**: MKV stays inline on iOS. Needs an mpv sample-buffer output; separate work |
| Navigation choices | Yes | Native tabs only | Yes | Dafa's decision on Oct 30 |

## Item 9: broken, messy, placeholder, duplicate

| Finding | Rating | Evidence | Status |
|---|---|---|---|
| Two-line titles shrink the poster in shelves (Dexter, Shaun the Sheep) | Broken | `ran`; `MediaPoster.swift`, art had no set height | **Fixed** |
| Discover shows two rows both named "Popular" | Messy | `ran`; `DiscoverView.swift` dropped the type Home shows | **Fixed** |
| Sign-in sheet forced 460pt wide on a 402pt iPhone | Broken | `code`; `AccountSettingsView.swift:60` | **Fixed** |
| Poster Card Style summary says "Hover" on iPhone | Messy | `ran`; `AppearanceSettingsView.swift:201` | **Fixed** |
| Integrations footer said keys stay on this device, though the vault backs them up | Messy | `code`; `MetadataSettingsView.swift` | **Fixed** |
| Same language picker written twice | Duplicate | `code`; `SubtitleAppearanceSettingsView.swift:200`, `VideoPlayerSettingsView.swift:457` were byte-identical apart from the name | **Fixed** |
| `isPhone` written by hand in the player files | Duplicate | `code` | **Fixed**: `OmniaDevice.isPhone` |
| Same copy-to-pasteboard block in three settings files | Duplicate | `code`; `AddonsSettingsView.swift:288`, `AddonDetailView.swift:233`, `PlaybackDiagnosticsSettingsView.swift:70` | Left: three short blocks with no bug |
| `Mac*` type names on code shared by all platforms (`MacPlaybackChrome`, `MacNavigationStyle`) | Messy | `code` | Left: a rename touches many files and changes no behaviour. Tell me if you want it |
| Placeholders | None found | `code`: grep for TODO, FIXME, stub, not implemented, coming soon. The only hits are real features (URL placeholders, "Coming Soon" shelf) | Clean |

The previous audit, `2026-11-03-post-pause-audit.md`, covers the Oct 29–30 work.

## Item 10: layouts

| Finding | Rating | Evidence | Status |
|---|---|---|---|
| Settings dropdown value drops under the title when the subtitle is long (Hero Style, Trailer Start Delay, After Trailer) | Broken | `ran`; `SettingsDropdown.swift`. Every Settings dropdown shares this row | **Fixed** on iPhone and iPad. The Mac draws its own row and was not affected |
| Mac stream page Back on the traffic lights | Broken | Dafa's screenshot; `StreamsPageViews.swift` | **Fixed**, not seen on Mac |
| iPad sidebar over the hero, content not behind it | Broken | `ran` | **Fixed** earlier today |
| iPad stream picker narrow and floating | Broken | Dafa's screenshot | **Fixed**, docked |
| iPhone grid: one huge landscape card, or two very large posters | Broken | Dafa's screenshot, `ran` | **Fixed**: 2 landscape or 3 posters across |
| iPad Library, Discover, Settings root | Good | `ran`, portrait | No change |

## Not covered

Not run in this audit, and worth checking by hand: VoiceOver, Dynamic Type, Full Keyboard Access, iPad multitasking and pointer, iPhone landscape on every page, and the Mac visually. The iPad keyboard controls were built but not pressed.
