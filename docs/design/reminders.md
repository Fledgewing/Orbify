# Bedtime and eye-rest reminders — BookSync 0.12.1

**APPROVED (2026-11-27) — design and every mockup.** Maintainer approval at
approximately 21:40 PT ("All approved") covers bedtime and Rest your eyes,
the reminder-only scope and the explicit reading-gate exception. Implementation
is authorized in the firmware R1 slices and the parallel Android slice. It ships on Android
(KOReader plugin + required companion), X4 Pro, X4 Classic and X3 after design,
simulator, size and device acceptance. No code or shipped-feature claim is added.

**Release scope:** the maintainer deferred bedtime and Rest your eyes to **0.12.1**.
The inert policy classes in #242 remain on 0.12; all delivery and UI implementation
targets `feature/0.12.1`.

[Static gallery](reminders-mockups.html) · [0.12.1 roadmap](../../ROADMAP.md)

## Outcome and settled decisions

The reader or a child sets a local reminder in Settings, such as “stop reading
at 9 PM”. At the chosen time BookSync draws one quiet sheet, including over an
open page. Reading remains available. There is no mandatory bedtime, lockout,
automatic book close, sound, vibration, PIN, parental enrollment or server dependency.
Only an explicit **Sleep** selection uses the existing position-save/sleep path.
**Got it** dismisses this occurrence; **10 more minutes** postpones it, repeatedly
if requested. Nothing wakes a sleeping or powered-off reader.

Up to eight bedtime (`kind=time`) reminders have On/Off, a local time, days and an optional short
message. Every day, Weekdays (Mon–Fri), Weekends (Sat–Sun), and Custom days are
available. Empty message displays **Time to stop reading**. Store minutes since
midnight, independent of display format. Show the device's 12/24-hour setting
throughout; 9:00 PM and 21:00 describe the same time. Custom days requires at
least one selected day. Message is plain single-line text, at most 60 Unicode
characters and 240 UTF-8 bytes; reject controls and newlines, never interpret markup.

The first source is local to the device. A future source may supply reminders
through the same capability; the UI never chooses a storage path or server.
Family controls, provisioning, authentication, remote editing and enforcement are
**not built in 0.12.1**. No local PIN is introduced. The local Reminders route must
remain reachable without unlocking unrelated Kids/PIN or protected settings.

