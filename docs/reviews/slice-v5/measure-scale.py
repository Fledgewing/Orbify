#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Measure approved/native cap heights against full image width (Pillow only).

Run against the review gallery's approved/, native/ PNGs and native UI XML dumps:
  python3 measure-scale.py --gallery <gallery directory> --out <report directory>
Crops exclude neighboring text and borders. Hero/row samples isolate one capital,
so descenders do not inflate the reported cap height. No image is modified.
"""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, ImageChops


def ink(path, box, white=False):
    image = Image.open(path).convert("RGB")
    red, green, blue = image.crop(tuple(box)).split()
    if white:
        channel = ImageChops.darker(ImageChops.darker(red, green), blue)
        mask = channel.point(lambda value: 255 if value > 220 else 0)
    else:
        channel = ImageChops.lighter(ImageChops.lighter(red, green), blue)
        mask = channel.point(lambda value: 255 if value < 100 else 0)
    return mask, image.width


def runs(projection):
    result = []
    for position, present in enumerate(projection):
        if present:
            if not result or position > result[-1][-1] + 1:
                result.append([position])
            else:
                result[-1].append(position)
    return result


def height(mask):
    box = mask.getbbox()
    if box is None:
        raise ValueError("empty measurement crop")
    return box[3] - box[1]


def capital(mask, index=0):
    columns = runs(mask.getprojection()[0])
    selected = columns[index]
    return height(mask.crop((selected[0], 0, selected[-1] + 1, mask.height)))


def node(gallery, name, text):
    for item in ET.parse(gallery / "native" / (name + ".xml")).iter("node"):
        if item.get("text") == text:
            return list(map(int, re.findall(r"\d+", item.get("bounds"))))
    raise ValueError((name, text))


def tile_bounds(gallery):
    root = ET.parse(gallery / "native/status-full.xml").getroot()
    parents = {child: parent for parent in root.iter() for child in parent}
    item = next(item for item in root.iter("node") if item.get("text") == "Other apps")
    while item.get("clickable") != "true":
        item = parents[item]
    return list(map(int, re.findall(r"\d+", item.get("bounds"))))


def measure(gallery):
    results = []
    for name in ["status-full", "status-full-bottom", "goal-editor", "checklist-needs", "settings", "crash-saved"]:
        with Image.open(gallery / "native" / (name + ".png")) as image:
            if image.size != (1404, 1872):
                raise ValueError(f"{name}: expected 1404×1872, got {image.size}")

    def record(label, approved, native, kind="cap height"):
        reference_size, reference_width = approved
        native_size, native_width = native
        error = 100 * ((native_size / native_width) / (reference_size / reference_width) - 1)
        results.append(dict(sample=label, kind=kind, approved_px=reference_size,
                            approved_width=reference_width, native_px=native_size,
                            native_width=native_width, error_percent=round(error, 2)))

    def sample(label, reference, crop, screen, text, prefix=None, inset=0):
        reference_mask, reference_width = ink(gallery / "approved" / reference, crop)
        box = node(gallery, screen, text)
        box = [box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset]
        if prefix:
            box[2] = box[0] + prefix
        native_mask, native_width = ink(gallery / "native" / (screen + ".png"), box)
        record(label, (height(reference_mask), reference_width), (height(native_mask), native_width))

    sample("Goal year", "goal-1.png", (50, 180, 270, 250), "goal-editor", "2026")
    sample("Goal label", "goal-1.png", (50, 300, 800, 350), "goal-editor", "Books to finish on this reader")
    sample("Goal numeric field", "goal-1.png", (60, 400, 175, 460), "goal-editor", "12", inset=12)
    sample("Goal Off", "goal-1.png", (62, 615, 150, 675), "goal-editor", "Off", inset=12)
    sample("Goal Save", "goal-1.png", (178, 615, 295, 675), "goal-editor", "Save", inset=12)

    # Isolate K in Open KOReader, avoiding the p descender.
    ref, rw = ink(gallery / "approved/launcher.png", (70, 180, 640, 275), white=True)
    box = node(gallery, "status-full", "Open KOReader\nback to your book")
    nat, nw = ink(gallery / "native/status-full.png", (100, box[1] + 10, 1300, box[3] - 10), white=True)
    line = next(row for row in runs(nat.getprojection()[1]) if len(row) > 10)
    nat = nat.crop((0, line[0], nat.width, line[-1] + 1))
    record("Launcher hero capital K", (capital(ref, 4), rw), (capital(nat, 4), nw))

    ref, rw = ink(gallery / "approved/launcher.png", (130, 505, 250, 532))
    box = node(gallery, "status-full", "Other apps")
    nat, nw = ink(gallery / "native/status-full.png", (box[0] + 8, box[1], box[2] - 8, box[3]))
    record("Launcher tile capital O", (capital(ref), rw), (capital(nat), nw))

    ref, rw = ink(gallery / "approved/launcher.png", (60, 606, 200, 635))
    nat, nw = ink(gallery / "native/status-full-bottom.png", node(gallery, "status-full-bottom", "Network"))
    record("Status row capital N", (capital(ref), rw), (capital(nat), nw))

    ref, rw = ink(gallery / "approved/crash-0.png", (52, 705, 450, 745))
    nat, nw = ink(gallery / "native/crash-saved.png", (47, 1000, 800, 1080))
    record("Crash summary Worker.run", (height(ref), rw), (height(nat), nw))

    field = node(gallery, "goal-editor", "12")
    record("Numeric field width", (132, 824), (field[2] - field[0], 1404), "control size")
    record("Numeric field height", (102, 824), (field[3] - field[1], 1404), "control size")
    hero = node(gallery, "status-full", "Open KOReader\nback to your book")
    record("Launcher hero height", (253, 702), (hero[3] - hero[1], 1404), "control size")
    tile = tile_bounds(gallery)
    record("Launcher tile height", (150, 702), (tile[3] - tile[1], 1404), "control size")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gallery", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    results = measure(args.gallery)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "scale-measurements.json").write_text(json.dumps(results, indent=2) + "\n")
    lines = ["# Width-normalized scale measurements", "",
             "Pixels are measured in the original approved crop and actual native capture, before gallery resizing. Error compares `(native size / native width)` with `(approved size / approved width)`. Capitals exclude descenders; forms with only digits use their full digit ink height.", "",
             "| Sample | Approved px / width | Native px / width | Difference |", "|---|---:|---:|---:|"]
    for row in results:
        lines.append(f'| {row["sample"]} | {row["approved_px"]} / {row["approved_width"]} | {row["native_px"]} / {row["native_width"]} | {row["error_percent"]:+.2f}% |')
    lines += ["", "The shared roles are in `CompanionStyle.kt`. Round 2 Settings and checklist use the common readable roles, with no Activity-specific downscale. Their body minimum is enforced by CompanionTypeScaleTest; this table retains the approved status/crash/goal scale samples. System chrome and synthetic content are excluded from these text measurements.", ""]
    (args.out / "scale-measurements.md").write_text("\n".join(lines))
    for row in results:
        print(f'{row["sample"]}: {row["error_percent"]:+.2f}%')
    if any(abs(row["error_percent"]) > 10 for row in results):
        raise SystemExit("A measured sample differs by more than 10%")


if __name__ == "__main__":
    main()
