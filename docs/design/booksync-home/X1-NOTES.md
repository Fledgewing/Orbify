# Slice X1: KOReader stability and offline navigation

Maintainer request 2026-11-28; the revised scope replaces menu default/migration
work with companion launch and Home routing fixes. `clean_menus` remains opt-in;
this slice changes no reading-panel appearance or saved menu preference.

The `feature/0.12.1` Android test workflow 46130229901 produced
`android-test-0.11.5-preview.66`, matching the device log's version. Inspection of
the APK manifest finds one MAIN/LAUNCHER entry, `StatusActivity`, no activity
alias, and a separate MAIN/HOME entry, `HomeActivity`. The launcher entry exists
and is exported. The Full-mode activity redirected to `LauncherActivity` and
finished its task root; it now renders the same Full companion screen in its
original root. There is no startup redirect from the companion icon to KOReader.
A resumed companion page also prevents an uncovered Home activity from covering
it. Explicit Home presses still navigate normally.

The supplied device log at line 4551 shows Home intercepted for `signed_in`, then
recovery with no command. Home no longer opens a setup prompt before navigation;
sign-in is an optional checklist action, not a prerequisite for local reading.
Both Home presses and uncovered recovery send explicit navigation, preserving the
user's existing smart/library choice. The untrusted-KOReader command restriction
is preserved. Existing Home sign-in/account actions remain available.

Retirement handles callable HandlerSandbox tables and inherited lifecycle hooks,
and supplies an inert constructor rather than executing a legacy constructor.
The neutral retirement descriptor and companion handshake still control writer
safety. No upstream project is changed.

The reported fatal crash was not reproduced in 20 Home/book/close/Home/swipe
cycles, including after a companion PATCH. Full unfiltered emulator logcat was
captured; recoverable SQLite busy reads did not terminate KOReader. One initial
driver trial used the raw close primitive and caused a normal exit code zero;
the recorded 20-cycle run uses KOReader's normal Home/book-close navigation.
A separate deliberate fatal fixture verified the KOReader-tag traceback and persisted cause; it is not the device crash. The real legacy handler returned `companion_owned`.
The fallback fatal traceback handoff is described in
[crash-summary](../crash-summary.md#slice-x1-lua-fatal-handoff).

The review gallery compares the approved Home and companion references with the
1404×1872, 300 dpi emulator. Synthetic books, covers and history differ from the
mockup data. Existing Home/companion typography and composition gaps belong to
the visual slices; this slice changes navigation and lifetime, not their design.
X4 Pro/X4/X3 keep their firmware navigation and diagnostics: these fixes concern
Android tasks and KOReader Lua exclusively.
