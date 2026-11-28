#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build a mock ServerAdapter companion in an external disposable source tree.

Shipping sources, trust policy, dependencies and production build configuration are unchanged.
"""
from pathlib import Path
import argparse
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]

def build(out: Path):
    out=out.resolve()
    if out == ROOT or ROOT in out.parents:
        raise ValueError("fixture build must be outside the repository")
    marker=out / ".booksync-e2e-build"
    if out.exists() and any(out.iterdir()) and not marker.is_file():
        raise ValueError("fixture output must be empty or owned by this builder")
    out.mkdir(parents=True,exist_ok=True)
    marker.touch()
    destination=out / "android/companion"
    if (destination / "app/src").exists(): shutil.rmtree(destination / "app/src")
    shutil.copytree(ROOT / "android/companion", destination,
                    ignore=shutil.ignore_patterns("build", ".gradle", ".kotlin", "local.properties"), dirs_exist_ok=True)
    shutil.copytree(ROOT / "shared",out / "shared",dirs_exist_ok=True)
    sources=destination / "app/src/main/java/net/fledgewing/orbitcompanion"
    composition=sources / "ServerAdapters.kt"
    composition.write_text(composition.read_text().replace("object ServerAdapters {", "object ShippingServerAdapters {",1))
    shutil.copyfile(Path(__file__).with_name("E2eServerAdapters.kt"),sources / "E2eServerAdapters.kt")
    fixture=Path(__file__).parent/"server/bookorbit/RetainedFixture.kt"
    if fixture.is_file(): shutil.copyfile(fixture,sources/"server/bookorbit/RetainedFixture.kt")
    shutil.copyfile(Path(__file__).with_name("CrashFixture.kt"), sources / "CrashFixture.kt")
    # Fake clocks live only in this disposable APK, not behind a shipping debug command.
    shutil.copyfile(Path(__file__).with_name("ReminderClock.kt"),sources / "ReminderClock.kt")
    reminders=sources / "LibraryReminders.kt"
    reminders.write_text(reminders.read_text().replace("System::currentTimeMillis,SystemClock::elapsedRealtime", "ReminderClock::wall,ReminderClock::elapsed")
        .replace("SystemClock.elapsedRealtime()", "ReminderClock.elapsed()")
        .replace('val sampledAt=(values["at"] as? Number)?.toLong() ?: now', "val sampledAt=now")
        .replace("System.currentTimeMillis()", "ReminderClock.wall()")
        .replace('}.also {check(LuaValue.encode(it).size<=8192)}', '}.let { it+mapOf("clockElapsed" to ReminderClock.elapsed()) }.also {check(LuaValue.encode(it).size<=8192)}')
        .replace("Reminders(storage,", "Reminders(object : Reminders.Store by storage { override fun save(state: Reminders.State) { check(!ReminderClock.failSave()); storage.save(state) } },"))
    sleep=sources / "OrbitService.kt"
    sleep.write_text(sleep.read_text().replace('internal fun reminderSleepNow(): String = sleepNow("reminder") ?: "ok"',
        'internal fun reminderSleepNow(): String = if(ReminderClock.failSleep()) "unavailable" else sleepNow("reminder") ?: "ok"'))
    shutil.copyfile(Path(__file__).with_name("HomeFixture.kt"), sources / "HomeFixture.kt")
    manifest=destination / "app/src/main/AndroidManifest.xml"
    manifest.write_text(manifest.read_text().replace("<application", '<application android:testOnly="true"',1).replace("</application>", '<receiver android:name=".CrashFixtureReceiver" android:exported="true" android:process=":crash_fixture" /><activity android:name=".CrashFixtureActivity" android:exported="true" android:process=":crash_fixture" /></application>'))
    subprocess.run(["./gradlew", "assembleDebug"],cwd=destination,check=True)
    return destination / "app/build/outputs/apk/debug/app-debug.apk"

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,required=True)
    print(build(parser.parse_args().out))
