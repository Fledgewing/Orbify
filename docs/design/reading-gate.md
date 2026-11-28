# Nothing interrupts reading

**Principle (v0.11.1).** While a book is open in the foreground, nothing from BookSync, BookSync
Companion or BookOrbit (as far as we can intercept it) appears on screen, restarts KOReader or
takes focus. Whatever would have shown waits for the next moment nobody is reading, or is dropped
once it has gone stale.

Exceptions, only where the reader acts inside the book: menus they open (and what those menus
show), the end-of-book sheet (they reached the end), and Sync and sleep (they asked; it runs as
the screen goes off).

One exception the user asked for outside that rule: the Full refresh's % badge
(`ko/badge.lua`, [sqlite-cache.md "Progress display"](sqlite-cache.md#progress-display-the-users-design)).
In a book it is a few characters in the bottom-left corner, a toast that every tap goes through,
never taking focus and redrawn only in its own rectangle at most every 3 s. Its start popup and
its full message still go through the gate.

Another: BookSync position sync's Yes / No popup when another reader's place turns up after the page rendered
(`ko/orbismart.lua`, [position-sync.md](position-sync.md) ruling 1): one draw, no animation, one at a time.

## Approved reminder exception (2026-11-27)

[Bedtime and Rest your eyes](reminders.md) share one narrowly typed reminder
exception. A service-owned, claimed, unexpired occurrence authorizes one initial
draw immediately on the main loop, against the current visible lifetime. Generic
messages, `UserOpened`, position consent, boolean consent and background callbacks
cannot exercise it. A hidden, sleeping, retired or A→B→A lifetime cannot revive a
permit. One sheet owns presentation at a time; reminders wait for position consent
and other modals rather than replacing or stacking on them.

Time kind requires proven clock provenance and its inclusive 60-minute missed
window; it may appear on the current page, Home or a reader-opened menu. Unknown
clock invalidates undrawn time grants. Interval kind uses monotonic active reading
and only a still-visible page in the current session; menus, modals, hidden views
and a five-minute idle break retire undrawn thresholds. Unknown wall time does
not block interval kind. Bedtime wins simultaneous arbitration. A visible sheet
has no countdown, automatic expiry, animation or timer-driven repaint.

Initial focus is Got it (time) or Done (interval). Opening/held/repeated input is
drained. Back, page-turn mappings/gestures and outside taps dismiss and consume
input. Only a fresh explicit action can snooze, turn off or request Sleep. Sleep
is a Library response after durable occurrence and position checkpoints, then the
existing native sleep path; failures keep the page and safe initial focus. No
claim wakes a device, starts an activity, foregrounds an app, enables a helper,
closes a book or authorizes a notification, update or network operation.

Firmware's `ReadingGate` uses a move-only one-use reminder permit and checks it
immediately before drawing. Durable device-effect completion is independent of
view lifetime and never paints. Explicit focus/input and visible action errors may
redraw the already owned sheet; background work cannot piggyback on that draw.
The firmware gate and its guard tests change together; Android's plugin and
companion guards remain part of the parallel Android implementation acceptance.

## The gate

**Plugin.** `reading()` (`ko/home.lua`) is true when a document is open, KOReader is in front
(`Wifi.state().foreground`), BookOrbit is not over the book, no reader menu is open and the
end-of-book sheet isn't showing. "BookOrbit over the book" (`bookorbitOverBook`, v0.11.2) walks the
window stack down to the ReaderUI: BookOrbit's catalog (Home or any list) or one of its views,
menus or dialogs (`bookorbit_*` widgets) anywhere above the book counts, whatever floats over them
(its loading pills, KOReader's messages: v0.11.1 held the Full refresh progress "while reading"
with Home on screen). Its status pills alone over the book don't. Just in time Wi-Fi's "done in a
book" off uses the same test (`ko/wifi.lua`). `Gate.show(what, fn, max_age_s)` runs `fn` at once when
not reading, else queues it (one entry per kind, the newest wins). `Gate.drain` shows what is
queued when BookOrbit Home comes on top, a book closes, and KOReader resumes; entries older than
their `max_age_s` (default 10 min, BookOrbit toasts 2 min) are dropped and
logged.

**Background notices on Home and browse.** `ko/notices.lua` marks automatic start, resume,
book-open and periodic sync, copies, mailbox replies, storage and cache repaints as background
work. That scope follows scheduled callbacks, native queued sync jobs and Trapper coroutines;
it is local to each coroutine so a suspended job cannot silence a concurrent user action.
Background notices are dropped rather than held for later. Native BookOrbit `show`, `error`
and `loading` pills, our own notes, direct InfoMessages/Notifications and Trapper progress text
all use the same suppression boundary as Full refresh. Thumbnail downloads and automatic clock
repaints are silent too. Every shown or suppressed message logs its text. Invisible Trapper
input traps still operate, and suppressed loading pills still return a closeable handle.
Explicit user actions retain their notices; Full refresh retains its tagged progress popup and
badge, and position-sync choices retain their dialog. Start/wake/copies, delayed and yielding
callbacks, cancellation, and foreground actions are covered in `test_flows.lua`.

**Companion.** A `Reading` gate mirrors the plugin from `STATS`: the plugin adds `reading=1|0`
to every `STATS` (0 on `close` and `suspend`); older plugins are read from `open` and
`resume`/`suspend`. Notifications and activity starts the companion makes by itself wait while
reading and are posted at the next non-reading moment (KOReader suspended or in the background,
the book closed, BookOrbit Home, a companion page in front). Never at screen-off: nobody would see
them. Posted quietly: no heads-up, no sound.

## Restarts after an update

| Update | When KOReader restarts |
|---|---|
| The reader asked (Update in the menu, Install in the companion) | at once, book or not: saved through KOReader's own close, the book reopens at its place, BookOrbit Home comes back if it was on top, the version remains in update status |
| Automatic (background check, the companion's daily job) | only when KOReader is out of the way: the screen goes off (restart), or another app is in front (KOReader saves and quits; the new plugin loads at its next start). Never on a closed book, BookOrbit Home or a list: the reader is still using KOReader |

`RestartPlan.decide` (`logic/prompts.lua`) and `UpdateFlow.restart` (companion `Logic.kt`) hold
these rules; `test_logic.lua` and `LogicTest` cover each trigger.

## Audit: plugin

Every `UIManager:show`, BookOrbit toast, `Jni.startActivity` and restart in `ko/*.lua` carries a
`-- gate: <why>` comment; `test_logic.lua` "reading gate" fails on a new one without it.

| Where | What | Gate |
|---|---|---|
| `ko/home.lua` `orbitNote` | short notes: "Applied N recommended settings", "Updated to vX" | `Gate.show`; a toast, so Home logic sees through it (`topWidget` skips it) |
| `ko/home.lua` `maybeRestart` | "close KOReader and open it again" (no companion) | `Gate.show` |
| `ko/home.lua` `restartForCompanion` | relaunch window, restart, quit | `RestartPlan` (manual, screen off, background) or the companion's own restart, which follows the same rule |
| `ko/home.lua` setup box | ConfirmBox | `SetupPrompt.decide` never shows it in a book; its buttons are user actions |
| `ko/home.lua` sign-in notes | "Signed in", "plugin isn't loaded" | user action (Setup's sign-in) |
| `ko/start.lua` `showWakeBanner` | "Can't reach BookOrbit" | background notice: suppressed and logged |
| `ko/endofbook.lua` next-sync downloads | "Downloaded: title" | `Gate.show` |
| `ko/endofbook.lua` sheet and its notes | end-of-book sheet | exception: the reader reached the end |
| `ko/badge.lua` Full refresh % badge | "37%", "Done" | exception: passive toast, the user's design |
| `ko/orbismart.lua` BookSync position sync popup | "Continue from Boox, p. 214? Yes / No" | exception: the user's ruling ([position sync](position-sync.md) ruling 1), one draw |
| `ko/cache.lua` `OC.note` | BookOrbit toasts | `Gate.installToast` wraps `bookorbit_toast.show`/`error` |
| `ko/cache.lua` offline miss | "This page isn't saved" ConfirmBox | user action (paging a list) |
| `ko/localfirst.lua` Remove | "This book is open" | user action |
| `ko/recommended.lua`, `ko/menu.lua`, `ko/companion_ui.lua`, `ko/test_sync_path.lua` | menus and their results | user action (menus) |
| `ko/sleep.lua` Sync and sleep | "Syncing…", "Synced" | user action; the screen goes off |
| BookOrbit toasts (sync results, conflicts shown as toasts) | `bookorbit_toast` | `Gate.installToast` |
| Wi-Fi "Connecting…" | KOReader's turn-on message | not shown: `wifi_backend.lua` brings the network up quietly |

BookOrbit's own modal dialogs (sync conflict, "further ahead") are not intercepted yet: they come
from its sync, which BookSync runs at wake and sleep, not mid-book.

## Audit: companion

One gate: `Reading.show(ctx, key, what) { post }` (`Reading.kt`, pure part `ReadingLogic.kt`). A
"reading" report lapses after 6 min without a new `STATS`. Held items post 1.5 s after a
non-reading moment with the screen on, and are dropped when their reason is gone. The guard test
`ReadingGuardTest` fails on a new `notify(` or `startActivity(` outside its allow-list (file, line
text, count, why).

| Where | What | Gate |
|---|---|---|
| `Attention.kt` setup reminder | notification | `Reading.show`; re-evaluated on release, so a step fixed meanwhile posts nothing |
| `Updater.kt` update ready (background check) | notification | `Reading.show`; dropped on install or when no longer newer. The Status page shows "Update ready · Install" any time |
| `Updater.kt` install prompt | activity | only for a check the reader started |
| `OrbitService.kt` Tailscale alert | notification | `Reading.show`; dropped when the VPN comes up |
| `OrbitService.kt` status | ongoing notification | low importance, never pops up |
| `OrbitKeys.kt` keyboard | notification | `Reading.show`; at once only when the reader focused a text field |
| `Installers.kt` KOReader install prompt | activity | `Reading.show`; dropped on success |
| `Core.kt` KOReader starts | activity | Home press, Setup taps, `RELAUNCH`; restarts follow the rule above |
| `Attention.kt`, `Pin.kt`, `Ui.kt`, `Launcher.kt`, `Clicker*.kt`, `Mode.kt`, `Pages.kt`, `ClickerService.kt` | pages, PIN | user actions |

Notification channels are quiet: no sound, no vibration, no heads-up (`updates_quiet`,
`alerts_quiet`; the old channels are deleted, since a channel's sound can't change).

## Xteink

The firmware should match: while a book is open, no OTA prompt, sync result banner or Tailscale
notice draws over the page; they show on the library or home screen, or after the next wake on a
non-reading screen. Automatic OTA installs only from the library screen or at sleep.

## Repainting an already visible owned modal

A ready response may inherit the background-notice scope. `Gate.show` accepts the
previous owned modal for replacement: it verifies that this widget is still
frontmost and `reading()` is false before running the replacement. A hidden modal
cannot authorize a show. The old dialog closes inside the approved operation, so
suppressing a replacement leaves the existing control intact. Source pickers also
wait while covered and retire their observer/timers on close. This does not change
the rule while a book is in the reading foreground.

For initial entry to that existing control, the explicit editor action supplies
its visible origin. The same frontmost/not-reading checks apply; catalog notice
suppression cannot disable a control the user is opening from the editor. An
automatic job has no such visible originating action.

## Android claimed reminder presentation (approved 2026-11-27)

The additional `Gate.reminder` type accepts only a current Library-issued claim.
Both bedtime and eye-rest sheets recheck owner generation, revision, visibility,
sleep and modal state immediately before drawing. Eye rest also requires the page;
bedtime may cover Home or a reader-opened menu. Hidden/sleeping always deny.
The companion evaluates bounded local values; it never shows an Activity or notification.
Ordinary `Gate.show`, notices, updates, network and restart negatives are unchanged.
A reminder draw never drains ordinary pending work. Input dismissal is consumed;
only a fresh explicit action can Sleep or Turn off. See [reminder rules](reminders.md).


### Native Android foreground state

Foreground eligibility reads the launcher's `android.isResumed()` scalar through
`Jni.isResumed`, as the pinned KOReader Android device itself does at
[`frontend/device/android/device.lua:228`](https://github.com/koreader/koreader/blob/9192014d8bd82a91dc1012473be0f238dedfdb54/frontend/device/android/device.lua#L228).
A reused reader/Home/settings owner can retain an older Resume memo after an app
switch; that memo must not decide whether the native activity is in front.
Native `false` always denies foreground eligibility. Host environments without the
Android helper retain the lifecycle memo fallback. Screen interactivity and the
claimed reminder's lifetime/kind predicates remain separate checks. This is a
scalar read, with no network, storage or Java reflection on paint.


The existing user-opened Storage and end-of-book exceptions also publish a
visibility-only reading report on entry/exit, as Home already does. The companion's
bulk pause owner therefore agrees with the plugin while preparing their bounded
snapshots, and resumes the reading gate on return to the page. These lifecycle
reports create no battery measurement and grant no network, notification or sleep
authority beyond the existing surface policy.
