# F1 · 0.12.1 development build review

Approved mockup left; actual native M8C emulator capture right. Both account states
use 1404×1872 at 300 dpi, the compiled fake ServerAdapter, 64 synthetic books with
covers/series/progress, a 50-day base statistics DB and native book annotations/history fixtures.
Original lossless PNGs and the full navigation logcat remain in the local gallery.
No physical device, release workflow, tag or updater publication was used.

The source version label remains the branch’s shared/version.json (0.11.3-rc.17).
This is the 0.12.1 feature set; release identity is left to the maintainer.

Validation: 275 Lua logic tests; 352 Lua flows; 1,038 companion tests (four existing
skips), verifySharedVersion, assembleDebug and lintDebug; 18 driver safety tests;
UI/server boundary and feature checks; pinned KOReader compatibility. Native
acceptance passed 22 reminder checks, 13 settings/Sleep checks, 10 crash-summary
checks, and all 34 Stats/Battery sizes in empty and seeded states. See checks.json. The Time picker also passes six actual-touch/discard checks
([receipt](proof/time-picker-touch.json)).

The navigation receipt proves signed-out Android Home reaches BookSync Home,
a real stock-launcher app-drawer icon tap opens the companion, and ten consecutive
open/tap-top/Back-to-close-panel/Home cycles complete without a crash.

![Signed-out Home](proof/home-signed-out.png)

![Actual launcher icon route](proof/launcher-icon.png)

Remaining differences: bundled Noto fonts replace proprietary mockup fonts;
native font/SVG rasterization, Android system chrome and keyboard differ.
Synthetic book art, counts, pagination, progress and statistics differ. Some
native per-book estimates are unavailable where the fixture has no published
per-book snapshot; the seeded 50-day Home statistics remain populated. Server-only
shelves are absent while signed out. Battery has no physical measurements.
The reminder approval uses a taller 480×800 review viewport; layout follows M8C
width and retains every action. Sleep is unavailable in the main gallery without
native permission; the additional native suite granted it and verified Sleep/wake.
The Unknown-clock screen is a labelled Library provider-error fixture; Android
trusts the OS clock. Connect to Wi-Fi opens the existing companion controls
without claiming time sync. All nine Android reminder approvals are represented.
Sections without a dedicated approval crop use the explicitly labelled parent
Settings reference. Companion sections follow their approved native inventory.

## signed-out

### account

![account](pairs/signed-out-account.webp)

### book-info

![book-info](pairs/signed-out-book-info.webp)

### bookmarks

![bookmarks](pairs/signed-out-bookmarks.webp)

### checklist

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![checklist](pairs/signed-out-checklist.webp)

### companion-reading

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![companion-reading](pairs/signed-out-companion-reading.webp)

### companion-settings

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![companion-settings](pairs/signed-out-companion-settings.webp)

### companion-status

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![companion-status](pairs/signed-out-companion-status.webp)

### contents

![contents](pairs/signed-out-contents.webp)

### crash-summary

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![crash-summary](pairs/signed-out-crash-summary.webp)

### editor

![editor](pairs/signed-out-editor.webp)

### end-of-book

![end-of-book](pairs/signed-out-end-of-book.webp)

### filter

![filter](pairs/signed-out-filter.webp)

### goal-editor

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![goal-editor](pairs/signed-out-goal-editor.webp)

### goal

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![goal](pairs/signed-out-goal.webp)

### goto

![goto](pairs/signed-out-goto.webp)

### home-1

![home-1](pairs/signed-out-home-1.webp)

### home-2

![home-2](pairs/signed-out-home-2.webp)

### library

![library](pairs/signed-out-library.webp)

### missed-reminder

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![missed-reminder](pairs/signed-out-missed-reminder.webp)

### picker

![picker](pairs/signed-out-picker.webp)

### reader-bottom

![reader-bottom](pairs/signed-out-reader-bottom.webp)

### reader-companion-helpers

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![reader-companion-helpers](pairs/signed-out-reader-companion-helpers.webp)

### reader-companion-status

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![reader-companion-status](pairs/signed-out-reader-companion-status.webp)

### reader-top

![reader-top](pairs/signed-out-reader-top.webp)

### reminder-editor

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminder-editor](pairs/signed-out-reminder-editor.webp)

### reminder-sheet

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminder-sheet](pairs/signed-out-reminder-sheet.webp)

### reminder-time

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminder-time](pairs/signed-out-reminder-time.webp)

### reminder-unknown-clock

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission. Unknown-clock provider-error fixture: Android trusts the OS clock. Connect to Wi-Fi opens the existing companion Wi-Fi controls; it does not claim time sync.

![reminder-unknown-clock](pairs/signed-out-reminder-unknown-clock.webp)

### reminders

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminders](pairs/signed-out-reminders.webp)

### rest-eyes-interval

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![rest-eyes-interval](pairs/signed-out-rest-eyes-interval.webp)

### rest-eyes-settings

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![rest-eyes-settings](pairs/signed-out-rest-eyes-settings.webp)

### rest-eyes-sheet

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![rest-eyes-sheet](pairs/signed-out-rest-eyes-sheet.webp)

### search

![search](pairs/signed-out-search.webp)

### series

![series](pairs/signed-out-series.webp)

