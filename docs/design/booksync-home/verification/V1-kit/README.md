# V1 kit native evidence

M8C emulator, 1404×1872 at 300 dpi, actual KOReader v2026.07.1 widgets.
The disposable ServerAdapter fixture is the only server; no external BookOrbit calls.
The fresh AVD needed Bluetooth disabled after an Android system startup crash.

![Approved crops left and native widgets right](components.png)

![Native kit gallery](kit-gallery.png)

All fifteen component/state renders and callback/edge-value assertions passed with
`python3 tools/e2e/android/ui_kit.py --serial emulator-5642 --out <external output>`.
The renderer writes the dimensions to [render-tests.json](render-tests.json).
The KOReader symbol compatibility check also passed at the repository's pin.

Differences: Noto Serif/Sans replace the prototype's proprietary Iowan/Avenir;
fixture labels/counts and placeholder covers are synthetic. Native SVG rasterization
and font hinting differ from browser output. The slider reports taps, without animated
dragging. This PR does not rebuild Home; the next V1 PR consumes these primitives.

Revision after review: Search uses the leading magnifier, regular left label and
muted formatted count. Resume has the play icon and white inverted pill. Card
headers use bold title/All labels with a separate owned chevron; rows have a
light-grey rounded icon well, bold count and chevron. Progress uses a rounded,
outlined track with endpoint clipping. Existing factory names and arguments stay
valid; `search`, `inverted`, `trailingIcon`, `align`, `bold` and `count` are additive.

Home review round 1: Search now uses the approved bold label and muted regular count.
Native `ui_kit.py` checks both styles explicitly; all 15 component renders pass.

![Revised Search](search-pair.png)
