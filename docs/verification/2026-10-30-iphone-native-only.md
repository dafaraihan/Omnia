# iPhone native-only navigation — 2026-10-30

User requested removal of all custom navigation on iPhone. OmniaRootView now gates custom navigation by device idiom, so all saved/shared Adaptive/Expanded/Compact values still render native iPhone tabs. Layout hides navigation style, tab style and dependent Glass Glow controls on iPhone, including landscape. iPad (including compact multitasking windows) and Mac choices are unchanged; shared preferences are not overwritten.

Validation: canonical generic iOS Simulator and macOS Debug builds, git diff --check. No tests/fixtures/scripts/dependencies, hosted operations or release publication. Remaining manual checks: native-only phone tabs with each previously saved custom value, portrait/landscape, keyboard, settings controls, Streams reachability, VoiceOver/focus; confirm iPad/Mac choice preservation. Exactly one current canonical Simulator app retained after validation.