A second kind, **Rest your eyes** (`kind=interval`), ships alongside bedtime
reminders in 0.12.1 on all four platforms. It is one device-local setting, **Off**
by default, with an interval of **20, 30, 45 or 60 minutes** (default **20**,
following the maintainer's 20-20-20 rule choice). It does not use one of the eight
bedtime slots. There is no custom eye-rest message, day picker, snooze, Sleep or
20-second enforcement. The static sheet says **Rest your eyes. Look at something
far away for 20 seconds.** with **Done** (initial focus) and **Turn off**.
The reader can dismiss immediately and keep reading.

## Library contract (proposed names, not an implemented wire protocol)

UI → Library → Reminders service → local storage/provider. Renderers receive
immutable values and send intents. They never call Companion, shared Settings,
a store, network, adapter DTOs or a scheduling engine directly. This extends the
[Home Library boundary](booksync-home/DESIGN.md#6-small-adapter-boundary-proposed-not-a-frozen-protocol)
and [plugin–companion interface](../../android/docs/INTERFACE.md); implementation
must update the versioned companion contract, both sides and its human documentation
together. This docs-only proposal does not register unused wire operations.

`capabilities.reminders` describes supported kinds and kind-specific operations,
limit 8 for time reminders plus one interval setting, message bounds, clock status
and sleep availability. Each row has a required `kind` (`time` or `interval`), opaque `id`,
`revision`, `source` (`local`, or a future registered source such as `family`),
service-supplied `sourceLabel`, `editable`, `enabled` and ready-to-draw labels.
The tagged payload for `time` contains `minuteOfDay`, seven-bit `days` and optional
`message`; `interval` contains `intervalMinutes` (20/30/45/60). Reject fields from
the other kind, unknown kinds and invalid intervals; a UI cannot change a row
from one kind to the other. IDs are namespaced by source;
local rows are device scoped, independent of account/catalog generations and
survive sign-out. UI renders labels; the service formats dates, days and times.

| Library operation | Input and bounded result |
|---|---|
| `reminders.list` | Immutable revision, at most 8 time rows plus the singleton interval row, clock status scoped to time reminders, per-kind count/limit, ready/pending/error/recovered state. One bounded snapshot, including the companion’s immutable `twelveHour` display preference. |
| `reminders.add` | Local time-reminder fields + idempotency key → durable ID/revision or validation/limit/storage error. UI cannot choose a source. |
| `reminders.edit` | ID, expected revision, complete kind-specific local fields, idempotency key → durable revision or conflict/error. |
| `reminders.setEnabled` | ID, expected revision, boolean, idempotency key → same result semantics. |
| `reminders.delete` | ID, expected revision, idempotency key → durable removal or conflict/error. Time kind only: ask “Delete reminder?” first; Cancel is initial focus. Interval is disabled, never added or deleted. |
| `reminders.claimDue` | Current visible presentation lifetime + candidate event ID → one-use presentation grant or stale/unavailable. Rechecks kind-specific clock/activity eligibility, revision, expiry, visibility, modal arbitration and sleep state. |
| `reminders.respond` | Grant/occurrence ID + time action (`gotIt`, `snooze10`, `sleep`) or interval action (`done`, `turnOff`) → accepted/stale/storage result. Reject wrong-kind actions. Only explicit Sleep returns a one-use native sleep intent; Turn off is an authorized local `setEnabled(false)` mutation. |
| `reminders.subscribe` | One lifecycle-owned subscription to bounded `changed`, `clockChanged`, `due` values tagged by kind; detach on retirement. No display callback from a worker. |

A `due` value carries kind, opaque event/occurrence ID, reminder ID/revision/source
and a bounded presentation payload. Time payloads carry original scheduled instant
and local date, effective due instant, `missed`, `dueLabel`, bounded message, expiry
and snooze sequence. Interval payloads carry a non-reused reading-session generation
and interval sequence, monotonic threshold and fixed message/actions; they contain
no invented wall-clock due time or missed label. It is data, never an
instruction to navigate, sleep or execute code. The service owns occurrence
identity, claiming, expiry, dedupe, sorting and persistent decision state. Device
reminders are not canceled by an account switch; stale screen subscriptions and
owner tickets are retired. A new visible owner can claim an eligible unpresented
occurrence without reviving the old callback.

Mutations reject stale revisions, non-local IDs, forged source values and
non-editable rows in the service, even if a caller bypasses the UI. Errors leave
the previous saved state live. Save returns success only after persistence;
pending does not mean saved. Retrying the same idempotency key cannot add a
second row or repeat an effect. An edit/disable/delete invalidates unclaimed
events and outstanding snoozes for that reminder. A currently visible obsolete
sheet closes safely, with no replacement popup; further responses are stale.

The interval singleton is present even when Off and uses the same `list`, `edit`,
`setEnabled`, `claimDue`, `respond` and subscription contract. Local storage owns
its stable ID; `add`/`delete` reject interval kind. Enabling or changing the
interval starts a full interval from zero; disabling invalidates any due grant.
Both the Settings switch and sheet Turn off go through Library and durable
revision-checked storage. Neither renderer owns a timer or writes settings.
Native lifecycle/input capture reports bounded reading/visibility/activity scalars
through Library; the companion or firmware Reminders service derives elapsed time.
No per-page IPC, file writes, directory scans or server calls are introduced.

### Future-source seam

Providers register inside Library, declare source identity/capabilities and
publish bounded neutral records/events. Only local registers in 0.12.1. A later
family adapter owns credentials, policy, protected updates, revocation and source
revision handling. A source string is a label, **not proof of authority**. No UI,
import file or unauthenticated remote message may create family authority.

Non-local rows always show their source and are read-only locally: no toggle,
edit, delete, or local override. Details say **Managed by Family** in the future
example. Both kinds remain reminder-only; a future source cannot add a lock or
disable Got it/snooze/Done under this contract. For a non-local interval source,
Turn off is disabled and labelled as managed by its source; the service rejects
local disable attempts. Done still dismisses. This resolves the local Turn off
action against the existing read-only source rule without creating a local override. A policy
change needs a separate approved design. Aggregate limit remains eight time reminders and one interval setting, across
sources; future admission must reject excess explicitly, never evict existing
local reminders. Provider priority/conflict/provisioning design is deferred.
The gallery labels this example **Future: not built in 0.12.1**; no family row or
family settings appears on an actual 0.12.1 installation.

## Reading-gate exception and bedtime presentation

This is an additional, narrowly typed exception to
[Nothing interrupts reading](reading-gate.md), approved on 2026-11-27. It does
not inherit an exemption for general messages, sync, errors, updates, navigation,
notifications, restarts or network activity. On implementation, update the gate
document, product-principle exception list and both guard suites together. Both
kinds use this single exception and the same claim/visibility/input guards;
the Home/menu and missed-time permissions below apply **only to time kind**.
Interval kind has the stricter page-only rules in the next section.

1. Only a claimed, unexpired reminder occurrence may use the new reminder
   presentation type. Gate checks run immediately before drawing on the main
   loop, including over a reader-opened menu. Sleeping, hidden or background
   consumers cannot draw. No companion activity/notification is started over
   KOReader or another app. If KOReader is not visible, retain eligibility until
   foreground return within the missed window.
2. Draw one non-animated sheet over the existing page, Home or menu, preserving
   its place and return target. One sheet at a time across reminder, position
   consent and other modal sheets. A reminder waits for the current modal to
   close and rechecks expiry; it never replaces or stacks on position consent.
   A visible reminder itself is not automatically expired out from under input.
3. Title **Reminder**, the message, optional **Due at 9:00 PM**, then **Got it**
   (initial focus), **10 more minutes**, **Sleep**, in that order on every platform.
   No countdown, animation, sound, forced close or compulsory action.
4. Back, page-turn buttons and page-turn gestures dismiss as Got it. Consume
   that input; the following fresh page turn changes the page. Taps outside the
   sheet also dismiss as Got it, never fall through. Do not replay any input.
   Opening input and held/repeated keys are drained before sheet focus activates.
5. Button navigation uses distinct Up/Down (or mapped focus actions) then a
   fresh Select to activate. Keys mapped to page-turn always dismiss, even if
   a generic dialog normally uses them to move focus. Hardware mapping tests
   must prove an independent route to all three actions. Touch requires a fresh
   release within the chosen action. Sleep is never the default or a shortcut.
6. Sleep responds to explicit selection only, checkpoints the occurrence and
   current position, then dispatches the existing native sleep path through
   Library. Never close the book to simulate sleep, install anything, or enable
   a permission/helper automatically. If native sleep is unavailable or saving
   fails, keep the page open and show **Could not sleep. Keep reading or try again.**
   in the user-opened sheet, with Got it focused. The companion has no autonomous
   right to lock the device because a reminder is due.
7. Dismiss restores the exact underlying page/menu and focus. Ready/background
   work cannot piggyback on this approved draw. Only explicit input/focus,
   dismissal or a visible error redraws the sheet; a timer never flashes it.

## Rest your eyes: continuous reading and presentation

**APPROVED (2026-11-27) — coordinator decisions (a)–(e), follow-up to PR #231.**

- Count elapsed time only while a book page is visible in the foreground and
  the reader is in use. User-opened menus/panels, Home, hidden/background state,
  closed books and sleep pause accumulation and cannot claim or show an eye-rest
  sheet. A loaded document beneath Home or a menu is not active reading.
- Use native input/activity and lifecycle state, not page count or catalog data.
  A page turn, reading tap or reading key counts as activity; automatic refresh,
  sync, clock ticks and arriving data do not. While a page is visible, presume
  reading until the native idle duration reaches five minutes. At that boundary,
  discard the continuous count before evaluating a due threshold. Do not wake,
  poll sensors or require a page turn to evaluate a due interval.
- At **five minutes or more** continuously idle, closed, asleep or otherwise
  outside active reading (including menus), reset the count and invalidate any
  undrawn interval occurrence. Shorter interruptions pause the count and preserve
  the accumulated active duration; no time spent outside reading is added. Check
  one inactivity gap across lifecycle changes before processing resumed input, so the wake/resume key cannot hide a
  five-minute break. Switching books within a shorter gap preserves the count.
- Use monotonic elapsed time for accumulation and suspend-aware gap measurement;
  wall-clock correction, timezone and 12/24 h changes cannot trigger or postpone
  eye rest. The decision-5 wall-clock qualification below still applies to bedtime,
  but **unknown wall time does not prevent interval reminders**. A process/cold
  restart starts at zero; persist the setting, not a reading-time history.
- At the selected threshold, claim one small sheet over the page. Render the
  fixed text **Rest your eyes. Look at something far away for 20 seconds.** and
  **Done**, **Turn off**, in that order. Done has initial focus. Back, page-turn
  buttons/gestures and outside taps act as Done, consuming the input without
  falling through. Drain held/repeated/opening input; a fresh explicit selection
  alone can Turn off. Use the same distinct focus navigation as the bedtime sheet.
- The text is static: **no countdown, animation, tick-driven redraw, timed close
  or extra e-ink refreshes**. The reader need not wait 20 seconds. Done dismisses
  and starts the next full interval when active reading resumes; time under the
  sheet does not count. No sound, lock, book close, Sleep action or forced break.
- Turn off persists local `enabled=false` through Library, then dismisses. If
  persistence fails, retain the setting and sheet with Done focused and the
  user-action error **Could not turn off reminder. Try again.** No repeated timer
  error or popup. Non-local records remain read-only as described above.
- **Bedtime wins at the same moment**, including a due bedtime snooze: arbitrate
  all candidates before granting a sheet, independent of callback/event order.
  Consume the conflicting eye-rest threshold and reset its count to zero; it
  waits for its next full interval of active reading. No immediate eye-rest sheet
  after bedtime dismissal, no snooze of eye rest and no missed eye-rest backlog.
- If another modal/menu is on top at delivery time, retire the undrawn eye-rest
  candidate and start its next full interval on active reading return; never hold
  it for Home or menu closure. A bedtime arriving after an eye-rest sheet is
  already visible follows the existing one-sheet rule and waits for dismissal;
  it cannot replace the sheet mid-input. Resetting/retiring a session makes late
  grants and duplicate Done/Turn off responses stale without another draw.

The default Settings row says **Rest your eyes — Off** with **Every 20 minutes
of reading**. Its local editor has On/Off and Interval only; the interval picker
contains **20 minutes**, **30 minutes**, **45 minutes**, **60 minutes**. Selecting
an interval updates the draft, Done returns to the editor, and Save persists.
Back discards the draft. There is no add/delete or per-book setting. The gallery
also shows On, the disable-failure state and a future read-only source sheet.

## Bedtime scheduling, missed times and snooze

For time kind, the service evaluates at startup, foreground/resume, known-clock/timezone change,
a reminder mutation and a coarse active-runtime tick (at most once per minute).
It does not depend on page turns. No Android exact alarm, special alarm permission,
wake lock, RTC wake timer, periodic network job or background service is added.
While suspended/off, do no work. Device sleep and ordinary OS timer delays are
expected; this is not an alarm-clock precision promise.

| Situation | Rule |
|---|---|
| Active and visible at due time | Offer one occurrence on the next evaluation (target within one minute while runtime executes). |
| Home or a menu | Same sheet, same words/actions; restore the underlying view on dismissal. |
| Asleep, off, or KOReader hidden | Never wake or foreground it. On next visible use, offer once if `0 ≤ now − due ≤ 60 minutes`. Show **Due at 9:00 PM** when first presentation is after the scheduled minute. |
| More than 60 minutes late | Expire silently. Never replay a backlog from yesterday. Check the previous local date too for a reminder crossing midnight within the window. |
| Multiple eligible reminders | Sort by effective due instant, then stable ID. After dismissal restore the underlying view; offer at most one waiting sheet on the next fresh user interaction, rechecking expiry. No immediate cascade. |
| Got it / Back / outside tap / page turn | Consume this occurrence; tomorrow's selected day is unaffected. |
| 10 more minutes | Replace this occurrence's pending delivery with one snooze due 10 elapsed minutes after response; no extra reminder slot. Repeated snoozes allowed. Original recurrence stays consumed. |
| Sleep or reboot during snooze | Persist target wall instant and original occurrence. On visible return, apply the same 60-minute window from the snooze target. Unknown time holds it without drawing. |
| Snooze after midnight or across a day change | Keep the original occurrence; do not re-test its weekday. New regular occurrences remain independent; at most one pending snooze per reminder, with a new snooze replacing its older pending one. |
| Change time/days or enable a reminder | A new revision starts with its next scheduled instant strictly after save; do not retroactively fire today's earlier time. Explicitly show the saved state without a toast. |

For each time reminder keep a durable high-water local occurrence date/claim and a
bounded latest response. A regular occurrence is identified by source/ID and
scheduled local date; revision is checked for validity but does not erase the
high-water date. Backward clock changes or a repeated DST hour never repeat a
claimed date. Forward jumps offer only the most recent eligible occurrence per
reminder within 60 minutes. Android uses the system timezone: a nonexistent DST
time maps to the first valid minute after the gap; a repeated time uses its first
instant. Firmware uses its current displayed UTC-offset setting (no invented
DST database), and applies any offset change as a clock change. Changing device
format alone never changes an instant. Services calculate the day after applying
the timezone/offset, including midnight, leap years and weekends.

For time kind, persist a presentation claim before granting its one draw.
For interval kind, a main-loop-owned atomic in-memory session/sequence claim is
enough: restart resets the count and invalidates old session tokens. Repeated events,
process restart and response retries cannot draw it twice. A crash after claim
but before drawing may lose that occurrence; prefer one quiet missed reminder
to repeating an already acknowledged one. Snooze persists atomically with its
response. Within a boot use suspend-aware elapsed time for ten minutes; after
restart use the persisted target only when wall time is known. A clock correction
within the boot must not stretch or shorten an elapsed snooze. No per-minute or
per-page storage writes; write only mutations, claims and responses.

## Exactly when firmware time is known

Source inspection pins (read from the local firmware Git objects; no checkout,
SDK change, time-setting operation or device access):

| Evidence | What exists today |
|---|---|
| F12 `84918ac86cde2712fc166e35a4106a42c62d37d7`, [`system/ReadingGate.cpp:4`](https://github.com/Fledgewing/booksync-firmware/blob/84918ac86cde2712fc166e35a4106a42c62d37d7/src/booksync/system/ReadingGate.cpp#L4) and [`ReadingGate.h:7`](https://github.com/Fledgewing/booksync-firmware/blob/84918ac86cde2712fc166e35a4106a42c62d37d7/src/booksync/system/ReadingGate.h#L7) | Hidden/sleeping draws denied; Message denied while reading; only user-opened/end-of-book/position-consent exceptions exist. Reminder type and claim are new work. |
| F12 [`services/Delivery.cpp:24`](https://github.com/Fledgewing/booksync-firmware/blob/84918ac86cde2712fc166e35a4106a42c62d37d7/src/booksync/services/Delivery.cpp#L24), [`Delivery.h:29`](https://github.com/Fledgewing/booksync-firmware/blob/84918ac86cde2712fc166e35a4106a42c62d37d7/src/booksync/services/Delivery.h#L29) | Device effects adopt state separately from presentation; callbacks must still check the gate. The 120-second pending-ticket timeout is not the reminder's 60-minute eligibility window. |
| Base `421366a1dd0f0114c42dc286b52e9c25eabb37ce`, [`main.cpp:1496`](https://github.com/Fledgewing/booksync-firmware/blob/421366a1dd0f0114c42dc286b52e9c25eabb37ce/src/main.cpp#L1496) | Begin HalClock, attempt RTC calendar adoption, then initialize TrustedTime's persisted floor. |
| Base [`lib/TrustedTime/TrustedTime.cpp:124`](https://github.com/Fledgewing/booksync-firmware/blob/421366a1dd0f0114c42dc286b52e9c25eabb37ce/lib/TrustedTime/TrustedTime.cpp#L124), `:149`, `:221` | NVS floor can seed system time on cold boot. RTC adoption checks plausible range, floor and excessive lead; `trustedNow()` is a monotonic floor suitable for expiry, not proof of accurate current bedtime. |
| Base [`WifiSelectionActivity.cpp:1472`](https://github.com/Fledgewing/booksync-firmware/blob/421366a1dd0f0114c42dc286b52e9c25eabb37ce/src/activities/network/WifiSelectionActivity.cpp#L1472), [`TrustedTime.cpp:93`](https://github.com/Fledgewing/booksync-firmware/blob/421366a1dd0f0114c42dc286b52e9c25eabb37ce/lib/TrustedTime/TrustedTime.cpp#L93) | Wi-Fi completion starts asynchronous SNTP; a successful callback notes time. Merely associating to Wi-Fi does not prove a sync succeeded. |
| Base [`lib/hal/HalClock.cpp:218`](https://github.com/Fledgewing/booksync-firmware/blob/421366a1dd0f0114c42dc286b52e9c25eabb37ce/lib/hal/HalClock.cpp#L218), [`ClockSyncActivity.cpp:65`](https://github.com/Fledgewing/booksync-firmware/blob/421366a1dd0f0114c42dc286b52e9c25eabb37ce/src/activities/settings/ClockSyncActivity.cpp#L65) | RTC sync waits for NTP then writes the RTC; manual sync records saved flags. Saved “has synced” flags alone are historical, not current clock quality. |

**Qualification to coordinator decision 5:** “no sync since boot” is not always
“unknown clock”. A valid accepted RTC, or a previously synchronized system clock
retained through deep sleep, can know current time without a new network sync.
Conversely a plausible NVS floor can be hours/days old and must not fire time reminders.
This qualification is retained from PR #231; interval kind uses elapsed time only.
The current clock API does not expose enough provenance to prove that distinction.

Proposed Library `clockStatus` is `known` only after a successful SNTP result in
the current cold-boot lifetime, an accepted live battery-backed RTC reading, or a
validated retained known-clock marker plus running system clock across deep sleep.
Mark `unknown` after cold power loss without accepted RTC until successful sync;
a floor-only restore, date-shaped epoch, Wi-Fi connection or persisted sync flag
never upgrades it. Keep validity through ordinary Wi-Fi disconnects. If provenance
or the running clock becomes invalid, stop time-kind firing and invalidate
undrawn time-kind grants.
Add that provenance at the clock/runtime seam; do not infer it by watching a number
increase. The actual RTC availability per board must be verified through the pinned
HAL/SDK at implementation, not assumed from a device name or simulator clock.

When unknown, the bedtime section of Settings says exactly **Reminders need the time. Connect to Wi-Fi
once to set the clock.** The reader may still add/edit time reminders; no time reminder fires.
Rest your eyes can still run from monotonic active-reading time, with its row
labelled **Uses reading time; no clock needed** in this state.
Connect to Wi-Fi is a reader-started existing connection route, with success only
after time sync. After clock recovery evaluate the usual missed window, not all
missed occurrences. Android uses the OS wall clock/timezone and receives time
change events; it does not initiate time sync or add a time-setting permission.

## Platform integration and Settings

| Platform | UI and owner |
|---|---|
| Android | BookSync reader settings → **Reminders**, reachable from the KOReader plugin menu without PIN. Plugin calls `Library.reminders`; companion worker owns storage, recurrence, time formatting, dedupe and scheduling. Library owns a lightweight active-runtime tick and due subscription; it consumes already published small values while reading. No network/SQLite query/JSON decoding/background scan on page paint; no Lua scheduling fallback if companion is missing or mismatched. Use existing workerProblem behavior. |
| X4 Pro touch | Settings → **Reminders**. Large touch rows and buttons, bottom-docked time keypad/message keyboard, fields and actions above it. Sheet retains the page. No gesture or outside tap can select Sleep. |
| X4 Classic buttons | Same words and fields, visible ring focus, digit-by-digit time adjustment and focused text keyboard. Back returns without saving draft; explicit Save commits. Page-turn mappings dismiss a due sheet rather than traversing its actions. |
| X3 text/buttons | Settings → **Reminders**, bounded numbered list, paged four rows, text editors with explicit focus and Select. No touch, spatial grid, artwork, PSRAM requirement or missing controls. Same recurrence and due contract as S3. |

The companion currently generates eight settings sections including **Reading
and Home** (`shared/settings/schema.json:5`; `SettingsPages.kt:219` under
`android/companion/app/src/main/java/net/fledgewing/orbitcompanion/`, inspected on
integration commit `552d04b5`). Proposed companion discoverability is one
**Reminders** information row under Reading and Home, searchable as reminder or
bedtime or eye rest, saying **Set reminders in BookSync reader settings**. It does not add a
second editor or automatically launch KOReader. It remains readable without PIN;
local reminder access cannot depend on protected companion settings. The gallery
includes this companion information state alongside the reader settings entry.

Firmware `services/Reminders` owns policy and its local provider; `storage/RemindersStore`
owns durable mechanics, exposed only through Library. Reuse F06 atomic current/tmp/backup
publication and F33 validation/recovery style: F06
[`storage/FilePublish.h:23`](https://github.com/Fledgewing/booksync-firmware/blob/01a59d21446be46f8271b979c88dbbbdb8cd1a7e/src/booksync/storage/FilePublish.h#L23),
F33 [`storage/LayoutStore.cpp:26`](https://github.com/Fledgewing/booksync-firmware/blob/e62455b4fc10895791a740ed56c545d28557cb72/src/booksync/storage/LayoutStore.cpp#L26)
and `:40`. Serialize one worker, validate version/length/checksum and every field,
close files, reconcile selection after ambiguous publication failure. Never open
tmp as committed data. Missing store starts empty; corrupt current falls back to
valid backup, with **Previous reminders recovered** visible only in Settings.
If neither is valid, retain bytes, schedule nothing and show **Reminders could not
be loaded** with Back/Retry. Never silently overwrite damaged data or reset to empty
success. Full/read-only/missing storage keeps the last valid schedule and unsaved
draft, showing **Could not save reminder. Try again.** only on the explicit screen.

Keep occurrence state independent of catalog/account revisions. Reuse device-effect
delivery for durable changes, but no durable callback may paint. A runtime-owned
reminder presenter acquires the current visible lifetime, validates a claim and
uses a new narrowly typed ReadingGate reminder exception. Do not label it
`UserOpened`, `Message` or `PositionConsent`, or weaken their tests. Delivery tickets
may time out/retire while a still-eligible occurrence stays service-owned.

Android's existing `SLEEP_NOW` requires device-admin approval and can leave the
screen on without it (`android/docs/INTERFACE.md`, SLEEP_NOW row); the Library
must expose sleep availability and use that existing path, never promise success
or request permission from a due sheet. Firmware uses its existing position-save
and `main.cpp:1248` sleep sequence at the base pin. No new loan-expiry, forced-lock
or book-close path is introduced.

## Budgets (limits to enforce; not measured performance claims)

| Surface/work | Hard proposed limit |
|---|---|
| Settings list | 8 time rows plus one interval row, four per page; ≤8 KiB published snapshot including labels; one lifecycle acquisition, zero work on paint. |
| Add/edit/time/days/message | One draft ≤1 KiB; interval picker has 4 fixed choices; 7 day choices for time kind; 60-character message; static picker/keyboard layout. No save per keystroke; Save only. |
| Due sheet | One ready occurrence ≤1 KiB; 3 time-kind or 2 interval-kind actions; zero data reads, JSON decode, subprocesses, network, storage or companion round-trips during paint. |
| Runtime service | Scan ≤8 time schedules plus one interval accumulator per tick/lifecycle event; ≤8 stored snoozes; interval runtime state ≤64 bytes. Calculate regular occurrences from the schedules, without a backlog queue; publish at most the earliest eligible candidate per reminder. No catalog/history joins or directory scans. |
| Durable store | ≤8 KiB validated envelope including 8 time records plus one interval setting, high-water claims, one snooze and latest mutation/response receipt per record. Current + tmp + backup ≤24 KiB. Android equivalent bounded transactional records. No unbounded receipt/event history. |
| Delivery | Publish at most 8 bounded due values, total ≤8 KiB, into the existing mailbox budget; dedupe event IDs and coalesce by reminder. Arbitrate at most 9 candidates in memory before publishing ≤8 in a batch; bedtime wins over interval. Never evict unrelated durable lifecycle work for a reminder. |
| Firmware working memory | Target ≤4 KiB resident service state and ≤1 KiB worker scratch; explicit fixed buffers, stream storage, no second framebuffer/PSRAM-only implementation. Measure actual peak/stack before acceptance. |

Preload/materialize outside paint. While reading, the Android timer receives
companion-published memo values through Library's existing event delivery, with
bounded worker evaluation off the UI thread. A due event may request its one
authorized draw; ordinary Home/settings publications remain silent. Declare named
screen/service budgets and timing spans in the existing registry, counting nested
rows and decoded bytes. Coalesce duplicate pending ticks; never accumulate work.
No wall-time callback does SD/NVS I/O or rendering on the firmware network task.
The interval service reuses the active-runtime scheduler and native lifecycle/input
capture; clock ticks never repaint. Coalesce activity scalars in the existing
Library bridge, without per-page companion round-trips; ensure lifecycle/pause
transitions and the five-minute boundary are not lost. Interval ticks/claims/Done
perform no disk writes; only explicit settings/Turn off persist through the worker.
Maintain the firmware plan's **131,072-byte app-slot reserve per device**; report
image/map/static RAM/runtime heap deltas on all three profiles. No size or timing
result is claimed by this document.

## Visible states and interaction acceptance

The self-contained gallery draws every state on Android, X4 Pro, X4 Classic and
X3 with one vocabulary: entry, empty list, saved/on/off list, unknown clock,
add, edit, time (12 and 24 h), days presets, custom days, message entry, delete
confirmation, full list, saving, save failure, recovered/unreadable storage,
in-book due, missed, due over Home/menu, sleep unavailable/failure and future
read-only detail; eye-rest Settings rows (Off/On), editor, interval picker,
page sheet, Turn off failure and future managed sheet. The companion information row is an additional Android state.
Every view and caption is **APPROVED (2026-11-27)**. Touch keyboards are direct screen
children at the bottom. The 480 × 800 gallery viewport follows the approved
firmware gallery, not physical panel resolution or proof of font fit. Android
uses rev-16 typography/actions at that review scale; actual tablet density and
X3 528 × 792 fitting need render acceptance. Draft Back discards without changing
the saved record; Cancel in deletion changes nothing. Days/time/message Done
returns to the draft; only Save persists. At eight time reminders Add is disabled with
**8 bedtime reminders — limit reached**. Enable/disable is an explicit row action;
non-local rows never render a toggle. The interval setting remains available
at the eight-time-reminder limit and while the wall clock is unknown.

## Tests and acceptance before shipment

Design approval must name this document and the gallery. Implementation then
adds tests in the existing suites; these are acceptance requirements, not tests
claimed to exist in this PR.

- Interval fixtures: default Off/20, each of 20/30/45/60, invalid values, singleton
  add/delete rejection, no time-kind fields/actions accepted. Short/long reading
  sessions and pause gaps at 4:59.999 versus 5:00; idle/menu/Home/closed/sleep
  transitions, switch books, resume input and due/reset at the same boundary.
  Never fire outside the page, including a stale ready callback after navigation.
- Arbitration in both event orders: simultaneous bedtime (including snooze) wins,
  eye rest starts a full next interval and never follows bedtime immediately.
  Other modal/position consent retires undrawn eye rest. A visible sheet is not
  replaced mid-input; duplicate/retired session responses cannot redraw.
- Interval input/storage/clock: exact fixed wording and Done initial focus on all
  four platforms; page turn/Back/outside tap dismiss without Turn off or fallthrough;
  explicit Turn off persists or leaves enabled on failure. Future managed Turn off
  is disabled/rejected; Done remains available. No countdown, timed close, extra
  e-ink refresh, sound, wake, lock or forced break. Unknown wall time, clock jumps
  and timezone changes leave elapsed scheduling intact; restart resets to zero.
  Tick/Done never writes storage or adds per-page IPC; no backlog after Home/wake.
- Shared deterministic clock fixtures: 12/24 h, every day/weekdays/weekends/custom,
  empty/custom messages, invalid fields, eight valid time rows versus nine rejected (plus the interval
  singleton), leap-day, midnight and
  timezone/DST gaps/repeats. Changing format is display-only; enabling/editing
  never backfires; backward/forward jumps honor the high-water claim.
- Fake clock/runtime: due without page turns, Home/menu/book, 60-minute inclusive
  boundary versus 60 minutes + 1 second, late at midnight, sleeping/off/hidden,
  no wake/permission requests, no stale backlog and simultaneous events without
  a cascade. Repeat snooze, elapsed time across clock correction/suspend,
  restart with known/unknown clock, snooze replacement and revision invalidation.
- Claim/response reliability: duplicate tick/event/response; crash before/after
  claim, draw, response and snooze commit; restart dedupe; callbacks after view
  retirement; A→B→A owner transitions; account sign-out retains local schedule.
  Ticket timeout never becomes a wake or redraw. Invalid source/revision grants
  cannot exercise the gate exception or native sleep.
- Source fakes: local CRUD; future non-local read-only projection; forged family
  writes/toggles/deletes fail in service; capacity overflow never evicts. No live
  family registration/credentials/server calls in 0.12.1.
- Gate guards on both Android sides and F12: only valid reminder claims permit a
  reminder draw while reading. All existing update/restart/network/news negatives
  remain. Book/position/other-modal transitions revalidate before draw; hidden
  and sleeping always deny. Reminder delivery causes no activity or notification.
- Input/render acceptance on all four platforms: every gallery state; initial
  Got it/Cancel focus; stale/held Select, page-turn keys/gestures, Back, outside
  tap and touch drag never select Sleep. Distinct focus keys reach snooze/Sleep.
  Dismiss restores exact page and focus; no clipped message, keyboard or action.
  Sleep saves position and uses native sleep; unavailable/failure keeps reading.
- Storage faults at every write/sync/rename/commit boundary, full/read-only/missing
  card, corrupt primary/backup and unknown version. Preserve bytes/last schedule;
  no success before durable commit and no scheduling from unvalidated data.
- Clock provenance: accepted RTC, retained deep-sleep clock, cold boot with only
  stale NVS floor, failed/successful SNTP and Wi-Fi without SNTP. Unknown shows
  the exact help text and cannot grant time-kind due; interval remains eligible; recovery honors only 60 minutes.
- Budgets/boundaries: zero paint I/O/JSON/network/spawns/round-trips, bounded
  snapshot/event/storage limits at 10,000-book catalog size; no companion fallback;
  all firmware profiles meet size/heap gates. Host timings are not device evidence.

After approved implementation, required Android unit/flow/boundary checks and
firmware host/simulator checks run normally. A maintainer performs real-device
acceptance on each platform before release using the normal test-build path:
set a reminder, read across its due minute, snooze twice, dismiss by page turn,
choose Sleep explicitly, wake within/outside the missed window, and cold-start
without time sync. Also enable eye rest, read across its interval, dismiss by
page turn, verify a five-minute break reset and simultaneous bedtime priority,
and turn it off explicitly. Agents do not sideload or operate devices. This design PR
publishes no build, release, feed entry or feature-matrix shipment claim.

## Validation of this documentation change

Repository branding and feature-reference checks pass (`test-repo-name.py`,
`test-features.py`), as does `git diff --check`. Original PR #231 headless browser QA of all 105
views at 1500, 1200 and 390 px found no clipped content, horizontal overflow,
broken gallery anchors or page errors. All six touch time/message keyboards are
direct screen children docked at the bottom. Representative in-book, message,
days, unavailable-Sleep and future-source views were rendered and visually
inspected; duplicate focus indicators were corrected. The HTML has inline CSS,
no scripts or external assets. These checks validate documentation rendering;
they do not prove firmware behavior, device font fit or performance.


Eye-rest follow-up QA: all 133 views (33 shared states × four platforms, plus
the companion information row) pass the same 1500/1200/390 px clipping, overflow,
anchor, page-error and bottom-keyboard checks. The new Off/On settings, editor,
interval picker, page sheet, Turn off failure and future managed sheet are **APPROVED (2026-11-27)**. Representative eye-rest renders were visually inspected.
Repository branding, feature-reference checks and `git diff --check` pass.

### Shared-kit time editor

The Android editor uses the snapshot’s `twelveHour` preference, separate hour and
minute fields, an AM/PM toggle when applicable and a docked numeric keypad. Field
selection replaces digits; Back discards the picker. Done sends a canonical draft
through the companion validator; the outer Save remains the only durable edit.
No OS format lookup, file access or schedule evaluation runs in the drawn page.
The companion still rejects invalid hours/minutes and owns localized formatting.

The approved Unknown clock screen is also exercised as a disposable Library
provider-error fixture. Android continues to trust the OS clock, as above; this
fixture proves presentation and does not add a clock-fault detector or claim
recovery. Its Connect to Wi-Fi action opens the companion’s existing manual Wi-Fi
controls. It never initiates OS time setting or displays a time-sync success.