### settings-about

![settings-about](pairs/signed-out-settings-about.webp)

### settings-home

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-home](pairs/signed-out-settings-home.webp)

### settings-library

![settings-library](pairs/signed-out-settings-library.webp)

### settings-reading-2

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-reading-2](pairs/signed-out-settings-reading-2.webp)

### settings-reading

![settings-reading](pairs/signed-out-settings-reading.webp)

### settings-root

![settings-root](pairs/signed-out-settings-root.webp)

### settings-sleep-2

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sleep-2](pairs/signed-out-settings-sleep-2.webp)

### settings-sleep

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sleep](pairs/signed-out-settings-sleep.webp)

### settings-sync-2

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sync-2](pairs/signed-out-settings-sync-2.webp)

### settings-sync-3

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sync-3](pairs/signed-out-settings-sync-3.webp)

### settings-sync

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sync](pairs/signed-out-settings-sync.webp)

### settings-updates

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-updates](pairs/signed-out-settings-updates.webp)

### signin

![signin](pairs/signed-out-signin.webp)

### storage

![storage](pairs/signed-out-storage.webp)

## signed-in

### account

![account](pairs/signed-in-account.webp)

### book-info

![book-info](pairs/signed-in-book-info.webp)

### bookmarks

![bookmarks](pairs/signed-in-bookmarks.webp)

### checklist

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![checklist](pairs/signed-in-checklist.webp)

### companion-reading

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![companion-reading](pairs/signed-in-companion-reading.webp)

### companion-settings

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![companion-settings](pairs/signed-in-companion-settings.webp)

### companion-status

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![companion-status](pairs/signed-in-companion-status.webp)

### contents

![contents](pairs/signed-in-contents.webp)

### crash-summary

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![crash-summary](pairs/signed-in-crash-summary.webp)

### editor

![editor](pairs/signed-in-editor.webp)

### end-of-book

![end-of-book](pairs/signed-in-end-of-book.webp)

### filter

![filter](pairs/signed-in-filter.webp)

### goal-editor

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![goal-editor](pairs/signed-in-goal-editor.webp)

### goal

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![goal](pairs/signed-in-goal.webp)

### goto

![goto](pairs/signed-in-goto.webp)

### home-1

![home-1](pairs/signed-in-home-1.webp)

### home-2

![home-2](pairs/signed-in-home-2.webp)

### library

![library](pairs/signed-in-library.webp)

### missed-reminder

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![missed-reminder](pairs/signed-in-missed-reminder.webp)

### picker

![picker](pairs/signed-in-picker.webp)

### reader-bottom

![reader-bottom](pairs/signed-in-reader-bottom.webp)

### reader-companion-helpers

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![reader-companion-helpers](pairs/signed-in-reader-companion-helpers.webp)

### reader-companion-status

Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.

![reader-companion-status](pairs/signed-in-reader-companion-status.webp)

### reader-top

![reader-top](pairs/signed-in-reader-top.webp)

### reminder-editor

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminder-editor](pairs/signed-in-reminder-editor.webp)

### reminder-sheet

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminder-sheet](pairs/signed-in-reminder-sheet.webp)

### reminder-time

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminder-time](pairs/signed-in-reminder-time.webp)

### reminder-unknown-clock

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission. Unknown-clock provider-error fixture: Android trusts the OS clock. Connect to Wi-Fi opens the existing companion Wi-Fi controls; it does not claim time sync.

![reminder-unknown-clock](pairs/signed-in-reminder-unknown-clock.webp)

### reminders

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![reminders](pairs/signed-in-reminders.webp)

### rest-eyes-interval

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![rest-eyes-interval](pairs/signed-in-rest-eyes-interval.webp)

### rest-eyes-settings

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![rest-eyes-settings](pairs/signed-in-rest-eyes-settings.webp)

### rest-eyes-sheet

Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.

![rest-eyes-sheet](pairs/signed-in-rest-eyes-sheet.webp)

### search

![search](pairs/signed-in-search.webp)

### series

![series](pairs/signed-in-series.webp)

### settings-about

![settings-about](pairs/signed-in-settings-about.webp)

### settings-home

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-home](pairs/signed-in-settings-home.webp)

### settings-library

![settings-library](pairs/signed-in-settings-library.webp)

### settings-reading-2

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-reading-2](pairs/signed-in-settings-reading-2.webp)

### settings-reading

![settings-reading](pairs/signed-in-settings-reading.webp)

### settings-root

![settings-root](pairs/signed-in-settings-root.webp)

### settings-sleep-2

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sleep-2](pairs/signed-in-settings-sleep-2.webp)

### settings-sleep

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sleep](pairs/signed-in-settings-sleep.webp)

### settings-sync-2

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sync-2](pairs/signed-in-settings-sync-2.webp)

### settings-sync-3

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sync-3](pairs/signed-in-settings-sync-3.webp)

### settings-sync

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-sync](pairs/signed-in-settings-sync.webp)

### settings-updates

Parent Settings reference: no dedicated approved crop exists for this section.

![settings-updates](pairs/signed-in-settings-updates.webp)

### signin

![signin](pairs/signed-in-signin.webp)

### storage

![storage](pairs/signed-in-storage.webp)
