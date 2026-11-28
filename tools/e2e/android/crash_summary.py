#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Companion-only crash capture on an explicitly selected disposable emulator."""
import argparse
import json
from pathlib import Path
import sys
import subprocess
import time
import xml.etree.ElementTree as ET
sys.dont_write_bytecode = True
from run import Emulator, PACKAGE


def review(device, apk, out):
    out.mkdir(parents=True, exist_ok=True)
    device.adb("install", "-r", "-t", apk)
    assert device.shell("wm", "size").splitlines()[-1].endswith("1404x1872"), "configure M8C resolution first"
    assert device.shell("wm", "density").splitlines()[-1].endswith(": 300"), "configure 300 dpi first"
    device.shell("settings", "put", "global", "auto_time_zone", "0")
    device.shell("cmd", "alarm", "set-timezone", "America/Los_Angeles")
    device.shell("settings", "put", "global", "show_first_crash_dialog", "0")
    def nodes():
        device.shell("uiautomator", "dump", "/sdcard/crash-ui.xml")
        return list(ET.fromstring(device.shell("cat", "/sdcard/crash-ui.xml")).iter("node"))
    def text():
        return "\n".join(n.get("text", "") for n in nodes())
    def wait_for(check, message):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            result = check()
            if result: return result
            time.sleep(.25)
        raise AssertionError(message)
    def click(label):
        import re
        def find():
            for n in nodes():
                if n.get("text") == label:
                    a,b,c,d = map(int, re.findall(r"\d+", n.get("bounds")))
                    if d > b and b < 1600:
                        device.shell("input", "tap", (a+c)//2, (b+d)//2); return True
            device.shell("input", "swipe", "600", "1400", "600", "400", "250")
        wait_for(find, "missing control: " + label)
    # Each fixture launch needs a new task: its Details child can otherwise receive the intent.
    def details():
        device.shell("am", "start", "-W", "-f", "0x18000000", "-n", PACKAGE + "/.CrashFixtureActivity")
        wait_for(lambda: "Companion crashes" in text() or scroll_to_crashes(), "Details did not load")
    def scroll_to_crashes():
        device.shell("input", "swipe", "600", "1400", "600", "400", "250")
        return False
    def record():
        return device.adb("exec-out", "run-as", PACKAGE, "cat", "no_backup/companion-crashes.bin")
    # Clear only this disposable fixture's diagnostic file; no user profiles or reader files.
    device.shell("run-as", PACKAGE, "rm", "-f", "no_backup/companion-crashes.bin", "no_backup/fixture-clipboard.txt")
    # A foreground fixture launch resets Android's bad-process throttle from a prior intentional crash.
    device.shell("am", "start", "-W", "-f", "0x18000000", "-n", PACKAGE + "/.CrashFixtureActivity", "--ez", "reset", "true")
    device.shell("am", "start", "-W", "-n", "org.koreader.launcher/.MainActivity")
    # Exercise the installed handler in a separate process while KOReader keeps the foreground book.
    device.command('Library.companion.setupLater();Library.open({local_path="/storage/emulated/0/Books/001 Seedfall.epub"});return true')
    wait_for(lambda: device.command('local ui=require("apps/reader/readerui").instance;return ui and ui.document and ui.document.file:find("001 Seedfall",1,true) and "open" or ""') == "open", "reader did not open")
    before = device.shell("dumpsys", "activity", "activities")
    assert "org.koreader.launcher" in before
    for count in (1, 2):
        device.shell("am", "broadcast", "--include-stopped-packages", "-n", PACKAGE + "/.CrashFixtureReceiver")
        def saved():
            import struct
            try:
                raw = record()
                return len(raw) <= 8192 and struct.unpack(">i", raw[-4:])[0] == count
            except Exception: return False
        wait_for(saved, "crash was not persisted/deduplicated")
        foreground = device.shell("dumpsys", "activity", "activities")
        resumed = "\n".join(line for line in foreground.splitlines() if "ResumedActivity" in line)
        assert "org.koreader.launcher" in resumed, "crash interrupted reading"
    device.shot(out / "reading-uninterrupted.png")
    # Restart the companion; the process must reconstruct the count from private disk.
    device.shell("am", "force-stop", PACKAGE)
    details()
    saved_text = wait_for(lambda: (t if "2 matching crashes" in (t := text()) else ""), "saved block missing")
    assert "PST" in saved_text and "UTC" not in saved_text
    assert "Worker.run" in saved_text and "IllegalStateException" in saved_text
    device.shot(out / "saved-local-time.png")
    click("Copy for support")
    device.shell("am", "start", "-W", "-f", "0x18000000", "-n", PACKAGE + "/.CrashFixtureActivity", "--ez", "clipboard", "true")
    def clipboard():
        try: return device.shell("run-as", PACKAGE, "cat", "no_backup/fixture-clipboard.txt")
        except subprocess.CalledProcessError: return ""
    copied = wait_for(clipboard, "clipboard empty")
    assert "Companion crashes" in copied and "2 matching crashes" in copied
    raw = record()
    for secret in ("synthetic-private-message", "/Books/private.epub", "https://private.example", "account-token"):
        assert secret not in copied and secret.encode() not in raw
    details(); click("Clear crash summaries")
    wait_for(lambda: "No companion crash summaries saved." in text(), "clear did not refresh Details")
    device.shell("am", "force-stop", PACKAGE); details()
    wait_for(lambda: "No companion crash summaries saved." in text(), "clear did not survive restart")
    device.shot(out / "cleared-reopened.png")
    evidence = {"checks": 10, "capture": "disposable companion process", "crashes": 2,
                "record_bytes": len(raw), "timezone": "America/Los_Angeles", "reading_interrupted": False,
                "copy_sanitized": True, "clear_survives_restart": True}
    (out / "review.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("10 Companion crash-summary emulator checks passed")

if __name__ == "__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--serial", required=True); p.add_argument("--apk", type=Path, required=True); p.add_argument("--out", type=Path, required=True)
    a=p.parse_args(); review(Emulator(a.serial), a.apk, a.out)
