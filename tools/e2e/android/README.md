# Native Android emulator review

These tools install and exercise actual KOReader widgets on an explicitly selected
Android emulator. Every adb invocation carries `-s emulator-N`, and construction
refuses a target unless `ro.kernel.qemu=1`. The host safety tests run in Android CI.
Use a disposable AVD: setup replaces its plugin and seeds synthetic books; the
upgrade test archives its KOReader and fixture Books directories together and
clears the two app profiles. Prior synthetic legacy EPUBs stay in those archives
instead of changing a later fresh fixture’s 59-book catalog.

Tested with Android 14 Google APIs ARM64, KOReader v2026.07.1 ARM64, a Pixel Tablet
AVD adjusted to 1200×1600 at 240 dpi, and the four-column `android-tablet` layout.
This is emulator acceptance, not a physical M8C timing measurement.

```sh
sdkmanager 'emulator' 'system-images;android-34;google_apis;arm64-v8a'
avdmanager create avd --name booksync-review \
  --package 'system-images;android-34;google_apis;arm64-v8a' --device pixel_tablet
"$ANDROID_HOME/emulator/emulator" -avd booksync-review -port 5580 \
  -no-window -no-audio -no-snapshot -gpu swiftshader_indirect
```

Wait until `adb -s emulator-5580 shell getprop sys.boot_completed` returns `1`.
`wait-for-device` alone does not mean PackageManager is available. Then:

```sh
adb -s emulator-5580 shell wm size 1200x1600
adb -s emulator-5580 shell wm density 240
python3 tools/e2e/android/build.py --out /tmp/booksync-emulator-build
python3 tools/e2e/android/run.py --serial emulator-5580 setup \
  --apk /tmp/booksync-emulator-build/android/companion/app/build/outputs/apk/debug/app-debug.apk \
  --koreader /tmp/koreader.apk \
  --apksigner "$ANDROID_HOME/build-tools/34.0.0/apksigner"
python3 tools/e2e/android/review.py --serial emulator-5580 --out /tmp/booksync-shots
python3 tools/e2e/android/test_driver.py
```

Setup launches the companion once to initialize its status before opening KOReader.
The native review dismisses only KOReader's exact initial color-rendering notice.
Other unexpected dialogs still fail the check; the Unopened restart flow may
choose Later once on the existing setup reminder before checking the saved pick.

`build.py` copies companion sources and shared inputs into an external directory,
preserving strict Gradle verification. Only that disposable copy replaces the
server composition with `E2eServerAdapters.kt`. The fixture implements the neutral
`ServerAdapter`; it reuses `DeviceLibrary`, `LibraryReadModel`, `SeriesPresentation`,
and the normal account worker and sync owner. Sign-in uses the synthetic address
`https://fixture.example.test`, user `reader`, password `fixture`. No HTTP listener
or external service is required. This tests the interface, not the shipping
adapter's HTTP protocol or a live server refresh/download.
Position consent uses a fixed remote-ahead snapshot; local uploads are recorded
separately so background sync cannot alter that scripted second reader.

`run.py setup` reuses `android/koreader/package.sh` for version stamping, settings,
credits and battery assets. APK `install -r` and whole plugin replacement follow
`tools/sideload-android.sh:158` and `:186`. It reads the debug APK's certificate
and pins it only in the staged emulator plugin copy. Production signing policy
and source files are unchanged. EPUBs reuse `tools/e2e/kit.py:151`; synthetic
KOReader sidecars provide saved titles, series and progress.

The test-only user patch `driver.lua` calls real screen entry points and native
button callbacks. `review.py` exercises default Home pages, editor/picker and
add/resize/move/save/reset, sign-in,
Library/filter, Series, Storage, Settings groups, every registered widget, book
opening, top/bottom reader panels, live Custom value edits with native setting
assertions, position consent/acceptance,
end sheet → Series, Full Refresh, and offline Library. It saves PNGs and a small
`review.json` outside the repository. Projection readiness is polled; an assertion
failure ends the run. Home readiness includes every visible widget snapshot;
covered widgets and stale list/Series roles do not hold a different screen open.
The per-screen deadline stays 20 seconds. There are no scenario retries.

