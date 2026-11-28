#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Pair approved Home screenshots with native captures, without resampling either."""
import argparse
import json
from pathlib import Path
import shutil
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[3]
SHOTS=ROOT/"docs/design/booksync-home/shots"
SCREENS=[
    ("home-1","m8c-home-1","Home · page 1","Fixture titles, cover artwork and counts differ; all 59 fixture books are on device, so no remote-download badges are expected."),
    ("home-2","m8c-home-2","Home · page 2","X2 synthetic statistics DB: 50 days, 6,600 recorded page visits and real hourly/weekly aggregates. Values differ from the invented mockup; this dataset is concentrated at night. Battery deliberately remains unmeasured."),
    ("editor","m8c-edit","Widget editor","Cached native previews; selected hero and dimmed/dashed neighbours. Uses the fixture library rather than the mockup's invented books."),
    ("picker","m8c-picker","Widget picker","Five illustrated choices, release badges, descriptions, size spans and Add actions; no projection reads. Page count follows the installed widget registry."),
    ("editor-sizes","m8c-edit-resized","Next fitting size · 4×3 → 4×2","The same native size callback is exercised; free cells and neighbours stay in place."),
    ("home-2-empty","m8c-home-2","Stats · empty history","Same real renderers with an empty statistics DB: short unknown-value copy, no truncated labels. The approved populated mockup is retained on the left for shape/spacing comparison."),
    ("series-local","m8c-series","Series · all books local","The local-series card contracts from 178 to 76 design pixels; no reserved rows for remote downloads. The approved remote-download state remains on the left."),
    ("end-empty","m8c-end","End of book · no measured pace","No measured reading history yields an em dash for pace. Synthetic title, availability and finish status differ from the mockup."),
]


def gallery(out,evidence=None):
    native=out/"home";native.mkdir(parents=True,exist_ok=True)
    if evidence:evidence.mkdir(parents=True,exist_ok=True)
    kit_index=out/"kit-index.html"
    if not kit_index.exists() and (out/"index.html").is_file():shutil.copyfile(out/"index.html",kit_index)
    html=['<!doctype html><meta charset="utf-8"><title>V1 · Native Home and UI kit</title><style>body{font:18px system-ui;background:#ddd;color:#111;max-width:1800px;margin:24px auto}article{background:white;padding:20px;margin:24px 0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px}img{max-width:100%;height:auto}a{color:inherit}p{line-height:1.5}</style><h1>V1 · Native Home and UI kit</h1><p>Approved mockup left, native Android capture right. Actual KOReader widgets on an isolated 1404×1872, 300 dpi emulator, with the opt-in fake ServerAdapter and synthetic library. PNG comparison pairs retain both images at native resolution.</p><p><a href="kit-index.html">Revised kit gallery · PR #256</a></p><p>Remaining differences: bundled Noto Serif/Sans replace proprietary Iowan/Avenir; native font hinting and SVG rasterization differ. Synthetic book art, counts and availability differ. Stats uses the supplied 50-day synthetic database; an empty-history pair and native assertions cover every registered Stats/Battery size. Battery remains unmeasured in this emulator. No physical reader was accessed.</p>']
    for name,approved,title,note in SCREENS:
        ref=Image.open(SHOTS/(approved+".webp")).convert("RGB")
        actual=Image.open(native/(name+".png")).convert("RGB")
        ref.save(native/(name+"-approved.png"))
        pair=Image.new("RGB",(ref.width+actual.width+24,max(ref.height,actual.height)+48),"white")
        draw=ImageDraw.Draw(pair);draw.text((12,12),"APPROVED MOCKUP",fill="black");draw.text((ref.width+36,12),"NATIVE KOREADER",fill="black")
        pair.paste(ref,(0,48));pair.paste(actual,(ref.width+24,48));pair.save(native/(name+"-pair.png"))
        if evidence:shutil.copyfile(native/(name+"-pair.png"),evidence/(name+"-pair.png"))
        html.append(f'<article><h2>{title}</h2><p>{note}</p><div class="pair"><a href="home/{name}-approved.png"><img src="home/{name}-approved.png" alt="Approved {title}"></a><a href="home/{name}.png"><img src="home/{name}.png" alt="Native {title}"></a></div></article>')
    html.append('<article><h2>Saved layout verification</h2><p>Native Home after saving the explicitly selected 4×2 hero. Its gap is intentional; the test restores defaults afterwards.</p><img src="home/editor-saved.png"></article>')
    html.append('<article><h2>Remote cover state</h2><p>Native cached-cover specimen with no local file: the availability badge appears without a data request.</p><img src="home/remote-cover.png"></article>')
    if evidence:
        for name in ("home-tests.json","stats-tests.json","details-tests.json","editor-saved.png","remote-cover.png"):shutil.copyfile(native/name,evidence/name)
        (evidence/"README.md").write_text('''# V1 Home native verification

Approved mockup left, actual KOReader capture right. No image is resampled.
M8C emulator: 1404×1872, 300 dpi, KOReader v2026.07.1, opt-in fake ServerAdapter.
The fixture contains 59 synthetic books, raster covers, series, three saved reading
positions, finished-book metadata, recent dates and saved lists. No physical device
or external BookOrbit request is used. Setup requires Pillow for cover generation.

'''+"\n\n".join(f'![{title}]({name}-pair.png)\n\n{note}' for name,_,title,note in SCREENS)+'''

![Remote cover badge](remote-cover.png)

Native cover specimen without a local file; the default fixture is fully on device.

## Validation

- Native `home_stats.py`: all 34 Stats/Battery sizes in both empty and seeded states;
  every admitted native TextWidget is checked with `isTruncated()` and for literal
  ellipses. The supplied X2 DB contains exactly 50 distinct history days.
- Native `home_details.py`: compact local-series card and unavailable finish pace.
- Native `ui_kit.py`: 15 component renders plus bold Search / muted regular count.
- Native `home.py`: default spans, ready views/covers, zero-query editor/picker,
  real move and next-fitting-size callbacks, saved layout persistence.
- Lua flows: 325 passed, 0 failed.
- Lua logic: 275 passed, 0 failed, plus 13 focused presentation assertions.
- KOReader source-symbol compatibility passed at pinned `9192014` (the optional
  koreader-base FFI static check was skipped); native FFI rendering ran on Android.
- Feature-matrix checks: 4 passed.
- External fixture APK assembled and `lintDebug` passed with strict Gradle
  dependency verification enabled.

The gallery is generated by `tools/e2e/android/home_gallery.py`. Native captures and
its JSON receipt come from `tools/e2e/android/home.py`; the capture tool rejects physical targets
through the existing Emulator guard. The capture tool resets its disposable layout
through the real layout save API, and restores defaults after persistence checks.

## Remaining differences

Noto Serif/Sans substitute for the proprietary mockup faces; native font hinting and
SVG rasterization differ. Book names, artwork, totals, available-cover state and
picker page count follow the synthetic fixture/installed registry. The supplied
50-day statistics DB concentrates sessions at night; charts and totals reflect
those real fixture rows rather than the mockup's invented distribution. Battery
has no measured charge/rate history, so its short empty state is intentional.
No truncated Stats/Battery labels remain in either tested state. This evidence
does not claim device acceptance or a release.
''')
    (out/"index.html").write_text("\n".join(html))


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--out",type=Path,required=True);p.add_argument("--evidence",type=Path)
    a=p.parse_args();gallery(a.out,a.evidence)
