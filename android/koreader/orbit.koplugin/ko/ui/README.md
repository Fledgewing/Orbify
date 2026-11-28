# BookSync KOReader UI kit

`kit.lua` loads into the plugin environment as `BookSyncUI`. Construct a kit with
`BookSyncUI.new()` (702 design units across the display) or pass an explicit scale.
Widget dimensions and positions are native pixels; `K.px(n)` converts design units.
`K.text` converts the resulting pixel size back through KOReader's DPI scaling once.
It uses KOReader's bundled Noto Serif for display and Noto Sans for UI; the mockup's
Iowan Old Style and Avenir Next are proprietary platform fonts, unavailable in the
Android KOReader distribution. No system-font search or UI-thread file scan occurs.

Tokens follow `docs/design/booksync-home/prototype.html:40–46,115–162` and
`DESIGN.md`'s shared-screen tokens. Home's one-design-pixel tile outline is distinct
from the two-native-pixel screen/card rule in the in-book design. Native consumers
own accessibility scaling and can supply a larger scale. The firmware clients
retain their own drawing primitives; this module depends on KOReader only.

Each factory returns an ordinary KOReader widget, owned/freed by its parent:

| Factory | Options |
| --- | --- |
| `button` | text, icon, trailingIcon, w, h, variant (`solid`, `outline`, `ghost`, `inverted`), align, bold, callback, enabled |
| `search` | w, count, callback (regular left label, muted formatted count, leading magnifier) |
| `iconTile` | text, icon (owned mockup icon name, or native SVG name), w, h, callback, enabled |
| `card` | title, w, h, ink, count, all (callback); append children to `.content` |
| `cover` | w, optional h (default 2:3), file, title/author for placeholder |
| `progress` | w, h, value (0–1), ink |
| `segments` | w, h, items (labels), selected (1-based), onChange(index) |
| `toggle` | w, h, value, onChange(bool), enabled |
| `slider` | w, value (0–1), onChange(value), enabled |
| `row` | text, sub, count (or legacy detail), icon, w, h, callback, enabled |

The owned SVGs in `icons/` preserve the paths from the approved prototype’s
original 24-unit icon set. No upstream icon artwork is copied into this kit.

`canvas`, `put`, `text`, `label`, `frame`, `icon` and `hit` compose these widgets.
The kit does not query data, decode covers asynchronously, schedule work, call
UIManager, or change focus. The caller owns the reading gate and invalidation.
State controls report intent; callers rebuild from their authoritative state.
Sliders use tap-to-set rather than continuous animated dragging on e-ink.

`BookSyncUI.gallery()` returns the gallery widget and kit. Show it only through an
explicit developer action after leaving the reading foreground. It is intentionally
not registered in reader settings or the editable widget registry.

Run the actual native render/callback regressions after the emulator fixture setup:

```sh
python3 tools/e2e/android/ui_kit.py --serial emulator-N --out /tmp/kit-render
```

This paints every factory to a native KOReader blitbuffer and saves its PNG, then
captures the full gallery. It checks disabled actions, toggles, slider coordinates,
and invalid/out-of-range progress values. It refuses non-emulator serials.

Review revision: Search has a separate muted count; inverted pills preserve black
text/icons on the white hero action; headers use bold UI labels and an owned
chevron; row icons sit in light-grey rounded wells. Progress has a rounded,
outlined track and clips its fill to that outline at both endpoints. Existing
factory names and arguments remain supported.