For upgrade/fresh-install checks, use another disposable emulator. Supply an
external `git archive origin/main` snapshot containing `android/`, `shared/`,
`tools/booksync-version.py` and `tools/e2e/`, and its debug APK:

```sh
python3 tools/e2e/android/upgrade.py --serial emulator-5582 \
  --legacy-source /tmp/booksync-main \
  --legacy-apk /tmp/booksync-main/android/companion/app/build/outputs/apk/debug/app-debug.apk \
  --apk android/companion/app/build/outputs/apk/debug/app-debug.apk \
  --koreader /tmp/koreader.apk \
  --apksigner "$ANDROID_HOME/build-tools/34.0.0/apksigner" --out /tmp/booksync-shots
```

The upgrade preserves a seven-minute idle setting and synthetic sentinel, checks
the Home migration and once-only news acknowledgment, then verifies a fresh profile
gets BookSync Home without upgrade news. The legacy and current builds use the
same local debug key; no release key is needed.

After the main review, the add-on fallback flow uses the same disposable emulator:

```sh
python3 tools/e2e/android/addon.py --serial emulator-5580 --out /tmp/booksync-addon-shots
```

It checks the native Download fallback, existing helper settings and the reader's
helper deep-link/update summary. It restores the fixture's preferences even when
an assertion fails; it never installs an update or opens a physical reader.


Card actions: after setup, run `python3 tools/e2e/android/card_actions.py --serial
emulator-N --out <evidence>`. This checks real native Undo/Done/confirmation widgets
and companion-backed file removal/cancel with exact sidecar preservation. It saves
and restores one synthetic EPUB. Status presentation uses a temporary test-only
Library double; the real adapter/journal protocol and ordering are JVM tests.


Transfer jobs: `python3 tools/e2e/android/downloads.py --serial emulator-N --out
<evidence>` covers offline consent, format/destination choice, Cancel, explicit
Resume and completion after departure without reader focus. The disposable
fixture uses production durable job control and synthetic file bytes; HTTP range
recovery and real catalog linking are JVM integration tests. Both this flow and
`review.py` disable Wi-Fi and mobile data before asserting offline behavior.


Series queues: `python3 tools/e2e/android/series_downloads.py --serial emulator-N
--out <evidence>` checks the native exact preview, count editor, per-book format
choices, queue and per-row/all cancellation without auto-opening. The fixture
executes the production durable Series/transfer control planes with synthetic bytes.
JVM tests cover actual protocol, catalog coverage, restart and offline recovery.


Reader navigation: after setup, `python3 tools/e2e/android/reader_navigation.py
--serial emulator-N --out <evidence>` exercises native menu hooks/escape and cached
Contents, annotations, page/percent and search. It includes landscape and a generated
twenty-chapter/8,000-paragraph EPUB outside the fixed 59-book fixture library,
asynchronous search and cancellation. Native annotations are toggled back to their
prior bookmark state. Menu enablement and rotation are restored.

Local completion and yearly goal: `python3 tools/e2e/android/local_completion.py
--serial emulator-N --out <evidence>` exercises the real numeric input and
bottom-docked touch keyboard, save/reopen/Off, native explicit finish/Undo/re-finish,
restart replay and offline local labels. `local_completion_upgrade.py` accepts the
same legacy/current build arguments as `upgrade.py` and checks additive proven
0.11 import without changing the borrowed sidecar or legacy queue.

Companion crash summary: after setup on a disposable AVD, run
`python3 tools/e2e/android/crash_summary.py --serial emulator-N --apk <fixture-apk>
--out <evidence>`. The external builder alone installs `CrashFixture.kt` and its
test manifest entries. Two uncaught synthetic exceptions in a disposable companion
process exercise the production Application hook without touching KOReader. The
flow verifies deduplication across process starts, uninterrupted foreground reading,
reader-local time, explicit sanitized clipboard copy, Clear and reopen. It writes
three screenshots and `review.json`; no intentional crash or unqualified adb runs
against physical readers. Use a fresh AVD; it sets the fixture timezone to Los Angeles.

