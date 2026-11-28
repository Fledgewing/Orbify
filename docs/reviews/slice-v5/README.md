# V5: native companion visual review — Round 2

[Comparison gallery](index.html) · [Measured scale](scale-measurements.md)

All native screens now use the same shared readable roles: **34 sp page title,
36 sp row title, 30 sp body, 28 sp segmented/toggle controls**, with a **24 sp
minimum** at the M8C reference width. There is no Settings-specific title size or
Activity multiplier. Smaller viewports retain the shared floor at their width
scale and scroll; no page is reduced to make its controls fit.

Setup uses the larger row titles, and Fix next uses the same 37 sp / 96 dp action
role as the approved goal forms. The old one-screen-fit assertion now verifies
readable type and intact content instead of requiring a screen to shrink.

The accepted status/crash/goal width-normalized samples remain in the measurement
report. Settings and checklist follow the Round 2 common-scale ruling; the
rejected separate Settings/checklist measurement profiles are not used as type
ceilings. The new rendered minimum test is the regression guard for every native
screen context and each Settings section.

Settings schema, Library commands, permission policy, checklist rules and X1
routing are unchanged. Launcher edits affect drawing dimensions and type only.
Reader Lua surfaces belong to V4 and are excluded from this gallery.

## Validation

- Dedicated Android 14 ARM64 AVD, **1404×1872 / 300 dpi**, with the repo's fake
  ServerAdapter and synthetic seeded EPUBs, covers, series and reading sidecars.
- Fixture APK assembly preserves strict Gradle dependency verification.
- 33 focused Kotlin tests pass, including the smaller-reader readable checklist,
  unchanged launcher Settings destination, numeric goal persistence and adjacent
  goal-action layout. `CompanionTypeScaleTest` checks every declared native screen
  context, renders every Settings section and locked mode, checks subtitle spans in both launcher tile sizes, and rejects new body
  views or raw text sizes that bypass the shared factories. Text inputs and
  checkbox labels use those factories too. `lintDebug`: zero errors, 35 warnings.
- Fifteen emulator-driver safety/seed tests pass.
- **All 15 `reader_companion.py` acceptance checks pass**, including Full/Add-on,
  denied/granted permission without helper enablement, protected Settings,
  return context, silent background revocation and changed-book retirement.
- The seed sets and flushes `color_rendering=true` before KOReader's first-run
  notice test. At pinned KOReader `9192014d8bd82a91dc1012473be0f238dedfdb54`,
  `reader.lua:190` runs late user patches; `reader.lua:195` checks this setting and
  `reader.lua:197` sets it when showing the notice. This prevents the known notice
  before the reviewed sheet opens, rather than dismissing arbitrary dialogs or
  relaxing the acceptance assertions.

Initialize the disposable emulator with the [repository setup flow](../../../tools/e2e/android/README.md) first; it grants KOReader storage access before starting the reader.

Commands:

```sh
python3 tools/e2e/android/test_driver.py
(cd android/companion && ./gradlew lintDebug testDebugUnitTest \
  --tests '*CompanionTypeScaleTest' --tests '*ChecklistPageTest' --tests '*SettingsPagesTest' \
  --tests '*LocalReadingSettingsTest' --tests '*UiPagesTest')
python3 tools/e2e/android/reader_companion.py --serial emulator-N --out <evidence>
python3 docs/reviews/slice-v5/measure-scale.py --gallery <gallery> --out <report>
```

The native all-set/group fixtures use production `ChecklistUi` with immutable
synthetic completed rows in an external fixture Activity. Other companion images
show production Activities. Intentional crash examples run only in the disposable
fixture process. No physical reader, production BookOrbit call, release, signing
change, dependency update or upstream change was made.

## Remaining environmental differences

Android supplies its own system fonts, status/navigation chrome and keyboard.
Snapshot version, local clock, permission state and synthetic sample values differ
from browser illustrations. E-ink ghosting and physical timing are not measured by
an emulator. These do not change the measured width-normalized type/control scale.
