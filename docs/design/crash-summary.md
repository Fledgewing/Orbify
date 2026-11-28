# BookSync persistent Android crash summary

Status: **APPROVED (2026-11-27)**. Android 0.12 parity gap 4.
Maintainer approved the design and mockups, including the coordinator change: display
times in the reader’s local time, not UTC.
X4 Pro/X4 keep existing diagnostics; X3 remains outside this Android outcome.

## Outcome and retention

Keep a small, deduplicated crash summary across process restarts, local only.
Do not automatically upload it, notify, open a sheet, restart KOReader or take focus.
The summary is available only when the user opens Setup → Details. Preserve the
existing Copy for support action; copying is explicit and never transmits anything.

Use an app-private, non-backed-up atomic record, bounded to 8 KiB, at most four
fingerprints. Retain component, BookSync version, exception type, first/last epoch
time (displayed in the reader’s local time), repeat count and up to eight allowlisted application frame symbols. Do not
retain exception messages, stack arguments, book titles/paths, document contents,
URLs, account identities or credentials. Never capture an arbitrary exception
string. Fingerprints use component/version/type/allowlisted frames, excluding time.
Repeated identical crashes update the same count. An unreadable/torn record is
ignored without preventing startup. Bound counters and handle clock rollback.

The companion records uncaught Java/Kotlin exceptions before delegating to its
previous/default handler exactly once, even if saving fails. Capturing native
KOReader failures needs a separate bounded handoff: do not pretend a companion
exception hook captures a native process crash. Do not scan unrestricted logs or
copy native crash dumps. Until that handoff is designed, label the scope precisely
as “Companion crashes”, with no fabricated plugin coverage.

## Approved Details mockup

Reuse the approved checklist Details typography and Back/Copy for support controls.
This approved block appears after the existing diagnostics. It adds no Home badge
or setup-attention count. Empty and saved states are shown in the
[review mockups](crash-summary-mockups.html).

```text
Details                                      Back
…existing diagnostics…
Companion crashes
2 matching crashes · BookSync 0.12.0-preview.1
Last seen: 27 Nov 2026, 18:00 (local time)
IllegalStateException · Worker.run
Saved on this reader. Never sent automatically.
[Clear crash summaries]

[Copy for support]
```

Empty: “No companion crash summaries saved.” Clear removes only these summaries;
then the same page displays the empty state. No confirmation dialog is proposed
for this bounded local diagnostic. Support text contains only the sanitised fields
above. A failure to load says “Crash summary unavailable”; it never crashes Details.

## Interface and budgets

UI requests a neutral Library diagnostics snapshot, never reads crash storage.
One local row, at most 8 KiB inside the existing Details screen budget; zero network,
subprocess or scan on paint. File IO/aggregation belongs behind the companion's
Library service. Clearing is an explicit Library command. Keep persistence off
KOReader's UI thread and preserve the reading gate.

## Acceptance

Unit tests: duplicate/restart/version separation, torn record, size cap, frame
allowlist, credential/path/message omission, clock rollback, write failure and
exactly-once handler delegation. Library tests: byte/row ceiling and explicit clear.
Emulator: synthetic crash in a disposable process, restart, reopen Details, check
count/dedup, copy sanitised support text, clear and reopen; no popup during reading.
No intentional crash runs against a real reader. Physical acceptance stays separate.

## Implementation on feature/0.12

`BookSyncApplication` installs the uncaught handler once per process. The record’s
schema fixes its component to Companion; it cannot represent native KOReader
failures. `CrashSummary` uses a bounded binary record in `noBackupFilesDir`, an
fsynced temporary file and atomic replacement. Record reads revalidate every
field, including exact frame/type allowlists, before exposing a summary.
`LibraryDiagnostics` owns asynchronous reads, local-time formatting and explicit
Clear. Setup → Details paints only its immutable snapshot and rejects callbacks
after leaving the page. The crash row is at most 8 KiB, alongside at most 8 KiB
of existing setup diagnostics; no paint scans, network or subprocesses are added.

The disposable emulator acceptance flow is `tools/e2e/android/crash_summary.py`.
Its crash trigger is added only to the external fixture build, never to shipping
sources or the shipping manifest. Physical reader acceptance remains separate.

## Slice X1: Lua fatal handoff

Maintainer request 2026-11-28 authorizes a fallback when the reported KOReader crash
cannot be reproduced: log the Lua traceback to KOReader and persist its cause for
the companion’s crash summary. This extends the original Companion-only scope.

The plugin wraps `UIManager:handleInput` (pinned KOReader
`9192014d8bd82a91dc1012473be0f238dedfdb54`, `frontend/ui/uimanager.lua:1459`)
with `xpcall`; the error handler retains the traceback before unwinding, logs it
with `logger.err` (Android’s KOReader tag), and atomically saves at most 4096 bytes
to `settings/orbit-cache/koreader-crash.txt`. The original error is rethrown.
Timed BookSync wrappers retain their inner traceback too. Saving failure cannot
replace the original error, and normal input/paint turns do no diagnostic IO.
This captures Lua failures escaping the input loop, not native signals, Android
kills, or a normal exit with code zero.

Setup → Details reads exactly that file off the UI thread, bounded to 4097 bytes
to reject oversized records. It includes the cause under its explicit KOReader
label in the existing local summary, within the 8 KiB presentation budget. Clear
removes this file too. This maintainer-requested local traceback can include Lua
error text and source paths, unlike the allowlisted Companion fingerprints; it
is never uploaded automatically. No logs or native dumps are scanned.