Reader companion surfaces: after setup, run
`python3 tools/e2e/android/reader_companion.py --serial emulator-N --out <evidence>`.
It exercises Full and Add-on Status/Helpers, explicit helper toggles, missing
screen-off permission, Later, native Android denial and grant, return with the
helper still off, native revocation without opening a reader sheet, existing
protected settings and book/session departure. It captures native PNGs and
`reader-companion.json`; synthetic mode/helper preferences are restored afterward.
The Android 14 fixture uses the explicit Device admin Settings component for
revocation because that image does not export the generic settings action.

Reminders: `python3 tools/e2e/android/reminders.py --serial emulator-N --out
<evidence>` exercises the native list, interval editor, docked time/message keyboards,
explicit Save/Back, failed Save, bedtime over Home/page, consumed page keys, repeated
snooze, the inclusive missed window and expiry, eye-rest threshold/reset, simultaneous
bedtime priority and durable Turn off/failure. `build.py` injects `ReminderClock` into
the disposable APK only. Its two clocks use the emulator's OS timezone and a small
synthetic control file; a third scalar injects a store-save failure. The production
APK, provider API, dependencies and trust policy contain no test-clock route. This
flow publishes PNGs and `checks.json`; JVM tests exercise SQLite publication faults
and the full recurrence, claim, source and lifecycle rule matrix.

`reminders_settings.py` adds capacity/four-row paging, custom days, 12-hour input,
delete Cancel focus, future read-only and load/recovery/clock render fakes, the
companion information row, and explicit Sleep failure/retry through native
`SLEEP_NOW`/`lockNow` with page restoration on wake. This disposable APK is marked
test-only so its synthetic device administrator can be removed in `finally`;
`run.py setup` installs it with `-t`. Shipping manifests and permission policy stay
unchanged. The render fakes replace only the Library presentation port; future
providers and credentials do not register. Run it after `reminders.py` on the same
verified emulator and supply a separate evidence directory.

The staged emulator plugin also consumes the fixture's published elapsed-clock memo.
Both halves therefore validate the same injected grant expiry, including the exact
60-minute boundary; host time spent editing cannot make a frozen test-clock grant
appear expired. This changes only disposable staged sources. Production uses the OS
suspend-aware clock; the fixture adds no paint IO and retains the actual gate predicates.

Home V1: after the ordinary fixture setup, run `python3 tools/e2e/android/home.py
--serial emulator-N --out <evidence>`. It requires Pillow for deterministic raster
cover fixtures and uses a marker in the disposable Books directory to opt into
`HomeFixture.kt`; other emulator scenarios retain the original adapter behavior.
The fixture provides synthetic reading/recent/Want to read windows and saved lists,
while production projections remain unchanged. It seeds 59 books with covers,
series, three saved in-progress positions and finished history. Native captures
wait for published views, expected cached covers and a completed repaint. It checks
that editor/picker previews make no queries and that move/size/save use their real
callbacks. The size action cycles to the next span that fits, preserving neighbours.
`--skip-seed` reuses an already seeded disposable AVD.

Catalog and finish presentation: `catalog_ui.py --serial emulator-N --out <evidence>`
checks the five-column Library, paging, filter counts/selection, grouped shelves,
Series, Storage, saved finish covers, rating and stale-poll cancellation. Configure
1404×1872 at 300 dpi and seed the 59-book fixture's sidecar covers first. It signs
in to the compiled fixture account and disables the disposable emulator's radios.
Main captures use the fixture companion; the additional next-three Series specimen
supplies one bounded saved adapter response to exercise remote-only visual states.
It uses the same native renderer and verifies the real download-card callback.

V1 Stats review: after `home.py`, run `home_stats.py --serial emulator-N --out <home-captures> --statistics-db <synthetic statistics.sqlite3>`.
It requires 50 distinct history days, copies the DB into the disposable emulator,
checks all 34 Stats/Battery sizes for native truncation in empty and seeded states,
and captures both. It stops only the two apps on that explicit emulator before
replacing its DB and removing its WAL/SHM files. `home_details.py` captures the
compact local-series card and verifies unavailable end-of-book pace. Both tools
use the same guarded Emulator and fake ServerAdapter as Home acceptance.
