# V4 emulator review

Round 1: setup is an owned non-blocking row; values are bold with chevrons; account rows, helper footers, compact result, saved goal 12 and outlined margins Done are corrected. V4 settings, account, goals and custom editors. Left: approved crop. Right: actual KOReader on the dedicated M8C-sized Android emulator. Fixture: 59 synthetic books, generated covers, six in progress, five finished and 58 days of history. No physical reader was used.

Bundled Noto/FreeSerif replace unavailable proprietary Avenir/Iowan/Baskerville/Literata faces. Native KOReader keyboards and Android permission dialogs are retained. Account connection uses the available signed-in state, not an invented connectivity probe. Battery estimates remain pending until sufficient device observations exist. Existing later reading-statistics and explicit login-source settings remain; some section pagination differs from older crops. Goals/companion references are conceptual component mockups; surrounding document prose is not reader UI.

Capture: `python3 tools/e2e/android/settings_v4.py --serial emulator-N --out <out>`, followed by `reader_companion.py` for real Android denial/grant/revocation. The companion is the disposable `tools/e2e/android/E2eServerAdapters.kt` fixture, not a live server.

No new feature or setting is introduced: this is Android presentation repair over existing interfaces. Firmware uses its existing native settings presentation and is outside this Android UI slice.
